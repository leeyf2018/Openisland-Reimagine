import Foundation

/// Read-only discovery of Grok Build TUI sessions from local state files.
///
/// Safety notes:
/// - Never writes to `~/.grok` or agent hook configs.
/// - Only reads identity fields (session_id / pid / cwd) — not chat history.
/// - Failures return empty arrays (fail-open for Grok; other tools unaffected).
public struct GrokActiveSessionRecord: Equatable, Sendable {
    public var sessionID: String
    public var pid: Int
    public var cwd: String?
    public var openedAt: Date?

    public init(sessionID: String, pid: Int, cwd: String? = nil, openedAt: Date? = nil) {
        self.sessionID = sessionID
        self.pid = pid
        self.cwd = cwd
        self.openedAt = openedAt
    }
}

/// Lightweight presentation fields for the island row (not full chat).
public struct GrokSessionPresentation: Equatable, Sendable {
    /// Short title (from `generated_title` / `session_summary`).
    public var title: String?
    /// One-line activity hint (last user prompt when available).
    public var activitySummary: String?
    /// Full-ish last assistant reply (for completion digest, not full chat dump).
    public var lastAssistantMessage: String?
    /// Pre-built 3-bullet completion digest for the island card.
    public var completionDigest: String?
    /// True when the latest turn appears finished (assistant replied; waiting for user).
    public var turnAppearsComplete: Bool
    /// Stable key for the latest completed turn (dedupe completion sounds).
    public var turnCompletionKey: String?

    public init(
        title: String? = nil,
        activitySummary: String? = nil,
        lastAssistantMessage: String? = nil,
        completionDigest: String? = nil,
        turnAppearsComplete: Bool = false,
        turnCompletionKey: String? = nil
    ) {
        self.title = title
        self.activitySummary = activitySummary
        self.lastAssistantMessage = lastAssistantMessage
        self.completionDigest = completionDigest
        self.turnAppearsComplete = turnAppearsComplete
        self.turnCompletionKey = turnCompletionKey
    }
}

/// Stored on `AgentSession.grokMetadata` so the island "You: …" / completion
/// lines resolve via the same paths Codex uses.
public struct GrokSessionMetadata: Equatable, Codable, Sendable {
    public var sessionTitle: String?
    public var initialUserPrompt: String?
    public var lastUserPrompt: String?
    public var lastAssistantMessage: String?
    public var completionDigest: String?

    public init(
        sessionTitle: String? = nil,
        initialUserPrompt: String? = nil,
        lastUserPrompt: String? = nil,
        lastAssistantMessage: String? = nil,
        completionDigest: String? = nil
    ) {
        self.sessionTitle = sessionTitle
        self.initialUserPrompt = initialUserPrompt
        self.lastUserPrompt = lastUserPrompt
        self.lastAssistantMessage = lastAssistantMessage
        self.completionDigest = completionDigest
    }

    public var isEmpty: Bool {
        sessionTitle == nil
            && initialUserPrompt == nil
            && lastUserPrompt == nil
            && lastAssistantMessage == nil
            && completionDigest == nil
    }
}

