import AuroraCore
import SwiftUI

/// Every caffeine entry, filterable by range and searchable by drink or note.
/// Recorded entries open Edit Entry; sample entries are read-only.
struct CaffeineHistoryView: View {
    enum Range: String, CaseIterable, Identifiable {
        case week = "7d"
        case twoWeeks = "14d"
        case month = "30d"
        case all = "All"

        var id: String { rawValue }

        var days: Int? {
            switch self {
            case .week: 7
            case .twoWeeks: 14
            case .month: 30
            case .all: nil
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var range: Range = .all
    @State private var query = ""
    @State private var sheet: DoseSheet?

    var body: some View {
        let doses = filtered
        List {
            Section {
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            Section {
                if doses.isEmpty {
                    Text(query.isEmpty ? "No caffeine logged in this range." : "No entries match “\(query)”.")
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    ForEach(doses) { dose in
                        DoseRow(dose: dose) { sheet = .edit(dose) }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(RecordID.isSample(dose.id) ? Palette.cardMuted : Palette.card)
                            .swipeActions {
                                if CaffeineLog.isEditable(dose) {
                                    Button("Edit") { sheet = .edit(dose) }.tint(Palette.tint)
                                }
                            }
                    }
                }
            } header: {
                Text("\(doses.count) \(doses.count == 1 ? "entry" : "entries")")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.screen)
        .searchable(text: $query, prompt: "Drink or note")
        .navigationTitle("Caffeine History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { sheet in
            if case .edit(let dose) = sheet {
                DoseEntrySheet(mode: sheet, draft: CaffeineLog.editDraft(for: dose)) { result in
                    switch result {
                    case .saved(let draft): model.correctDose(id: dose.id, with: draft)
                    case .deleted: model.deleteDose(id: dose.id)
                    case .cancelled: break
                    }
                }
            }
        }
    }

    private var filtered: [Dose] {
        let now = model.now
        let start = range.days.map { model.clock.addingDays(-($0 - 1), to: model.clock.startOfDay(now)) }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return CaffeineLog.recent(model.state.doses, limit: .max).filter { dose in
            if let start, dose.timestamp < start { return false }
            guard !needle.isEmpty else { return true }
            return [dose.source, dose.note, numberText(dose.mg)].compactMap { $0?.lowercased() }.contains { $0.contains(needle) }
        }
    }
}
