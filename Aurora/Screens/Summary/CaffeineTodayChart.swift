import AuroraCore
import Charts
import SwiftUI

/// Today's modeled active caffeine, from local midnight to midnight. Tap or
/// drag to inspect a time; VoiceOver can step through the hours. The user's
/// own cutoff is marked as context, never as a recommendation.
struct CaffeineTodayChart: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isWideLayout) private var wide
    @State private var selectedTime: Date?
    @State private var inspectedIndex: Int?

    var body: some View {
        let state = model.state
        let today = TodayCaffeineSeries.make(doses: state.doses, halfLifeHours: state.prefs.halfLife, now: model.now, clock: model.clock)
        let cutoff = Summary.cutoffAnnotation(
            now: model.now, cutoffHour: state.prefs.cutoffHour, doses: state.doses, clock: model.clock, formatTime: model.text.clockTime
        )
        let hasSignal = Summary.hasCaffeineSignal(series: today.series, doses: state.doses, dayStart: today.start, dayEnd: today.end)

        VStack(alignment: .leading, spacing: Metrics.sm) {
            if hasSignal {
                let index = currentIndex(today)
                let inspection = Summary.inspect(
                    point: today.series[index], doses: state.doses, sleeps: state.sleeps,
                    inputs: EstimateInputs(prefs: state.prefs, clock: model.clock), dayStart: today.start, now: model.now
                )
                readout(inspection)
                chart(today, cutoff: cutoff, inspectedT: today.series[index].t)
                    .frame(height: wide ? 240 : 160)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Summary.describeCaffeineDay(
                        series: today.series, doses: state.doses, dayStart: today.start, dayEnd: today.end, formatTime: model.text.clockTime
                    ))
                    .accessibilityValue(Summary.describe(inspection, formatTime: model.text.clockTime))
                    .accessibilityAdjustableAction { direction in
                        let current = currentIndex(today)
                        switch direction {
                        case .increment: inspectedIndex = min(today.series.count - 1, current + 1)
                        case .decrement: inspectedIndex = max(0, current - 1)
                        @unknown default: break
                        }
                        selectedTime = nil
                    }
                    .accessibilityIdentifier("caffeine-today-chart")
            } else {
                VStack(alignment: .leading, spacing: Metrics.xxs) {
                    Text(Summary.noCaffeineTitle)
                        .font(.headline)
                        .foregroundStyle(Palette.textPrimary)
                    Text(Summary.noCaffeineBody)
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Summary.describeNoCaffeineNote(cutoffText: cutoff?.text))
            }
            if let cutoff {
                Label(cutoff.text, systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(hasSignal == false)
            }
        }
        .onChange(of: model.now) { _, _ in
            if selectedTime == nil { inspectedIndex = nil }
        }
    }

    private func currentIndex(_ today: TodayCaffeineSeries) -> Int {
        if let selectedTime {
            let ms = selectedTime.timeIntervalSince1970 * 1000
            return max(0, Summary.nearestIndex(today.series.map(\.t), to: ms))
        }
        if let inspectedIndex, inspectedIndex < today.series.count { return inspectedIndex }
        return Summary.nowIndex(today.series, now: today.now)
    }

    private func readout(_ inspection: Summary.CaffeineInspection) -> some View {
        let time = inspection.isNow ? "Now, \(model.text.clockTime(inspection.t))" : model.text.clockTime(inspection.t)
        return HStack(alignment: .firstTextBaseline, spacing: Metrics.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(time).font(.footnote.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                Text("\(jsRoundInt(inspection.activeMg)) mg")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
                Text(inspection.isFuture ? "Projected active caffeine" : "Modeled active caffeine")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(inspection.loggedCount == 0 ? "None logged by then" : "\(jsRoundInt(inspection.loggedMg)) mg logged")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(inspection.loggedCount == 0 ? "Logged today" : "\(inspection.loggedCount) \(inspection.loggedCount == 1 ? "dose" : "doses") today")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .accessibilityHidden(true)
    }

    private func chart(_ today: TodayCaffeineSeries, cutoff: Summary.CutoffAnnotation?, inspectedT: Millis) -> some View {
        let points = today.series.map { (date: Date(timeIntervalSince1970: $0.t / 1000), mg: $0.mg, hasDose: $0.hasDose) }
        let nowDate = Date(timeIntervalSince1970: today.now / 1000)
        return Chart {
            ForEach(points.indices, id: \.self) { i in
                AreaMark(x: .value("Time", points[i].date), y: .value("Active caffeine", points[i].mg))
                    .foregroundStyle(
                        LinearGradient(colors: [Palette.activeCaffeineAccent.opacity(0.28), Palette.activeCaffeineAccent.opacity(0.02)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", points[i].date), y: .value("Active caffeine", points[i].mg))
                    .foregroundStyle(Palette.activeCaffeineAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let cutoff {
                RuleMark(x: .value("Cutoff", Date(timeIntervalSince1970: cutoff.at / 1000)))
                    .foregroundStyle(Palette.cutoffAccent)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            RuleMark(x: .value("Now", nowDate))
                .foregroundStyle(Palette.textTertiary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1))
            if let point = points.first(where: { $0.date.timeIntervalSince1970 * 1000 == inspectedT }) {
                PointMark(x: .value("Time", point.date), y: .value("Active caffeine", point.mg))
                    .foregroundStyle(Palette.tint)
                    .symbolSize(80)
            }
        }
        .chartXScale(domain: Date(timeIntervalSince1970: today.start / 1000)...Date(timeIntervalSince1970: today.end / 1000))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Palette.separator)
                AxisValueLabel {
                    if let mg = value.as(Double.self) { Text("\(Int(mg))") }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine().foregroundStyle(Palette.separator)
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartXSelection(value: $selectedTime)
    }
}
