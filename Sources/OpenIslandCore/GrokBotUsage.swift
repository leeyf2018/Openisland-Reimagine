import Foundation

/// Grok Bot / grok.com Chat share SuperGrok's `GrokChat` product slice.
///
/// **G** on the island is Grok CLI overall `creditUsagePercent` from
/// `~/.grok/logs/unified.jsonl`. Those log lines do **not** include
/// `productUsage`, so they cannot drive this chip.
///
/// **GB** reads the live credits config (`cli-chat-proxy.grok.com`) with the
/// local Grok CLI OAuth token and takes `productUsage` where
/// `product == GrokChat` (aliases: `PRODUCT_GROK_CHAT`, `GrokBot`, `Chat`).
/// That is the same 1% SuperGrok Chat number shown in grok.com → Settings → Usage.
///
/// There is no separate daily Chat window in that payload — SuperGrok Chat is
/// a weekly pool, displayed with the same used% + remaining-days chip as G.
public struct GrokBotUsageSnapshot: Equatable, Codable, Sendable {
    public var source: String
    public var capturedAt: Date?
    public var usedPercentage: Double
    public var product: String
    public var periodType: String?
    public var periodStart: Date?
    public var resetsAt: Date?
    public var subscriptionTier: String?
    public var overallUsedPercentage: Double?

    public init(
        source: String,
        capturedAt: Date? = nil,
        usedPercentage: Double,
        product: String = "GrokChat",
        periodType: String? = nil,
        periodStart: Date? = nil,
        resetsAt: Date? = nil,
        subscriptionTier: String? = nil,
        overallUsedPercentage: Double? = nil
    ) {
        self.source = source
        self.capturedAt = capturedAt
        self.usedPercentage = usedPercentage
        self.product = product
        self.periodType = periodType
        self.periodStart = periodStart
        self.resetsAt = resetsAt
        self.subscriptionTier = subscriptionTier
        self.overallUsedPercentage = overallUsedPercentage
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

public enum GrokBotUsageLoader {
    public static let creditsURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!

    public static var defaultAuthURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/auth.json")
    }

    public static var defaultCacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenIsland", isDirectory: true)
            .appendingPathComponent("grokbot-chat-usage.json")
    }

    /// Reject extremely old offline cache so a dead token cannot freeze the chip.
    public static let maxOfflineCacheAge: TimeInterval = 7 * 86_400

    public static let requestTimeout: TimeInterval = 8

    /// Live fetch via Grok CLI OAuth, then last good cache. `nil` only when
    /// both live and cache are unavailable.
    public static func load(
        authURL: URL = defaultAuthURL,
        cacheURL: URL = defaultCacheURL,
        fileManager: FileManager = .default,
        now: Date = .now,
        session: URLSession = .shared
    ) throws -> GrokBotUsageSnapshot? {
        if let live = try? fetchLiveSnapshot(
            authURL: authURL,
            now: now,
            session: session
        ) {
            let normalized = normalizeForCurrentPeriod(live, now: now)
            try? writeCache(normalized, to: cacheURL, fileManager: fileManager)
            return normalized
        }
        return try? readCache(from: cacheURL, fileManager: fileManager, now: now)
    }

    public static func fetchLiveSnapshot(
        authURL: URL = defaultAuthURL,
        now: Date = .now,
        session: URLSession = .shared
    ) throws -> GrokBotUsageSnapshot? {
        guard let token = readBearerToken(from: authURL, now: now) else {
            return nil
        }

        var request = URLRequest(url: creditsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OpenIsland-Reimagine-grokbot-usage", forHTTPHeaderField: "User-Agent")

        let data = try send(request, session: session)
        return try parse(data: data, source: "cli-chat-proxy /v1/billing?format=credits", capturedAt: now)
    }

    /// Parse a credits-config JSON body. Token is never stored on the snapshot.
    public static func parse(
        data: Data,
        source: String,
        capturedAt: Date = .now
    ) throws -> GrokBotUsageSnapshot? {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            return nil
        }

        let config = (root["config"] as? [String: Any]) ?? root
        let productUsage = config["productUsage"] as? [[String: Any]]
        guard let productUsage else {
            return nil
        }

        let chat = chatProduct(from: productUsage)
        let usedPercentage = min(max(chat.percent ?? 0, 0), 100)
        let currentPeriod = config["currentPeriod"] as? [String: Any]
        let periodStart = date(from: currentPeriod?["start"] ?? config["billingPeriodStart"])
        let resetsAt = date(from: currentPeriod?["end"] ?? config["billingPeriodEnd"])

        return GrokBotUsageSnapshot(
            source: source,
            capturedAt: capturedAt,
            usedPercentage: usedPercentage,
            product: chat.name ?? "GrokChat",
            periodType: string(from: currentPeriod?["type"]),
            periodStart: periodStart,
            resetsAt: resetsAt,
            subscriptionTier: string(from: config["subscriptionTier"])
                ?? string(from: root["subscriptionTier"]),
            overallUsedPercentage: number(from: config["creditUsagePercent"])
        )
    }

