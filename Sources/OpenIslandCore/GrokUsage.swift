import Foundation

public struct GrokUsageSnapshot: Equatable, Codable, Sendable {
    public var sourceFilePath: String
    public var capturedAt: Date?
    public var usedPercentage: Double
    public var periodType: String?
    public var periodStart: Date?
    public var resetsAt: Date?
    public var subscriptionTier: String?

    public init(
        sourceFilePath: String,
        capturedAt: Date?,
        usedPercentage: Double,
        periodType: String? = nil,
        periodStart: Date? = nil,
        resetsAt: Date? = nil,
        subscriptionTier: String? = nil
    ) {
        self.sourceFilePath = sourceFilePath
        self.capturedAt = capturedAt
        self.usedPercentage = usedPercentage
        self.periodType = periodType
        self.periodStart = periodStart
        self.resetsAt = resetsAt
        self.subscriptionTier = subscriptionTier
    }

    public var roundedUsedPercentage: Int {
        Int(usedPercentage.rounded())
    }

    public var windowLabel: String {
        if periodType == "USAGE_PERIOD_TYPE_WEEKLY" {
            return "7d"
        }

        if let periodStart, let resetsAt {
            let days = Int((resetsAt.timeIntervalSince(periodStart) / 86_400).rounded())
            if days > 0 {
                return "\(days)d"
            }
        }

        return "usage"
    }
}

