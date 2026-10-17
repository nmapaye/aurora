import AuroraCore
import Foundation
import Testing
import UserNotifications
@testable import Aurora

/// ReminderService against a controlled backend: nothing reaches iOS.
@MainActor
@Suite struct ReminderServiceTests {
    /// Records every call in order and holds each `add` until released.
    @MainActor final class GatedBackend: NotificationBackend {
        enum Event: Equatable { case add(String, String), removePending([String]), removeDelivered([String]) }
        var events: [Event] = []
        var status = UNAuthorizationStatus.authorized
        var holdAdds = true
        private var waiting: [CheckedContinuation<Void, Never>] = []
        var waitingCount: Int { waiting.count }

        func authorizationStatus() async -> UNAuthorizationStatus { status }
        func requestAuthorization() async {}
        func add(_ request: UNNotificationRequest) async throws {
            events.append(.add(request.identifier, request.content.body))
            if holdAdds { await withCheckedContinuation { waiting.append($0) } }
        }
        func removePending(_ ids: [String]) { events.append(.removePending(ids)) }
        func removeDelivered(_ ids: [String]) { events.append(.removeDelivered(ids)) }
        func pendingIdentifiers() async -> [String] { [] }
        func deliveredIdentifiers() async -> [String] { [] }
        func releaseAdd() { waiting.removeFirst().resume() }
        func waitForAdds(_ count: Int) async {
            for _ in 0..<1000 where waitingCount < count { await Task.yield() }
        }
    }

    private func content(_ body: String) -> CutoffScenario.ReminderContent {
        .init(title: "Your cutoff scenario", body: body, fireAt: (Date.now.timeIntervalSince1970 + 3600) * 1000)
    }

    private var adds: (GatedBackend) -> [String] {
        { $0.events.compactMap { if case .add(_, let body) = $0 { body } else { nil } } }
    }

    @Test func writeQueuedBeforeEraseNeverReachesNotificationsAfterIt() async {
        let backend = GatedBackend()
        let service = ReminderService(backend: backend)
        let a = Task { await service.scheduleScenario(content("A")) }
        await backend.waitForAdds(1)
        // B is queued behind A, then everything is erased.
        let b = Task { await service.scheduleScenario(content("B")) }
        for _ in 0..<20 { await Task.yield() }
        service.cancelForErase()
        backend.releaseAdd()
        #expect(await a.value == .failed)
        #expect(await b.value == .failed)
        #expect(adds(backend) == ["A"])
        // A's own request is removed after the erase; B never wrote anything.
        let removalsAfterErase = backend.events.drop { $0 != .removeDelivered([CutoffReminder.identifier, CutoffScenario.reminderIdentifier]) }
        #expect(removalsAfterErase.contains(.removePending([CutoffScenario.reminderIdentifier])))

        // A Save made after the erase is genuinely new and succeeds.
        let c = Task { await service.scheduleScenario(content("C")) }
        await backend.waitForAdds(1)
        backend.releaseAdd()
        #expect(await c.value == .scheduled)
        #expect(adds(backend) == ["A", "C"])
        // Nothing removed the scenario request after C was added.
        let afterC = backend.events.drop { $0 != .add(CutoffScenario.reminderIdentifier, "C") }.dropFirst()
        #expect(afterC.isEmpty)
    }

    @Test func writesLandInTapOrder() async {
        let backend = GatedBackend()
        let service = ReminderService(backend: backend)
        let a = Task { await service.scheduleScenario(content("A")) }
        await backend.waitForAdds(1)
        let b = Task { await service.scheduleScenario(content("B")) }
        for _ in 0..<20 { await Task.yield() }
        // B can't start until A finishes.
        #expect(adds(backend) == ["A"])
        backend.releaseAdd()
        await backend.waitForAdds(1)
        backend.releaseAdd()
        let first = await a.value, second = await b.value
        #expect(first == .scheduled && second == .scheduled)
        #expect(adds(backend) == ["A", "B"])
    }

    @Test(arguments: [UNAuthorizationStatus.notDetermined, .denied]) func notAllowedNeverWritesOrPrompts(status: UNAuthorizationStatus) async {
        let backend = GatedBackend()
        backend.status = status
        let service = ReminderService(backend: backend)
        #expect(await service.scheduleScenario(content("A")) == .notAllowed)
        #expect(backend.events.isEmpty)
    }
}

