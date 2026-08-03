import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct GrokProcessMonitoringTests {
    @Test
    func recoveredGrokProcessClearsEndedStateAndRestoresLiveness() {
        let sessionID = "019fc5e3-a1de-7792-9384-913e2045c491"
        var session = AgentSession(
            id: sessionID,
            title: "Grok · Project",
            tool: .grok,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Ready",
            updatedAt: Date(timeIntervalSince1970: 10_000)
        )
        session.isSessionEnded = true
        session.isProcessAlive = false

        let coordinator = ProcessMonitoringCoordinator()
        let merged = coordinator.mergedWithSyntheticGrokSessions(
            existingSessions: [session],
            activeProcesses: [
                .init(
                    tool: .grok,
                    sessionID: sessionID,
                    workingDirectory: "/tmp/project",
                    terminalTTY: "/dev/ttys001",
                    terminalApp: "Ghostty"
                ),
            ],
            now: Date(timeIntervalSince1970: 10_100)
        )

        #expect(merged.count == 1)
        #expect(merged[0].isProcessAlive)
        #expect(!merged[0].isSessionEnded)
        #expect(merged[0].phase == .running)
    }

    @Test
    func missingGrokProcessEndsOnlyItsOwnSession() {
        func makeSession(id: String) -> AgentSession {
            var session = AgentSession(
                id: id,
                title: "Grok · Project",
                tool: .grok,
                origin: .live,
                attachmentState: .attached,
                phase: .running,
                summary: "Working",
                updatedAt: Date(timeIntervalSince1970: 20_000)
            )
            session.isProcessAlive = true
            return session
        }

        let aliveID = "019fc5e3-a1de-7792-9384-913e2045c491"
        let missingID = "019fc6fa-3725-7d58-9d2f-74c1c2ecbeaf"
        let coordinator = ProcessMonitoringCoordinator()
        let merged = coordinator.mergedWithSyntheticGrokSessions(
            existingSessions: [makeSession(id: aliveID), makeSession(id: missingID)],
            activeProcesses: [
                .init(
                    tool: .grok,
                    sessionID: aliveID,
                    workingDirectory: "/tmp/project",
                    terminalTTY: "/dev/ttys001",
                    terminalApp: "Ghostty"
                ),
            ],
            now: Date(timeIntervalSince1970: 20_100)
        )

        let alive = merged.first { $0.id == aliveID }
        let missing = merged.first { $0.id == missingID }
        #expect(alive?.isProcessAlive == true)
        #expect(alive?.isSessionEnded == false)
        #expect(missing?.isProcessAlive == false)
        #expect(missing?.isSessionEnded == true)
        #expect(missing?.phase == .completed)
    }

    @Test
    func completedAliveGrokSessionReentersRunningWhenHistorySaysTurnOpen() {
        // Without a completed chat_history tail, turnAppearsComplete is false, so
        // a completed-but-alive row correctly returns to `.running`.
        let sessionID = "019fc800-aaaa-bbbb-cccc-120039934db8"
        var session = AgentSession(
            id: sessionID,
            title: "Grok · Project",
            tool: .grok,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "1. Done",
            updatedAt: Date(timeIntervalSince1970: 30_000)
        )
        session.isProcessAlive = true
        session.isSessionEnded = false

        let coordinator = ProcessMonitoringCoordinator()
        let merged = coordinator.mergedWithSyntheticGrokSessions(
            existingSessions: [session],
            activeProcesses: [
                .init(
                    tool: .grok,
                    sessionID: sessionID,
                    workingDirectory: "/tmp/project-without-history",
                    terminalTTY: "/dev/ttys001",
                    terminalApp: "Ghostty"
                ),
            ],
            now: Date(timeIntervalSince1970: 30_100)
        )

        #expect(merged.count == 1)
        #expect(merged[0].id == sessionID)
        #expect(merged[0].isProcessAlive)
        #expect(merged[0].phase == .running)
    }

    @Test
    func lightMergeDoesNotEndGrokSessionWhenRegistryOmitsIt() {
        // Light poll uses endMissingSessions=false so a mid-write empty
        // active_sessions.json cannot wipe the island for up to 60–300s.
        let sessionID = "019fc800-dddd-eeee-ffff-120039934db8"
        var session = AgentSession(
            id: sessionID,
            title: "Grok · Project",
            tool: .grok,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 40_000)
        )
        session.isProcessAlive = true

        let coordinator = ProcessMonitoringCoordinator()
        let merged = coordinator.mergedWithSyntheticGrokSessions(
            existingSessions: [session],
            activeProcesses: [],
            now: Date(timeIntervalSince1970: 40_100),
            endMissingSessions: false
        )

        #expect(merged.count == 1)
        #expect(merged[0].id == sessionID)
        #expect(merged[0].isSessionEnded == false)
        #expect(merged[0].phase == .running)
    }

    @Test
    func fullMergeEndsGrokSessionWhenRegistryOmitsIt() {
        let sessionID = "019fc800-dddd-eeee-ffff-120039934db9"
        var session = AgentSession(
            id: sessionID,
            title: "Grok · Project",
            tool: .grok,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 50_000)
        )
        session.isProcessAlive = true

        let coordinator = ProcessMonitoringCoordinator()
        let merged = coordinator.mergedWithSyntheticGrokSessions(
            existingSessions: [session],
            activeProcesses: [],
            now: Date(timeIntervalSince1970: 50_100),
            endMissingSessions: true
        )

        #expect(merged.count == 1)
        #expect(merged[0].isSessionEnded == true)
        #expect(merged[0].phase == .completed)
        #expect(merged[0].isProcessAlive == false)
    }
}
