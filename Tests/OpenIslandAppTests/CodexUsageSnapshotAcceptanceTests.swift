import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct CodexUsageSnapshotAcceptanceTests {
    @Test
    func staleRolloutCannotOverwriteFreshLiveSnapshot() {
        let coordinator = HookInstallationCoordinator()
        let liveCapturedAt = Date(timeIntervalSince1970: 200)
        let staleCapturedAt = Date(timeIntervalSince1970: 100)

        coordinator.acceptCodexUsageSnapshot(
            snapshot(usedPercentage: 2, capturedAt: liveCapturedAt, source: "codex-app-server://live")
        )
        coordinator.acceptCodexUsageSnapshot(
            snapshot(usedPercentage: 29, capturedAt: staleCapturedAt, source: "rollout-stale.jsonl")
        )

        #expect(coordinator.codexUsageSnapshot?.windows.first?.roundedUsedPercentage == 2)
        #expect(coordinator.codexUsageSnapshot?.capturedAt == liveCapturedAt)
    }

    private func snapshot(
        usedPercentage: Double,
        capturedAt: Date,
        source: String
    ) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            sourceFilePath: source,
            capturedAt: capturedAt,
            windows: [
                CodexUsageWindow(
                    key: "primary",
                    label: "7d",
                    usedPercentage: usedPercentage,
                    leftPercentage: 100 - usedPercentage,
                    windowMinutes: 10_080,
                    resetsAt: nil
                ),
            ]
        )
    }
}
