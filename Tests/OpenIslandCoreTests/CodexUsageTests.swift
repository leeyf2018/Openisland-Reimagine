import Foundation
import Testing
@testable import OpenIslandCore

struct CodexUsageTests {
    /// Parsing tests exercise active-window values. Keep their reset boundary
    /// independent of the wall clock so the suite does not start failing when
    /// a historical fixture date passes on CI.
    private static let activeWindowResetTimestamp = Date.distantFuture.timeIntervalSince1970

    @Test
    func codexUsageSnapshotDetectsFullyUsedWindow() {
        let fullWindow = CodexUsageWindow(
            key: "primary",
            label: "7d",
            usedPercentage: 100,
            leftPercentage: 0,
            windowMinutes: 10_080,
            resetsAt: nil
        )
        let availableWindow = CodexUsageWindow(
            key: "primary",
            label: "7d",
            usedPercentage: 99,
            leftPercentage: 1,
            windowMinutes: 10_080,
            resetsAt: nil
        )

        #expect(
            CodexUsageSnapshot(
                sourceFilePath: "full.jsonl",
                capturedAt: nil,
                windows: [fullWindow]
            ).hasFullyUsedWindow
        )
        #expect(
            CodexUsageSnapshot(
                sourceFilePath: "available.jsonl",
                capturedAt: nil,
                windows: [availableWindow]
            ).hasFullyUsedWindow == false
        )
    }

    @Test
    func codexUsageLoaderParsesLastTokenCountRateLimits() throws {
        let rootURL = temporaryRootURL(named: "codex-usage")
        let rolloutURL = rootURL
            .appendingPathComponent("2026/04/03", isDirectory: true)
            .appendingPathComponent("rollout-latest.jsonl")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-03T01:49:35.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "info": [
                            "total_token_usage": [
                                "total_tokens": 999_999,
                            ],
                        ],
                        "rate_limits": [
                            "limit_id": "codex",
                            "plan_type": "pro",
                            "primary": [
                                "used_percent": 12.0,
                                "window_minutes": 300,
                                "resets_at": Self.activeWindowResetTimestamp,
                            ],
                            "secondary": [
                                "used_percent": 24.0,
                                "window_minutes": 10_080,
                                "resets_at": Self.activeWindowResetTimestamp,
                            ],
                        ],
                    ]
                ),
                rolloutLine(
                    timestamp: "2026-04-03T01:50:35.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "info": [
                            "total_token_usage": [
                                "total_tokens": 1_234_567,
                            ],
                        ],
                        "rate_limits": [
                            "limit_id": "codex",
                            "plan_type": "pro",
                            "primary": [
                                "used_percent": 13.0,
                                "window_minutes": 300,
                                "resets_at": Self.activeWindowResetTimestamp,
                            ],
                            "secondary": [
                                "used_percent": 25.0,
                                "window_minutes": 10_080,
                                "resets_at": Self.activeWindowResetTimestamp,
                            ],
                        ],
                    ]
                ),
            ],
            to: rolloutURL
        )
        try setModificationDate(
            Date(timeIntervalSince1970: 2_000),
            for: rolloutURL
        )

        let snapshot = try CodexUsageLoader.load(fromRootURL: rootURL)

        #expect(resolvedPath(snapshot?.sourceFilePath) == rolloutURL.resolvingSymlinksInPath().path)
        #expect(snapshot?.limitID == "codex")
        #expect(snapshot?.planType == "pro")
        #expect(snapshot?.windows.map(\.label) == ["5h", "7d"])
        #expect(snapshot?.windows.map(\.roundedUsedPercentage) == [13, 25])
        #expect(snapshot?.windows.first?.leftPercentage == 87)
        #expect(
            snapshot?.windows.first?.resetsAt
                == Date(timeIntervalSince1970: Self.activeWindowResetTimestamp)
        )
        #expect(snapshot?.capturedAt == isoDate("2026-04-03T01:50:35.000Z"))
    }

    @Test
    func codexUsageLoaderFallsBackWhenNewestRolloutHasNoRateLimits() throws {
        let rootURL = temporaryRootURL(named: "codex-usage-fallback")
        let oldRolloutURL = rootURL
            .appendingPathComponent("2026/04/02", isDirectory: true)
            .appendingPathComponent("rollout-has-rate-limits.jsonl")
        let newRolloutURL = rootURL
            .appendingPathComponent("2026/04/03", isDirectory: true)
            .appendingPathComponent("rollout-no-rate-limits.jsonl")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-02T17:54:17.621Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "rate_limits": [
                            "limit_id": "codex",
                            "plan_type": "pro",
                            "primary": [
                                "used_percent": 13.0,
                                "window_minutes": 300,
                                "resets_at": Self.activeWindowResetTimestamp,
                            ],
                        ],
                    ]
                ),
            ],
            to: oldRolloutURL
        )
        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-03T03:00:00.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "user_message",
                        "message": "Start a fresh session.",
                    ]
                ),
            ],
            to: newRolloutURL
        )

        try setModificationDate(Date(timeIntervalSince1970: 1_000), for: oldRolloutURL)
        try setModificationDate(Date(timeIntervalSince1970: 2_000), for: newRolloutURL)

        let snapshot = try CodexUsageLoader.load(fromRootURL: rootURL)

        #expect(resolvedPath(snapshot?.sourceFilePath) == oldRolloutURL.resolvingSymlinksInPath().path)
        #expect(snapshot?.windows.map(\.label) == ["5h"])
        #expect(snapshot?.windows.first?.roundedUsedPercentage == 13)
    }

    @Test
    func codexUsageLoaderFormatsNonStandardWindowLengths() throws {
        let rootURL = temporaryRootURL(named: "codex-usage-labels")
        let rolloutURL = rootURL
            .appendingPathComponent("2026/04/03", isDirectory: true)
            .appendingPathComponent("rollout-custom-window.jsonl")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-03T05:30:00.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "rate_limits": [
                            "primary": [
                                "used_percent": 8.0,
                                "window_minutes": 90,
                                "resets_at": Self.activeWindowResetTimestamp,
                            ],
                            "secondary": [
                                "used_percent": 11.0,
                                "window_minutes": 1_500,
                                "resets_at": Self.activeWindowResetTimestamp,
                            ],
                        ],
                    ]
                ),
            ],
            to: rolloutURL
        )

        let snapshot = try CodexUsageLoader.load(fromRootURL: rootURL)

        #expect(snapshot?.windows.map(\.label) == ["1h 30m", "1d 1h"])
    }

    /// Regression: after quota reset, Codex moves the fresh rollout into
    /// `archived_sessions/` while `sessions/` still holds a pre-reset 100%
    /// snapshot. The loader must prefer the newer event, not the stale live tree.
    @Test
    func codexUsageLoaderPrefersNewerArchivedRateLimitsOverStaleSessions() throws {
        let sessionsRoot = temporaryRootURL(named: "codex-usage-sessions")
        let archivedRoot = temporaryRootURL(named: "codex-usage-archived")
        let staleRolloutURL = sessionsRoot
            .appendingPathComponent("2026/08/03", isDirectory: true)
            .appendingPathComponent("rollout-stale-100.jsonl")
        let freshRolloutURL = archivedRoot
            .appendingPathComponent("rollout-fresh-45.jsonl")

        defer {
            try? FileManager.default.removeItem(at: sessionsRoot)
            try? FileManager.default.removeItem(at: archivedRoot)
        }

        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-08-03T13:19:18.730Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "rate_limits": [
                            "limit_id": "codex",
                            "plan_type": "plus",
                            "primary": [
                                "used_percent": 100.0,
                                "window_minutes": 10_080,
                                "resets_at": Self.activeWindowResetTimestamp,
                            ],
                        ],
                    ]
                ),
            ],
            to: staleRolloutURL
        )
        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-08-04T10:03:07.175Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "rate_limits": [
                            "limit_id": "codex",
                            "plan_type": "plus",
                            "primary": [
                                "used_percent": 45.0,
                                "window_minutes": 10_080,
                                "resets_at": Self.activeWindowResetTimestamp,
                            ],
                        ],
                    ]
                ),
            ],
            to: freshRolloutURL
        )

        // Even if the stale sessions/ file was re-touched and has a newer mtime,
        // multi-root + event-timestamp selection must still pick the post-reset 45%.
        try setModificationDate(Date(timeIntervalSince1970: 5_000), for: staleRolloutURL)
        try setModificationDate(Date(timeIntervalSince1970: 4_000), for: freshRolloutURL)

        let snapshot = try CodexUsageLoader.load(
            fromRootURLs: [sessionsRoot, archivedRoot]
        )

        #expect(resolvedPath(snapshot?.sourceFilePath) == freshRolloutURL.resolvingSymlinksInPath().path)
        #expect(snapshot?.windows.first?.roundedUsedPercentage == 45)
        #expect(snapshot?.capturedAt == isoDate("2026-08-04T10:03:07.175Z"))
    }

    @Test
    func codexUsageZerosWindowAfterResetsAtElapses() {
        let stale = CodexUsageSnapshot(
            sourceFilePath: "jsonl",
            capturedAt: isoDate("2026-08-16T03:00:00Z"),
            planType: "plus",
            windows: [
                CodexUsageWindow(
                    key: "primary",
                    label: "7d",
                    usedPercentage: 100,
                    leftPercentage: 0,
                    windowMinutes: 10_080,
                    resetsAt: isoDate("2026-08-16T02:00:00Z")
                ),
            ]
        )

        let normalized = CodexUsageLoader.normalizeForCurrentPeriod(
            stale,
            now: isoDate("2026-08-16T03:30:00Z")!
        )
        #expect(normalized.windows.first?.roundedUsedPercentage == 0)
        #expect(normalized.windows.first?.leftPercentage == 100)
    }
}

private func temporaryRootURL(named name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("open-island-\(name)-\(UUID().uuidString)", isDirectory: true)
}

private func writeRollout(_ lines: [String], to url: URL) throws {
    let directoryURL = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
}

private func setModificationDate(_ date: Date, for url: URL) throws {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
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

private func resolvedPath(_ value: String?) -> String? {
    guard let value else {
        return nil
    }

    return URL(fileURLWithPath: value).resolvingSymlinksInPath().path
}

private func rolloutLine(
    timestamp: String,
    type: String,
    payload: [String: Any]
) -> String {
    let object: [String: Any] = [
        "timestamp": timestamp,
        "type": type,
        "payload": payload,
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}
