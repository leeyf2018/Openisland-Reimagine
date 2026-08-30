import Foundation

/// Last verified WorkBuddy points balance.
///
/// WorkBuddy exposes one whole-number balance rather than a reset window, so
/// this snapshot intentionally has no percentage or reset-date fields.
public struct WorkBuddyUsageSnapshot: Equatable, Codable, Sendable {
    public var source: String
    public var capturedAt: Date?
    public var pointsRemaining: Int

    public init(
        source: String,
        capturedAt: Date? = nil,
        pointsRemaining: Int
    ) {
        self.source = source
        self.capturedAt = capturedAt
        self.pointsRemaining = max(0, pointsRemaining)
    }
}

public enum WorkBuddyUsageLoader {
    /// A small, secret-free bridge file. WorkBuddy does not currently expose
    /// its account balance through its public local probe.
    public static var defaultSnapshotURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenIsland", isDirectory: true)
            .appendingPathComponent("workbuddy-usage.json")
    }

    public static func load(
        from url: URL = defaultSnapshotURL,
        fileManager: FileManager = .default
    ) throws -> WorkBuddyUsageSnapshot? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkBuddyUsageSnapshot.self, from: data)
    }

    public static func write(
        _ snapshot: WorkBuddyUsageSnapshot,
        to url: URL = defaultSnapshotURL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}

public enum WorkBuddyUsageParser {
    /// Parses the combined accessibility label emitted by WorkBuddy's balance
    /// row, for example `积分余额 刷新 6,200` or `Credits balance Refresh 6,200`.
    public static func pointsBalance(from accessibilityText: String) -> Int? {
        let lowered = accessibilityText.lowercased()
        guard accessibilityText.contains("积分余额")
                || lowered.contains("credit balance")
                || lowered.contains("credits balance") else {
            return nil
        }

        let pattern = #"([0-9][0-9,，\s]*(?:\.[0-9]+)?)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.matches(
                in: accessibilityText,
                range: NSRange(accessibilityText.startIndex..., in: accessibilityText)
              ).last,
              let range = Range(match.range(at: 1), in: accessibilityText) else {
            return nil
        }

        let normalized = accessibilityText[range]
            .filter { $0.isNumber || $0 == "." }
        return Double(normalized).map(Int.init)
    }
}
