import Foundation
import Testing
@testable import OpenIslandCore

struct GrokBotUsageTests {
    private static let midPeriodNow = isoDate("2026-09-06T08:00:00.000Z")!

    @Test
    func parseReadsGrokChatSliceFromLiveCreditsPayload() throws {
        let snapshot = try GrokBotUsageLoader.parse(
            data: creditsJSON(
                overall: 67,
                products: [
                    ("GrokBuild", 52),
                    ("GrokImagine", 14),
                    ("GrokChat", 1),
                ]
            ),
            source: "test",
            capturedAt: Self.midPeriodNow
        )

        #expect(snapshot?.roundedUsedPercentage == 1)
        #expect(snapshot?.product == "GrokChat")
        #expect(snapshot?.overallUsedPercentage == 67)
        #expect(snapshot?.windowLabel == "7d")
        #expect(snapshot?.resetsAt == isoDate("2026-09-09T15:11:55.430921Z"))
        #expect(snapshot?.subscriptionTier == "SuperGrok")
    }

    @Test
    func parseAcceptsProductGrokChatAndGrokBotAliases() throws {
        let chat = try GrokBotUsageLoader.parse(
            data: creditsJSON(products: [("PRODUCT_GROK_CHAT", 3)]),
            source: "test",
            capturedAt: Self.midPeriodNow
        )
        #expect(chat?.roundedUsedPercentage == 3)

        let bot = try GrokBotUsageLoader.parse(
            data: creditsJSON(products: [("GrokBot", 8)]),
            source: "test",
            capturedAt: Self.midPeriodNow
        )
        #expect(bot?.roundedUsedPercentage == 8)
        #expect(GrokBotUsageLoader.isChatProductName("GrokBuild") == false)
        #expect(GrokBotUsageLoader.isChatProductName("GrokImagine") == false)
    }

    @Test
    func parseTreatsMissingChatRowAsZeroWhenProductUsageExists() throws {
        let snapshot = try GrokBotUsageLoader.parse(
            data: creditsJSON(products: [("GrokBuild", 52), ("GrokImagine", 14)]),
            source: "test",
            capturedAt: Self.midPeriodNow
        )

        #expect(snapshot?.roundedUsedPercentage == 0)
        #expect(snapshot?.product == "GrokChat")
    }

    @Test
    func parseReturnsNilWithoutProductUsageArray() throws {
        let json = """
        {"config":{"creditUsagePercent":67.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-09-02T15:11:55.430921Z","end":"2026-09-09T15:11:55.430921Z"}}}
        """.data(using: .utf8)!

        let snapshot = try GrokBotUsageLoader.parse(data: json, source: "test")
        #expect(snapshot == nil)
    }

    @Test
    func normalizeZerosUsedAfterPeriodEnd() throws {
        let live = GrokBotUsageSnapshot(
            source: "test",
            capturedAt: isoDate("2026-09-09T14:00:00.000Z"),
            usedPercentage: 91,
            product: "GrokChat",
            periodType: "USAGE_PERIOD_TYPE_WEEKLY",
            periodStart: isoDate("2026-09-02T15:11:55.430921Z"),
            resetsAt: isoDate("2026-09-09T15:11:55.430921Z")
        )

        let snapshot = GrokBotUsageLoader.normalizeForCurrentPeriod(
            live,
            now: isoDate("2026-09-09T16:00:00.000Z")!
        )

        #expect(snapshot.roundedUsedPercentage == 0)
        #expect(snapshot.periodStart == isoDate("2026-09-09T15:11:55.430921Z"))
        #expect(snapshot.resetsAt == isoDate("2026-09-16T15:11:55.430921Z"))
    }

    @Test
    func loadFallsBackToCacheWhenAuthFileIsMissing() throws {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-grokbot-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let cached = GrokBotUsageSnapshot(
            source: "cache",
            capturedAt: Self.midPeriodNow,
            usedPercentage: 1,
            product: "GrokChat",
            periodType: "USAGE_PERIOD_TYPE_WEEKLY",
            periodStart: isoDate("2026-09-02T15:11:55.430921Z"),
            resetsAt: isoDate("2026-09-09T15:11:55.430921Z")
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(cached).write(to: cacheURL, options: .atomic)

        let missingAuth = cacheURL.deletingLastPathComponent()
            .appendingPathComponent("missing-auth.json")
        let snapshot = try GrokBotUsageLoader.load(
            authURL: missingAuth,
            cacheURL: cacheURL,
            now: Self.midPeriodNow
        )

        #expect(snapshot?.roundedUsedPercentage == 1)
        #expect(snapshot?.product == "GrokChat")
    }

    @Test
    func readBearerTokenSkipsExpiredEntries() throws {
        let authURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-grokbot-auth-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: authURL) }

        let payload: [String: Any] = [
            "https://auth.x.ai::test": [
                "key": "expired-token-value-that-is-long-enough",
                "expires_at": "2026-09-01T00:00:00.000Z",
            ],
        ]
        try JSONSerialization.data(withJSONObject: payload).write(to: authURL)

        let token = GrokBotUsageLoader.readBearerToken(from: authURL, now: Self.midPeriodNow)
        #expect(token == nil)
    }
}

private func creditsJSON(
    overall: Double = 67,
    products: [(String, Double)]
) -> Data {
    let productUsage: [[String: Any]] = products.map { name, percent in
        ["product": name, "usagePercent": percent]
    }
    let object: [String: Any] = [
        "config": [
            "creditUsagePercent": overall,
            "currentPeriod": [
                "type": "USAGE_PERIOD_TYPE_WEEKLY",
                "start": "2026-09-02T15:11:55.430921Z",
                "end": "2026-09-09T15:11:55.430921Z",
            ],
            "productUsage": productUsage,
            "subscriptionTier": "SuperGrok",
        ],
    ]
    return try! JSONSerialization.data(withJSONObject: object)
}

private func isoDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}
