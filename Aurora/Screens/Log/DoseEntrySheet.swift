import AuroraCore
import SwiftUI

/// Custom Entry and Edit Entry: amount, source, date and time, and a note.
/// Edit keeps the entry's id; Delete asks first.
struct DoseEntrySheet: View {
    enum Result {
        case saved(CustomDoseDraft)
        case deleted
        case cancelled(CustomDoseDraft)
    }

    let mode: DoseSheet
    let onFinish: (Result) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomDoseDraft
    @State private var followsClock: Bool
    @State private var confirmDelete = false
    @State private var message: String?
    @FocusState private var amountFocused: Bool

    init(mode: DoseSheet, draft: CustomDoseDraft, onFinish: @escaping (Result) -> Void) {
        self.mode = mode
        self.onFinish = onFinish
        _draft = State(initialValue: draft)
        // A new entry's time follows the clock until someone picks one.
        if case .new = mode { _followsClock = State(initialValue: true) } else { _followsClock = State(initialValue: false) }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    HStack {
                        TextField("Amount", text: $draft.mg)
                            .keyboardType(.numberPad)
                            .focused($amountFocused)
                            .font(.title2.monospacedDigit())
                            .accessibilityIdentifier("dose-amount")
                        Text("mg").foregroundStyle(Palette.textSecondary)
                    }
                }
                Section("Source") {
                    sourcePicker
                }
                Section("Date and Time") {
                    DatePicker(
                        "Time",
                        selection: Binding(
                            get: { Date(timeIntervalSince1970: (followsClock ? model.now : draft.timestamp) / 1000) },
                            set: {
                                followsClock = false
                                draft.timestamp = ($0.timeIntervalSince1970 * 1000).rounded()
                            }
                        ),
                        in: ...Date.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                Section("Note") {
                    TextField("Optional", text: $draft.note, axis: .vertical)
                }
                if let message {
                    Section {
                        Text(message)
                            .foregroundStyle(StatusTone.error.foreground)
                            .accessibilityIdentifier("dose-error")
                    }
                }
                if isEditing {
                    Section {
                        Button("Delete Entry", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.modalBackground)
            .navigationTitle(isEditing ? "Edit Entry" : "Custom Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { finish(.cancelled(currentDraft)) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("dose-save")
                }
            }
            .alert("Delete this entry?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    Haptics.warning()
                    finish(.deleted)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(CaffeineLog.title(Dose(id: "", timestamp: draft.timestamp, mg: Double(draft.mg) ?? 0, source: draft.source)))
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
        .onDisappear {
            if !finished { onFinish(.cancelled(currentDraft)) }
        }
    }

    @State private var finished = false

    private var currentDraft: CustomDoseDraft {
        var current = draft
        if followsClock { current.timestamp = model.now }
        return current
    }

    private var sourcePicker: some View {
        let options = CaffeineLog.customSources
        return VStack(alignment: .leading, spacing: Metrics.sm) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Metrics.xs)], spacing: Metrics.xs) {
                ForEach(options, id: \.self) { option in
                    let selected = draft.source == option
                    Button {
                        draft.source = option
                    } label: {
                        Text(option)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget)
                            .foregroundStyle(selected ? Palette.secondaryButtonText : Palette.textPrimary)
                            .background(Capsule().fill(selected ? Palette.selectionFill : Palette.fieldBackground))
                            .overlay(Capsule().strokeBorder(selected ? Palette.tint : Palette.cardBorder))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if !options.contains(draft.source) && !draft.source.isEmpty {
                Text("Source: \(draft.source)").font(.footnote).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private func save() {
        model.tick()
        let candidate = currentDraft
        if let error = CaffeineLog.validate(candidate, now: model.now).message {
            message = error
            UIAccessibility.post(notification: .announcement, argument: error)
            return
        }
        finish(.saved(candidate))
    }

    private func finish(_ result: Result) {
        finished = true
        onFinish(result)
        dismiss()
    }
}
