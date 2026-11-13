#if DEBUG
import AuroraCore
import SwiftUI

/// Debug builds only (Aurora Settings › Developer › Research Models): the two
/// research models side by side for the current records, so the owner can
/// compare them. Never compiled into Release/TestFlight, never shown to
/// normal users, and nothing here feeds an estimate, card or notification.
/// Both models are unvalidated for individuals; their outputs are on
/// different scales (KSS rating vs PVT lapses) and are not combined.
struct ResearchModelsView: View {
    @Environment(AppModel.self) private var app
    /// Off by default: neither model imputes a missing night.
    @State private var confirmedAwake = false

    private var comparison: ResearchComparison {
        ResearchComparison.evaluate(at: app.now, sleeps: app.state.sleeps, doses: app.state.doses,
                                    timeZone: app.clock.timeZone, unrecordedTimeIsConfirmedAwake: confirmedAwake)
    }

    var body: some View {
        let c = comparison
        List {
            Section {
                Text("Research only, unvalidated, Debug builds only. Not shown to anyone using Aurora.")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
                Toggle("Treat Unrecorded Time as Awake", isOn: $confirmedAwake)
                    .accessibilityIdentifier("research-confirmed-awake")
                row("Schedule", "\(c.segments.count) segments in the last \(Int(ResearchComparison.windowHours)) h")
                row("Caffeine entries since first sleep", "\(c.ump.dosesInWindow)")
                if includesSample { Text("Includes Sample Data.").font(.footnote).foregroundStyle(Palette.textSecondary) }
            } header: { Text("Inputs") }

            Section {
                kss(c.kss.caffeineExcluded, label: "Caffeine left out")
                kss(c.kss.withRecordedCaffeine, label: "With recorded caffeine")
                Text(KSSModel.version).font(.caption.monospaced()).foregroundStyle(Palette.textSecondary)
            } header: { Text("Three-Process Model · KSS 1–9") }
                footer: { Text("Ingre et al. 2014, eqs 1.1–1.9. No validated caffeine term, so any dose is refused.") }

            Section {
                ump(c.ump.caffeineFree, label: "Caffeine-free")
                ump(c.ump.withRecordedCaffeine, label: "With recorded caffeine (capsule rate, F3)")
                Text(UMPCaffeineModel.version).font(.caption.monospaced()).foregroundStyle(Palette.textSecondary)
            } header: { Text("Unified Model of Performance · PVT lapses") }
                footer: { Text("Ramakrishnan et al. 2016. Group-average 10-min PVT lapses; t = 0 is the first recorded sleep start (F1). One dose at most (F2).") }
        }
        .textCase(nil)
        .navigationTitle("Research Models")
        .accessibilityIdentifier("research-models")
    }

    private var includesSample: Bool {
        app.state.sleeps.contains { $0.id.hasPrefix("demo:") } || app.state.doses.contains { $0.id.hasPrefix("demo:") }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) { Text(value).monospacedDigit() }
    }

    @ViewBuilder private func kss(_ result: KSSModel.Result, label: String) -> some View {
        if let p = result.prediction {
            VStack(alignment: .leading, spacing: Metrics.xxs) {
                row(label, String(format: "%.2f (raw %.2f)", p.boundedKSS, p.rawKSS))
                Text(String(format: "S %.2f · C %.2f · U %.2f · W %.2f · awake %.1f h",
                            p.components.homeostatic, p.components.circadian, p.components.ultradian, p.components.inertia, p.hoursAwake))
                    .font(.caption.monospacedDigit()).foregroundStyle(Palette.textSecondary)
            }
        } else if let refusal = result.refusal {
            row(label, "Refused: \(refusal.rawValue)")
        }
    }

    @ViewBuilder private func ump(_ outcome: ResearchComparison.UMPOutcome, label: String) -> some View {
        switch outcome {
        case .sample(let s):
            VStack(alignment: .leading, spacing: Metrics.xxs) {
                row(label, String(format: "%.2f lapses", s.impairment))
                Text(String(format: "S %.2f · L %.2f · C %.2f · P0 %.2f · gPD %.3f · t %.1f h",
                            s.homeostatic, s.lowerAsymptote, s.circadian, s.caffeineFree, s.caffeineFactor, s.t))
                    .font(.caption.monospacedDigit()).foregroundStyle(Palette.textSecondary)
            }
        case .refused(let why):
            VStack(alignment: .leading, spacing: Metrics.xxs) {
                Text(label)
                Text("Refused: \(why)").font(.footnote).foregroundStyle(Palette.textSecondary)
            }
        }
    }
}
#endif
