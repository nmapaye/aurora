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
            HStack(spacing: Metrics.md) {
                Button("Terms") { showing = .terms }
                    .accessibilityHint("Opens Aurora’s Terms.")
                    .accessibilityIdentifier("onboarding-terms")
                Button("Privacy Policy") { showing = .privacy }
                    .accessibilityHint("Opens Aurora’s Privacy Policy.")
                    .accessibilityIdentifier("onboarding-privacy")
            }
            .font(.footnote.weight(.semibold))
            .tint(Palette.tint)
            .frame(minHeight: Metrics.minimumTouchTarget)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $showing) { LegalDocumentView(document: $0) }
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
