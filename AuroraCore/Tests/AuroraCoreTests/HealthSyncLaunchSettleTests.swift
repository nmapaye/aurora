import Testing
@testable import AuroraCore

@Suite struct HealthSyncLaunchSettleTests {
    @Test func interruptedImportSettlesToIdleOnLaunch() {
        let stuck = HealthSync(lastSyncedAt: 1_793_136_304_428, lastMessage: "Importing recent sleep from Health.", importedCount: 34, importStatus: .importing)
        let settled = stuck.settledAfterLaunch()
        #expect(settled.importStatus == .idle)
        #expect(settled.lastSyncedAt == stuck.lastSyncedAt && settled.importedCount == 34)
    }

    @Test func otherStatusesAreKept() {
        for status in [HealthImportStatus.idle, .succeeded, .partial] {
            let sync = HealthSync(importedCount: 1, importStatus: status)
            #expect(sync.settledAfterLaunch() == sync)
        }
    }
}
