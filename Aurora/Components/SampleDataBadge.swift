import SwiftUI

/// The one label for Sample Data, wherever it appears: its own symbol in
/// the sample accent (design.md), so sample records never read as the
/// person's own. It sits on the card color with an accent edge, which keeps
/// the text above 4.5:1 on muted sample rows too. An optional detail
/// follows the name, such as the sample share of a total.
struct SampleDataBadge: View {
    var detail: String?

    /// The sample accent.
    static let accent = Palette.caffeineAccent

    var body: some View {
        Label {
            Text(["Sample Data", detail].compactMap { $0 }.joined(separator: " · "))
        } icon: {
            Image(systemName: "testtube.2").accessibilityHidden(true)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Self.accent)
        .padding(.horizontal, Metrics.sm)
        .padding(.vertical, Metrics.xxs)
        .background(Palette.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Self.accent))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sample-data-badge")
    }
}
