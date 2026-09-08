import Foundation
import Testing
@testable import OpenIslandApp

struct UsageWindowPresentationTests {
    @Test
    func resetBadgeUsesWeeklyWindowInsteadOfPeakUsageWindow() {
        let provider = UsageProviderPresentation(
            id: "codex",
            title: "C",
            windows: [
                UsageWindowPresentation(
                    id: "codex-primary",
                    label: "5h",
                    usedPercentage: 11,
                    windowMinutes: 300,
                    resetsAt: Date(timeIntervalSince1970: 1_000)
                ),
                UsageWindowPresentation(
                    id: "codex-secondary",
                    label: "7d",
                    usedPercentage: 2,
                    windowMinutes: 10_080,
                    resetsAt: Date(timeIntervalSince1970: 2_000)
                ),
            ]
        )

        #expect(provider.peakWindow?.id == "codex-primary")
        #expect(provider.resetWindow?.id == "codex-secondary")
        #expect(provider.primaryMetricText == "11")
    }
}
