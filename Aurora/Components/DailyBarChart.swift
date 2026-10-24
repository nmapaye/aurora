import AuroraCore
import Charts
import SwiftUI
import UIKit

/// One bar per local day. A day without a record has no bar and reads "No
/// record" (or the caller's wording), never zero. Tap or drag to read a day;
/// VoiceOver steps through days.
struct DailyBarChart: View {
    struct Day: Identifiable {
        let date: Millis
        /// `nil` when nothing was recorded.
        let value: Double?
        let title: String
        let readout: String
        var isSample = false

        var id: Millis { date }
    }

    let title: String
    let days: [Day]
    var unit: String
    var accent: Color
    var reference: (value: Double, label: String)?
    var defaultIndex: Int?
    var accessibilitySummary: String
    var emptyMessage: String
    /// False inside a card that already draws its own surface, so the chart
    /// isn't a box within a box.
    var framed = true

    @State var selected: Date?
    @State var adjustedIndex: Int?
    @Environment(\.isWideLayout) private var wide
    @Environment(\.self) private var environment

    var body: some View {
        if framed { Card { content } } else { VStack(alignment: .leading, spacing: Metrics.sm) { content } }
    }

    @ViewBuilder private var content: some View {
        let index = currentIndex
        let recorded = days.contains { $0.value != nil }
        // Sample Data bars are hatched, not faded, so every bar keeps its contrast.
        let hatch = days.contains { $0.isSample && $0.value != nil } ? SampleHatch.paint(accent, in: environment) : nil
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline).foregroundStyle(Palette.textPrimary)
            Spacer()
            if let index, days.indices.contains(index) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(days[index].title).font(.caption).foregroundStyle(Palette.textSecondary)
                    Text(days[index].readout).font(.footnote.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                }
                .accessibilityHidden(true)
            }
        }
        if recorded {
            chart(highlight: index, hatch: hatch)
                .frame(height: wide ? 240 : 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary)
                .accessibilityValue(index.flatMap { days.indices.contains($0) ? "\(days[$0].title), \(days[$0].readout)\(days[$0].isSample ? ", Sample Data" : "")" : nil } ?? "")
                .accessibilityAdjustableAction { direction in
                    let current = currentIndex ?? (days.count - 1)
                    switch direction {
                    case .increment: adjustedIndex = min(days.count - 1, current + 1)
                    case .decrement: adjustedIndex = max(0, current - 1)
                    @unknown default: break
                    }
                    selected = nil
                }
            if let hatch {
                ChartLegend(items: [
                    .init(title: "Recorded", swatch: AnyView(RoundedRectangle(cornerRadius: 2).fill(accent))),
                    .init(title: "Sample Data", swatch: AnyView(RoundedRectangle(cornerRadius: 2).fill(hatch))),
                ])
            }
        } else {
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityLabel(accessibilitySummary)
        }
    }

    private var currentIndex: Int? {
        if let selected {
            let ms = selected.timeIntervalSince1970 * 1000
            return days.indices.min { abs(days[$0].date + dayMs / 2 - ms) < abs(days[$1].date + dayMs / 2 - ms) }
        }
        if let adjustedIndex, days.indices.contains(adjustedIndex) { return adjustedIndex }
        return defaultIndex
    }

    private func chart(highlight: Int?, hatch: ImagePaint?) -> some View {
        Chart {
            // The selected day is a rule behind the bars; no bar is dimmed.
            if let highlight, days.indices.contains(highlight) {
                RuleMark(x: .value("Selected", Date(timeIntervalSince1970: days[highlight].date / 1000), unit: .day))
                    .foregroundStyle(Palette.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            ForEach(days) { day in
                if let value = day.value {
                    let mark = BarMark(
                        x: .value("Day", Date(timeIntervalSince1970: day.date / 1000), unit: .day),
                        y: .value(unit, value)
                    )
                    .cornerRadius(4)
                    if day.isSample, let hatch { mark.foregroundStyle(hatch) } else { mark.foregroundStyle(accent) }
                }
            }
            if let reference {
                RuleMark(y: .value(reference.label, reference.value))
                    .foregroundStyle(Palette.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(reference.label).font(.caption2).foregroundStyle(Palette.textSecondary)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: days.count > 14 ? 7 : 1)) { _ in
                AxisValueLabel(format: days.count > 14 ? .dateTime.month(.abbreviated).day() : .dateTime.weekday(.narrow), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Palette.separator)
                AxisValueLabel()
            }
        }
        .chartXSelection(value: $selected)
    }
}

/// Diagonal stripes of a mark's color over a light wash of it. Sample Data
/// marks differ by pattern and by legend, never by opacity alone.
enum SampleHatch {
    static func paint(_ color: Color, in environment: EnvironmentValues) -> ImagePaint {
        let ink = UIColor(Color(color.resolve(in: environment)))
        let side: CGFloat = 6
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            ink.withAlphaComponent(0.22).setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            // One diagonal plus its wrapped corners, so tiles join seamlessly.
            let stripe = UIBezierPath()
            stripe.lineWidth = 1.6
            for offset in [-side, 0, side] {
                stripe.move(to: CGPoint(x: offset - 1, y: side + 1))
                stripe.addLine(to: CGPoint(x: offset + side + 1, y: -1))
            }
            ink.setStroke()
            stripe.stroke()
        }
        return ImagePaint(image: Image(uiImage: image))
    }
}

/// A chart's key in two columns, one at accessibility text sizes. Each
/// swatch is drawn with the same style as the marks it names.
struct ChartLegend: View {
    struct Item: Identifiable {
        let title: String
        let swatch: AnyView
        var id: String { title }
    }

    let items: [Item]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Eager, not a LazyVGrid: a lazy grid kept its titles as separate
        // accessibility elements whatever was applied to the grid.
        let columns = typeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
        Grid(alignment: .leading, horizontalSpacing: Metrics.md, verticalSpacing: Metrics.xs) {
            ForEach(rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(rows[row]) { item in
                        HStack(spacing: Metrics.xs) {
                            item.swatch.frame(width: 18, height: 12)
                            Text(item.title)
                        }
                    }
                }
            }
        }
        .font(.caption).foregroundStyle(Palette.textSecondary)
        // A key to shapes and colors. Each chart is one element whose label
        // and value say what it shows, so the key isn't read; combined, the
        // lazy grid still left each short title as its own tiny element.
        .accessibilityHidden(true)
    }
}

/// W / 2W / M style segmented control.
struct RangeControl<Value: Hashable>: View {
    let label: String
    let options: [(value: Value, title: String, spoken: String)]
    @Binding var selection: Value

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(options.indices, id: \.self) { index in
                Text(options[index].title)
                    .accessibilityLabel(options[index].spoken)
                    .tag(options[index].value)
            }
        }
        .pickerStyle(.segmented)
    }
}
