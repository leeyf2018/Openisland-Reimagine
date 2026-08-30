import Foundation
import Testing
@testable import OpenIslandCore

struct WorkBuddyUsageTests {
    @Test
    func workBuddyUsageRoundTripsWholePointsWithoutResetWindow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("workbuddy-usage.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let snapshot = WorkBuddyUsageSnapshot(
            source: "workbuddy-account-menu",
            capturedAt: Date(timeIntervalSince1970: 1_788_000_000),
            pointsRemaining: 6_200
        )

        try WorkBuddyUsageLoader.write(snapshot, to: url)
        let loaded = try WorkBuddyUsageLoader.load(from: url)

        #expect(loaded == snapshot)
        #expect(loaded?.pointsRemaining == 6_200)
    }

    @Test
    func workBuddyUsageClampsInvalidNegativeBalance() {
        let snapshot = WorkBuddyUsageSnapshot(
            source: "fixture",
            pointsRemaining: -1
        )

        #expect(snapshot.pointsRemaining == 0)
    }

    @Test
    func workBuddyUsageParsesChineseAndEnglishAccessibilityLabels() {
        #expect(WorkBuddyUsageParser.pointsBalance(from: "积分余额 刷新 6,200") == 6_200)
        #expect(WorkBuddyUsageParser.pointsBalance(from: "积分余额 刷新 6,291.18") == 6_291)
        #expect(WorkBuddyUsageParser.pointsBalance(from: "Credits balance Refresh 12,345") == 12_345)
        #expect(WorkBuddyUsageParser.pointsBalance(from: "去邀约 最高得 650 积分/人") == nil)
    }
}
