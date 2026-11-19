import Foundation

/// The model selects/composes verified estimator-factor clauses, not new claims.
/// Every signed share comes from the captured estimator's contributions; model
/// output carries placeholders only, replaced by code after whole-output validation.
public struct GroundedLocalExplanation: Sendable {
    public struct Factor: Equatable, Sendable {
        public let kind: EnergyContribution.Kind
        public let signedPoints: String
        public let placeholder: String
        public let clause: String
    }
    public let factors: [Factor]
    public let allowedCompositions: [String]
    private let replacements: [String: String]
    private let note: String

    public init(estimate: EnergyEstimate) {
        var values: [String: String] = [:]
        var facts: [Factor] = []
        var compositions: [String] = []
        if let score = estimate.modeledScore {
            values["[score]"] = String(score)
            // Reuse captured shares, already calculated using Alertness's exact
            // weights. No recomputed causal weights or attribution percentages.
            let ordered = estimate.contributions.filter { $0.kind != .baseline }.sorted {
                if abs($0.points) != abs($1.points) { return abs($0.points) > abs($1.points) }
                return $0.kind.rawValue < $1.kind.rawValue
            }
            for part in ordered where part.points.isFinite {
                let label: String
                switch part.kind {
                case .baseline: continue
                case .timeOfDay: label = "the generic time-of-day curve"
                case .sleepDebt:
                    guard estimate.sleepHoursLast24 > 0 else { continue }
                    label = "the recorded-sleep debt term"
                case .caffeine:
                    // An absent record is not an observed zero caffeine value.
                    guard estimate.evidence.hasActiveCaffeine else { continue }
                    label = "the recorded-caffeine term"
                case .inertia:
                    guard part.term > 0, estimate.evidence.lastWakeAt != nil else { continue }
                    label = "the recent-wake term"
                }
                let placeholder = "[factor_" + part.kind.rawValue + "]"
                values[placeholder] = part.pointsText
                var clause = label + " contributes " + placeholder + " points"
                if part.kind == .caffeine {
                    values["[active]"] = numberText(jsRound(estimate.evidence.activeCaffeineMg))
                    clause += " with [active] mg modeled active"
                }
                facts.append(.init(kind: part.kind, signedPoints: part.pointsText, placeholder: placeholder, clause: clause))
            }
            let prefix = "Modeled alertness is [score]; in the unclamped model, "
            for fact in facts {
                compositions.append(prefix + fact.clause + ".")
                for second in facts where second.kind != fact.kind {
                    compositions.append(prefix + fact.clause + " and " + second.clause + ".")
                }
            }
            if compositions.isEmpty {
                compositions = ["Modeled alertness is [score], but this snapshot has no verified factor breakdown."]
            }
        } else {
            // Contributions are not calculated for an unavailable score. Do not
            // invent a sleep-debt or caffeine share to make an explanation sound useful.
            let sleep: String
            if estimate.sleepHoursLast24 > 0 {
                values["[sleep]"] = formatSleepHours(estimate.sleepHoursLast24)
                sleep = "recorded sleep in the last day is [sleep], with no qualifying sleep block"
            } else { sleep = "sleep in the last day has No record" }
            compositions = ["Modeled alertness is unavailable; " + sleep + "."]
        }
        factors = facts
        allowedCompositions = compositions
        replacements = values
        // Estimate and not-medical-advice disclosures live in Terms and
        // Privacy, acknowledged at first launch; the card carries only facts.
        // Sample Data stays labeled wherever it contributes.
        note = estimate.includesSample ? "Includes Sample Data." : ""
    }
    public var prompt: String {
        "Explain WHY this snapshot's modeled score has its value by selecting one or two supplied estimator-factor clauses. Clauses are ordered by the magnitude of their actual contribution; prefer the most informative applicable factors, not a restatement of the score. Signed point placeholders are unclamped model shares, NOT measured causes. Choose exactly one allowed composition verbatim, retaining placeholders. No new facts or numbers:\n" + allowedCompositions.joined(separator: "\n")
    }
    public func render(_ composition: String) -> String? {
        guard allowedCompositions.contains(composition) else { return nil }
        var rendered = composition
        for (key, value) in replacements { rendered = rendered.replacingOccurrences(of: key, with: value) }
        return note.isEmpty ? rendered : rendered + " " + note
    }
    public var fallback: String { render(allowedCompositions[0]) ?? "No record." }
}
