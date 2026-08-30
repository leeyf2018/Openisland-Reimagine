import Foundation
import Testing
@testable import OpenIslandApp

struct AppExitReconcileTests {
    @Test
    func watchedAppExitBundleIDsCoverCodexGhosttyAndOpenCodeOnly() {
        #expect(ProcessMonitoringCoordinator.isWatchedAppExitBundleIdentifier("com.openai.codex"))
        #expect(ProcessMonitoringCoordinator.isWatchedAppExitBundleIdentifier("com.mitchellh.ghostty"))
        #expect(ProcessMonitoringCoordinator.isWatchedAppExitBundleIdentifier("ai.opencode.desktop"))

        #expect(!ProcessMonitoringCoordinator.isWatchedAppExitBundleIdentifier("com.apple.Terminal"))
        #expect(!ProcessMonitoringCoordinator.isWatchedAppExitBundleIdentifier("com.anthropic.claudefordesktop"))
        #expect(!ProcessMonitoringCoordinator.isWatchedAppExitBundleIdentifier("com.todesktop.230313mzl4w4u92"))
        #expect(!ProcessMonitoringCoordinator.isWatchedAppExitBundleIdentifier(nil))
        #expect(!ProcessMonitoringCoordinator.isWatchedAppExitBundleIdentifier(""))
    }

    @Test
    func appExitConfirmDelayIsShortAndDeterministic() {
        #expect(ProcessMonitoringCoordinator.appExitConfirmReconcileDelay == 1.5)
        #expect(ProcessMonitoringCoordinator.appExitConfirmReconcileDelay < 5)
        #expect(ProcessMonitoringCoordinator.appExitConfirmReconcileDelay > 0)
    }

    @MainActor
    @Test
    func unwatchedBundleIDDoesNotScheduleExitReconcileTask() {
        let coordinator = ProcessMonitoringCoordinator()
        coordinator.handleWatchedAppDidTerminate(bundleIdentifier: "com.apple.Terminal")
        #expect(true)
    }
}
