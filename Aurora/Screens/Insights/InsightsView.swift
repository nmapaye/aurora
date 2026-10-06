import AuroraCore
import SwiftUI

/// Insights: what was recorded over a range. Days without entries read "No
/// record", never 0 mg; the average counts recorded days only; a comparison
/// appears only when both periods have enough recorded days.
struct InsightsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var range: InsightsRange = .default
    @State private var showDetails = false

    var body: some View {
        let state = model.state
        let p = Insights.presentation(
            doses: state.doses, vigilanceSessions: state.vigilanceSessions, range: range,
            now: model.now, clock: model.clock, text: model.text
        )
        AppScreen(title: "Insights", subtitle: "What you recorded over time.") {
            RangeControl(
                label: "Insights range",
                options: [(InsightsRange.week, "W", "Week"), (.twoWeeks, "2W", "Two weeks"), (.month, "M", "Month")],
                selection: $range
            )
            WideColumns {
                intake(p)
            } trailing: {
                reaction(p)
                details(p)
            }
        }
    }

    private func intake(_ p: InsightsPresentation) -> some View {
        let days = p.points.map { point -> DailyBarChart.Day in
            let readout = Insights.describeChartDay(point, text: model.text)
            return DailyBarChart.Day(
                date: point.date,
                value: point.mg.map(Double.init),
                title: readout.title,
                readout: readout.value,
                isSample: point.source == .sample
            )
        }
        return VStack(alignment: .leading, spacing: Metrics.sm) {
            if let headline = p.headline {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.largeTitle.bold().monospacedDigit())
                        .foregroundStyle(p.source == .sample ? Palette.textSecondary : Palette.textPrimary)
                    Text(p.period).font(.footnote).foregroundStyle(Palette.textSecondary)
                    if let source = p.source {
                        Text(source.rawValue)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(source == .manual ? Palette.textSecondary : StatusTone.warning.foreground)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            DailyBarChart(
                title: "Caffeine Intake",
                days: days,
                unit: "mg",
                accent: Palette.caffeineAccent,
                defaultIndex: p.isEmpty ? nil : p.latestRecordedIndex,
                accessibilitySummary: p.accessibilitySummary,
                emptyMessage: "No caffeine recorded in this range."
            )
            Text(p.trend.text)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if case .compared(_, _, _, _, _, let detail) = p.trend {
                Text(detail).font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private func reaction(_ p: InsightsPresentation) -> some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            SignalCard(model: p.reaction.signal, symbol: "speedometer", accent: Palette.vigilanceAccent) {
                router.presentReactionTest()
            }
            Button("Take Reaction Test") { router.presentReactionTest() }
                .buttonStyle(.auroraSecondary)
        }
    }

    private func details(_ p: InsightsPresentation) -> some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            Button {
                withAnimation { showDetails.toggle() }
            } label: {
                HStack {
                    Text("Details").font(.headline).foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down").foregroundStyle(Palette.textTertiary)
                }
                .padding(Metrics.md)
                .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.card))
                .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.cardBorder))
            }
            .buttonStyle(.plain)
            .accessibilityHint(showDetails ? "Hides time of day and drinks" : "Shows time of day and drinks")

            if showDetails {
                Card {
                    SectionLabel(text: "Time of Day")
                    ForEach(p.dayparts, id: \.label) { part in
                        row(part.label, value: part.entries == 0 ? "No record" : "\(numberText(jsRound(part.mg))) mg · \(part.entries) \(part.entries == 1 ? "entry" : "entries")")
                    }
                }
                Card {
                    SectionLabel(text: "Drinks")
                    if p.drinkMix.isEmpty {
                        Text("No record").font(.footnote).foregroundStyle(Palette.textSecondary)
                    }
                    ForEach(p.drinkMix, id: \.label) { item in
                        row(item.label, value: "\(numberText(jsRound(item.mg))) mg · \(item.pct)%")
                    }
                    if let source = p.source, source != .manual {
                        Text("Includes \(source == .sample ? "only " : "")Sample Data.")
                            .font(.caption)
                            .foregroundStyle(StatusTone.warning.foreground)
                    }
                }
                Button("Show All Caffeine Data") {
                    router.open(.caffeineHistory)
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Palette.textPrimary)
            Spacer()
            Text(value).foregroundStyle(Palette.textSecondary).monospacedDigit()
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
