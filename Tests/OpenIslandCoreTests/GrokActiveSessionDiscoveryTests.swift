import Foundation
import Testing
@testable import OpenIslandCore

struct GrokActiveSessionDiscoveryTests {
    @Test
    func loadActiveSessionsParsesPIDAndFiltersDeadProcesses() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-grok-discovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("active_sessions.json")
        let payload: [[String: Any]] = [
            [
                "session_id": "session-live",
                "pid": 4242,
                "cwd": "/tmp/project-a",
                "opened_at": "2026-08-03T07:00:00.000000Z",
            ],
            [
                "session_id": "session-dead",
                "pid": 999_999,
                "cwd": "/tmp/project-b",
                "opened_at": "2026-08-03T07:00:00.000000Z",
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: url)

        let discovery = GrokActiveSessionDiscovery(
            activeSessionsURL: url,
            processAliveCheck: { $0 == 4242 }
        )

        let records = discovery.loadActiveSessions(requireAliveProcess: true)
        #expect(records.count == 1)
        #expect(records[0].sessionID == "session-live")
        #expect(records[0].pid == 4242)
        #expect(records[0].cwd == "/tmp/project-a")

        let byPID = discovery.recordsByPID(requireAliveProcess: true)
        #expect(byPID[4242]?.sessionID == "session-live")
        #expect(byPID[999_999] == nil)
    }

    @Test
    func loadActiveSessionsFailsOpenOnMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-grok-sessions-\(UUID().uuidString).json")
        let discovery = GrokActiveSessionDiscovery(activeSessionsURL: url)
        #expect(discovery.loadActiveSessions().isEmpty)
    }

    @Test
    func recoversOneRegistryOrphanFromUnambiguousOpenSessionFiles() {
        let sessionID = "019fc5e3-a1de-7792-9384-913e2045c491"
        let output = """
        fcwd
        n/tmp/project-b
        n/Users/test/.grok/sessions/%2Ftmp%2Fproject-b/\(sessionID)/events.jsonl
        n/Users/test/.grok/sessions/%2Ftmp%2Fproject-b/\(sessionID)/terminal/call-1.log
        """

        let records = GrokActiveSessionDiscovery.recoverOrphanedSessions(
            activePIDs: [94175],
            lsofOutputByPID: [94175: output]
        )

        #expect(records == [
            GrokActiveSessionRecord(sessionID: sessionID, pid: 94175, cwd: "/tmp/project-b"),
        ])
    }

    @Test
    func rejectsAmbiguousOrUnidentifiedGrokProcesses() {
        let first = "019fc5e3-a1de-7792-9384-913e2045c491"
        let second = "019fc6fa-5c3f-7631-89b0-d260b8ad1739"
        let ambiguous = """
        n/Users/test/.grok/sessions/%2Ftmp%2Fproject/\(first)/events.jsonl
        n/Users/test/.grok/sessions/%2Ftmp%2Fproject/\(second)/events.jsonl
        """

        let records = GrokActiveSessionDiscovery.recoverOrphanedSessions(
            activePIDs: [101, 102],
            lsofOutputByPID: [
                101: ambiguous,
                102: "fcwd\nn/tmp/project",
            ]
        )

        #expect(records.isEmpty)
    }

    @Test
    func newestRegistryRowWinsWhenOnePIDHasHistoricalSessionIDs() {
        let older = GrokActiveSessionRecord(
            sessionID: "019fc6fa-5c3f-7631-89b0-d260b8ad1739",
            pid: 699,
            openedAt: Date(timeIntervalSince1970: 10)
        )
        let newer = GrokActiveSessionRecord(
            sessionID: "019fc70b-ee81-7362-b6d3-a92fe750f8a7",
            pid: 699,
            openedAt: Date(timeIntervalSince1970: 20)
        )

        let records = GrokActiveSessionDiscovery.newestRecordsByPID([older, newer])

        #expect(records.count == 1)
        #expect(records[699]?.sessionID == newer.sessionID)
    }

    @Test
    func imageAttachmentWithUserQueryIsNotNoise() {
        let combined = """
        <image_files>
        The following images were provided by the user and saved to the workspace for future use:
        1. /tmp/shot.png
        </image_files>
        <user_query>
        执行完之后，它应该变成一个小绿点
        </user_query>
        """
        #expect(GrokActiveSessionDiscovery.isNoiseUserMessage(combined) == false)
        #expect(
            GrokActiveSessionDiscovery.cleanUserPrompt(combined)
                .contains("小绿点")
        )
    }

    @Test
    func pureImageOrSystemInjectionIsNoise() {
        #expect(
            GrokActiveSessionDiscovery.isNoiseUserMessage(
                "<image_files>\n1. /tmp/a.png\n</image_files>"
            )
        )
        #expect(
            GrokActiveSessionDiscovery.isNoiseUserMessage(
                "<system-reminder>\nMCP servers connected:\n- gmail\n</system-reminder>"
            )
        )
        #expect(
            GrokActiveSessionDiscovery.isNoiseUserMessage(
                "<user_info>\nOS Version: macos\n</user_info>"
            )
        )
    }

    @Test
    func cleanUserPromptExtractsQueryEvenWhenImageWrapperPresent() {
        let combined = """
        <image_files>
        1. /tmp/a.png
        </image_files>
        <user_query>
        修好绿点动画
        </user_query>
        """
        let cleaned = GrokActiveSessionDiscovery.cleanUserPrompt(combined)
        #expect(cleaned.contains("修好绿点动画"))
        #expect(!cleaned.contains("<image_files>"))
        #expect(GrokActiveSessionDiscovery.isNoiseUserMessage(combined) == false)
    }

    @Test
    func assistantWithToolCallsIsStillPending() {
        let withTools: [String: Any] = [
            "role": "assistant",
            "content": "先查一下。",
            "tool_calls": [["name": "run_terminal_command"]],
        ]
        let finalText: [String: Any] = [
            "role": "assistant",
            "content": "已完成修复。",
        ]
        #expect(GrokActiveSessionDiscovery.assistantHasPendingToolCalls(withTools))
        #expect(GrokActiveSessionDiscovery.assistantHasPendingToolCalls(finalText) == false)
    }
}
