import AuroraCore
import Charts
import SwiftUI

/// Sleep impact for one logged drink: change what it was, shots, cups, when
/// it was had, bedtime and half-life, and every number updates. "Update
/// Entry" is the only write and corrects the entry it was opened from.
struct DrinkImpactSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(AssistantModel.self) private var assistant
    @Environment(\.dismiss) private var dismiss

    let dose: Dose
    @State private var input: DrinkImpact.Input
    @State private var problem: String?

    init(dose: Dose, input: DrinkImpact.Input) {
        self.dose = dose
        _input = State(initialValue: input)
    }

    private var result: DrinkImpact.Result { DrinkImpact.evaluate(input) }
    private func time(_ ms: Millis) -> String { app.text.clockTime(ms) }
    private func date(_ ms: Millis) -> Date { Date(timeIntervalSince1970: ms / 1000) }
    private func millis(_ date: Date) -> Millis { (date.timeIntervalSince1970 * 1000).rounded() }

    var body: some View {
        NavigationStack {
            Form {
                Section("Drink") {
                    Picker("What It Was", selection: $input.kind) {
                        ForEach(DrinkImpact.Kind.allCases) { Text($0.label).tag($0) }
                    }
                    .accessibilityIdentifier("impact-kind")
                    if input.kind.usesShots {
                        Stepper("Espresso Shots: \(input.shots)", value: $input.shots, in: 1...4)
                            .accessibilityIdentifier("impact-shots")
                    }
                    Picker("Cups", selection: $input.cups) {
                        Text("1 Cup").tag(1)
                        Text("2 Cups").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("impact-cups")
                }
                Section("Timing") {
                    DatePicker("Had It At", selection: Binding(get: { date(input.drankAt) }, set: { input.drankAt = millis($0) }))
                    DatePicker("Bedtime", selection: Binding(get: { date(input.bedtime) }, set: { input.bedtime = millis($0) }))
                    VStack(alignment: .leading, spacing: Metrics.xxs) {
                        HStack {
                            Text("Half-Life")
                            Spacer()
                            Text(String(format: input.halfLifeHours.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f h" : "%.1f h", input.halfLifeHours))
                                .monospacedDigit().foregroundStyle(Palette.textSecondary)
                        }
                        Slider(value: $input.halfLifeHours, in: DrinkImpact.halfLifeRange, step: 0.5)
                            .accessibilityIdentifier("impact-half-life")
                    }
                }
                Section("Impact") {
                    results
                    chart.frame(height: 150)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Caffeine in your body from \(time(input.drankAt)) for 12 hours, \(Int(result.mgAtBed.rounded())) mg at bedtime.")
                    Text(input.kind.note + " " + DrinkImpact.timingLine(result, formatTime: time))
                        .font(.footnote).foregroundStyle(Palette.textSecondary)
                    Text("Estimates for a typical adult, not medical advice.")
                        .font(.caption).foregroundStyle(Palette.textSecondary)
                }
                if changesEntry {
                    Section {
                        Button("Update Entry to \(Int(result.totalMg.rounded())) mg") { updateEntry() }
                            .accessibilityIdentifier("impact-update-entry")
                        if let problem { Text(problem).font(.footnote).foregroundStyle(Palette.textSecondary) }
                    } footer: {
                        Text("Changes your \(time(dose.timestamp)) entry to \(entryName) instead of adding a new one.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.modalBackground)
            .navigationTitle("Sleep Impact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("impact-done")
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var results: some View {
        let r = result
        return Grid(alignment: .leading, horizontalSpacing: Metrics.md, verticalSpacing: Metrics.sm) {
            GridRow {
                metric("Caffeine", "\(Int(r.totalMg.rounded())) mg",
                       (input.cups > 1 ? "\(Int(r.perCupMg.rounded())) mg per cup · " : "") + "\(Int(r.percentOfLimit.rounded()))% of \(Int(input.dailyLimitMg)) mg")
                metric("In You at Bed", "\(Int(r.mgAtBed.rounded())) mg", time(input.bedtime))
            }
            GridRow {
                metric("Under 50 mg", r.underThresholdAt.map(time) ?? "Already", r.underThresholdAt == nil ? "Starts under 50 mg" : (r.underThresholdAt! <= input.bedtime ? "Before bed" : "After bed"))
                metric("Sleep Impact", r.level.rawValue, r.level.summary, tint: r.level == .low ? Palette.tint : nil)
            }
        }
    }

    private func metric(_ label: String, _ value: String, _ detail: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Palette.textSecondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(tint ?? Palette.textPrimary)
            Text(detail).font(.caption2).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var chart: some View {
        let points = DrinkImpact.curve(input)
        return Chart {
            ForEach(points.indices, id: \.self) { i in
                AreaMark(x: .value("Time", date(points[i].t)), y: .value("mg", points[i].mg))
                    .foregroundStyle(Palette.tint.opacity(0.12))
                LineMark(x: .value("Time", date(points[i].t)), y: .value("mg", points[i].mg))
                    .foregroundStyle(Palette.tint)
            }
            RuleMark(x: .value("Bedtime", date(input.bedtime)))
                .foregroundStyle(Palette.textSecondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) { Text("Bed").font(.caption2).foregroundStyle(Palette.textSecondary) }
            RuleMark(y: .value("50 mg", DrinkImpact.thresholdMg))
                .foregroundStyle(Palette.textSecondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
        .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel() } }
    }

    private var entryName: String {
        input.kind == .asLogged ? (dose.source ?? "Caffeine") : input.kind.label + (input.cups > 1 ? " × \(input.cups)" : "")
    }

    private var changesEntry: Bool {
        guard CaffeineLog.isEditable(dose), app.state.doses.contains(where: { $0.id == dose.id }) else { return false }
        return Int(result.totalMg.rounded()) != Int(dose.mg.rounded()) || input.drankAt != dose.timestamp
            || (input.kind != .asLogged && entryName != dose.source)
    }

    private func updateEntry() {
        guard let current = app.state.doses.first(where: { $0.id == dose.id }) else { problem = "That entry is gone. Nothing changed."; return }
        var draft = CaffeineLog.editDraft(for: current)
        draft.mg = String(Int(result.totalMg.rounded()))
        draft.source = entryName
        draft.timestamp = input.drankAt
        app.tick()
        if let message = CaffeineLog.validate(draft, now: app.now).message { problem = message; return }
        app.correctDose(id: current.id, with: draft)
        if let failure = app.mutationFailure { problem = failure; return }
        assistant.receipt(recordID: current.id, kind: "caffeine", app: app, title: "Caffeine updated")
        dismiss()
    }
}
