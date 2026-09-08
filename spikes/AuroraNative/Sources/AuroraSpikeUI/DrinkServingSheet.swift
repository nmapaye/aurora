import AuroraSpikeCore
import SwiftUI

@MainActor
struct DrinkServingSheet: View {
    let model: PreviewModel
    @State private var draft: SavedDrink
    @State private var remember: Bool
    @State private var exactAmount = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(model: PreviewModel, initial: SavedDrink) {
        self.model = model
        _draft = State(initialValue: initial)
        _remember = State(initialValue: initial.recipe.basis.needsShotChoice)
    }

    private var isEspresso: Bool {
        if case .espresso = draft.recipe.basis { return true }
        return false
    }

    private var validationMessage: String? {
        do {
            _ = try ServingSnapshot(recipe: draft.recipe, container: draft.container, consumedML: draft.container.capacityML * draft.fraction)
            return nil
        } catch { return error.localizedDescription }
    }

    private var shots: Binding<Int> {
        Binding(get: {
            if case .espresso(let count) = draft.recipe.basis { return count ?? 0 }
            return 0
        }, set: { count in draft.recipe.basis = .espresso(shots: count == 0 ? nil : count) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(draft.recipe.name).font(.title2.bold())
                        Text("Set the amount you drank.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if draft.id == "tumbler" { preparationChoice }
                    if isEspresso { shotChoice }
                    containerPicker
                    cupSection
                    estimate
                    details
                    Toggle("Use as my usual serving", isOn: $remember)
                        .font(.subheadline)
                    Text("Your usual serving is remembered for this preview session only.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    if let validationMessage, !draft.recipe.basis.needsShotChoice {
                        Text(validationMessage).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(24)
            }
            .background(SpikeStyle.background)
            .navigationTitle("Drink serving")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard draft.snapshot != nil else { return }
                    if remember { model.update(draft) }
                    model.log(draft)
                    dismiss()
                } label: {
                    Text(draft.snapshot.map { "Log \($0.caffeineMG.mgText) mg" } ?? (draft.recipe.basis.needsShotChoice ? "Choose your shots to continue" : "Check serving details"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(draft.snapshot == nil)
                .accessibilityIdentifier("log-serving")
                .padding(20)
                .background(.regularMaterial)
            }
        }
        .frame(idealWidth: 490, idealHeight: 760)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var shotChoice: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("How many espresso shots?").font(.headline)
            Picker("Espresso shots", selection: shots) {
                Text("Choose").tag(0)
                Text("1 shot").tag(1)
                Text("2 shots").tag(2)
                Text("3 shots").tag(3)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("espresso-shots")
            Text("60 mg per shot is a reference estimate. Choose the count used to prepare your drink.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var preparationChoice: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("How is your coffee prepared?").font(.headline)
            Picker("Coffee preparation", selection: Binding(get: { isEspresso }, set: { espresso in
                guard espresso != isEspresso else { return }
                if espresso {
                    draft.recipe.basis = .espresso(shots: nil)
                } else {
                    draft.recipe.basis = .concentration(mgPerML: 95 / 240.0, reference: "95 mg per 240 ml is a reference estimate for filter coffee. Actual brewing strength varies.")
                }
            })) {
                Text("Espresso").tag(true)
                Text("Brewed").tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("coffee-preparation")
        }
    }

    private var containerPicker: some View {
        Picker(selection: Binding(get: { draft.container.id }, set: { id in
            if let container = model.containers.first(where: { $0.id == id }) { draft.container = container }
        })) {
            ForEach(model.containers) { container in
                let shown = container.id == draft.container.id ? draft.container : container
                Text("\(shown.name) · \(model.volume(shown.capacityML))").tag(container.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("Container").font(.subheadline.weight(.semibold))
                Text("Preset capacities are editable estimates").font(.caption).foregroundStyle(.secondary)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("drink-container")
    }

    private var cupSection: some View {
        VStack(spacing: 14) {
            CupFillControl(fraction: $draft.fraction, container: draft.container, volume: model.volume, green: draft.id == "matcha")
                .frame(height: 210)
            VStack(spacing: 3) {
                Text(model.volume(draft.container.capacityML * draft.fraction))
                    .font(.system(.title, design: .rounded).weight(.semibold)).monospacedDigit()
                Text("\((draft.fraction * 100).formatted(.number.precision(.fractionLength(0))))% of \(model.volume(draft.container.capacityML)) prepared")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("Amount consumed", selection: $draft.fraction) {
                Text("¼").tag(0.25)
                Text("½").tag(0.5)
                Text("¾").tag(0.75)
                Text("Full").tag(1.0)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("drink-fraction")
            Text("Drag the fill level or choose a fraction.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var estimate: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Caffeine estimate").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(draft.snapshot.map { "\($0.caffeineMG.mgText) mg" } ?? (draft.recipe.basis.needsShotChoice ? "Choose shots" : "Check details"))
                        .font(.headline).foregroundStyle(SpikeStyle.blue).monospacedDigit()
                        .accessibilityIdentifier("serving-caffeine-estimate")
                }
                Text(draft.recipe.basis.explanation).font(.caption).foregroundStyle(.secondary)
                if isEspresso || draft.id == "matcha" {
                    Text("More milk or a larger container keeps the prepared drink’s caffeine the same. A smaller consumed fraction reduces the amount logged.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var details: some View {
        DisclosureGroup("Exact amount and container details") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Container name", text: $draft.container.name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("container-name")
                HStack {
                    Text("Capacity (ml)").font(.subheadline)
                    TextField("Capacity in ml", value: $draft.container.capacityML, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("container-capacity")
                }
                HStack {
                    TextField("Amount consumed (\(model.unit.symbol))", text: $exactAmount)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(applyExactAmount)
                        .accessibilityIdentifier("exact-consumed-volume")
                    Button("Apply", action: applyExactAmount).disabled(exactAmount.isEmpty)
                }
                Text("A valid amount is greater than zero and no larger than the container. Container capacity is stored in milliliters.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 12)
        }
        .font(.subheadline)
    }

    private func applyExactAmount() {
        let parsed = try? Double(exactAmount, format: .number)
        guard let parsed, parsed.isFinite else { error = "Enter a number for the amount consumed."; return }
        let ml = model.unit.milliliters(parsed)
        guard draft.container.capacityML.isFinite, draft.container.capacityML > 0, ml > 0, ml <= draft.container.capacityML else {
            error = ServingError.invalidVolume.localizedDescription
            return
        }
        draft.fraction = ml / draft.container.capacityML
        error = nil
    }
}

struct CupShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 8, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - 8, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.minY + 8))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + 10), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 17, y: rect.maxY - 14))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - 33, y: rect.maxY), control: CGPoint(x: rect.maxX - 18, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + 33, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 17, y: rect.maxY - 14), control: CGPoint(x: rect.minX + 18, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 10))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 8, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct CupFillControl: View {
    @Binding var fraction: Double
    let container: DrinkContainer
    let volume: (Double) -> String
    var green = false
    private var color: Color { green ? .green : SpikeStyle.blue }

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .trailing) {
                Text("Full")
                Spacer()
                Text("¾")
                Spacer()
                Text("½")
                Spacer()
                Text("¼")
                Spacer()
                Text("0")
            }
            .font(.caption).foregroundStyle(.secondary).frame(width: 32)
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    CupShape().fill(color.opacity(0.06))
                    Rectangle()
                        .fill(LinearGradient(colors: [color.opacity(0.5), color.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                        .frame(height: geometry.size.height * min(1, max(0, fraction)))
                    ForEach(1..<4) { tick in
                        Rectangle().fill(.white.opacity(0.45)).frame(height: 1)
                            .offset(y: -geometry.size.height * Double(tick) / 4)
                    }
                }
                .clipShape(CupShape())
                .overlay(CupShape().stroke(color.opacity(0.45), lineWidth: 2))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                    let raw = min(1, max(0.01, 1 - gesture.location.y / geometry.size.height))
                    let quarter = (raw * 4).rounded() / 4
                    change(to: abs(raw - quarter) < 0.055 && quarter > 0 ? quarter : raw)
                })
            }
            .frame(width: 145)
            Image(systemName: "arrow.up.and.down")
                .font(.caption.weight(.semibold)).foregroundStyle(color.opacity(0.7)).frame(width: 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amount consumed")
        .accessibilityValue("\(volume(container.capacityML * fraction)), \((fraction * 100).formatted(.number.precision(.fractionLength(0)))) percent of the prepared drink")
        .accessibilityHint("Swipe up or down to change by one quarter. Exact amount is available in details.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(to: min(1, (fraction * 4).rounded(.down) / 4 + 0.25))
            case .decrement: change(to: max(0.01, (fraction * 4).rounded(.up) / 4 - 0.25))
            @unknown default: break
            }
        }
        .accessibilityIdentifier("drink-fill")
    }

    private func change(to value: Double) {
        #if os(iOS)
        if Int((value * 4).rounded()) != Int((fraction * 4).rounded()) {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        #endif
        fraction = value
    }
}