public enum GrokUsageLoader {
    public static let defaultLogURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".grok/logs/unified.jsonl")

    public static let defaultLogsDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".grok/logs", isDirectory: true)

    /// Live `unified.jsonl` plus any rotated siblings (`unified.jsonl.1`, …).
    public static func defaultLogURLs(fileManager: FileManager = .default) -> [URL] {
        let directory = defaultLogsDirectoryURL
        guard fileManager.fileExists(atPath: directory.path),
              let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return [defaultLogURL]
        }

        let matched = names.filter { name in
            name == "unified.jsonl" || name.hasPrefix("unified.jsonl.")
        }

        let urls = matched.map { directory.appendingPathComponent($0) }
        let sorted = urls.sorted { lhs, rhs in
            let left = (try? fileManager.attributesOfItem(atPath: lhs.path)[.modificationDate] as? Date)
                ?? .distantPast
            let right = (try? fileManager.attributesOfItem(atPath: rhs.path)[.modificationDate] as? Date)
                ?? .distantPast
            if left == right {
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedDescending
            }
            return left > right
        }

        return sorted.isEmpty ? [defaultLogURL] : sorted
    }

    /// Production entry: newest billing line across live + rotated logs, then
    /// normalize for an already-elapsed weekly period (post-reset without a new
    /// Grok CLI fetch would otherwise keep showing last period’s high %).
    public static func load(
        fileManager: FileManager = .default,
        now: Date = .now
    ) throws -> GrokUsageSnapshot? {
        try load(fromLogURLs: defaultLogURLs(fileManager: fileManager), now: now)
    }

    /// Single-file load (tests + pinned fixtures).
    public static func load(
        from logURL: URL,
        now: Date = .now
    ) throws -> GrokUsageSnapshot? {
        try load(fromLogURLs: [logURL], now: now)
    }

    public static func load(
        fromLogURLs logURLs: [URL],
        now: Date = .now
    ) throws -> GrokUsageSnapshot? {
        var bestRaw: GrokUsageSnapshot?

        for logURL in logURLs {
            guard let snapshot = try loadRaw(from: logURL) else {
                continue
            }
            let captured = snapshot.capturedAt ?? .distantPast
            let bestCaptured = bestRaw?.capturedAt ?? .distantPast
            if bestRaw == nil || captured > bestCaptured {
                bestRaw = snapshot
            }
        }

        guard let bestRaw else {
            return nil
        }
        return normalizeForCurrentPeriod(bestRaw, now: now)
    }

    /// When `resetsAt` is already past, the last log line is pre-reset. Surface
    /// a fresh period at 0% used instead of a frozen high watermark.
    public static func normalizeForCurrentPeriod(
        _ snapshot: GrokUsageSnapshot,
        now: Date = .now
    ) -> GrokUsageSnapshot {
        guard let resetsAt = snapshot.resetsAt, resetsAt <= now else {
            return snapshot
        }

        var periodStart = snapshot.periodStart ?? resetsAt
        var periodEnd = resetsAt
        var length = periodEnd.timeIntervalSince(periodStart)
        if length <= 0 {
            // SuperGrok weekly window default when period start is missing.
            length = 7 * 86_400
        }

        var guardCount = 0
        while periodEnd <= now, guardCount < 52 {
            periodStart = periodEnd
            periodEnd = periodEnd.addingTimeInterval(length)
            guardCount += 1
        }

        return GrokUsageSnapshot(
            sourceFilePath: snapshot.sourceFilePath,
            capturedAt: snapshot.capturedAt,
            usedPercentage: 0,
            periodType: snapshot.periodType,
            periodStart: periodStart,
            resetsAt: periodEnd,
            subscriptionTier: snapshot.subscriptionTier
        )
    }

    private static func loadRaw(from logURL: URL) throws -> GrokUsageSnapshot? {
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            return nil
        }

        let fileHandle = try FileHandle(forReadingFrom: logURL)
        defer { try? fileHandle.close() }

        let chunkSize: UInt64 = 64 * 1_024
        var endOffset = try fileHandle.seekToEnd()
        var newerLineFragment = Data()

        while endOffset > 0 {
            let readSize = min(chunkSize, endOffset)
            let startOffset = endOffset - readSize
            try fileHandle.seek(toOffset: startOffset)

            var buffer = try fileHandle.read(upToCount: Int(readSize)) ?? Data()
            buffer.append(newerLineFragment)
            let lines = buffer.split(separator: 0x0A, omittingEmptySubsequences: false)
            let completeLines = startOffset == 0 ? lines[...] : lines.dropFirst()

            for lineData in completeLines.reversed() {
                let line = String(decoding: lineData, as: UTF8.self)
                if let snapshot = snapshot(from: line, sourceFilePath: logURL.path) {
                    return snapshot
                }
            }

            newerLineFragment = startOffset == 0
                ? Data()
                : Data(lines.first ?? Data.SubSequence())
            endOffset = startOffset
        }

        return nil
    }

    private static func snapshot(from line: String, sourceFilePath: String) -> GrokUsageSnapshot? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["msg"] as? String == "billing: fetched credits config",
              let context = object["ctx"] as? [String: Any],
              let config = context["config"] as? [String: Any] else {
            return nil
        }

        // After a usage reset, Grok CLI still writes a successful billing
        // fetch but omits `creditUsagePercent` (observed 2026-08-13 and
        // 2026-08-16). Treating that as "unparseable" walked back to the
        // last 100% line and froze the island. Missing/null = 0 used.
        let rawUsedPercentage = number(from: config["creditUsagePercent"]) ?? 0

        let currentPeriod = config["currentPeriod"] as? [String: Any]
        let periodStart = date(from: currentPeriod?["start"] ?? config["billingPeriodStart"])
        let resetsAt = date(from: currentPeriod?["end"] ?? config["billingPeriodEnd"])

        return GrokUsageSnapshot(
            sourceFilePath: sourceFilePath,
            capturedAt: date(from: object["ts"]),
            usedPercentage: min(max(rawUsedPercentage, 0), 100),
            periodType: string(from: currentPeriod?["type"]),
            periodStart: periodStart,
            resetsAt: resetsAt,
            subscriptionTier: string(from: config["subscriptionTier"])
                ?? string(from: context["subscriptionTier"])
        )
    }

    private static func number(from value: Any?) -> Double? {
        switch value {
        case let value as NSNumber:
            value.doubleValue
        case let value as String:
            Double(value)
        default:
            nil
        }
    }

    private static func string(from value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func date(from value: Any?) -> Date? {
        guard let value = value as? String else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
