import Foundation

/// OpenCode island usage is **GitHub Copilot premium quota** (scheme B),
/// because this workspace’s default OpenCode model is `github-copilot/…`.
/// Source: `gh api /copilot_internal/user` → `quota_snapshots.premium_interactions`.
///
/// **Important (Business seats):** when `unlimited == true` and `entitlement == 0`,
/// GitHub keeps `percent_remaining` at **100** even after real spend. The honest
/// signal is `credits_used` vs the plan’s included premium allowance (Business=300).
public struct OpenCodeUsageSnapshot: Equatable, Codable, Sendable {
    public var source: String
    public var capturedAt: Date?
    public var usedPercentage: Double
    public var remainingPercentage: Double
    public var isUnlimited: Bool
    public var planType: String?
    public var quotaID: String?
    public var creditsUsed: Double?
    /// Resolved denominator for % (API entitlement, or plan default e.g. 300).
    public var creditsEntitlement: Double?
    /// How used% was derived: `percent_remaining` | `credits_vs_entitlement` | `credits_vs_plan_default`.
    public var usageBasis: String?
    public var resetsAt: Date?

    public init(
        source: String,
        capturedAt: Date? = nil,
        usedPercentage: Double,
        remainingPercentage: Double,
        isUnlimited: Bool,
        planType: String? = nil,
        quotaID: String? = nil,
        creditsUsed: Double? = nil,
        creditsEntitlement: Double? = nil,
        usageBasis: String? = nil,
        resetsAt: Date? = nil
    ) {
        self.source = source
        self.capturedAt = capturedAt
        self.usedPercentage = usedPercentage
        self.remainingPercentage = remainingPercentage
        self.isUnlimited = isUnlimited
        self.planType = planType
        self.quotaID = quotaID
        self.creditsUsed = creditsUsed
        self.creditsEntitlement = creditsEntitlement
        self.usageBasis = usageBasis
        self.resetsAt = resetsAt
    }

    public var roundedUsedPercentage: Int {
        Int(usedPercentage.rounded())
    }

    /// Monthly Copilot seats → `mo`; otherwise day-span label like Grok/Codex.
    public var windowLabel: String {
        guard let resetsAt else {
            return "mo"
        }
        let days = max(1, Int(ceil(resetsAt.timeIntervalSinceNow / 86_400)))
        if days >= 25 {
            return "mo"
        }
        return "\(days)d"
    }
}

