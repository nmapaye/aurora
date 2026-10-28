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
                if snapshot.includesSample { SampleDataBadge() }
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
                Text("No parts to show. The model needs a recorded sleep block of at least 3 hours reaching the 18 hours before this time. Ongoing sleep counts only up to this time.")
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

/// One energy or briefing metric. A value is a hero quantity with its
/// source; alertness with no score leads with the record that's missing
/// instead, with no scale for a value that doesn't exist.
struct EnergyMetricHero: View {
    let item: AssistantCard.Metric

    /// Cards captured before the missing line existed say "Modeled" there.
    private var missingLine: String {
        item.source.hasPrefix("No ") ? item.source : EnergyEstimate.missingSleepLine
    }

    var body: some View {
        if item.id == "alertness" && item.missing {
            VStack(alignment: .leading, spacing: Metrics.xxs) {
                Text(item.label).font(Typography.label).foregroundStyle(Palette.textSecondary)
                Label(missingLine, systemImage: StatusTone.warning.symbol)
                    .font(Typography.evidence.weight(.semibold)).foregroundStyle(Palette.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("assistant-energy-missing")
        } else {
            VStack(alignment: .leading, spacing: Metrics.xxs) {
                Text(item.label).font(Typography.label).foregroundStyle(Palette.textSecondary)
                Text(item.value).font(Typography.heroValue).monospacedDigit()
                if !item.source.isEmpty { Text(item.source).font(Typography.source).foregroundStyle(Palette.textSecondary) }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// A way to add each missing record. Sleep is the primary action when its
/// absence is what keeps alertness from being modeled; otherwise every
/// action is secondary.
struct EnergyRecordActions: View {
    let metrics: [AssistantCard.Metric]
    /// "sleep" or "caffeine".
    let record: (String) -> Void

    var body: some View {
        let unscored = metrics.contains { $0.id == "alertness" && $0.missing }
        ForEach(metrics.filter { $0.missing && ($0.id == "sleep" || $0.id == "caffeine") }) { item in
            if item.id == "sleep" && unscored {
                Button("Record sleep") { record("sleep") }.buttonStyle(.auroraPrimary)
            } else {
                Button(item.id == "sleep" ? "Record sleep" : "Record caffeine") { record(item.id) }.buttonStyle(.auroraSecondary)
            }
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
                    Text("\(test.title) · \(test.score) · \(test.rating)").font(.subheadline.weight(.medium)).monospacedDigit()
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

    private struct Band: Identifiable {
        let id: Int
        let start: Millis
        let end: Millis
    }

    /// Derived once from the frozen snapshot, not on every selection redraw.
    private let runs: [Run]
    private let sleepBands: [Band]
    private let doses: [EnergyObservation]

    init(snapshot: EnergySnapshot, projection: EnergyProjection, text: DateText, timeZone: TimeZone) {
        self.snapshot = snapshot
        self.projection = projection
        self.text = text
        self.timeZone = timeZone
        let first = projection.points.first?.t
        runs = Self.runs(projection.points)
        sleepBands = snapshot.mergedSleep.enumerated().map { Band(id: $0.offset, start: max($0.element.start, first ?? $0.element.start), end: $0.element.end) }
        doses = snapshot.observations.filter { $0.kind == .caffeine && $0.start >= (first ?? 0) }
    }

    /// Every mark's style, shared by the chart and its legend.
    private enum Style {
        static let lineWidth: CGFloat = 2
        static let projectedDash: [CGFloat] = [5, 4]
        static let line = Palette.tint
        static let now = Palette.textTertiary
        static let selection = Palette.textTertiary
        static let caffeine = Palette.caffeineAccent
        static let sleep = Palette.sleepAccent.opacity(0.14)
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
        let score = point.modeledScore.map { "\(EnergyEstimate.title) \($0)" } ?? "No modeled score, no recorded sleep block of at least 3 hours reaches the 18 hours before"
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
    private static func runs(_ points: [EnergyProjection.Point]) -> [Run] {
        var runs: [Run] = []
        var current: [EnergyProjection.Point] = []
        var projected = false
        func close() {
            if !current.isEmpty { runs.append(Run(id: runs.count, projected: projected, points: current)) }
            current = []
        }
        for point in points {
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
            ForEach(sleepBands) { sleep in
                RectangleMark(
                    xStart: .value("Sleep start", date(sleep.start)),
                    xEnd: .value("Sleep end", date(sleep.end)),
                    yStart: .value("Score", 0), yEnd: .value("Score", 100)
                )
                .foregroundStyle(Style.sleep)
            }
            ForEach(runs) { run in
                ForEach(run.points, id: \.t) { point in
                    LineMark(x: .value("Time", date(point.t)), y: .value("Modeled alertness", point.modeledScore ?? 0), series: .value("Run", "\(run.id)"))
                        .foregroundStyle(Style.line)
                        .lineStyle(StrokeStyle(lineWidth: Style.lineWidth, dash: run.projected ? Style.projectedDash : []))
                        .interpolationMethod(.linear)
                }
            }
            ForEach(doses) { dose in
                PointMark(x: .value("Recorded caffeine", date(dose.start)), y: .value("Score", 4))
                    .symbol(.triangle)
                    .symbolSize(50)
                    .foregroundStyle(Style.caffeine.opacity(dose.source == .sample ? 0.5 : 1))
            }
            // The legend and the chart's summary say where now is; as its own
            // element this hairline was a 1 pt target.
            RuleMark(x: .value("Now", date(projection.capturedAt)))
                .foregroundStyle(Style.now)
                .lineStyle(StrokeStyle(lineWidth: 1))
                .accessibilityHidden(true)
            if let score = projection.current.modeledScore {
                // The score is the card's headline; as a point it was a tiny target.
                PointMark(x: .value("Now", date(projection.capturedAt)), y: .value("Modeled alertness", score))
                    .symbolSize(70)
                    .foregroundStyle(Style.line)
                    .accessibilityHidden(true)
            }
            if highlight != projection.currentIndex {
                let point = projection.points[highlight]
                RuleMark(x: .value("Selected", date(point.t)))
                    .foregroundStyle(Style.selection)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .accessibilityHidden(true)
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

    /// Shapes and dash patterns name each mark, so color is never the only
    /// cue. Each swatch uses its mark's own style, and only marks the chart
    /// draws are listed.
    private var legend: some View {
        var items: [ChartLegend.Item] = []
        if runs.contains(where: { !$0.projected }) { items.append(.init(title: "Modeled", swatch: AnyView(Self.lineSwatch(dash: [])))) }
        if runs.contains(where: \.projected) { items.append(.init(title: "Projected", swatch: AnyView(Self.lineSwatch(dash: Style.projectedDash)))) }
        items.append(.init(title: "Now", swatch: AnyView(Rectangle().fill(Style.now).frame(width: 1).overlay {
            if projection.current.modeledScore != nil { Circle().fill(Style.line).frame(width: 6, height: 6) }
        })))
        if !doses.isEmpty { items.append(.init(title: "Recorded caffeine", swatch: AnyView(Image(systemName: "triangle.fill").font(.caption2).foregroundStyle(Style.caffeine)))) }
        if !sleepBands.isEmpty { items.append(.init(title: "Recorded sleep", swatch: AnyView(Rectangle().fill(Style.sleep)))) }
        return ChartLegend(items: items)
    }

    private static func lineSwatch(dash: [CGFloat]) -> some View {
        Path { path in path.move(to: CGPoint(x: 0, y: 6)); path.addLine(to: CGPoint(x: 18, y: 6)) }
            .stroke(Style.line, style: StrokeStyle(lineWidth: Style.lineWidth, dash: dash))
    }

    var observations: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
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

/// What the curve means for the day, up front: when modeled energy is
/// highest and lowest, and how now compares with the past week.
struct EnergyOutlookView: View {
    let outlook: EnergyOutlook
    let text: DateText

    var body: some View {
        let lines = outlook.lines(text: text)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text("Your day").font(Typography.label).foregroundStyle(Palette.textSecondary)
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    // The line says highest or lowest; the arrow is decoration.
                    Label { Text(line) } icon: { Image(systemName: symbol(index, line)).accessibilityHidden(true) }
                        .font(Typography.evidence.monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                }
                if outlook.includesSample {
                    SampleDataBadge()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("assistant-energy-outlook")
        }
    }

    private func symbol(_ index: Int, _ line: String) -> String {
        if line.hasPrefix("Highest") { return "arrow.up.right" }
        if line.hasPrefix("Lowest") { return "arrow.down.right" }
        return "calendar.badge.clock"
    }
}

enum EnergyExplainer {
    /// "What this means", in plain words.
    static let meaning = "Aurora estimates your alertness from 0 to 100 using your recorded sleep, caffeine and the time of day. Higher means more alert. After now, the line assumes you add no more sleep or caffeine. It's an estimate, not a measurement."
}
