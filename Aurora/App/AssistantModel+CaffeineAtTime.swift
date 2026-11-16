import AuroraCore
import Foundation

/// Follow-up chat: "how much caffeine at <time>". Routed in code before any
/// model, so it works with Apple Intelligence off. The card's numbers come
/// from `CaffeineAtTime`; nothing here records a dose or writes to Health.
/// "Log This Drink" opens the usual confirm card and saves only on Save.
extension AssistantModel {
    var caffeineAtTimeZone: TimeZone { cutoffZone() }

    func openCaffeineAtTime(_ parsed: CaffeineQuestion.Parsed, question: String, app: AppModel) {
        app.tick()
        expireDraft()
        let zone = caffeineAtTimeZone
        let clock = LocalClock(timeZone: zone)
        var card = AssistantCards.make(.caffeineAtTime, state: app.state, now: app.now, clock: clock, text: .localized(timeZone: zone))
        card.timeZone = zone.identifier
        card.caffeineAtTime = CaffeineAtTimeCard.start(parsed, question: question, db: CaffeineDatabase.bundled, doses: app.state.doses,
                                                       sleeps: app.state.sleeps, halfLifeHours: app.state.prefs.halfLife, now: app.now, clock: clock)
        caffeineAtTimeID = appendCard(card)
    }

    /// The open follow-up card's id, if `id` is it and it can still act.
    func openCaffeineAtTimeCard(_ id: UUID?) -> UUID? {
        guard let id, id == caffeineAtTimeID, activeCards.contains(id),
              let card = conversation.messages.first(where: { $0.id == id })?.card,
              card.kind == .caffeineAtTime, card.state == .ready, card.caffeineAtTime != nil else { return nil }
        return id
    }

    private func changeCaffeineAtTime(_ id: UUID?, app: AppModel, _ change: (inout CaffeineAtTimeCard, Millis) -> Void) {
        guard let id = openCaffeineAtTimeCard(id) else { return }
        app.tick()
        let now = app.now
        updateCard(id) { card in
            guard var state = card.caffeineAtTime else { return }
            change(&state, now)
            state.capturedAt = now
            card.capturedAt = now
            card.caffeineAtTime = state
        }
    }

    func chooseCaffeineAtTime(_ id: UUID, _ choice: CaffeineAtTimeCard.Choice, app: AppModel) {
        let doses = app.state.doses
        changeCaffeineAtTime(id, app: app) { $0.choose(choice, db: CaffeineDatabase.bundled, doses: doses, now: $1) }
    }

    func setCaffeineAtTimeSleep(_ id: UUID, hour: Int, minute: Int, app: AppModel) {
        let doses = app.state.doses
        changeCaffeineAtTime(id, app: app) { $0.setSleepTime(hour: hour, minute: minute, doses: doses, now: $1) }
    }

    /// Returns false (and changes nothing) for an amount outside 1–1999 whole mg.
    @discardableResult
    func setCaffeineAtTimeAmount(_ id: UUID, _ text: String, app: AppModel) -> Bool {
        let doses = app.state.doses
        var accepted = false
        changeCaffeineAtTime(id, app: app) { accepted = $0.setAmount(text, doses: doses, now: $1) }
        return accepted
    }

    /// "Actually a caramel latte" while a follow-up card with a drink is open.
    func correctCaffeineAtTime(_ phrase: String, app: AppModel) -> Bool {
        guard let id = openCaffeineAtTimeCard(caffeineAtTimeID),
              conversation.messages.first(where: { $0.id == id })?.card?.caffeineAtTime?.drink != nil else { return false }
        let clock = LocalClock(timeZone: caffeineAtTimeZone)
        let doses = app.state.doses
        changeCaffeineAtTime(id, app: app) { _ = $0.correct(phrase, db: CaffeineDatabase.bundled, doses: doses, now: $1, clock: clock) }
        return true
    }

    /// Opens the confirm card with the Not Logged drink. Always confirm:
    /// the save switch never applies here, and nothing saves without Save.
    func logCaffeineAtTimeDrink(_ id: UUID, app: AppModel) {
        guard let id = openCaffeineAtTimeCard(id), !processing,
              let draft = conversation.messages.first(where: { $0.id == id })?.card?.caffeineAtTime?.logDraft else { return }
        app.tick()
        expireDraft()
        pendingDraft = draft
        pendingMessageID = appendCard(AssistantCards.make(.caffeineDraft, state: app.state, now: app.now, clock: app.clock, text: app.text), intent: .logCaffeine)
        captureDraft(app: app)
    }

    /// A later request closes the follow-up card; its rows stay as captured.
    func closeCaffeineAtTime() {
        guard let id = caffeineAtTimeID else { return }
        caffeineAtTimeID = nil
        activeCards.remove(id)
        updateCard(id) { if $0.state == .ready { $0.state = .expired } }
    }
}
