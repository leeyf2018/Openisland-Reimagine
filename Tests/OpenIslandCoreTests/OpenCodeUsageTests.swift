import Foundation
import Testing
@testable import OpenIslandCore

struct OpenCodeUsageTests {
    @Test
    func openCodeUsageNormalizesPastResetToZeroCredits() throws {
        let stale = OpenCodeUsageSnapshot(
            source: "cache",
            capturedAt: isoDate("2026-08-31T12:00:00Z"),
            usedPercentage: 226.6,
            remainingPercentage: 0,
            isUnlimited: true,
            planType: "business",
            quotaID: "premium_interactions",
            creditsUsed: 680,
            creditsEntitlement: 300,
            usageBasis: "credits_vs_plan_default",
            resetsAt: isoDate("2026-09-01T00:00:00Z")
        )

        let afterReset = isoDate("2026-09-01T08:00:00Z")!
        let normalized = OpenCodeUsageLoader.normalizeForCurrentPeriod(stale, now: afterReset)

        #expect(normalized.creditsUsed == 0)
        #expect(normalized.roundedUsedPercentage == 0)
        #expect(normalized.remainingPercentage == 100)
        #expect(normalized.usageBasis == "period_reset")
        #expect(normalized.resetsAt == isoDate("2026-10-01T00:00:00Z"))
    }

    @Test
    func openCodeUsageLeavesActivePeriodUnchanged() throws {
        let live = OpenCodeUsageSnapshot(
            source: "gh api",
            capturedAt: isoDate("2026-08-04T11:00:00Z"),
            usedPercentage: 50,
            remainingPercentage: 50,
            isUnlimited: true,
            planType: "business",
            creditsUsed: 150,
            creditsEntitlement: 300,
            usageBasis: "credits_vs_plan_default",
            resetsAt: isoDate("2026-09-01T00:00:00Z")
        )

        let now = isoDate("2026-08-04T12:00:00Z")!
        let normalized = OpenCodeUsageLoader.normalizeForCurrentPeriod(live, now: now)

        #expect(normalized.creditsUsed == 150)
        #expect(normalized.usageBasis == "credits_vs_plan_default")
        #expect(normalized.resetsAt == live.resetsAt)
    }

    @Test
    func openCodeBusinessUnlimitedUsesCreditsNotFake100Percent() throws {
        let metrics = OpenCodeUsageLoader.resolveUsageMetrics(
            planType: "business",
            unlimited: true,
            percentRemaining: 100,
            creditsUsed: 680,
            apiEntitlement: 0,
            absoluteRemaining: 0
        )

        #expect(metrics.usageBasis == "credits_vs_plan_default")
        #expect(metrics.creditsEntitlement == 300)
        #expect(Int(metrics.usedPercentage.rounded()) == 227)
    }
}

private func isoDate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) {
        return date
    }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: value)
}
