import Foundation
import Testing
@testable import OpenIslandApp

struct PerformancePolicyTests {
    @Test
    func workBuddyPollingUsesTenMinuteCadence() {
        #expect(WorkBuddyUsageRefreshPolicy.pollingInterval == .seconds(600))
    }

    @Test
    func workBuddyForcesOfficialRefreshOnlyWhileBackgrounded() {
        #expect(WorkBuddyUsageRefreshPolicy.shouldForceRefresh(isApplicationActive: false))
        #expect(!WorkBuddyUsageRefreshPolicy.shouldForceRefresh(isApplicationActive: true))
    }

    @Test
    func idleUnifiedBarsDoesNotRequireAnimationTimeline() {
        #expect(UnifiedBars.Mode.idle.timelineInterval == nil)
    }

    @Test
    func activeUnifiedBarsDoNotRequireAnimationTimeline() {
        #expect(UnifiedBars.Mode.running.timelineInterval == nil)
        #expect(UnifiedBars.Mode.waiting.timelineInterval == nil)
    }

    @Test
    func activeUnifiedBarsUseCoreAnimationLayerAnimation() {
        #expect(!UnifiedBars.Mode.idle.usesLayerAnimation)
        #expect(UnifiedBars.Mode.running.usesLayerAnimation)
        #expect(UnifiedBars.Mode.waiting.usesLayerAnimation)
    }

    @MainActor
    @Test
    func monitoringPollIntervalBacksOffOutsideStartupResolution() {
        #expect(ProcessMonitoringCoordinator.monitoringPollInterval(
            isResolvingInitialLiveSessions: true,
            hasTrackedLiveSessions: false
        ) == 2)
        #expect(ProcessMonitoringCoordinator.monitoringPollInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: true
        ) == 60)
        #expect(ProcessMonitoringCoordinator.monitoringPollInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: false
        ) == 300)
    }

    @MainActor
    @Test
    func codexDesktopProbeKeepsShortWakeCadenceWhileFullReconcileBacksOff() {
        #expect(ProcessMonitoringCoordinator.monitoringWakeInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: false
        ) == 2)
        #expect(ProcessMonitoringCoordinator.monitoringWakeInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: true
        ) == 2)
    }

    @MainActor
    @Test
    func trackedSessionTransitionForcesFullReconcileBeforeIdleDeadline() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let idleDeadline = now.addingTimeInterval(300)

        #expect(!ProcessMonitoringCoordinator.shouldPerformFullMonitorReconcile(
            now: now,
            nextFullReconcileAt: idleDeadline,
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: false,
            hadTrackedLiveSessions: false
        ))
        #expect(ProcessMonitoringCoordinator.shouldPerformFullMonitorReconcile(
            now: now,
            nextFullReconcileAt: idleDeadline,
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: true,
            hadTrackedLiveSessions: false
        ))
    }

    @Test
    func inactiveSessionDotDoesNotRequireAnimationTimeline() {
        #expect(IslandSessionStateIndicator.animatedDot.timelineInterval(
            presence: .inactive,
            isActionable: false
        ) == nil)
        #expect(IslandSessionStateIndicator.animatedDot.timelineInterval(
            presence: .active,
            isActionable: false
        ) == nil)
        #expect(IslandSessionStateIndicator.animatedDot.timelineInterval(
            presence: .running,
            isActionable: false
        ) == 1.0 / 15.0)
        #expect(IslandSessionStateIndicator.animatedDot.timelineInterval(
            presence: .inactive,
            isActionable: true
        ) == 1.0 / 15.0)
    }

    @Test
    func animatedStatusVisualMatchesSessionLifecycle() {
        #expect(IslandAnimatedStatusVisual.resolve(
            phase: .running,
            presence: .running
        ) == .runningWaveform)
        #expect(IslandAnimatedStatusVisual.resolve(
            phase: .waitingForApproval,
            presence: .active
        ) == .approvalAttention)
        #expect(IslandAnimatedStatusVisual.resolve(
            phase: .waitingForAnswer,
            presence: .active
        ) == .answerAttention)
        #expect(IslandAnimatedStatusVisual.resolve(
            phase: .completed,
            presence: .active
        ) == .completedBadge)
        #expect(IslandAnimatedStatusVisual.resolve(
            phase: .completed,
            presence: .inactive
        ) == .idleDot)
    }

    @Test
    func runningWaveformMovesWithinItsVisualBounds() {
        let phaseZero = (0..<IslandRunningWaveformMetrics.barCount).map {
            IslandRunningWaveformMetrics.barHeight(index: $0, phase: 0)
        }
        let phaseOne = (0..<IslandRunningWaveformMetrics.barCount).map {
            IslandRunningWaveformMetrics.barHeight(index: $0, phase: 1)
        }
        let samples = phaseZero + phaseOne

        #expect(samples.allSatisfy {
            $0 >= IslandRunningWaveformMetrics.minimumBarHeight
                && $0 <= IslandRunningWaveformMetrics.maximumBarHeight
        })
        #expect(phaseZero != phaseOne)
        #expect((phaseZero.max() ?? 0) > (phaseZero.min() ?? 0))
    }
}
