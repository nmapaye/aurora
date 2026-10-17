import AuroraCore
import SwiftUI

/// Static, cited reading from `CaffeineEvidence`: "What changes half-life"
/// beside the half-life setting, and "About the evidence" from Settings and
/// the cutoff card's assumptions. It shows no number of the person's own,
/// asks nothing and is never placed beside a threshold or reference input.
struct CaffeineEvidenceSheet: View {
    enum Topic: String, Identifiable {
        case halfLife, evidence
        var id: String { rawValue }
    }

    let topic: Topic
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private typealias E = CaffeineEvidence

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.lg) {
                    switch topic {
                    case .halfLife:
                        Text(E.halfLifeSummary).font(Typography.evidence)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(E.absorptionNote).font(.footnote).foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        section(title: "Reported effects", intro: nil, items: E.halfLifeFactors)
                    case .evidence:
                        Text(E.evidenceIntro).font(Typography.evidence)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(E.evidenceSections) { section(title: $0.title, intro: $0.intro, items: $0.items) }
                    }
                    Text(E.footer).font(.footnote).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: Metrics.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(Metrics.md)
            }
            .background(Palette.screen)
            .navigationTitle(topic == .halfLife ? E.halfLifeTitle : E.evidenceTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .accessibilityIdentifier("caffeine-evidence-\(topic.rawValue)")
    }

    private func section(title: String, intro: String?, items: [E.Item]) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            SectionLabel(text: title).padding(.horizontal, Metrics.xxs)
            if let intro {
                Text(intro).font(.footnote).foregroundStyle(Palette.textSecondary).padding(.horizontal, Metrics.xxs)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Card {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    row(item)
                }
            }
        }
    }

    private func row(_ item: E.Item) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xxs) {
            Text(item.title).font(.headline).foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(item.text).font(Typography.explanation).foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(item.sources, id: \.self) { source in
                if let link = source.url.flatMap(URL.init(string:)) {
                    Button { openURL(link) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Metrics.xxs) {
                            Text(source.citation).multilineTextAlignment(.leading)
                            Image(systemName: "arrow.up.right").accessibilityHidden(true)
                        }
                        .font(Typography.source)
                        .frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.tint)
                    .accessibilityLabel("Source: \(source.citation)")
                    .accessibilityAddTraits(.isLink)
                } else {
                    Text(source.citation).font(Typography.source).foregroundStyle(Palette.textSecondary)
                        .accessibilityLabel("Source: \(source.citation)")
                }
            }
        }
        .padding(.vertical, Metrics.xxs)
    }
}
