import AuroraSpikeCore
import Charts
import SwiftUI

enum SpikeStyle {
    static let blue = Color(red: 0.04, green: 0.43, blue: 0.96)
    static let purple = Color(red: 0.45, green: 0.32, blue: 0.85)
    static var background: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
    static var card: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(SpikeStyle.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CardLabel: View {
    let title: String
    let symbol: String
    var color: Color = SpikeStyle.blue
    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
    }
}

struct MetricCard: View {
    let title: String
    let symbol: String
    let value: String
    let unit: String
    let detail: String
    var color: Color = SpikeStyle.blue
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardLabel(title: title, symbol: symbol, color: color)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.system(.title, design: .rounded).weight(.semibold)).monospacedDigit()
                    Text(unit).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

struct ChartPoint: Identifiable {
    let time: Date
    let mg: Double
    var id: Date { time }
}

@MainActor
struct CaffeineTimeline: View {
    let model: PreviewModel
    let now: Date
    var height: CGFloat = 190
    @State private var inspectedTime: Date?

    private var start: Date { now.addingTimeInterval(-8 * 3600) }
    private var end: Date {
        let desiredEnd = max(now.addingTimeInterval(12 * 3600), model.acceptedPlan(at: now)?.start.addingTimeInterval(3600) ?? now)
        return min(desiredEnd, now.addingTimeInterval(48 * 3600))
    }
    private var points: [ChartPoint] {
        let intervals = Int(end.timeIntervalSince(start) / 900)
        var times = (0...intervals).map { start.addingTimeInterval(Double($0) * 900) }
        for dose in model.history.doses where dose.timestamp > start && dose.timestamp < end {
            times.append(dose.timestamp.addingTimeInterval(-0.01))
            times.append(dose.timestamp)
        }
        return times.sorted().map { .init(time: $0, mg: model.active(at: $0)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Time", point.time), y: .value("Caffeine", point.mg))
                        .foregroundStyle(LinearGradient(colors: [SpikeStyle.blue.opacity(0.2), SpikeStyle.blue.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Time", point.time), y: .value("Caffeine", point.mg))
                        .foregroundStyle(SpikeStyle.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .annotation(position: .top, alignment: .leading) { Text("Now").font(.caption2).foregroundStyle(.secondary) }
                if let plan = model.acceptedPlan(at: now), plan.start <= end {
                    RuleMark(x: .value("Bedtime", plan.start))
                        .foregroundStyle(SpikeStyle.purple.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    PointMark(x: .value("Bedtime", plan.start), y: .value("Caffeine", model.active(at: plan.start)))
                        .foregroundStyle(SpikeStyle.purple)
                        .symbolSize(55)
                }
                if let inspectedTime {
                    RuleMark(x: .value("Selected", inspectedTime)).foregroundStyle(SpikeStyle.blue.opacity(0.4))
                    PointMark(x: .value("Selected", inspectedTime), y: .value("Caffeine", model.active(at: inspectedTime))).foregroundStyle(SpikeStyle.blue)
                }
            }
            .chartXScale(domain: start...end)
            .chartYScale(domain: 0...max(60, (points.map(\.mg).max() ?? 0) * 1.15))
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.1))
                    AxisValueLabel { if let mg = value.as(Double.self) { Text("\(mg.formatted(.number.precision(.fractionLength(0))))") } }
                }
            }
            .chartXSelection(value: $inspectedTime)
            .frame(height: height)
            .accessibilityLabel("Estimated caffeine timeline")
            .accessibilityHint("An equivalent table is available in Insights.")
            if let inspectedTime {
                Text("\(inspectedTime.formatted(date: .omitted, time: .shortened)): \(model.active(at: inspectedTime).formatted(.number.precision(.fractionLength(0)))) mg estimated")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

extension Double {
    var mgText: String { formatted(.number.precision(.fractionLength(0))) }
}