/// The daily reminder's sync order, permission and failure reporting,
/// carried over from main's ReminderService tests.
@MainActor
@Suite struct DailyReminderSyncTests {
    /// Keeps pending requests like the system does. `holdStatus` parks the
    /// next authorization check until `release()`, so tests can overlap syncs.
    @MainActor final class ScriptedBackend: NotificationBackend {
        var status: UNAuthorizationStatus = .authorized
        var statusAfterRequest: UNAuthorizationStatus = .authorized
        var addError: Error?
        var holdStatus = false
        private(set) var pending: [String: UNNotificationRequest] = [:]
        private(set) var removed: [[String]] = []
        private(set) var requested = 0
        private var parked: CheckedContinuation<Void, Never>?

        var isParked: Bool { parked != nil }

        func release() {
            holdStatus = false
            parked?.resume()
            parked = nil
        }

        func authorizationStatus() async -> UNAuthorizationStatus {
            if holdStatus { await withCheckedContinuation { parked = $0 } }
            return status
        }
        func requestAuthorization() async {
            requested += 1
            status = statusAfterRequest
        }
        func add(_ request: UNNotificationRequest) async throws {
            if let addError { throw addError }
            pending[request.identifier] = request
        }
        func removePending(_ ids: [String]) {
            removed.append(ids)
            for id in ids { pending[id] = nil }
        }
        func removeDelivered(_ ids: [String]) {}
        func pendingIdentifiers() async -> [String] { Array(pending.keys) }
        func deliveredIdentifiers() async -> [String] { [] }
    }

    struct AddFailed: Error {}

    let backend = ScriptedBackend()
    var service: ReminderService {
        ReminderService(backend: backend, clock: { LocalClock(timeZone: TimeZone(identifier: "UTC")!) }, text: { .current })
    }

    @Test func schedulesUnderTheReactNativeIdentifier() async {
        let service = service
        #expect(await service.sync(enabled: true, cutoffHour: 14, prompt: false) == .scheduled(hour: 14))
        #expect(CutoffReminder.identifier == "cutoff-reminder")
        let trigger = backend.pending["cutoff-reminder"]?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.repeats == true)
        #expect(trigger?.dateComponents.hour == 14)
        #expect(backend.removed.first == ["cutoff-reminder"])
    }

    /// The reminder states the person's own time: no directive, no
    /// prediction. With no time set, nothing is scheduled.
    @Test func reminderNamesTheirTimeAndNeedsOne() async throws {
        let service = service
        _ = await service.sync(enabled: true, cutoffHour: 14, prompt: false)
        let content = try #require(backend.pending["cutoff-reminder"]?.content)
        #expect(content.title == "Your cutoff time")
        #expect(content.body.hasSuffix(" · the time you set."))
        #expect(await service.sync(enabled: true, cutoffHour: nil, prompt: true) == .off)
        #expect(backend.pending.isEmpty && backend.requested == 0)
    }

    @Test func switchingOffCancelsAndSchedulesNothing() async {
        let service = service
        _ = await service.sync(enabled: true, cutoffHour: 14, prompt: false)
        #expect(await service.sync(enabled: false, cutoffHour: 14, prompt: false) == .off)
        #expect(backend.pending.isEmpty)
    }

    @Test func deniedPermissionIsReportedAndForegroundNeverPrompts() async {
        backend.status = .notDetermined
        let service = service
        #expect(await service.sync(enabled: true, cutoffHour: 14, prompt: false) == .denied)
        #expect(backend.requested == 0)
        backend.statusAfterRequest = .denied
        #expect(await service.sync(enabled: true, cutoffHour: 14, prompt: true) == .denied)
        #expect(backend.requested == 1)
        #expect(backend.pending.isEmpty)
    }

    @Test func schedulingErrorIsNotReportedAsDenied() async {
        backend.addError = AddFailed()
        #expect(await service.sync(enabled: true, cutoffHour: 14, prompt: false) == .failed)
    }

    @Test func aLaterSwitchOffWinsOverAnEarlierSync() async {
        backend.holdStatus = true
        let service = service
        async let first = service.sync(enabled: true, cutoffHour: 14, prompt: false)
        while !backend.isParked { await Task.yield() }
        async let second = service.sync(enabled: false, cutoffHour: 14, prompt: false)
        // Release only once the second sync has registered, so the first is
        // superseded every time rather than by timing.
        while service.latestIntent < 2 { await Task.yield() }
        backend.release()
        let results = await (first, second)
        #expect(results.0 == .off)
        #expect(results.1 == .off)
        #expect(backend.pending.isEmpty)
    }
}