    public static func normalizeForCurrentPeriod(
        _ snapshot: GrokBotUsageSnapshot,
        now: Date = .now
    ) -> GrokBotUsageSnapshot {
        guard let resetsAt = snapshot.resetsAt, resetsAt <= now else {
            return snapshot
        }

        var periodStart = snapshot.periodStart ?? resetsAt
        var periodEnd = resetsAt
        var length = periodEnd.timeIntervalSince(periodStart)
        if length <= 0 {
            length = 7 * 86_400
        }

        var guardCount = 0
        while periodEnd <= now, guardCount < 52 {
            periodStart = periodEnd
            periodEnd = periodEnd.addingTimeInterval(length)
            guardCount += 1
        }

        return GrokBotUsageSnapshot(
            source: snapshot.source,
            capturedAt: now,
            usedPercentage: 0,
            product: snapshot.product,
            periodType: snapshot.periodType,
            periodStart: periodStart,
            resetsAt: periodEnd,
            subscriptionTier: snapshot.subscriptionTier,
            overallUsedPercentage: 0
        )
    }

    public static func isChatProductName(_ name: String) -> Bool {
        let folded = name
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        if folded.contains("grokbuild") || folded.contains("grokimagine") {
            return false
        }
        return folded.contains("grokchat")
            || folded.contains("productgrokchat")
            || folded.contains("grokbot")
            || folded == "chat"
    }

    // MARK: - Auth (never log or persist the token)

    static func readBearerToken(from url: URL, now: Date = .now) -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var preferred: (expires: Date, key: String)?
        var fallback: (expires: Date, key: String)?

        for (scope, value) in object {
            guard let entry = value as? [String: Any],
                  let key = entry["key"] as? String,
                  key.count > 20 else {
                continue
            }
            guard let expires = date(from: entry["expires_at"]), expires > now else {
                continue
            }
            let candidate = (expires, key)
            if scope.contains("auth.x.ai") {
                if preferred == nil || expires > preferred!.expires {
                    preferred = candidate
                }
            } else if fallback == nil || expires > fallback!.expires {
                fallback = candidate
            }
        }

        return preferred?.key ?? fallback?.key
    }

    // MARK: - Private

    private static func chatProduct(
        from rows: [[String: Any]]
    ) -> (name: String?, percent: Double?) {
        for row in rows {
            guard let name = string(from: row["product"]),
                  isChatProductName(name) else {
                continue
            }
            return (name, number(from: row["usagePercent"]))
        }
        return (nil, nil)
    }

    private static func send(_ request: URLRequest, session: URLSession) throws -> Data {
        let box = ResponseBox()
        let semaphore = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            box.error = error
            box.data = data
            box.status = (response as? HTTPURLResponse)?.statusCode
            semaphore.signal()
        }
        task.resume()
        let wait = semaphore.wait(timeout: .now() + requestTimeout + 2)
        if wait == .timedOut {
            task.cancel()
            throw GrokBotUsageError.timeout
        }
        if let error = box.error {
            throw error
        }
        guard let status = box.status, (200..<300).contains(status), let data = box.data else {
            throw GrokBotUsageError.httpStatus(box.status ?? -1)
        }
        return data
    }

    private static func writeCache(
        _ snapshot: GrokBotUsageSnapshot,
        to url: URL,
        fileManager: FileManager
    ) throws {
        let dir = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    private static func readCache(
        from url: URL,
        fileManager: FileManager,
        now: Date
    ) throws -> GrokBotUsageSnapshot? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(GrokBotUsageSnapshot.self, from: data)
        if let capturedAt = snapshot.capturedAt,
           now.timeIntervalSince(capturedAt) > maxOfflineCacheAge {
            return nil
        }
        return normalizeForCurrentPeriod(snapshot, now: now)
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

public enum GrokBotUsageError: Error {
    case timeout
    case httpStatus(Int)
}

/// Mutable box so the URLSession callback can hop off the waiter thread.
private final class ResponseBox: @unchecked Sendable {
    var data: Data?
    var status: Int?
    var error: Error?
}
