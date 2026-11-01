import AuroraCore
import SwiftUI

/// "Why this number": the captured estimate explained from the inputs the
/// model used. Everything shown comes from `AlertnessExplanation`, which
/// reads only the snapshot's `EnergyEstimate`.
struct WhyThisNumberCard: View {
    let estimate: EnergyEstimate
    let text: DateText


    var body: some View {
        let explanation = AlertnessExplanation.explain(estimate, text: text)
        VStack(alignment: .leading, spacing: Metrics.sm) {
            Text(explanation.headline)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if explanation.includesSample { SampleDataBadge() }
            ForEach(explanation.factors) { factor in
                VStack(alignment: .leading, spacing: Metrics.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
                        Text(factor.title).font(Typography.label)
                        if factor.kind == explanation.largest {
                            Text("Largest part").font(.caption2.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                        if let points = factor.points {
                            Text(points).font(Typography.value).monospacedDigit()
                        }
                    }
                    Text(factor.detail)
                        .font(Typography.source).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel([factor.title, factor.points.map { "\($0) points" }, factor.detail].compactMap { $0 }.joined(separator: ". "))
            }
            ForEach(explanation.notes, id: \.self) { note in
                Text(note).font(.footnote).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("why-this-number")
    }
}
