import AuroraCore
import SwiftUI

/// The welcome card's three starting points. Each chip sends its
/// capability's own phrase, so it does exactly what the same tile or typed
/// request does. Chips wrap onto more lines rather than shrink their text.
struct WelcomeChips: View {
    @Environment(AppModel.self) private var app
    @Environment(AssistantModel.self) private var assistant

    var body: some View {
        ChipFlow(spacing: Metrics.xs) {
            ForEach(Capabilities.welcome.compactMap(Capabilities.capability)) { chip($0) }
        }
        .accessibilityElement(children: .contain)
    }

    private func chip(_ capability: Capability) -> some View {
        Button { assistant.send(capability.phrase, app: app) } label: {
            Label(capability.title, systemImage: capability.symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, Metrics.sm).padding(.vertical, Metrics.xs)
                .frame(minHeight: 36)
                .background(Palette.selectionFill, in: Capsule())
                // The visible capsule stays compact; the target is 44 pt.
                .frame(minHeight: Metrics.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.auroraPress)
        .foregroundStyle(Palette.tint)
        .disabled(assistant.processing)
        .accessibilityIdentifier("welcome-\(capability.intent.rawValue)")
    }
}

/// Lays chips out left to right and starts a new line when the next one
/// doesn't fit. A chip wider than the line gets the whole line and wraps
/// its own text.
private struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > width {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
                size.width = min(size.width, width)
            }
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.items.isEmpty {
                rows.append(row); row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
