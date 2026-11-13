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

    /// The summary restates the full text; it adds no claim of its own.
    @Test func summaryRestatesTheFullTerms() {
        let full = (LegalCopy.terms + LegalCopy.privacy).map(\.body).joined(separator: " ")
        #expect(LegalCopy.updateSummary.count == 4)
        for phrase in ["modeled from what you record", "aren’t measurements", "isn’t a medical device",
                       "Check with a doctor before medical decisions", "no Aurora account, no cloud AI service, no analytics and no tracking",
                       "Apple Health is optional", "advertising, marketing or resale", "Informational only"] {
            #expect(full.contains(phrase), "\(phrase)")
            #expect(LegalCopy.updateSummary.contains { $0.contains(phrase) }, "\(phrase)")
        }
        #expect(LegalCopy.acknowledgement.hasPrefix("By continuing"))
    }
}