public struct GrokActiveSessionDiscovery: Sendable {
    public static let defaultActiveSessionsURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".grok", isDirectory: true)
        .appendingPathComponent("active_sessions.json")

    private let activeSessionsURL: URL
    private let processAliveCheck: @Sendable (Int) -> Bool

    public init(
        activeSessionsURL: URL = GrokActiveSessionDiscovery.defaultActiveSessionsURL,
        processAliveCheck: @escaping @Sendable (Int) -> Bool = { pid in
            kill(pid_t(pid), 0) == 0
        }
    ) {
        self.activeSessionsURL = activeSessionsURL
        self.processAliveCheck = processAliveCheck
    }

    /// Loads active Grok sessions. Optionally drop rows whose PID is no longer alive.
    public func loadActiveSessions(requireAliveProcess: Bool = true) -> [GrokActiveSessionRecord] {
        let path = activeSessionsURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            return []
        }

        guard let data = try? Data(contentsOf: activeSessionsURL) else {
            return []
        }

        guard let raw = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        let items: [[String: Any]]
        if let array = raw as? [[String: Any]] {
            items = array
        } else if let dict = raw as? [String: Any],
                  let array = dict["sessions"] as? [[String: Any]] {
            items = array
        } else {
            return []
        }

        var records: [GrokActiveSessionRecord] = []
        records.reserveCapacity(items.count)

        for item in items {
            guard let sessionID = stringValue(item["session_id"]) ?? stringValue(item["sessionId"]),
                  !sessionID.isEmpty else {
                continue
            }

            guard let pid = intValue(item["pid"]), pid > 0 else {
                continue
            }

            if requireAliveProcess, !processAliveCheck(pid) {
                continue
            }

            let cwd = stringValue(item["cwd"])
            let openedAt = dateValue(item["opened_at"] ?? item["openedAt"])

            records.append(
                GrokActiveSessionRecord(
                    sessionID: sessionID,
                    pid: pid,
                    cwd: cwd,
                    openedAt: openedAt
                )
            )
        }

        return records
    }

    /// Lookup map pid → newest session record.
    public func recordsByPID(requireAliveProcess: Bool = true) -> [Int: GrokActiveSessionRecord] {
        Self.newestRecordsByPID(loadActiveSessions(requireAliveProcess: requireAliveProcess))
    }

    /// A live Grok PID represents one TUI even if the upstream registry leaves
    /// several historical rows for that PID. Prefer the newest openedAt value;
    /// array order is the fallback when timestamps are absent.
    public static func newestRecordsByPID(
        _ records: [GrokActiveSessionRecord]
    ) -> [Int: GrokActiveSessionRecord] {
        var map: [Int: GrokActiveSessionRecord] = [:]
        for record in records {
            guard let existing = map[record.pid] else {
                map[record.pid] = record
                continue
            }

            let shouldReplace: Bool
            switch (existing.openedAt, record.openedAt) {
            case let (existingDate?, recordDate?):
                shouldReplace = recordDate >= existingDate
            case (nil, _):
                shouldReplace = true
            case (_?, nil):
                shouldReplace = false
            }
            if shouldReplace {
                map[record.pid] = record
            }
        }
        return map
    }

    /// Recovers registry-orphaned Grok sessions only when one live PID has one
    /// unambiguous session directory open under `~/.grok/sessions/…`.
    ///
    /// This deliberately rejects ambiguous PIDs instead of guessing from cwd or
    /// inventing a `grok-pid-*` identity. Grok can retain descriptors for older
    /// sessions, so multiple distinct session IDs are not safe to recover.
    public static func recoverOrphanedSessions(
        activePIDs: [Int],
        lsofOutputByPID: [Int: String],
        excludingSessionIDs: Set<String> = []
    ) -> [GrokActiveSessionRecord] {
        var recovered: [GrokActiveSessionRecord] = []
        var claimedSessionIDs = excludingSessionIDs

        for pid in activePIDs.sorted() {
            guard pid > 0,
                  let output = lsofOutputByPID[pid],
                  let record = orphanedSessionRecord(pid: pid, lsofOutput: output),
                  claimedSessionIDs.insert(record.sessionID).inserted else {
                continue
            }
            recovered.append(record)
        }

        return recovered
    }

    private static func orphanedSessionRecord(
        pid: Int,
        lsofOutput: String
    ) -> GrokActiveSessionRecord? {
        let marker = "/.grok/sessions/"
        var identities: [String: String] = [:]

        for line in lsofOutput.split(whereSeparator: \.isNewline) {
            guard line.first == "n" else { continue }
            let path = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let markerRange = path.range(of: marker) else { continue }

            let relativePath = path[markerRange.upperBound...]
            let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
            guard components.count >= 3 else { continue }

            let encodedCWD = String(components[0])
            let sessionID = String(components[1])
            guard UUID(uuidString: sessionID) != nil else { continue }

            let evidencePath = components.dropFirst(2).joined(separator: "/")
            let hasSessionSpecificEvidence = evidencePath == "events.jsonl"
                || evidencePath == "chat_history.jsonl"
                || evidencePath == "hunk_records.jsonl"
                || evidencePath.hasPrefix("terminal/")
            guard hasSessionSpecificEvidence else { continue }

            guard let cwd = encodedCWD.removingPercentEncoding, !cwd.isEmpty else { continue }
            identities[sessionID] = cwd
        }

        guard identities.count == 1,
              let (sessionID, cwd) = identities.first else {
            return nil
        }

        return GrokActiveSessionRecord(sessionID: sessionID, pid: pid, cwd: cwd)
    }

    /// Reads only small local files under `~/.grok/sessions/…` for island UI text.
    /// Does **not** load full `chat_history` into memory — only a bounded tail
    /// when resolving the latest user prompt / turn state.
    public func loadPresentation(sessionID: String, cwd: String?) -> GrokSessionPresentation {
        guard let sessionDirectory = sessionDirectoryURL(sessionID: sessionID, cwd: cwd) else {
            return GrokSessionPresentation()
        }

        var title: String?
        var activityFromSummary: String?

        let summaryURL = sessionDirectory.appendingPathComponent("summary.json")
        if let data = try? Data(contentsOf: summaryURL),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            title = firstNonEmpty(
                stringValue(object["generated_title"]),
                stringValue(object["session_summary"])
            )
            activityFromSummary = firstNonEmpty(
                stringValue(object["session_summary"]),
                stringValue(object["generated_title"])
            )
        }

        let history = scanChatHistoryTail(in: sessionDirectory)
        // Prefer real `<user_query>` text; never fall back to session title for
        // the "You:" line (that looked like a broken summary in the UI).
        let lastUser = history.lastUserQuery ?? history.lastUserAny
        let activity = lastUser
        let cleanedActivity = activity.map { Self.truncateOneLine(Self.cleanUserPrompt($0)) }
            .flatMap { $0.isEmpty ? nil : $0 }

        let assistantBody = history.lastAssistantMessage
        // Build a 3-bullet completion digest from the assistant reply — this is
        // what the island notification must show (not the user prompt).
        let digest: String?
        if let assistantBody, !assistantBody.isEmpty {
            digest = Self.buildCompletionDigest(from: assistantBody, limit: 3)
        } else {
            digest = nil
        }

        let turnKey: String?
        if let user = cleanedActivity, history.turnAppearsComplete {
            let assistantHash = assistantBody?.hashValue ?? history.lastAssistantPreview?.hashValue ?? 0
            turnKey = "\(sessionID)|\(user.hashValue)|\(assistantHash)"
        } else {
            turnKey = nil
        }

        return GrokSessionPresentation(
            title: title.map { Self.truncateOneLine($0) },
            // Never fall back to session title here — that produced a fake
            // "You: Open-Vibe-Island …" line identical to the headline.
            activitySummary: cleanedActivity,
            lastAssistantMessage: assistantBody.map { Self.truncateOneLine($0, limit: 2_000) },
            completionDigest: digest,
            turnAppearsComplete: history.turnAppearsComplete,
            turnCompletionKey: turnKey
        )
    }

    /// Build `1. …\n2. …\n3. …` from an assistant completion body.
    public static func buildCompletionDigest(from text: String, limit: Int = 3) -> String? {
        let bullets = extractOutcomeBullets(from: text, limit: limit)
        guard !bullets.isEmpty else { return nil }
        return bullets
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
    }

    /// Prefer markdown/list outcome lines; fall back to short sentences.
    public static func extractOutcomeBullets(from text: String, limit: Int = 3) -> [String] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var bullets: [String] = []
        let bulletPrefix = try? NSRegularExpression(pattern: #"^([\-•*]|\d+[\.\)])\s+"#)

        for line in lines {
            if line.hasPrefix("#") { continue }
            if line == "---" || line == "***" { continue }
            let lowered = line.lowercased()
            if lowered == "已完成" || lowered == "done" || lowered == "completed" { continue }
            if lowered.hasPrefix("worked for ") { continue }
            if lowered.hasPrefix("交接材料") || lowered.hasPrefix("handoff") { continue }
            if lowered.hasPrefix("需要你") || lowered.hasPrefix("grok 可以") { continue }
            if lowered.hasPrefix("原因") || lowered.hasPrefix("不做的影响") { continue }

            var candidate = line
            if let regex = bulletPrefix {
                let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
                candidate = regex.stringByReplacingMatches(
                    in: candidate, options: [], range: range, withTemplate: ""
                )
            }

            let looksUseful =
                candidate.contains("已")
                || candidate.contains("完成")
                || candidate.contains("通过")
                || candidate.contains("创建")
                || candidate.contains("推送")
                || candidate.contains("部署")
                || candidate.contains("写入")
                || candidate.contains("更新")
                || candidate.contains("修复")
                || candidate.contains("http")
                || candidate.contains("/")
                || candidate.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) != nil

            guard looksUseful else { continue }
            let trimmed = truncateOneLine(candidate, limit: 70)
            guard trimmed.count >= 6 else { continue }
            if bullets.contains(where: { $0 == trimmed }) { continue }
            bullets.append(trimmed)
            if bullets.count >= limit { break }
        }

        if bullets.isEmpty {
            let collapsed = text
                .replacingOccurrences(of: "\n+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = collapsed
                .components(separatedBy: CharacterSet(charactersIn: "。；;\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 10 && !$0.lowercased().hasPrefix("you:") }
            for part in parts.prefix(limit) {
                bullets.append(truncateOneLine(part, limit: 70))
            }
        }
        return bullets
    }

    private struct ChatHistoryTailScan: Sendable {
        var lastUserQuery: String?
        var lastUserAny: String?
        var lastAssistantPreview: String?
        /// Longer assistant body (bounded) for digest extraction.
        var lastAssistantMessage: String?
        var turnAppearsComplete: Bool
    }

    private func scanChatHistoryTail(in sessionDirectory: URL) -> ChatHistoryTailScan {
        let historyURL = sessionDirectory.appendingPathComponent("chat_history.jsonl")
        guard let handle = try? FileHandle(forReadingFrom: historyURL) else {
            return ChatHistoryTailScan(turnAppearsComplete: false)
        }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        // Large sessions bury the last real user turn far above the last 48KB
        // of tool/assistant noise — scan up to 1.5MB from the end.
        let maxTail: UInt64 = 1_500_000
        let start = fileSize > maxTail ? fileSize - maxTail : 0
        do {
            try handle.seek(toOffset: start)
        } catch {
            return ChatHistoryTailScan(turnAppearsComplete: false)
        }
        guard let data = try? handle.readToEnd(), !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else {
            return ChatHistoryTailScan(turnAppearsComplete: false)
        }

        var lastUserQuery: String?
        var lastUserAny: String?
        var lastAssistantPreview: String?
        var lastAssistantMessage: String?
        var lastRole: String?
        // Accumulate consecutive assistant text chunks for the latest turn.
        var assistantBuffer: [String] = []

        for line in text.split(whereSeparator: \.isNewline) {
            guard let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let role = (stringValue(object["role"]) ?? stringValue(object["type"]) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            if role == "user" || role == "human" {
                let raw = extractTextContent(from: object)
                guard let raw, !raw.isEmpty else { continue }
                if Self.isNoiseUserMessage(raw) {
                    continue
                }
                // New user turn — flush previous assistant buffer as completed turn.
                if !assistantBuffer.isEmpty {
                    let joined = assistantBuffer.joined(separator: "\n")
                    lastAssistantMessage = String(joined.prefix(6_000))
                    lastAssistantPreview = String(joined.prefix(200))
                    assistantBuffer = []
                }
                lastUserAny = raw
                lastRole = "user"
                if raw.contains("<user_query>") || raw.contains("user_query") {
                    lastUserQuery = raw
                }
            } else if role == "assistant" {
                if let raw = extractTextContent(from: object), !raw.isEmpty {
                    assistantBuffer.append(raw)
                    lastAssistantPreview = String(raw.prefix(200))
                }
                // Grok often emits assistant text + tool_calls in one row. That is
                // still mid-turn — treating it as complete caused green-check /
                // completion-card flashes while tools were still running.
                if Self.assistantHasPendingToolCalls(object) {
                    lastRole = "tool"
                } else if extractTextContent(from: object) != nil {
                    lastRole = "assistant"
                }
            } else if role == "tool" || role == "tool_result" || role == "tool_use" {
                lastRole = "tool"
            } else if role == "reasoning" {
                lastRole = "reasoning"
            }
        }

        if !assistantBuffer.isEmpty {
            let joined = assistantBuffer.joined(separator: "\n")
            lastAssistantMessage = String(joined.prefix(6_000))
            lastAssistantPreview = String(joined.prefix(200))
        }

        // Turn complete when we have a user turn and the latest meaningful
        // role is assistant (not tool/reasoning still running).
        let turnAppearsComplete = (lastUserQuery != nil || lastUserAny != nil)
            && lastRole == "assistant"

        return ChatHistoryTailScan(
            lastUserQuery: lastUserQuery,
            lastUserAny: lastUserAny,
            lastAssistantPreview: lastAssistantPreview,
            lastAssistantMessage: lastAssistantMessage,
            turnAppearsComplete: turnAppearsComplete
        )
    }

    private func extractTextContent(from object: [String: Any]) -> String? {
        if let content = stringValue(object["content"]) ?? stringValue(object["text"])
            ?? stringValue(object["message"]) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let parts = object["content"] as? [[String: Any]] {
            let joined = parts.compactMap { stringValue($0["text"]) }.joined(separator: " ")
            let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// True when this assistant row still has tool invocations to run.
    public static func assistantHasPendingToolCalls(_ object: [String: Any]) -> Bool {
        if let calls = object["tool_calls"] as? [Any], !calls.isEmpty {
            return true
        }
        if let calls = object["toolCalls"] as? [Any], !calls.isEmpty {
            return true
        }
        // Some rows store a single tool call dict / non-empty string id.
        if let call = object["tool_calls"] as? [String: Any], !call.isEmpty {
            return true
        }
        if let call = object["tool_call"] as? [String: Any], !call.isEmpty {
            return true
        }
        return false
    }

    /// Drop system/injection blobs that appear as role=user but are not the task.
    ///
    /// Important: Grok often packs `<image_files>` + real `<user_query>` into one
    /// user row. Image-only noise must not discard that turn, or the island stays
    /// stuck on animated "Running" forever (no turnAppearsComplete / no green dot).
    public static func isNoiseUserMessage(_ text: String) -> Bool {
        let lowered = text.lowercased()
        // Real user task always wins — even when attachments / wrappers co-exist.
        if lowered.contains("<user_query>") {
            let cleaned = cleanUserPrompt(text)
            return cleaned.count < 4
        }
        if lowered.contains("<image_files>") || lowered.contains("images were provided by the user") {
            return true
        }
        if lowered.contains("mcp servers connected") || lowered.contains("system-reminder") {
            return true
        }
        if lowered.contains("<user_info>") {
            return true
        }
        // Pure whitespace / very short
        let cleaned = cleanUserPrompt(text)
        return cleaned.count < 4
    }

    public func sessionDirectoryURL(sessionID: String, cwd: String?) -> URL? {
        let sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        if let cwd, !cwd.isEmpty {
            let encoded = encodeSessionCWD(cwd)
            let candidate = sessionsRoot
                .appendingPathComponent(encoded, isDirectory: true)
                .appendingPathComponent(sessionID, isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        // Fallback: scan one level of session roots (bounded) for this session id.
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for child in children.prefix(80) {
            let candidate = child.appendingPathComponent(sessionID, isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Grok stores cwd segments as percent-encoded full paths (spaces → %20, / → %2F).
    public func encodeSessionCWD(_ cwd: String) -> String {
        var allowed = CharacterSet.alphanumerics
        // Keep a few safe punctuation characters unescaped if present; encode the rest.
        // Matches observed dirs like `%2FUsers%2F…%2FProject%20Buddy`.
        allowed.insert(charactersIn: "-_.~")
        return cwd.addingPercentEncoding(withAllowedCharacters: allowed) ?? cwd
            .replacingOccurrences(of: "/", with: "%2F")
            .replacingOccurrences(of: " ", with: "%20")
    }

    /// Prefer the inner text of `<user_query>…</user_query>`; strip other wrappers.
    public static func cleanUserPrompt(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(
            pattern: #"<user_query>\s*([\s\S]*?)\s*</user_query>"#,
            options: [.caseInsensitive]
        ) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            if let match = regex.firstMatch(in: result, options: [], range: range),
               match.numberOfRanges > 1,
               let inner = Range(match.range(at: 1), in: result) {
                result = String(result[inner])
            }
        }
        result = result.replacingOccurrences(of: "</?[^>]+>", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    public static func truncateOneLine(_ text: String, limit: Int = 140) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else {
            return collapsed
        }
        let end = collapsed.index(collapsed.startIndex, offsetBy: limit)
        return String(collapsed[..<end]) + "…"
    }

    private func stringValue(_ any: Any?) -> String? {
        if let string = any as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = any as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func intValue(_ any: Any?) -> Int? {
        if let int = any as? Int {
            return int
        }
        if let number = any as? NSNumber {
            return number.intValue
        }
        if let string = any as? String, let int = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return int
        }
        return nil
    }

    private func dateValue(_ any: Any?) -> Date? {
        guard let string = stringValue(any) else {
            return nil
        }
        // ISO-8601 with fractional seconds (Grok uses this form).
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
