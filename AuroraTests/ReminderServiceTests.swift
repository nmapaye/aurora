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
