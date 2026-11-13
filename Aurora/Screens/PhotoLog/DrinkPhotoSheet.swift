import AuroraCore
import PhotosUI
import SwiftUI

/// Photo logging: take or choose a photo, Apple's on-device frameworks read
/// it, Aurora matches the bundled USDA caffeine database, and the person
/// confirms or edits a card before Save. Nothing is saved automatically and
/// the photo is never stored, uploaded or kept after this sheet closes.
struct DrinkPhotoSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(AssistantModel.self) private var assistant
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case pick, reading, review }
    @State private var phase: Phase = .pick
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var image: UIImage?
    @State private var card: DrinkPhotoConfirmation?
    @State private var search = ""
    @State private var typing = false
    @State private var typedText = ""
    @State private var failure: String?
    @State private var analysis: Task<Void, Never>?
    /// Set once Save succeeds, so a second tap can't add the drink twice.
    @State private var saved = false
    @FocusState private var amountFocused: Bool

    private let db = CaffeineDatabase.bundled

    var body: some View {
        NavigationStack {
            Group {
                if db == nil {
                    unavailable("Aurora's caffeine database couldn't be read. Use Log caffeine to enter the amount yourself.")
                } else {
                    switch phase {
                    case .pick: pickView
                    case .reading: readingView
                    case .review: reviewForm
                    }
                }
            }
            .background(Palette.modalBackground)
            .navigationTitle("Log from Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { close() }.accessibilityIdentifier("photo-log-cancel")
                }
                if phase == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(currentDraft == nil || saved)
                            .accessibilityIdentifier("photo-log-save")
                    }
                }
                if amountFocused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { amountFocused = false }
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { captured in
                showCamera = false
                if let captured { begin(captured) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                // Loaded into memory only; PhotosPicker runs out of process
                // and needs no photo-library permission.
                if let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) { begin(picked) }
                else { failure = "That photo couldn't be opened. Try another one." }
                pickerItem = nil
            }
        }
        .onDisappear { analysis?.cancel(); image = nil; card = nil }
    }

    // MARK: Phases

    private var pickView: some View {
        VStack(spacing: Metrics.md) {
            Image(systemName: "camera.viewfinder").font(.system(size: 48)).foregroundStyle(Palette.tint).accessibilityHidden(true)
            Text("Photograph the can, bottle or cup label. Aurora reads it on this device and looks up caffeine in USDA FoodData Central. You confirm before anything is saved.")
                .font(.callout).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: {
                    Label("Take Photo", systemImage: "camera").frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget)
                }
                .buttonStyle(.borderedProminent).tint(Palette.primaryButton)
                .accessibilityIdentifier("photo-log-camera")
            }
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label("Choose Photo", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget)
            }
            .buttonStyle(.bordered).tint(Palette.tint)
            .accessibilityIdentifier("photo-log-library")
            if let failure {
                Text(failure).font(.footnote).foregroundStyle(StatusTone.error.foreground)
            }
            Spacer()
        }
        .padding(Metrics.lg)
    }

    private var readingView: some View {
        VStack(spacing: Metrics.md) {
            if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: Metrics.heroRadius)) }
            ProgressView("Reading the photo on this device…")
            Spacer()
        }
        .padding(Metrics.lg)
    }

    @ViewBuilder private var reviewForm: some View {
        if let db, let card {
            Form {
                if let image {
                    Section {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160).frame(maxWidth: .infinity)
                            .accessibilityLabel("Your drink photo. Not saved.")
                    } footer: { Text("This photo stays on your device and is discarded when you close this sheet.") }
                }
                if card.manualName != nil { manualSection(card) } else { drinkSection(card, db: db) }
                if card.entry != nil { servingSection(card, db: db) }
                amountSection(card, db: db)
                Section("Time") {
                    DatePicker("Time", selection: Binding(
                        get: { Date(timeIntervalSince1970: card.timestamp / 1000) },
                        set: { self.card?.timestamp = ($0.timeIntervalSince1970 * 1000).rounded() }
                    ), in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                }
                if let failure {
                    Section { Text(failure).foregroundStyle(StatusTone.error.foreground) }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func drinkSection(_ card: DrinkPhotoConfirmation, db: CaffeineDatabase) -> some View {
        Section {
            ForEach(card.candidates) { candidate in
                selectableRow(candidate.entry.displayName,
                              detail: candidate.reason == .barcode ? "Barcode match" : nil,
                              selected: card.entry?.id == candidate.entry.id) {
                    self.card?.select(candidate.entry); typing = false; typedText = ""
                }
            }
            TextField("Search the database", text: $search).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("photo-log-search")
            if !search.trimmingCharacters(in: .whitespaces).isEmpty {
                let results = DrinkPhotoMatcher.search(search, in: db)
                if results.isEmpty { Text(DrinkPhotoConfirmation.notInDatabaseTitle).foregroundStyle(Palette.textSecondary).accessibilityIdentifier("photo-log-search-not-found") }
                ForEach(results) { result in
                    selectableRow(result.entry.displayName, detail: nil, selected: card.entry?.id == result.entry.id) {
                        self.card?.select(result.entry); search = ""; typing = false; typedText = ""
                    }
                }
            }
            Button("Enter It Yourself") { startManualEntry() }
                .frame(minHeight: Metrics.minimumTouchTarget)
                .accessibilityIdentifier("photo-log-enter-manually")
        } header: {
            Text(card.isNotInDatabase ? DrinkPhotoConfirmation.notInDatabaseTitle : "Drink")
                .accessibilityIdentifier(card.isNotInDatabase ? "photo-log-not-in-database" : "photo-log-drink")
        } footer: {
            if card.entry == nil, let ask = card.clarification(db: db) { Text(ask) }
        }
    }

    /// A drink the database doesn't have: the person names it and types the
    /// amount. "Search the Database" returns to the matches.
    private func manualSection(_ card: DrinkPhotoConfirmation) -> some View {
        Section {
            TextField("Drink Name", text: Binding(get: { card.manualName ?? "" }, set: { self.card?.name($0) }))
                .accessibilityIdentifier("photo-log-manual-name")
            Button("Search the Database") { leaveManualEntry() }
                .frame(minHeight: Metrics.minimumTouchTarget)
        } header: { Text(DrinkPhotoConfirmation.notInDatabaseTitle).accessibilityIdentifier("photo-log-not-in-database") } footer: {
            Text(DrinkPhotoConfirmation.manualEntryLine).accessibilityIdentifier("photo-log-manual-line")
        }
    }

    private func servingSection(_ card: DrinkPhotoConfirmation, db: CaffeineDatabase) -> some View {
        Section {
            if let entry = card.entry {
                ForEach(Array(card.usableLabelVolumes.enumerated()), id: \.offset) { _, volume in
                    let mg = db.mg(for: entry, volume: volume)
                    selectableRow("\(volume.label) · from label", detail: mg.map { "\($0) mg" },
                                  selected: card.serving == .label(volume)) { self.card?.choose(.label(volume)); typing = false }
                }
                ForEach(Array(entry.servings.enumerated()), id: \.offset) { index, serving in
                    selectableRow(serving.label, detail: "\(serving.mg) mg", selected: card.serving == .listed(index)) {
                        self.card?.choose(.listed(index)); typing = false
                    }
                }
                if entry.servings.isEmpty && card.usableLabelVolumes.isEmpty {
                    Text("This entry lists no serving size. Enter the amount below.").foregroundStyle(Palette.textSecondary)
                }
            }
        } header: { Text("Size") }
    }

    private func amountSection(_ card: DrinkPhotoConfirmation, db: CaffeineDatabase) -> some View {
        Section {
            if let amount = card.amount(db: db), !typing {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(amount.mg) mg").font(.title2.monospacedDigit().weight(.semibold)).accessibilityIdentifier("photo-log-mg")
                    Spacer()
                    Button("Edit") { typedText = String(amount.mg); typing = true; self.card?.type(mg: typedText); amountFocused = true }
                }
            } else if typing || card.entry != nil || card.manualName != nil {
                HStack {
                    TextField("Amount", text: Binding(get: { typedText }, set: { typedText = $0; self.card?.type(mg: $0) }))
                        .keyboardType(.numberPad).focused($amountFocused).font(.title2.monospacedDigit())
                        .accessibilityLabel("Amount, milligrams").accessibilityIdentifier("photo-log-amount")
                    Text("mg").foregroundStyle(Palette.textSecondary).accessibilityHidden(true)
                }
                if typing, card.manualName == nil {
                    Button("Use Database Amount") { typing = false; typedText = ""; self.card?.clearTypedAmount() }
                }
            }
        } header: { Text("Caffeine") } footer: {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                if let amount = card.amount(db: db) { Text("Source: " + amount.provenance) }
                if card.entry != nil || card.manualName != nil, let ask = card.clarification(db: db) { Text(ask) }
                if let entry = card.entry, let source = db.source(for: entry) {
                    Text("\(source.name), released \(source.release). \(source.license).").foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }

    private func selectableRow(_ title: String, detail: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.selection(); action() }) {
            HStack {
                Text(title).foregroundStyle(Palette.textPrimary).multilineTextAlignment(.leading)
                Spacer()
                if let detail { Text(detail).foregroundStyle(Palette.textSecondary).monospacedDigit() }
                if selected { Image(systemName: "checkmark").foregroundStyle(Palette.tint).accessibilityHidden(true) }
            }
            .frame(minHeight: Metrics.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func unavailable(_ message: String) -> some View {
        VStack { Text(message).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center).padding(Metrics.lg); Spacer() }
    }

    // MARK: Actions

    private func begin(_ picked: UIImage) {
        guard let db else { return }
        failure = nil
        image = picked
        phase = .reading
        analysis?.cancel()
        analysis = Task {
            let observation = await DrinkPhotoAnalyzer.analyze(picked)
            guard !Task.isCancelled else { return }
            app.tick()
            card = DrinkPhotoConfirmation(result: DrinkPhotoMatcher.match(observation, in: db), observation: observation, timestamp: app.now)
            phase = .review
        }
    }

    private func startManualEntry() {
        card?.enterManually(); search = ""
        typedText = ""; typing = true; amountFocused = false
    }
    private func leaveManualEntry() {
        card?.leaveManualEntry(); typing = false; typedText = ""
    }

    private var currentDraft: CustomDoseDraft? {
        guard let db, let card else { return nil }
        return card.draft(db: db, now: app.now)
    }

    /// Save is the only write. The conversation then shows the standard
    /// "Caffeine saved" card with Undo for this entry.
    private func save() {
        guard !saved else { return }
        app.tick()
        guard let draft = currentDraft else { failure = "Pick a drink and a size first. Nothing was saved."; return }
        if let problem = assistant.savePhotoDose(draft, app: app) { failure = problem; return }
        saved = true
        // The saved card's badge gives the success haptic.
        close()
    }

    private func close() {
        analysis?.cancel()
        image = nil; card = nil
        dismiss()
    }
}

/// The system camera. Camera permission is asked by iOS the first time this
/// opens, never earlier. The captured photo is returned in memory only and is
/// not written to the photo library.
private struct CameraCapture: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}
