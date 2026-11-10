import Foundation
import Testing
@testable import AuroraCore

/// Nov 10 CPO conditions for the existing-install Terms sheet: Continue only,
/// no implied consent, covering work until Continue, and shown again only
/// when the Terms version goes up.
@Suite struct TermsUpdatePromptTests {
    var preTerms: Onboarding { var o = Onboarding.defaults; o.completed = true; return o }

    @Test func sheetCanOnlyBeLeftWithContinue() {
        var onboarding = preTerms
        #expect(TermsUpdatePrompt.isPresented(onboarding, welcomeShowing: false))
        // A swipe changes nothing saved, so it's refused and the sheet stays.
        #expect(!TermsUpdatePrompt.allowsDismiss(onboarding))
        #expect(TermsUpdatePrompt.coversWork(onboarding))
        #expect(onboarding.termsAcceptedVersion == nil)
        // Only Continue's save lets it go.
        var state = AppState(); state.onboarding = onboarding
        state.acknowledgeTerms(); onboarding = state.onboarding
        #expect(TermsUpdatePrompt.allowsDismiss(onboarding))
        #expect(!TermsUpdatePrompt.isPresented(onboarding, welcomeShowing: false))
        #expect(!TermsUpdatePrompt.coversWork(onboarding))
        #expect(TermsUpdatePrompt.title == "Terms and Privacy" && TermsUpdatePrompt.continueTitle == "Continue")
    }

    @Test func waitsForTheWelcomeButStillCoversWork() {
        #expect(!TermsUpdatePrompt.isPresented(preTerms, welcomeShowing: true))
        #expect(TermsUpdatePrompt.coversWork(preTerms))
        // Setup isn't finished: first run records its own acknowledgement.
        #expect(!TermsUpdatePrompt.isPresented(.defaults, welcomeShowing: false))
    }

    @Test func shownAgainOnlyWhenTheVersionGoesUp() {
        var onboarding = preTerms
        onboarding.termsAcceptedVersion = LegalCopy.version
        // Same version, every later launch: not shown.
        #expect(!TermsUpdatePrompt.isPresented(onboarding, welcomeShowing: false))
        // A newer Terms version: shown, and can't be swiped away.
        #expect(TermsUpdatePrompt.isPresented(onboarding, welcomeShowing: false, currentVersion: LegalCopy.version + 1))
        #expect(!TermsUpdatePrompt.allowsDismiss(onboarding, currentVersion: LegalCopy.version + 1))
        // An older build reading a newer acknowledgement: not shown.
        #expect(!TermsUpdatePrompt.isPresented(onboarding, welcomeShowing: false, currentVersion: LegalCopy.version - 1))
        onboarding.termsAcceptedVersion = LegalCopy.version + 1
        #expect(!TermsUpdatePrompt.isPresented(onboarding, welcomeShowing: false))
    }

    /// Terms v2 moved the card disclaimers into Terms, so an install that
    /// acknowledged v1 sees the sheet again, once, until Continue.
    @Test func versionTwoAsksInstallsThatAcknowledgedVersionOne() {
        #expect(LegalCopy.version == 2)
        var onboarding = preTerms
        onboarding.termsAcceptedVersion = 1
        #expect(TermsUpdatePrompt.isPresented(onboarding, welcomeShowing: false))
        #expect(!TermsUpdatePrompt.allowsDismiss(onboarding))
        #expect(TermsUpdatePrompt.coversWork(onboarding))
        var state = AppState(); state.onboarding = onboarding
        state.acknowledgeTerms()
        #expect(state.onboarding.termsAcceptedVersion == 2)
        #expect(!TermsUpdatePrompt.isPresented(state.onboarding, welcomeShowing: false))
        #expect(!TermsUpdatePrompt.coversWork(state.onboarding))
    }

    /// The summary restates the full text; it adds no claim of its own.
    @Test func summaryRestatesTheFullTerms() {
        let full = (LegalCopy.terms + LegalCopy.privacy).map(\.body).joined(separator: " ")
        #expect(LegalCopy.updateSummary.count == 4)
        for phrase in ["modeled from what you record", "aren’t measurements", "isn’t a medical device",
                       "Check with a doctor before medical decisions", "no Aurora account, no cloud AI service, no analytics and no tracking",
                       "Apple Health is optional", "advertising, marketing or resale", "Informational only", "safety limit"] {
            #expect(full.contains(phrase), "\(phrase)")
            #expect(LegalCopy.updateSummary.contains { $0.contains(phrase) }, "\(phrase)")
        }
        #expect(LegalCopy.acknowledgement.hasPrefix("By continuing"))
    }

    /// Nathan's rule (Nov 10): disclaimers live in Terms and Privacy. The
    /// estimate, projection and scenario text no longer says them.
    @Test func disclaimersAreInTermsNotInAppText() throws {
        let la = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let clock = LocalClock(timeZone: la)
        let text = DateText.localized(locale: Locale(identifier: "en_US"), timeZone: la)
        let now: Millis = 1_790_527_260_000
        var state = AppState()
        state.sleeps = [SleepSession(id: "manual:sleep:1:a", start: now - 9 * hourMs, end: now - hourMs)]
        let estimate = Summary.estimateAlertness(at: now, doses: [], sleeps: state.sleeps, inputs: EstimateInputs(prefs: state.prefs, clock: clock))
        let projection = AssistantCards.make(.energyProjection, state: state, now: now, clock: clock, text: text)
        let scenario = AssistantCards.make(.cutoffScenario, state: state, now: now, clock: clock, text: text)
        for copy in [Summary.describe(estimate), Summary.describe(.needsSleep), projection.summary, scenario.summary] {
            for phrase in ["not a measurement", "aren’t measured", "safety limit", "recommendation", "assume no further"] {
                #expect(!copy.contains(phrase), "\(phrase) in \(copy)")
            }
        }
        #expect(projection.summary.isEmpty)
    }

    /// R7: with a curve and no failure the 24-hour card has no text line at
    /// all, so there's no blank row or empty VoiceOver element.
    @Test func projectionCardHasNoEmptyStatusLine() throws {
        let la = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let clock = LocalClock(timeZone: la)
        let text = DateText.localized(locale: Locale(identifier: "en_US"), timeZone: la)
        let now: Millis = 1_790_527_260_000
        var state = AppState()
        state.sleeps = [SleepSession(id: "manual:sleep:1:a", start: now - 9 * hourMs, end: now - hourMs)]
        var card = AssistantCards.make(.energyProjection, state: state, now: now, clock: clock, text: text)
        #expect(card.energy?.projection?.points.isEmpty == false)
        #expect(card.summary.isEmpty && card.projectionStatusLine == nil)
        // A failure with no message still draws nothing empty.
        card.state = .failed
        #expect(card.projectionStatusLine == nil)
        card.summary = "This request didn't finish. Refresh for a current result."
        #expect(card.projectionStatusLine == card.summary)
        // No curve: the refresh line, never an empty string.
        card.energy?.projection = nil; card.summary = ""; card.state = .ready
        #expect(card.projectionStatusLine == "This snapshot has no curve. Refresh for a current one.")
        // Q8: the projected point label is the word alone.
        #expect(EnergyProjection.PointKind.projected.label == "Projected")
    }
}
