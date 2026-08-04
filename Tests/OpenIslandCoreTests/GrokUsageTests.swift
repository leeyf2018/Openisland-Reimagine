import Foundation
import Testing
@testable import OpenIslandCore

struct GrokUsageTests {
    /// Fixed "now" inside the fixture weekly window so suite stays stable after 2026-08-05.
    private static let midPeriodNow = isoDate("2026-08-04T12:00:00.000Z")!

    @Test
    func grokUsageLoaderParsesLatestWeeklyBillingSnapshot() throws {
        let logURL = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }

        try writeLog(
            [
                billingLine(timestamp: "2026-08-03T09:52:57.203Z", usedPercentage: 40),
                unrelatedLine(),
                billingLine(timestamp: "2026-08-03T09:59:06.852Z", usedPercentage: 41),
            ],
            to: logURL
        )

        let snapshot = try GrokUsageLoader.load(from: logURL, now: Self.midPeriodNow)

        #expect(snapshot?.sourceFilePath == logURL.path)
        #expect(snapshot?.roundedUsedPercentage == 41)
        #expect(snapshot?.windowLabel == "7d")
        #expect(snapshot?.subscriptionTier == "SuperGrok")
        #expect(snapshot?.capturedAt == isoDate("2026-08-03T09:59:06.852Z"))
        #expect(snapshot?.periodStart == isoDate("2026-07-29T15:11:55.430921Z"))
        #expect(snapshot?.resetsAt == isoDate("2026-08-05T15:11:55.430921Z"))
    }

    @Test
    func grokUsageLoaderIgnoresMalformedTrailingLines() throws {
        let logURL = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }

        try writeLog(
            [
                billingLine(timestamp: "2026-08-03T09:59:06.852Z", usedPercentage: 41),
                "{\"msg\":\"billing: fetched credits config\",\"ctx\":",
            ],
            to: logURL
        )

        let snapshot = try GrokUsageLoader.load(from: logURL, now: Self.midPeriodNow)

        #expect(snapshot?.roundedUsedPercentage == 41)
    }

    @Test
    func grokUsageLoaderReturnsNilWhenLogIsMissing() throws {
        let logURL = temporaryLogURL()
        #expect(try GrokUsageLoader.load(from: logURL, now: Self.midPeriodNow) == nil)
    }

    /// After weekly reset, Grok CLI may not re-fetch billing immediately. The last
    /// log line still has high creditUsagePercent + past period end — Island must
    /// show 0% for the new period (same class of bug as Codex C post-reset).
    @Test
    func grokUsageLoaderZerosUsedAfterPeriodEndWithoutNewFetch() throws {
        let logURL = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }

        try writeLog(
            [
                billingLine(timestamp: "2026-08-05T14:00:00.000Z", usedPercentage: 97),
            ],
            to: logURL
        )

        let afterReset = isoDate("2026-08-05T16:00:00.000Z")!
        let snapshot = try GrokUsageLoader.load(from: logURL, now: afterReset)

        #expect(snapshot?.roundedUsedPercentage == 0)
        #expect(snapshot?.periodStart == isoDate("2026-08-05T15:11:55.430921Z"))
        #expect(snapshot?.resetsAt == isoDate("2026-08-12T15:11:55.430921Z"))
    }

    @Test
    func grokUsageLoaderPrefersNewerBillingAcrossRotatedLogs() throws {
        let directory = temporaryLogURL().deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }

        let older = directory.appendingPathComponent("unified.jsonl.1")
        let newer = directory.appendingPathComponent("unified.jsonl")
        try writeLog(
            [billingLine(timestamp: "2026-08-03T09:00:00.000Z", usedPercentage: 10)],
            to: older
        )
        try writeLog(
            [billingLine(timestamp: "2026-08-03T10:00:00.000Z", usedPercentage: 22)],
            to: newer
        )

        let snapshot = try GrokUsageLoader.load(
            fromLogURLs: [older, newer],
            now: Self.midPeriodNow
        )
        #expect(snapshot?.roundedUsedPercentage == 22)
        #expect(snapshot?.sourceFilePath == newer.path)
    }
}

private func temporaryLogURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("open-island-grok-usage-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("unified.jsonl")
}

private func writeLog(_ lines: [String], to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
}

private func billingLine(timestamp: String, usedPercentage: Double) -> String {
    jsonLine(
        [
            "ts": timestamp,
            "msg": "billing: fetched credits config",
            "ctx": [
                "config": [
                    "creditUsagePercent": usedPercentage,
                    "currentPeriod": [
                        "type": "USAGE_PERIOD_TYPE_WEEKLY",
                        "start": "2026-07-29T15:11:55.430921Z",
                        "end": "2026-08-05T15:11:55.430921Z",
                    ],
                    "subscriptionTier": "SuperGrok",
                ],
            ],
        ]
    )
}

private func unrelatedLine() -> String {
    jsonLine(["ts": "2026-08-03T09:55:00.000Z", "msg": "session active"])
}

private func jsonLine(_ object: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

private func isoDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
}
