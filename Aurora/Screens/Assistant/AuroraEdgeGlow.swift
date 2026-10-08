import SwiftUI

/// Decoration follows real work; warmups and instant quick actions never add
/// fake delay. TimelineView is only instantiated while processing is active.
struct AuroraEdgeGlow: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if active {
            if reduceMotion { edge(angle: 0) }
            else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    edge(angle: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) / 8 * 360)
                }
            }
        }
    }
    private func edge(angle: Double) -> some View {
        let gradient = AngularGradient(colors: [.teal, .cyan, .indigo, .purple, .pink, .orange, .teal], center: .center, angle: .degrees(angle))
        return RoundedRectangle(cornerRadius: 42)
            .stroke(gradient, lineWidth: 5)
            .padding(3)
            .overlay { RoundedRectangle(cornerRadius: 42).stroke(gradient, lineWidth: 9).blur(radius: 9).padding(3).opacity(0.55) }
    }
}
