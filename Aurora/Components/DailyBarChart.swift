import AuroraCore
import Charts
import SwiftUI

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

    @State var selected: Date?
    @State var adjustedIndex: Int?
    @Environment(\.isWideLayout) private var wide

    var body: some View {
        let index = currentIndex
        let recorded = days.contains { $0.value != nil }
        Card {
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
                chart(highlight: index)
                    .frame(height: wide ? 240 : 180)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilitySummary)
                    .accessibilityValue(index.flatMap { days.indices.contains($0) ? "\(days[$0].title), \(days[$0].readout)" : nil } ?? "")
                    .accessibilityAdjustableAction { direction in
                        let current = currentIndex ?? (days.count - 1)
                        switch direction {
                        case .increment: adjustedIndex = min(days.count - 1, current + 1)
                        case .decrement: adjustedIndex = max(0, current - 1)
                        @unknown default: break
                        }
                        selected = nil
                    }
            } else {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityLabel(accessibilitySummary)
            }
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

    private func chart(highlight: Int?) -> some View {
        Chart {
            ForEach(Array(days.enumerated()), id: \.element.id) { offset, day in
                if let value = day.value {
                    BarMark(
                        x: .value("Day", Date(timeIntervalSince1970: day.date / 1000), unit: .day),
                        y: .value(unit, value)
                    )
                    .foregroundStyle(accent.opacity(highlight == nil || highlight == offset ? (day.isSample ? 0.5 : 1) : 0.35))
                    .cornerRadius(4)
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
