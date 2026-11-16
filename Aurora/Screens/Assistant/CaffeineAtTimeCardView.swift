import AuroraCore
import SwiftUI

/// "Estimated Active Caffeine": rows from `CaffeineAtTime`, the chips the
/// question still needs, and Log This Drink for a Not Logged drink. Nothing
/// here records anything; Log This Drink opens the confirm card.
struct CaffeineAtTimeCardView: View {
    let message: ConversationMessage
    let card: AssistantCard
    let active: Bool
    @Environment(AppModel.self) private var app
    @Environment(AssistantModel.self) private var assistant
    @State private var showsInfo = false
    @State private var amount = ""
    @State private var amountRejected = false
    @State private var sleepTime = Date()
    @FocusState private var amountFocused: Bool

    private var zone: TimeZone { TimeZone(identifier: card.timeZone) ?? .current }
    private var text: DateText { .localized(timeZone: zone) }
    private var db: CaffeineDatabase? { CaffeineDatabase.bundled }

    var body: some View {
        if let state = card.caffeineAtTime {
            VStack(alignment: .leading, spacing: Metrics.md) {
                HStack(alignment: .center) {
                    Text("Times in \(zone.identifier)").font(Typography.source).foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                    InfoButton(topic: CaffeineAtTime.title, isShown: $showsInfo)
                }
                if showsInfo {
                    InfoText(text: CaffeineAtTime.halfLifeInfo(state.halfLifeHours), id: "caffeine-at-time-info")
                }
                ForEach(Array(state.rows(text: text).enumerated()), id: \.offset) { index, row in
                    valueRow(row).accessibilityIdentifier("caffeine-at-time-row-\(index)")
                }
                ForEach(state.lines(text: text, db: db), id: \.self) { line in
                    Text(line).font(.footnote).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if active { controls(state) }
            }
            .onChange(of: amountFocused) { _, focused in assistant.cardFocus(message.id, focused: focused) }
            .onDisappear { assistant.cardFocus(message.id, focused: false) }
        }
    }

    @ViewBuilder private func controls(_ state: CaffeineAtTimeCard) -> some View {
        let now = AppModel.currentMillis()
        ForEach(state.choices, id: \.self) { choice in
            Button(state.label(for: choice, text: text, db: db, now: now)) {
                assistant.chooseCaffeineAtTime(message.id, choice, app: app)
            }
            .buttonStyle(.auroraSecondary)
            .disabled(assistant.processing)
            .accessibilityIdentifier("caffeine-at-time-choice")
        }
        if state.needsSleepTime {
            DatePicker(CaffeineAtTimeCard.sleepPickerLabel, selection: $sleepTime, displayedComponents: .hourAndMinute)
                .environment(\.timeZone, zone)
                .accessibilityIdentifier("caffeine-at-time-sleep-picker")
            Button("Use This Sleep Time") {
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
                let parts = calendar.dateComponents([.hour, .minute], from: sleepTime)
                assistant.setCaffeineAtTimeSleep(message.id, hour: parts.hour ?? 0, minute: parts.minute ?? 0, app: app)
            }
            .buttonStyle(.auroraSecondary)
            .accessibilityIdentifier("caffeine-at-time-sleep-use")
        }
        if state.needsAmount {
            HStack(spacing: Metrics.sm) {
                TextField(CaffeineAtTimeCard.enterAmountLabel, text: $amount)
                    .keyboardType(.numberPad)
                    .focused($amountFocused)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("caffeine-at-time-amount")
                Text("mg").foregroundStyle(Palette.textSecondary)
                Button(CaffeineAtTimeCard.enterAmountLabel) {
                    amountRejected = !assistant.setCaffeineAtTimeAmount(message.id, amount, app: app)
                    if !amountRejected { amountFocused = false }
                }
                .buttonStyle(.auroraSecondary)
                .accessibilityIdentifier("caffeine-at-time-amount-enter")
            }
            if amountRejected {
                Text(TypedDrinkEntry.amountRangeMessage).font(.footnote).foregroundStyle(Palette.destructive)
            }
        }
        if state.logDraft != nil {
            Button(CaffeineAtTime.logThisDrinkLabel) { assistant.logCaffeineAtTimeDrink(message.id, app: app) }
                .buttonStyle(.auroraPrimary)
                .disabled(assistant.processing)
                .accessibilityIdentifier("caffeine-at-time-log")
        }
    }

    private func valueRow(_ row: CaffeineAtTimeCard.RowView) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
                Text(row.label).font(Typography.label).foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
                Text(row.value).font(Typography.value).monospacedDigit().multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: Metrics.xxs) {
                Text(row.label).font(Typography.label).foregroundStyle(Palette.textSecondary)
                Text(row.value).font(Typography.value).monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spoken)
    }
}
