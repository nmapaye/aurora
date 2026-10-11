import AuroraCore
import Charts
import SwiftUI

/// Evidence captured with an energy card: what the model used, what was
/// missing, its limits, and the person's own ratings and tests, kept apart.
/// Everything reads from the snapshot, never from current records.
struct EnergyEvidenceSections: View {
    let snapshot: EnergySnapshot
    let text: DateText
    var showsRecordedByYou = true

    private var estimate: EnergyEstimate { snapshot.estimate }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.md) {
            status
            contributions
            if showsRecordedByYou { EnergyRecordedByYou(snapshot: snapshot, text: text) }
        }
    }

    @ViewBuilder private var status: some View {
        if snapshot.includesSample || !estimate.missingInputs.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                if snapshot.includesSample { StatusBadge(text: "Includes Sample Data", tone: .info) }
                ForEach(estimate.missingInputs, id: \.self) { missing in
                    Label(missing.text, systemImage: StatusTone.warning.symbol)
                        .font(.footnote).foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    private var contributions: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            SectionLabel(text: "What the model used")
            if estimate.contributions.isEmpty {
                Text("No parts to show. The model needs recorded sleep in the 24 hours before this time.")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            ForEach(estimate.contributions, id: \.kind) { part in
                VStack(alignment: .leading, spacing: Metrics.xxs) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
                            Text(part.kind.label).font(Typography.label)
                            Spacer(minLength: 0)
                            Text(part.pointsText).font(Typography.value).monospacedDigit()
                        }
                        VStack(alignment: .leading, spacing: Metrics.xxs) {
                            Text(part.kind.label).font(Typography.label)
                            Text(part.pointsText).font(Typography.value).monospacedDigit()
                        }
                    }
                    Text(detail(part)).font(Typography.source).foregroundStyle(Palette.textSecondary)
                }
                .padding(.vertical, Metrics.xxs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(part.kind.label), \(part.pointsText) points. \(detail(part))")
            }
            if !estimate.contributions.isEmpty {
                Text("Points on the model scale, rounded.")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private func detail(_ part: EnergyContribution) -> String {
        switch part.kind {
        case .baseline: return "Where every estimate starts."
        case .timeOfDay: return "The same daily curve for everyone, by local time."
        case .caffeine:
            return "\(numberText(jsRound(estimate.evidence.activeCaffeineMg))) mg modeled as active, with a \(numberText(estimate.halfLifeHours))h half-life."
        case .sleepDebt:
            return "Recorded sleep in the 24 hours before: \(formatSleepHours(estimate.sleepHoursLast24)). Your goal: \(numberText(estimate.targetSleepHours))h."
        case .inertia:
            return estimate.evidence.lastWakeAt.map { "Recorded sleep ended at \(text.clockTime($0))." } ?? "Not shortly after recorded sleep."
        }
    }
}

/// Ratings and Reaction Tests captured with the card. Listed as recorded,
/// never plotted against or compared with the model.
struct EnergyRecordedByYou: View {
    let snapshot: EnergySnapshot
    let text: DateText

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            SectionLabel(text: "Recorded by you · shown separately")
            if snapshot.checkIns.isEmpty && snapshot.reactions.isEmpty {
                Text("No check-ins or Reaction Tests in this window.").font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            ForEach(snapshot.checkIns) { checkIn in
                CheckInRow(checkIn: checkIn, text: text)
            }
            ForEach(snapshot.reactions) { test in
                VStack(alignment: .leading, spacing: Metrics.xxs) {
                    Text("Reaction Test · \(test.score) · \(test.rating)").font(.subheadline.weight(.medium)).monospacedDigit()
                    Text((test.sample ? "Sample Data" : "Recorded") + " · " + text.fullDateTime(test.completedAt))
                        .font(Typography.source).foregroundStyle(Palette.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            Text(EnergySnapshot.separateNote).font(.footnote).foregroundStyle(Palette.textSecondary)
        }
    }
}

struct CheckInRow: View {
    let checkIn: EnergyCheckIn
    let text: DateText

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xxs) {
            Text("Check-in · \(checkIn.ratingText)").font(.subheadline.weight(.medium)).monospacedDigit()
            Text(EnergyCheckIn.sourceLabel + " · " + text.fullDateTime(checkIn.recordedAt))
                .font(Typography.source).foregroundStyle(Palette.textSecondary)
            if let note = checkIn.note { Text(note).font(.footnote).foregroundStyle(Palette.textSecondary) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The 24-hour modeled curve with its current marker. Recorded sleep and
/// caffeine are drawn as their own marks; modeled points are a line, solid
/// before capture and dashed after. Tap or drag to read a point; VoiceOver
/// steps through points.
struct EnergyTimelineChart: View {
    let snapshot: EnergySnapshot
    let projection: EnergyProjection
    let text: DateText
    let timeZone: TimeZone
    @State private var selected: Date?
    @State private var adjustedIndex: Int?
    @Environment(\.isWideLayout) private var wide

    private struct Run: Identifiable {
        let id: Int
        let projected: Bool
        let points: [EnergyProjection.Point]
    }

    var body: some View {
        let index = currentIndex
        VStack(alignment: .leading, spacing: Metrics.sm) {
            readout(projection.points[index])
                .accessibilityHidden(true)
            chart(highlight: index)
                .frame(height: wide ? 240 : 180)
                .environment(\.timeZone, timeZone)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary)
                .accessibilityValue(spoken(projection.points[index]))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: adjustedIndex = min(projection.points.count - 1, index + 1)
                    case .decrement: adjustedIndex = max(0, index - 1)
                    @unknown default: break
                    }
                    selected = nil
                }
                .accessibilityIdentifier("assistant-energy-curve")
            legend
            Text(EnergyProjection.futureAssumption).font(.footnote).foregroundStyle(Palette.textSecondary)
            observations
        }
    }

    private var currentIndex: Int {
        if let selected {
            let ms = selected.timeIntervalSince1970 * 1000
            return projection.points.indices.min { abs(projection.points[$0].t - ms) < abs(projection.points[$1].t - ms) } ?? projection.currentIndex
        }
        if let adjustedIndex, projection.points.indices.contains(adjustedIndex) { return adjustedIndex }
        return projection.currentIndex
    }

    private func value(_ point: EnergyProjection.Point) -> String {
        point.modeledScore.map { "\($0)" } ?? "No score"
    }

    private func spoken(_ point: EnergyProjection.Point) -> String {
        let score = point.modeledScore.map { "\(EnergyEstimate.title) \($0)" } ?? "No modeled score, no sleep recorded in the 24 hours before"
        return "\(text.fullDateTime(point.t)), \(score). \(point.kind.label)."
    }

    private var accessibilitySummary: String {
        "\(EnergyEstimate.title), 24 hours. \(text.clockTime(projection.points.first?.t ?? projection.capturedAt)) to \(text.clockTime(projection.points.last?.t ?? projection.capturedAt)). Modeled."
    }

    private func readout(_ point: EnergyProjection.Point) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.fullDateTime(point.t)).font(.caption).foregroundStyle(Palette.textSecondary)
                    Text(point.kind.label).font(.caption).foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 0)
                Text(value(point)).font(Typography.heroValue).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value(point)).font(Typography.heroValue).monospacedDigit()
                Text(text.fullDateTime(point.t)).font(.caption).foregroundStyle(Palette.textSecondary)
                Text(point.kind.label).font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    /// Contiguous scored points, split where there is no score and where
    /// modeled turns to projected. The current point joins both sides.
    private var runs: [Run] {
        var runs: [Run] = []
        var current: [EnergyProjection.Point] = []
        var projected = false
        func close() {
            if !current.isEmpty { runs.append(Run(id: runs.count, projected: projected, points: current)) }
            current = []
        }
        for point in projection.points {
            guard point.modeledScore != nil else { close(); continue }
            let isProjected = point.kind == .projected
            if isProjected != projected {
                let joint = current.last
                close()
                if let joint, joint.kind == .current { current = [joint] }
                projected = isProjected
            }
            current.append(point)
        }
        close()
        return runs
    }

    private func date(_ t: Millis) -> Date { Date(timeIntervalSince1970: t / 1000) }

    private func chart(highlight: Int) -> some View {
        Chart {
            ForEach(Array(snapshot.mergedSleep.enumerated()), id: \.offset) { _, sleep in
                RectangleMark(
                    xStart: .value("Sleep start", date(max(sleep.start, projection.points.first?.t ?? sleep.start))),
                    xEnd: .value("Sleep end", date(sleep.end)),
                    yStart: .value("Score", 0), yEnd: .value("Score", 100)
                )
                .foregroundStyle(Palette.sleepAccent.opacity(0.14))
            }
            ForEach(runs) { run in
                ForEach(run.points, id: \.t) { point in
                    LineMark(x: .value("Time", date(point.t)), y: .value("Modeled alertness", point.modeledScore ?? 0), series: .value("Run", "\(run.id)"))
                        .foregroundStyle(Palette.tint)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: run.projected ? [5, 4] : []))
                        .interpolationMethod(.linear)
                }
            }
            ForEach(snapshot.observations.filter { $0.kind == .caffeine && $0.start >= (projection.points.first?.t ?? 0) }) { dose in
                PointMark(x: .value("Recorded caffeine", date(dose.start)), y: .value("Score", 4))
                    .symbol(.triangle)
                    .symbolSize(50)
                    .foregroundStyle(Palette.caffeineAccent.opacity(dose.source == .sample ? 0.5 : 1))
            }
            RuleMark(x: .value("Now", date(projection.capturedAt)))
                .foregroundStyle(Palette.textTertiary)
                .lineStyle(StrokeStyle(lineWidth: 1))
            if let score = projection.current.modeledScore {
                PointMark(x: .value("Now", date(projection.capturedAt)), y: .value("Modeled alertness", score))
                    .symbolSize(70)
                    .foregroundStyle(Palette.tint)
            }
            if highlight != projection.currentIndex {
                let point = projection.points[highlight]
                RuleMark(x: .value("Selected", date(point.t)))
                    .foregroundStyle(Palette.separator)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine().foregroundStyle(Palette.separator)
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { _ in
                AxisGridLine().foregroundStyle(Palette.separator)
                AxisValueLabel()
            }
        }
        .chartXSelection(value: $selected)
    }

    /// Shapes and dash patterns name each mark, so color is never the only cue.
    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Metrics.md) { legendItems }
            VStack(alignment: .leading, spacing: Metrics.xs) { legendItems }
        }
        .font(.caption).foregroundStyle(Palette.textSecondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var legendItems: some View {
        Label("Modeled", systemImage: "line.diagonal")
        Label("Projected", systemImage: "ellipsis")
        Label("Now", systemImage: "circle.fill")
        Label("Recorded caffeine", systemImage: "triangle.fill")
        Label("Recorded sleep", systemImage: "rectangle.fill")
    }

    private var observations: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            SectionLabel(text: "Recorded in this window")
            if snapshot.observations.isEmpty {
                Text("No sleep or caffeine recorded in this window.").font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            ForEach(snapshot.observations) { item in
                VStack(alignment: .leading, spacing: Metrics.xxs) {
                    Text(item.kind == .sleep
                         ? "Sleep · \(text.clockTime(item.start)) – \(text.clockTime(item.end)) · \(formatHoursMinutes(durationMs: item.end - item.start))"
                         : "Caffeine · \(numberText(item.mg ?? 0)) mg · \(text.clockTime(item.start))")
                        .font(.subheadline.weight(.medium)).monospacedDigit()
                    Text(sourceLabel(item.source)).font(Typography.source).foregroundStyle(Palette.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func sourceLabel(_ source: EnergyInputSource) -> String {
        switch source {
        case .manual: "Manual"
        case .health: "Health · read-only"
        case .sample: "Sample Data"
        }
    }
}
