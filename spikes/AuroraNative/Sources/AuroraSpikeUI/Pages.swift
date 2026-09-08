import AuroraSpikeCore
import SwiftUI

@MainActor
struct TodayPage: View {
    let model: PreviewModel
    let now: Date
    let editSleep: () -> Void
    let openDrink: (SavedDrink) -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    CardLabel(title: "Caffeine near bedtime", symbol: "moon.stars.fill")
                    Spacer()
                    Text("ESTIMATE").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
                if let plan = model.acceptedPlan(at: now) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(model.active(at: plan.start).mgText).font(.system(size: 46, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("mg at \(plan.start.formatted(date: .omitted, time: .shortened))").font(.title3).foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your evening, in view.").font(.title2.bold())
                        Text("Choose your next sleep time to see the estimate there.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                CaffeineTimeline(model: model, now: now)
                Divider()
                Button(action: editSleep) {
                    HStack {
                        Label(model.acceptedPlan(at: now) == nil ? "Set your next sleep window" : "Sleep window", systemImage: "bed.double")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if let plan = model.acceptedPlan(at: now) { Text(plan.start, style: .time).font(.subheadline) }
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("edit-sleep-plan")
            }
        }

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) { metrics }
            VStack(spacing: 14) { metrics }
        }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your usual drinks").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Tap to log").font(.caption).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { favoriteCards }
                VStack(spacing: 14) { favoriteCards }
            }
        }
        if !model.history.doses.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Recent in this preview").font(.headline)
                    ForEach(model.history.doses.sorted { $0.timestamp > $1.timestamp }.prefix(4)) { dose in
                        HStack(spacing: 12) {
                            Image(systemName: "cup.and.saucer.fill").foregroundStyle(SpikeStyle.blue).frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(dose.serving.drinkName).font(.subheadline.weight(.medium))
                                Text("\(dose.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(dose.isExample ? "Example" : "Session entry")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(dose.serving.caffeineMG.mgText) mg").font(.subheadline).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    @ViewBuilder private var metrics: some View {
        if model.showIntake {
            MetricCard(title: "Today's intake", symbol: "cup.and.saucer.fill", value: model.intake(at: now)?.mgText ?? "—", unit: model.intake(at: now) == nil ? "" : "mg", detail: model.intake(at: now) == nil ? "No entries today" : "Preview records, including examples")
                .frame(minWidth: 145)
        }
        if model.showSleep {
            let last = model.episodes.max { $0.end < $1.end }
            let hours = last.map { $0.end.timeIntervalSince($0.start) / 3600 }
            MetricCard(title: "Last night's sleep", symbol: "bed.double.fill", value: hours?.formatted(.number.precision(.fractionLength(1))) ?? "—", unit: "h", detail: "Example sleep · Health not connected", color: SpikeStyle.purple)
                .frame(minWidth: 145)
        }
    }

    @ViewBuilder private var favoriteCards: some View {
        ForEach(model.favorites) { drink in
            FavoriteCard(drink: drink, model: model, open: { openDrink(drink) })
                .frame(minWidth: 145)
        }
    }
}

@MainActor
struct FavoriteCard: View {
    let drink: SavedDrink
    let model: PreviewModel
    let open: () -> Void
    var body: some View {
        Card {
            Button {
                if drink.recipe.basis.needsShotChoice { open() } else { model.log(drink) }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: drink.symbol).font(.title2).foregroundStyle(SpikeStyle.blue)
                        Spacer(minLength: 44)
                    }
                    .frame(height: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(drink.recipe.name).font(.headline).foregroundStyle(.primary)
                        Text(drink.snapshot.map { "\($0.caffeineMG.mgText) mg · \(model.volume($0.consumedVolumeML))" } ?? "Choose your usual shots")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(drink.recipe.basis.needsShotChoice ? "Set up once" : "Log usual serving")
                            .font(.caption.weight(.semibold)).foregroundStyle(SpikeStyle.blue).padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("favorite-\(drink.id)")
            .contextMenu { Button("Edit serving", systemImage: "slider.horizontal.3", action: open) }
            .overlay(alignment: .topTrailing) {
                Menu {
                    Button("Edit serving", systemImage: "slider.horizontal.3", action: open)
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Options for \(drink.recipe.name)")
            }
        }
    }
}

@MainActor
struct SleepPage: View {
    let model: PreviewModel
    let now: Date
    let editSleep: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(title: "Your next sleep", symbol: "moon.stars.fill", color: SpikeStyle.purple)
                if let plan = model.acceptedPlan(at: now) {
                    Text("\(plan.start.formatted(date: .omitted, time: .shortened)) – \(plan.end.formatted(date: .omitted, time: .shortened))")
                        .font(.system(.title, design: .rounded).weight(.semibold))
                    Text("\(plan.start.formatted(date: .abbreviated, time: .omitted)) · Accepted by you in this preview")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("About \(model.active(at: plan.start).mgText) mg estimated at bedtime. Your chosen time stays the same.")
                        .font(.subheadline)
                } else {
                    Text("Make room for tonight.").font(.title2.bold())
                    Text("A suggested time stays a suggestion until you accept it.").foregroundStyle(.secondary)
                }
                Button(model.acceptedPlan(at: now) == nil ? "Choose sleep window" : "Edit sleep window", action: editSleep)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("edit-sleep-plan")
            }
        }
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardLabel(title: "Recent sleep", symbol: "bed.double.fill", color: SpikeStyle.purple)
                Text("These are example nights. Apple Health is not connected in this preview.").font(.subheadline).foregroundStyle(.secondary)
                ForEach(model.episodes.sorted { $0.end > $1.end }.prefix(4)) { episode in
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.end.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.subheadline.weight(.medium))
                            Text("\(episode.start.formatted(date: .omitted, time: .shortened)) – \(episode.end.formatted(date: .omitted, time: .shortened)) · Example")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\((episode.end.timeIntervalSince(episode.start) / 3600).formatted(.number.precision(.fractionLength(1)))) h")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
                if !model.episodes.isEmpty {
                    Button("Try without sleep history") { model.episodes = [] }
                        .font(.caption).padding(.top, 4)
                } else {
                    Text("No example sleep history. You can still choose a sleep time manually.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}

@MainActor
struct InsightsPage: View {
    @Bindable var model: PreviewModel
    let now: Date
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(title: "How the estimate works", symbol: "chart.xyaxis.line")
                Text("Caffeine fades gradually.").font(.title2.bold())
                Text("This preview uses a simple half-life model. Every \(model.halfLifeHours.formatted(.number.precision(.fractionLength(1)))) hours, the estimated amount halves. Individual metabolism and drink strength vary.")
                    .font(.subheadline).foregroundStyle(.secondary)
                CaffeineTimeline(model: model, now: now, height: 220)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Explore half-life").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(model.halfLifeHours.formatted(.number.precision(.fractionLength(1)))) hours").font(.subheadline).monospacedDigit()
                    }
                    Slider(value: $model.halfLifeHours, in: 2...10, step: 0.5) { Text("Half-life in hours") }
                        .accessibilityValue("\(model.halfLifeHours.formatted()) hours")
                    Text("Changes only this preview. This is not a safe-to-sleep threshold or a measured caffeine level.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Timeline as a table").font(.headline).accessibilityAddTraits(.isHeader)
                ForEach(0..<7) { offset in
                    let time = now.addingTimeInterval(Double(offset) * 2 * 3600)
                    HStack {
                        Text(offset == 0 ? "Now" : time.formatted(date: .omitted, time: .shortened))
                        Spacer()
                        Text("\(model.active(at: time).mgText) mg estimated").foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                    if offset < 6 { Divider() }
                }
            }
        }
    }
}

@MainActor
struct BrowsePage: View {
    @Bindable var model: PreviewModel
    let openDrink: (SavedDrink) -> Void
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                CardLabel(title: "Drink library", symbol: "cup.and.saucer.fill")
                Text("A serving that looks like yours.").font(.title2.bold())
                Text("Choose a drink, then its container and the amount you drank. Recipe estimates are explained inside.")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(model.drinks) { drink in
                    Divider()
                    Button { openDrink(drink) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: drink.symbol).font(.title2).foregroundStyle(drink.id == "matcha" ? .green : SpikeStyle.blue).frame(width: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(drink.recipe.name).font(.headline).foregroundStyle(.primary)
                                Text(drink.recipe.basis.needsShotChoice ? "Choose your usual shots" : "\(drink.snapshot?.caffeineMG.mgText ?? "—") mg · \(model.volume(drink.container.capacityML * drink.fraction))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library-\(drink.id)")
                }
            }
        }
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Volume units", selection: $model.unit) {
                    ForEach(VolumeUnit.allCases) { unit in Text(unit.symbol).tag(unit) }
                }
                Text("My Tumbler starts at 16 US fl oz, about 473 ml. You can edit its name and capacity in a drink’s serving sheet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
