import AuroraCore
import SwiftUI

/// The first-launch acknowledgement under the story: one line, with Terms
/// and Privacy each opening in a sheet. Leaving the story (Skip or Begin
/// setup) records the acknowledgement.
struct LegalAcknowledgement: View {
    @State private var showing: LegalDocument?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xxs) {
            Text(LegalCopy.acknowledgement)
                .font(.footnote).foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Each link is its own 44 pt target, and the pair stacks when
            // large text no longer fits both on one line (audit: hit region
            // and clipped "Privacy Policy").
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Metrics.md) { links }
                VStack(alignment: .leading, spacing: 0) { links }
            }
            .font(.footnote.weight(.semibold))
            .tint(Palette.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $showing) { LegalDocumentView(document: $0) }
    }

    @ViewBuilder private var links: some View {
        link("Terms", .terms, hint: "Opens Aurora’s Terms.", id: "onboarding-terms")
        link("Privacy Policy", .privacy, hint: "Opens Aurora’s Privacy Policy.", id: "onboarding-privacy")
    }

    private func link(_ title: String, _ document: LegalDocument, hint: String, id: String) -> some View {
        Button { showing = document } label: {
            Text(title)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: Metrics.minimumTouchTarget, minHeight: Metrics.minimumTouchTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .accessibilityHint(hint)
        .accessibilityIdentifier(id)
    }
}

enum LegalDocument: String, Identifiable {
    case terms, privacy
    var id: String { rawValue }
    var title: String { self == .terms ? "Terms" : "Privacy Policy" }
    var sections: [LegalCopy.Section] { self == .terms ? LegalCopy.terms : LegalCopy.privacy }
}

/// Terms or Privacy in the app, readable offline. Settings opens the same
/// view.
struct LegalDocumentView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.lg) {
                    ForEach(document.sections) { section in
                        VStack(alignment: .leading, spacing: Metrics.xs) {
                            Text(section.title).font(.headline).foregroundStyle(Palette.textPrimary)
                                .accessibilityAddTraits(.isHeader)
                            Text(section.body).font(.body).foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(Metrics.lg)
                .frame(maxWidth: Metrics.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.modalBackground.ignoresSafeArea())
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("legal-done")
                }
            }
        }
        .accessibilityIdentifier("legal-\(document.rawValue)")
    }
}

/// Shown to an install that finished setup before Terms existed, or on an
/// older version. It needs an explicit Continue: no swipe-to-dismiss, and
/// nothing counts as agreement until Continue saves. It comes back only when
/// the Terms version goes up. Settings keeps Terms and Privacy available.
struct TermsUpdateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.md) {
                    Text("Aurora’s Terms and Privacy Policy are now in the app. In short:")
                        .font(.body).foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: Metrics.sm) {
                        ForEach(LegalCopy.updateSummary, id: \.self) { line in
                            HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                                Text("•").accessibilityHidden(true)
                                Text(line).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.body).foregroundStyle(Palette.textSecondary)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    LegalAcknowledgement()
                    if let failure {
                        StatusText(text: failure, tone: .error)
                            .accessibilityIdentifier("terms-update-failure")
                    }
                }
                .padding(Metrics.lg)
                .frame(maxWidth: Metrics.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Palette.modalBackground.ignoresSafeArea())
            .navigationTitle(TermsUpdatePrompt.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // In the bar, so it's never scrolled or clipped off screen.
                ToolbarItem(placement: .confirmationAction) {
                    Button(TermsUpdatePrompt.continueTitle, action: accept)
                        .accessibilityHint("Agrees to Aurora’s Terms and Privacy Policy.")
                        .accessibilityIdentifier("terms-update-continue")
                }
            }
        }
        // Large text gets the full height; the content scrolls either way.
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .interactiveDismissDisabled(true)
        .accessibilityIdentifier("terms-update")
    }

    private func accept() {
        if model.acknowledgeTerms() { failure = nil; dismiss() }
        else { failure = model.mutationFailure ?? "Couldn’t save. Try again." }
    }
}
