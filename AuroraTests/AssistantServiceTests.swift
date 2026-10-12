import AuroraCore
import Foundation
import Testing
@testable import Aurora

@MainActor
@Suite struct AssistantServiceTests {
    @Test func mirrorAuthorityNeverSelectsBothConnections() {
        let service = CalendarService()
        let prior = service.selected; let priorMirrors = service.mirrorAuthority
        defer { service.selected = prior; service.mirrorAuthority = priorMirrors }
        service.selected = []
        service.linkMirror(appleID: "test.apple", googleID: "test.google", authority: .google)
        #expect(service.selected == ["google:test.google"])
        service.toggle(.init(id: "test.apple", provider: .apple, title: "Mirror", writable: true))
        #expect(service.selected == ["google:test.google"])
        #expect(!service.selected.contains("apple:test.apple"))
    }
    @Test func approvalWithoutSelectedCalendarIsRejected() async {
        let service = CalendarService()
        let now = Date.now
        let original = Commitment(id: "missing", calendarID: "unselected", provider: .apple, title: "Study", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200), timeZone: "UTC", revision: "v1", canMove: true, recurring: false)
        let proposal = CalendarChange(original: original, newStart: original.start.addingTimeInterval(3600), newEnd: original.end.addingTimeInterval(3600))
        do { _ = try await service.approve(proposal); Issue.record("Unapproved calendar was written") }
        catch { #expect(error as? CalendarActionError == .approvalRequired) }
    }
    @Test func corruptConversationIsPreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try StateStore.prepareExcludedDirectory(directory)
        let store = ConversationStore(directory: directory)
        let bytes = Data("not-json".utf8)
        try bytes.write(to: store.url)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try Data(contentsOf: store.url) == bytes)
    }
    @Test func normalConversationSurvivesRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(directory: directory)
        var state = ConversationState(); state.messages = [.init(text: "Show this week", isUser: true)]
        state.preferences.proactive = true
        try store.save(state)
        #expect(try store.load() == state)
    }
    @Test func intentCacheRequiresExactRequestAndModel() {
        var cache = IntentCache()
        let now = Date(timeIntervalSince1970: 100)
        cache.insert(.explainEnergy, text: "Help with my sluggishness", model: "apple", now: now)
        #expect(cache.lookup("Help with my sluggishness", model: "apple", now: now) == .explainEnergy)
        #expect(cache.lookup("Help with my sluggishness yesterday", model: "apple", now: now) == nil)
        #expect(cache.lookup("Help with my sluggishness", model: "mac:gemma", now: now) == nil)
        #expect(cache.lookup("Help with my sluggishness", model: "apple", now: now.addingTimeInterval(300)) == nil)
    }

    @Test func intentCacheEvictsLeastRecentlyUsedAndClears() {
        var cache = IntentCache(capacity: 2)
        let now = Date(timeIntervalSince1970: 100)
        cache.insert(.explainEnergy, text: "a", model: "apple", now: now)
        cache.insert(.weeklyTrends, text: "b", model: "apple", now: now)
        #expect(cache.lookup("a", model: "apple", now: now) == .explainEnergy)
        cache.insert(.history, text: "c", model: "apple", now: now)
        #expect(cache.lookup("b", model: "apple", now: now) == nil)
        #expect(cache.lookup("c", model: "apple", now: now) == .history)
        cache.clear()
        #expect(cache.lookup("a", model: "apple", now: now) == nil)
        #expect(cache.lookup("c", model: "apple", now: now) == nil)
    }

    @Test func unsupportedInterpretationsAreNotCached() {
        var cache = IntentCache()
        cache.insert(.unsupported, text: "ambiguous", model: "apple")
        #expect(cache.lookup("ambiguous", model: "apple") == nil)
    }

}
