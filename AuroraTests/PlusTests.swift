import AuroraCore
import Foundation
import Testing
@testable import Aurora

@Suite struct PlusAccessTests {
    @Test func weekStaysFree() {
        #expect(!PlusAccess.requiresPlus(InsightsRange.week))
        #expect(!PlusAccess.requiresPlus(SleepRange.week))
        #expect(PlusAccess.shown(InsightsRange.week, unlocked: false) == .week)
        #expect(PlusAccess.shown(SleepRange.week, unlocked: false) == .week)
    }

    @Test func longerRangesNeedPlus() {
        #expect(PlusAccess.requiresPlus(InsightsRange.twoWeeks))
        #expect(PlusAccess.requiresPlus(InsightsRange.month))
        #expect(PlusAccess.requiresPlus(SleepRange.month))
    }

    @Test func lockedShowsWeekInsteadOfTheChosenRange() {
        #expect(PlusAccess.shown(InsightsRange.twoWeeks, unlocked: false) == .week)
        #expect(PlusAccess.shown(InsightsRange.month, unlocked: false) == .week)
        #expect(PlusAccess.shown(SleepRange.month, unlocked: false) == .week)
    }

    @Test func unlockedShowsTheChosenRange() {
        for range in InsightsRange.allCases {
            #expect(PlusAccess.shown(range, unlocked: true) == range)
        }
        for range in SleepRange.allCases {
            #expect(PlusAccess.shown(range, unlocked: true) == range)
        }
    }
}

@MainActor
@Suite struct PurchaseServiceTests {
    private func defaults() -> UserDefaults {
        let name = "aurora-plus-tests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func startsLockedWithNothingCached() {
        let service = PurchaseService(defaults: defaults(), forced: nil)
        #expect(!service.isUnlocked)
    }

    @Test func startsFromTheCachedFlag() {
        let store = defaults()
        store.set(true, forKey: "plus.unlocked")
        let service = PurchaseService(defaults: store, forced: nil)
        #expect(service.isUnlocked)
    }

    @Test func launchOverrideWinsOverTheCache() {
        let store = defaults()
        store.set(true, forKey: "plus.unlocked")
        #expect(!PurchaseService(defaults: store, forced: false).isUnlocked)
        #expect(PurchaseService(defaults: defaults(), forced: true).isUnlocked)
    }

    @Test func overriddenServiceSkipsTheAppStore() async {
        let service = PurchaseService(defaults: defaults(), forced: true)
        await service.start()
        #expect(service.productState == .unavailable)
        #expect(service.isUnlocked)
    }

    @Test func everyNoticeHasText() {
        let notices: [PurchaseService.Notice] = [.pending, .unverified, .failed, .restoreFailed, .nothingToRestore]
        for notice in notices {
            #expect(!notice.text.isEmpty)
        }
        #expect(!PurchaseService.Notice.pending.isError)
        #expect(PurchaseService.Notice.failed.isError)
    }
}