public enum OpenCodeUsageLoader {
    public static var defaultCacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenIsland", isDirectory: true)
            .appendingPathComponent("opencode-copilot-usage.json")
    }

    private static let ghCandidates = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh",
    ]

    /// Reject extremely old offline cache (days) so a long-dead `gh` path cannot
    /// freeze the notch forever. Mid-period multi-hour cache is still OK.
    public static let maxOfflineCacheAge: TimeInterval = 7 * 86_400

    /// Live fetch via `gh`, fall back to last good cache. Returns `nil` only when
    /// both live and cache are unavailable.
    ///
    /// **Period-reset guard:** when the cached `resetsAt` is already past (monthly
    /// Copilot window rolled over) and live fetch is unavailable, do **not** keep
    /// showing pre-reset `credits_used` — same class of bug as Codex C after reset.
    ///
    /// **Stale-live guard:** GitHub may bump `quota_reset_date` to the next month
    /// while still reporting last month's `credits_used` (same class as Grok
    /// omitting `creditUsagePercent` after reset). Detect that and surface 0.
    public static func load(
        cacheURL: URL = defaultCacheURL,
        fileManager: FileManager = .default,
        now: Date = .now
    ) throws -> OpenCodeUsageSnapshot? {
        let previous = try? decodeCache(from: cacheURL, fileManager: fileManager)
        if let live = try? fetchLiveSnapshot() {
            let reconciled = reconcileStaleLiveSnapshot(live, previous: previous, now: now)
            let normalized = normalizeForCurrentPeriod(reconciled, now: now)
            try? writeCache(normalized, to: cacheURL, fileManager: fileManager)
            return normalized
        }
        return try? readCache(from: cacheURL, fileManager: fileManager, now: now)
    }

    /// Drop last-period spend when a live fetch is clearly from the old window.
    public static func reconcileStaleLiveSnapshot(
        _ live: OpenCodeUsageSnapshot,
        previous: OpenCodeUsageSnapshot?,
        now: Date = .now
    ) -> OpenCodeUsageSnapshot {
        if isCapturedBeforeCurrentWindow(live) {
            return zeroed(live, now: now, basis: "stale_timestamp")
        }

        guard let previous,
              let liveReset = live.resetsAt,
              let previousReset = previous.resetsAt,
              liveReset > previousReset.addingTimeInterval(12 * 3_600),
              let liveCredits = live.creditsUsed,
              let previousCredits = previous.creditsUsed,
              previousCredits > 0,
              liveCredits + 0.5 >= previousCredits else {
            return live
        }

        return zeroed(live, now: now, basis: "window_rolled_stale_credits")
    }

    /// `timestamp_utc` still sitting in the previous month after `resetsAt`
    /// moved forward — the credits number is leftover, not new spend.
    public static func isCapturedBeforeCurrentWindow(_ snapshot: OpenCodeUsageSnapshot) -> Bool {
        guard let resetsAt = snapshot.resetsAt,
              let capturedAt = snapshot.capturedAt else {
            return false
        }

        let calendar = Calendar(identifier: .gregorian)
        let windowStart = calendar.date(byAdding: .month, value: -1, to: resetsAt)
            ?? resetsAt.addingTimeInterval(-30 * 86_400)
        // 6h slack so a snapshot taken just after the previous reset is kept.
        return capturedAt.addingTimeInterval(6 * 3_600) < windowStart
    }

    private static func zeroed(
        _ snapshot: OpenCodeUsageSnapshot,
        now: Date,
        basis: String
    ) -> OpenCodeUsageSnapshot {
        OpenCodeUsageSnapshot(
            source: snapshot.source,
            capturedAt: now,
            usedPercentage: 0,
            remainingPercentage: 100,
            isUnlimited: snapshot.isUnlimited,
            planType: snapshot.planType,
            quotaID: snapshot.quotaID,
            creditsUsed: 0,
            creditsEntitlement: snapshot.creditsEntitlement
                ?? planDefaultPremiumAllowance(snapshot.planType),
            usageBasis: basis,
            resetsAt: snapshot.resetsAt
        )
    }

    /// When the quota window end is in the past, surface a post-reset zero-spend
    /// snapshot instead of a frozen pre-reset credit total.
    public static func normalizeForCurrentPeriod(
        _ snapshot: OpenCodeUsageSnapshot,
        now: Date = .now
    ) -> OpenCodeUsageSnapshot {
        guard let resetsAt = snapshot.resetsAt, resetsAt <= now else {
            return snapshot
        }

        let nextReset = advancedResetDate(from: resetsAt, past: now)
        return OpenCodeUsageSnapshot(
            source: snapshot.source,
            capturedAt: now,
            usedPercentage: 0,
            remainingPercentage: 100,
            isUnlimited: snapshot.isUnlimited,
            planType: snapshot.planType,
            quotaID: snapshot.quotaID,
            creditsUsed: 0,
            creditsEntitlement: snapshot.creditsEntitlement
                ?? planDefaultPremiumAllowance(snapshot.planType),
            usageBasis: "period_reset",
            resetsAt: nextReset
        )
    }

    /// Advance a monthly (or other) reset date until it is in the future.
    public static func advancedResetDate(from resetsAt: Date, past now: Date) -> Date {
        var cursor = resetsAt
        var guardCount = 0
        // Prefer calendar months for GitHub monthly seats; fall back to +30d.
        let calendar = Calendar(identifier: .gregorian)
        while cursor <= now, guardCount < 24 {
            if let next = calendar.date(byAdding: .month, value: 1, to: cursor) {
                cursor = next
            } else {
                cursor = cursor.addingTimeInterval(30 * 86_400)
            }
            guardCount += 1
        }
        return cursor
    }

    public static func fetchLiveSnapshot() throws -> OpenCodeUsageSnapshot? {
        guard let gh = resolveGhExecutable() else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = ["api", "/copilot_internal/user"]
        process.environment = processEnvironment()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        _ = stderr.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0, data.isEmpty == false else {
            return nil
        }

        return try parse(data: data, source: "gh api /copilot_internal/user")
    }

    public static func parse(data: Data, source: String) throws -> OpenCodeUsageSnapshot? {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            return nil
        }

        let snapshots = root["quota_snapshots"] as? [String: Any]
        let premium = snapshots?["premium_interactions"] as? [String: Any]
        // Prefer premium interactions (OpenCode chat-class usage). Fall back to chat.
        let window = premium ?? (snapshots?["chat"] as? [String: Any])
        guard let window else {
            return nil
        }

        let planType = string(from: root["copilot_plan"])
        let percentRemaining = number(from: window["percent_remaining"]) ?? 100
        let unlimited = bool(from: window["unlimited"]) ?? false
        let creditsUsed = number(from: window["credits_used"]) ?? 0
        let apiEntitlement = number(from: window["entitlement"]) ?? 0
        // Some seats put remaining absolute credits here (0 when unlimited/no budget).
        let absoluteRemaining = number(from: window["remaining"]) ?? number(from: window["quota_remaining"])

        let metrics = resolveUsageMetrics(
            planType: planType,
            unlimited: unlimited,
            percentRemaining: percentRemaining,
            creditsUsed: creditsUsed,
            apiEntitlement: apiEntitlement,
            absoluteRemaining: absoluteRemaining
        )

        let resetsAt =
            date(from: root["quota_reset_date_utc"])
            ?? date(from: root["quota_reset_date"])
            ?? date(from: window["quota_reset_at"])

        let capturedAt =
            date(from: window["timestamp_utc"])
            ?? Date()

        return OpenCodeUsageSnapshot(
            source: source,
            capturedAt: capturedAt,
            usedPercentage: metrics.usedPercentage,
            remainingPercentage: metrics.remainingPercentage,
            isUnlimited: unlimited,
            planType: planType,
            quotaID: string(from: window["quota_id"]),
            creditsUsed: creditsUsed,
            creditsEntitlement: metrics.creditsEntitlement,
            usageBasis: metrics.usageBasis,
            resetsAt: resetsAt
        )
    }

    /// Resolve used% for individual *and* business seats.
    ///
    /// Business (`unlimited=true`, `entitlement=0`) always reports
    /// `percent_remaining=100`; use `credits_used` / plan default (300) instead.
    static func resolveUsageMetrics(
        planType: String?,
        unlimited: Bool,
        percentRemaining: Double,
        creditsUsed: Double,
        apiEntitlement: Double,
        absoluteRemaining: Double?
    ) -> (usedPercentage: Double, remainingPercentage: Double, creditsEntitlement: Double?, usageBasis: String) {
        // 1) Explicit entitlement from API (budget / included pack).
        if apiEntitlement > 0 {
            let used = (creditsUsed / apiEntitlement) * 100
            return (
                usedPercentage: min(max(used, 0), 999),
                remainingPercentage: min(max(100 - used, 0), 100),
                creditsEntitlement: apiEntitlement,
                usageBasis: "credits_vs_entitlement"
            )
        }

        // 2) Absolute remaining + used imply entitlement.
        if let absoluteRemaining, absoluteRemaining > 0, creditsUsed >= 0 {
            let entitlement = creditsUsed + absoluteRemaining
            if entitlement > 0 {
                let used = (creditsUsed / entitlement) * 100
                return (
                    usedPercentage: min(max(used, 0), 999),
                    remainingPercentage: min(max(100 - used, 0), 100),
                    creditsEntitlement: entitlement,
                    usageBasis: "credits_vs_entitlement"
                )
            }
        }

        // 3) Limited seat with a real percent_remaining (not the Business "always 100" lie).
        let percentLooksLimited = !unlimited && (percentRemaining < 99.5 || creditsUsed <= 0)
        if percentLooksLimited {
            let used = min(max(100 - percentRemaining, 0), 100)
            return (
                usedPercentage: used,
                remainingPercentage: min(max(percentRemaining, 0), 100),
                creditsEntitlement: nil,
                usageBasis: "percent_remaining"
            )
        }

        // 4) Business/Enterprise unlimited seat: use plan-included premium requests.
        //    Official: Business 300 / Enterprise 1000 / Pro 300 / Pro+ 1500 per month.
        if creditsUsed > 0, let planDefault = planDefaultPremiumAllowance(planType) {
            let used = (creditsUsed / planDefault) * 100
            return (
                usedPercentage: min(max(used, 0), 999),
                remainingPercentage: min(max(100 - used, 0), 100),
                creditsEntitlement: planDefault,
                usageBasis: "credits_vs_plan_default"
            )
        }

        // 5) Truly unused unlimited seat.
        if unlimited {
            return (
                usedPercentage: 0,
                remainingPercentage: 100,
                creditsEntitlement: planDefaultPremiumAllowance(planType),
                usageBasis: "unlimited_zero"
            )
        }

        let used = min(max(100 - percentRemaining, 0), 100)
        return (
            usedPercentage: used,
            remainingPercentage: min(max(percentRemaining, 0), 100),
            creditsEntitlement: nil,
            usageBasis: "percent_remaining"
        )
    }

    /// Included premium-request allowance per GitHub plan (per user / month).
    static func planDefaultPremiumAllowance(_ planType: String?) -> Double? {
        switch planType?.lowercased() {
        case "business", "copilot_for_business", "copilot_business":
            return 300
        case "enterprise", "copilot_enterprise":
            return 1_000
        case "pro", "individual", "copilot_pro":
            return 300
        case "pro_plus", "pro+", "copilot_pro_plus":
            return 1_500
        case "free", "copilot_free":
            return 50
        default:
            // access_type_sku often says business even when plan is "business"
            if planType?.localizedCaseInsensitiveContains("business") == true {
                return 300
            }
            if planType?.localizedCaseInsensitiveContains("enterprise") == true {
                return 1_000
            }
            return 300 // safe default for seat quotas we see in the wild
        }
    }

    // MARK: - Cache

    private static func writeCache(
        _ snapshot: OpenCodeUsageSnapshot,
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
        now: Date = .now
    ) throws -> OpenCodeUsageSnapshot? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        guard let snapshot = try decodeCache(from: url, fileManager: fileManager) else {
            return nil
        }

        if let capturedAt = snapshot.capturedAt,
           now.timeIntervalSince(capturedAt) > maxOfflineCacheAge {
            // Dead cache: better show empty than multi-week-old spend.
            return nil
        }

        return normalizeForCurrentPeriod(snapshot, now: now)
    }

    private static func decodeCache(
        from url: URL,
        fileManager: FileManager
    ) throws -> OpenCodeUsageSnapshot? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OpenCodeUsageSnapshot.self, from: data)
    }

    // MARK: - Process helpers

    private static func resolveGhExecutable() -> String? {
        for path in ghCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["gh"]
        process.environment = processEnvironment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private static func processEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        env["HOME"] = home
        let pathParts = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            env["PATH"] ?? "",
        ]
        env["PATH"] = pathParts.filter { !$0.isEmpty }.joined(separator: ":")
        // GUI apps often lack interactive shell auth path; gh reads hosts.yml under HOME.
        if env["GH_CONFIG_DIR"] == nil {
            env["GH_CONFIG_DIR"] = "\(home)/.config/gh"
        }
        return env
    }

    // MARK: - JSON helpers

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

    private static func bool(from value: Any?) -> Bool? {
        switch value {
        case let value as Bool:
            value
        case let value as NSNumber:
            value.boolValue
        case let value as String:
            ["1", "true", "yes"].contains(value.lowercased())
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
        switch value {
        case let value as NSNumber:
            let n = value.doubleValue
            // 0 / tiny = unset; large = unix seconds
            if n <= 0 { return nil }
            if n > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: n / 1000)
            }
            return Date(timeIntervalSince1970: n)
        case let value as String:
            if let seconds = Double(value), seconds > 1_000_000_000 {
                return Date(timeIntervalSince1970: seconds)
            }
            // Date-only: 2026-09-01
            if value.count == 10, value.contains("-") {
                let formatter = DateFormatter()
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.date(from: value)
            }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return plain.date(from: value)
        default:
            return nil
        }
    }
}
