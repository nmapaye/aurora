import AuroraSpikeCore
import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
    case today = "Today", sleep = "Sleep", insights = "Insights", browse = "Browse"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .sleep: "bed.double.fill"
        case .insights: "chart.xyaxis.line"
        case .browse: "square.grid.2x2.fill"
        }
    }
}

@MainActor
public struct AuroraSpikeRootView: View {
    @State private var model = PreviewModel()
    @State private var selected = Destination.today
    @State private var editingDrink: SavedDrink?
    @State private var editingSleep = false
    @State private var showingAbout = false

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            Group {
                if geometry.size.width >= 760 {
                    NavigationSplitView {
                        List(Destination.allCases, selection: Binding<Destination?>(get: { selected }, set: { if let value = $0 { selected = value } })) { destination in
                            Label(destination.rawValue, systemImage: destination.symbol)
                                .tag(destination)
                                .padding(.vertical, 6)
                        }
                        .navigationTitle("Aurora")
                        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
                        .safeAreaInset(edge: .bottom) { previewBadge.padding(16) }
                    } detail: {
                        page(selected)
                    }
                } else {
                    TabView(selection: $selected) {
                        ForEach(Destination.allCases) { destination in
                            NavigationStack { page(destination) }
                                .tabItem { Label(destination.rawValue, systemImage: destination.symbol) }
                                .tag(destination)
                        }
                    }
                }
            }
            .background(SpikeStyle.background)
            .tint(SpikeStyle.blue)
            .safeAreaInset(edge: .bottom, spacing: 0) { undoBar }
            .sheet(item: $editingDrink) { drink in
                DrinkServingSheet(model: model, initial: drink)
            }
            .sheet(isPresented: $editingSleep) { SleepEditorSheet(model: model) }
            .sheet(isPresented: $showingAbout) { aboutSheet }
            .alert("Preview", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
                Button("OK", role: .cancel) { model.notice = nil }
            } message: { Text(model.notice ?? "") }
        }
    }

    @ViewBuilder private func page(_ destination: Destination) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = max(context.date, model.lastChange)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        PageHeading(title: destination.rawValue, subtitle: now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        if destination == .today { customizationMenu }
                    }
                    switch destination {
                    case .today:
                        TodayPage(model: model, now: now, editSleep: { editingSleep = true }, openDrink: { editingDrink = $0 })
                    case .sleep:
                        SleepPage(model: model, now: now, editSleep: { editingSleep = true })
                    case .insights:
                        InsightsPage(model: model, now: now)
                    case .browse:
                        BrowsePage(model: model, openDrink: { editingDrink = $0 })
                    }
                    previewBadge.padding(.vertical, 3)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
                .frame(maxWidth: 940)
                .frame(maxWidth: .infinity)
            }
            .background(SpikeStyle.background)
        }
    }

    private var customizationMenu: some View {
        Menu {
            Toggle("Today's intake", isOn: $model.showIntake)
            Toggle("Last night's sleep", isOn: $model.showSleep)
            Divider()
            Button("About this preview", systemImage: "info.circle") { showingAbout = true }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Customize Today")
    }

    private var previewBadge: some View {
        Button { showingAbout = true } label: {
            Label("Design preview · example data", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minHeight: 32)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("preview-banner")
    }

    @ViewBuilder private var undoBar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let undo = model.lastUndo, undo.expiresAt > context.date {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(SpikeStyle.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(undo.dose.serving.drinkName) logged").font(.subheadline.weight(.semibold))
                        Text("\(undo.dose.serving.caffeineMG.mgText) mg · This preview only").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Undo") { model.undo(now: Date()) }
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("undo-dose")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .padding(12)
                .frame(maxWidth: 620)
                .accessibilityElement(children: .contain)
            }
        }
    }

    private var aboutSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "sun.horizon.fill").font(.system(size: 46)).foregroundStyle(SpikeStyle.blue)
                    Text("A feel for the next Aurora").font(.title.bold())
                    Text("Try the daily flow, adjust a drink by its fill level, and choose your next sleep window.")
                    Text("This is an isolated design preview. It uses example caffeine and sleep records. Your changes stay in memory and reset when the preview closes.")
                    Text("It does not read Apple Health, request permissions, open production data, or save to your existing Aurora app. Caffeine amounts are reference estimates, and the curve is an illustrative half-life model.")
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .navigationTitle("About this preview")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingAbout = false } } }
        }
        .frame(idealWidth: 490, idealHeight: 480)
    }
}
