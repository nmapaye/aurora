import AuroraCore
import Foundation
import Testing
import UserNotifications
@testable import Aurora

/// Stands in for the notification center. `holdStatus` parks the next
/// authorization check until `release()`, so tests can overlap two syncs.
@MainActor
final class FakeNotificationCenter: NotificationScheduling {
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

    func removePending(identifiers: [String]) {
        removed.append(identifiers)
        for id in identifiers { pending[id] = nil }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        if holdStatus {
            await withCheckedContinuation { parked = $0 }
        }
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
}

@MainActor
@Suite struct ReminderServiceTests {
    struct AddFailed: Error {}

    let center = FakeNotificationCenter()
    var service: ReminderService {
        ReminderService(center: center, clock: { LocalClock(timeZone: TimeZone(identifier: "UTC")!) }, text: { .current })
    }

    @Test func schedulesUnderTheReactNativeIdentifier() async {
        let service = service
        let status = await service.sync(enabled: true, cutoffHour: 14, prompt: false)
        #expect(status == .scheduled(hour: 14))
        #expect(CutoffReminder.identifier == "cutoff-reminder")
        let trigger = center.pending["cutoff-reminder"]?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.repeats == true)
        #expect(trigger?.dateComponents.hour == 14)
        #expect(center.removed.first == ["cutoff-reminder"])
    }

    @Test func switchingOffCancelsAndSchedulesNothing() async {
        let service = service
        _ = await service.sync(enabled: true, cutoffHour: 14, prompt: false)
        #expect(await service.sync(enabled: false, cutoffHour: 14, prompt: false) == .off)
        #expect(center.pending.isEmpty)
    }

    @Test func deniedPermissionIsReportedAndForegroundNeverPrompts() async {
        center.status = .notDetermined
        let service = service
        #expect(await service.sync(enabled: true, cutoffHour: 14, prompt: false) == .denied)
        #expect(center.requested == 0)
        center.statusAfterRequest = .denied
        #expect(await service.sync(enabled: true, cutoffHour: 14, prompt: true) == .denied)
        #expect(center.requested == 1)
        #expect(center.pending.isEmpty)
    }

    @Test func schedulingErrorIsNotReportedAsDenied() async {
        center.addError = AddFailed()
        let service = service
        #expect(await service.sync(enabled: true, cutoffHour: 14, prompt: false) == .failed)
    }

    @Test func aLaterSwitchOffWinsOverAnEarlierSync() async {
        center.holdStatus = true
        let service = service
        async let first = service.sync(enabled: true, cutoffHour: 14, prompt: false)
        while !center.isParked { await Task.yield() }
        async let second = service.sync(enabled: false, cutoffHour: 14, prompt: false)
        await Task.yield()
        center.release()
        let results = await (first, second)
        #expect(results.0 == .off)
        #expect(results.1 == .off)
        #expect(center.pending.isEmpty)
    }
}
