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

    public static func load(from logURL: URL = defaultLogURL) throws -> GrokUsageSnapshot? {
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
              let config = context["config"] as? [String: Any],
              let rawUsedPercentage = number(from: config["creditUsagePercent"]) else {
            return nil
        }

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
