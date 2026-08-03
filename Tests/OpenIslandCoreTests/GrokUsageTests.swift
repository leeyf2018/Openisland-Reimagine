import Foundation
import Testing
@testable import OpenIslandCore

struct GrokUsageTests {
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

        let snapshot = try GrokUsageLoader.load(from: logURL)

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

        let snapshot = try GrokUsageLoader.load(from: logURL)

        #expect(snapshot?.roundedUsedPercentage == 41)
    }

    @Test
    func grokUsageLoaderReturnsNilWhenLogIsMissing() throws {
        let logURL = temporaryLogURL()
        #expect(try GrokUsageLoader.load(from: logURL) == nil)
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
