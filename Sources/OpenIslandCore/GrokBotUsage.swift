import Foundation
import Security
import SQLite3

/// Grok Bot weekly included usage (Cursor "Sand"), not grok.com Chat.
///
/// **G** on the island is Grok CLI overall SuperGrok `creditUsagePercent`.
/// **GB** is the Grok Bot.app / Cursor Sand weekly allowance:
/// `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus`
/// with the local Cursor JWT (`state.vscdb` `cursorAuth/accessToken`).
///
/// That meter is independent of SuperGrok `productUsage.GrokChat`. Chat is a
/// tiny slice of the shared SuperGrok pool (often stuck at 1% while Bot is 8%+).
/// If Sand auth/network fails, GB falls back to the GrokChat slice so the chip
/// does not go blank.
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
        product: String = "GrokBot",
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

    public var isSandMeter: Bool {
        GrokBotUsageLoader.isSandProductName(product)
            || source.localizedCaseInsensitiveContains("GetSandUsageStatus")
            || source.localizedCaseInsensitiveContains("sand")
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
    public static let sandUsageURL = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus"
    )!

    public static let creditsURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!

    public static var defaultAuthURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/auth.json")
    }

    public static var defaultCursorStateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
            )
    }

    public static var defaultCacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenIsland", isDirectory: true)
            .appendingPathComponent("grokbot-chat-usage.json")
    }

    /// Reject extremely old offline cache so a dead token cannot freeze the chip.
    public static let maxOfflineCacheAge: TimeInterval = 7 * 86_400

    public static let requestTimeout: TimeInterval = 8

    public static let keychainTokenService = "cursor-access-token"
    public static let keychainTokenAccount = "cursor-user"

    /// Live Sand meter first, then last good Sand cache, then SuperGrok Chat
    /// slice, then any remaining cache.
    public static func load(
        authURL: URL = defaultAuthURL,
        cursorStateURL: URL = defaultCursorStateURL,
        cacheURL: URL = defaultCacheURL,
        fileManager: FileManager = .default,
        now: Date = .now,
        session: URLSession = .shared
    ) throws -> GrokBotUsageSnapshot? {
        if let liveSand = try? fetchSandSnapshot(
            cursorStateURL: cursorStateURL,
            now: now,
            session: session
        ) {
            let normalized = normalizeForCurrentPeriod(liveSand, now: now)
            try? writeCache(normalized, to: cacheURL, fileManager: fileManager)
            return normalized
        }

        if let cached = try? readCache(from: cacheURL, fileManager: fileManager, now: now),
           cached.isSandMeter {
            return cached
        }

        if let liveChat = try? fetchLiveSnapshot(
            authURL: authURL,
            now: now,
            session: session
        ) {
            let normalized = normalizeForCurrentPeriod(liveChat, now: now)
            try? writeCache(normalized, to: cacheURL, fileManager: fileManager)
            return normalized
        }

        return try? readCache(from: cacheURL, fileManager: fileManager, now: now)
    }

    public static func fetchSandSnapshot(
        cursorStateURL: URL = defaultCursorStateURL,
        now: Date = .now,
        session: URLSession = .shared
    ) throws -> GrokBotUsageSnapshot? {
        guard let token = readCursorAccessToken(from: cursorStateURL, now: now) else {
            return nil
        }

        var request = URLRequest(url: sandUsageURL)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("OpenIsland-Reimagine-grokbot-usage", forHTTPHeaderField: "User-Agent")

        let data = try send(request, session: session)
        return try parseSand(data: data, capturedAt: now)
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

    /// Cursor Sand `GetSandUsageStatus` JSON. Token is never stored.
    public static func parseSand(
        data: Data,
        capturedAt: Date = .now
    ) throws -> GrokBotUsageSnapshot? {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            return nil
        }

        if let hasLimit = root["hasNonZeroIncludedLimit"] as? Bool, hasLimit == false {
            return nil
        }

        guard let usedPercentage = number(from: root["usagePercent"] ?? root["usage_percent"]) else {
            return nil
        }

        let periodStart = date(
            from: root["currentPeriodStart"] ?? root["current_period_start"]
        )
        let resetsAt = date(
            from: root["nextResetTimestampUtc"] ?? root["next_reset_timestamp_utc"]
        )
        let plan = string(from: root["grokPlanLabel"] ?? root["grok_plan_label"])
            ?? string(from: root["includedUsageSuperGrokPlan"] ?? root["included_usage_super_grok_plan"])

        return GrokBotUsageSnapshot(
            source: "cursor api2 GetSandUsageStatus",
            capturedAt: capturedAt,
            usedPercentage: min(max(usedPercentage, 0), 100),
            product: "GrokBot",
            periodType: nil,
            periodStart: periodStart,
            resetsAt: resetsAt,
            subscriptionTier: plan,
            overallUsedPercentage: nil
        )
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
            overallUsedPercentage: snapshot.isSandMeter ? nil : 0
        )
    }

    public static func isChatProductName(_ name: String) -> Bool {
        let folded = foldProductName(name)
        if folded.contains("grokbuild") || folded.contains("grokimagine") || folded.contains("grokbot") {
            return false
        }
        return folded.contains("grokchat")
            || folded.contains("productgrokchat")
            || folded == "chat"
    }

    public static func isSandProductName(_ name: String) -> Bool {
        let folded = foldProductName(name)
        return folded.contains("grokbot") || folded == "sand" || folded.contains("sandusage")
    }

    // MARK: - Cursor auth (never log or persist the token)

    static func readCursorAccessToken(
        from cursorStateURL: URL,
        now: Date = .now
    ) -> String? {
        if let token = readCursorStateToken(from: cursorStateURL),
           isUsableAccessToken(token, now: now) {
            return token
        }
        if let token = readKeychainToken(
            service: keychainTokenService,
            account: keychainTokenAccount
        ), isUsableAccessToken(token, now: now) {
            return token
        }
        return nil
    }

    static func readCursorStateToken(from url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
            if db != nil { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 60)

        let sql = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }
        guard sqlite3_column_type(stmt, 0) != SQLITE_NULL else {
            return nil
        }

        let byteCount = Int(sqlite3_column_bytes(stmt, 0))
        guard byteCount > 0, let bytes = sqlite3_column_blob(stmt, 0) else {
            return nil
        }
        let data = Data(bytes: bytes, count: byteCount)
        return decodeTokenData(data)
    }

    static func readKeychainToken(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return decodeTokenData(data)
    }

    static func isUsableAccessToken(_ token: String, now: Date) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 20 else { return false }
        return jwtExpiry(of: trimmed).map { $0 > now.addingTimeInterval(60) } ?? true
    }

    static func jwtExpiry(of token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - base64.count % 4) % 4
        if pad > 0 {
            base64 += String(repeating: "=", count: pad)
        }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let exp = object["exp"] as? Double {
            return Date(timeIntervalSince1970: exp)
        }
        if let exp = object["exp"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(exp))
        }
        return nil
    }

    // MARK: - Grok CLI auth (never log or persist the token)

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

    private static func foldProductName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

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
        if !snapshot.isSandMeter,
           let existing = try? readCache(from: url, fileManager: fileManager, now: snapshot.capturedAt ?? .now),
           existing.isSandMeter {
            return
        }

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

    private static func decodeTokenData(_ data: Data) -> String? {
        let encodings: [String.Encoding] = [.utf8, .utf16LittleEndian, .utf16]
        for encoding in encodings {
            if var text = String(data: data, encoding: encoding) {
                if text.hasPrefix("\u{FEFF}") {
                    text.removeFirst()
                }
                text = text.replacingOccurrences(of: "\0", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if text.count > 20 {
                    return text
                }
            }
        }
        return nil
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
