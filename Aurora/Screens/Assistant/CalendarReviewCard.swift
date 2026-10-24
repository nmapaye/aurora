import AuroraCore
import SwiftUI

struct CalendarReviewCard: View {
    @Bindable var service: CalendarService
    var snapshot: [Commitment]? = nil
    var editable = true
    var snapshotMessage: String? = nil
    /// When a snapshot was captured; a snapshot lists what was left of that day.
    var capturedAt: Date? = nil
    var onOutcome: ((String, Commitment?) -> Void)? = nil
    var connect: () -> Void
    @State private var proposal: CalendarChange?
    @State private var result: String?
    @State private var applying = false
    @State private var reversal: CalendarChange?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Everything loaded, hidden routines included, so a proposed move never
    /// lands on them.
    private var events: [Commitment] { (snapshot ?? service.commitments).sorted { $0.start < $1.start } }
    private var reference: Date { editable ? .now : (capturedAt ?? .now) }
    /// What's left of the day, without sleep and routine blocks.
    private var shown: [Commitment] { CalendarAgenda.restOfToday(events, now: reference, calendar: .current) }

    var body: some View {
        Card {
            HStack {
                Label("Calendar", systemImage: "calendar").font(Typography.cardTitle)
                Spacer()
                if service.loading { ProgressView().controlSize(.small) }
                Button(action: connect) {
                    Image(systemName: "gearshape").font(.body).frame(width: Metrics.minimumTouchTarget, height: Metrics.minimumTouchTarget)
                }
                .buttonStyle(.auroraPress)
                .accessibilityLabel("Calendar connections")
            }
            if service.selected.isEmpty && editable && events.isEmpty {
                Button("Choose calendars", action: connect).buttonStyle(.auroraSecondary)
            }
            if let message = snapshotMessage ?? (snapshot == nil ? service.message : nil) {
                Label(message, systemImage: StatusTone.error.symbol).font(.footnote).foregroundStyle(StatusTone.error.foreground)
            }
            if shown.isEmpty && snapshotMessage == nil && !service.selected.isEmpty {
                Text("Nothing else today.").font(.subheadline).foregroundStyle(Palette.textSecondary)
            }
            let clashes = CalendarAgenda.clashing(shown)
            let labelSource = CalendarAgenda.showsSource(shown)
            ForEach(days, id: \.self) { day in
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    Text(dayTitle(day)).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(shown.filter { Calendar.current.isDate(max($0.start, Calendar.current.startOfDay(for: reference)), inSameDayAs: day) }, id: \.identity) { event in
                        VStack(alignment: .leading, spacing: Metrics.xxs) {
                            if event.provider == .google { GoogleEventRow(event: event, time: time(event), showsSource: labelSource) }
                            else { AppleEventRow(event: event, time: time(event), showsSource: labelSource) }
                            // Only a clash needs moving.
                            if editable && clashes.contains(event.identity) && event.canMove && event.start > .now && proposal?.original.identity != event.identity {
                                Button("Find a later slot") { propose(event) }
                                    .font(.footnote.weight(.semibold))
                                    .buttonStyle(.auroraPress)
                                    .foregroundStyle(Palette.tint)
                                    .frame(minHeight: Metrics.minimumTouchTarget)
                                    .disabled(applying || service.message != nil)
                            }
                        }
                    }
                }
            }
            if editable, let proposal { review(proposal) }
            if let result { Text(result).font(.footnote).foregroundStyle(Palette.textSecondary).accessibilityIdentifier("calendar-result") }
            if editable, let reversal, proposal == nil, reversal.newStart > .now {
                Button("Undo this move") { proposal = reversal; self.reversal = nil }
                    .buttonStyle(.auroraSecondary)
                    .disabled(applying)
            }
        }
        .animation(Motion.stateChange(reduceMotion: reduceMotion), value: proposal?.id)
    }

    /// Today's heading; an event already running since yesterday counts as today.
    private var days: [Date] {
        var seen = Set<Date>()
        let today = Calendar.current.startOfDay(for: reference)
        return shown.map { max(Calendar.current.startOfDay(for: $0.start), today) }.filter { seen.insert($0).inserted }
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// Local times; the event's own zone is named only when it differs.
    private func time(_ event: Commitment) -> String {
        if event.allDay == true { return "All day" }
        let ends = event.end.formatted(date: .omitted, time: .shortened)
        let range = "\(event.start.formatted(date: .omitted, time: .shortened)) – \(ends)\(CalendarAgenda.endsNextDay(event, calendar: .current) ? " next day" : "")"
        guard let zone = TimeZone(identifier: event.timeZone), zone.secondsFromGMT(for: event.start) != TimeZone.current.secondsFromGMT(for: event.start) else { return range }
        return "\(range) · \(zone.abbreviation(for: event.start) ?? event.timeZone)"
    }

    private func propose(_ event: Commitment) {
        reversal = nil
        proposal = CalendarActionValidator.proposedMove(event, among: events, now: .now, calendar: .current)
        if proposal == nil { result = "No free later slot that day." }
    }

    @ViewBuilder private func review(_ proposal: CalendarChange) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Text("Move \u{201C}\(proposal.original.title)\u{201D}?").font(Typography.cardTitle)
            HStack(spacing: Metrics.xs) {
                Text(proposal.original.start.formatted(date: .omitted, time: .shortened)).strikethrough().foregroundStyle(Palette.textSecondary)
                Image(systemName: "arrow.right").foregroundStyle(Palette.textSecondary).accessibilityHidden(true)
                Text("\(proposal.newStart.formatted(date: .omitted, time: .shortened)) – \(proposal.newEnd.formatted(date: .omitted, time: .shortened))").fontWeight(.semibold)
            }
            .font(.subheadline.monospacedDigit())
            .accessibilityElement(children: .combine)
            Text(proposal.original.recurring ? "This occurrence only. No invitations sent." : "No invitations sent.")
                .font(.caption).foregroundStyle(Palette.textSecondary)
            Button(applying ? "Moving…" : "Approve move") { Task { await apply(proposal) } }
                .buttonStyle(.auroraPrimary).disabled(applying).accessibilityIdentifier("calendar-approve")
            Button("Cancel") { self.proposal = nil }.buttonStyle(.auroraSecondary).disabled(applying)
        }
        .padding(Metrics.sm)
        .background(Palette.cardMuted, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
        .transition(Motion.stateTransition(reduceMotion: reduceMotion))
    }

    private func apply(_ change: CalendarChange) async {
        guard !applying else { return }
        applying = true; defer { applying = false; proposal = nil }
        do {
            let updated = try await service.approve(change)
            result = "Moved \u{2018}\(updated.title)\u{2019}."
            reversal = .init(original: updated, newStart: change.original.start, newEnd: change.original.end)
            onOutcome?(result ?? "Moved event.", updated)
        } catch CalendarActionError.stale {
            result = "This event changed after the preview. Nothing was moved."
            onOutcome?(result!, nil)
        } catch CalendarActionError.conflict {
            result = "Something now overlaps that slot. Nothing was moved."
            onOutcome?(result!, nil)
        } catch {
            result = "Couldn't confirm the move. Refresh before trying again."
            onOutcome?(result!, nil)
        }
    }
}

extension Color {
    /// "#RRGGBB" from a calendar; nil when it isn't one.
    init?(calendarHex: String?) {
        guard let calendarHex, calendarHex.hasPrefix("#"), calendarHex.count == 7, let value = Int(calendarHex.dropFirst(), radix: 16) else { return nil }
        self.init(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    /// Black or white, whichever reads better on this color.
    static func readableText(onHex hex: String?) -> Color {
        guard let hex, let value = Int(hex.dropFirst(), radix: 16) else { return .white }
        func linear(_ c: Int) -> Double { let v = Double(c) / 255; return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear((value >> 16) & 0xFF) + 0.7152 * linear((value >> 8) & 0xFF) + 0.0722 * linear(value & 0xFF)
        return luminance > 0.4 ? Color(white: 0.12) : .white
    }
}

/// Google Calendar's schedule look: a solid block in the calendar's color.
private struct GoogleEventRow: View {
    let event: Commitment
    let time: String
    var showsSource = true
    static let defaultHex = "#039BE5"

    var body: some View {
        let hex = event.colorHex ?? Self.defaultHex
        let ink = Color.readableText(onHex: hex)
        VStack(alignment: .leading, spacing: 2) {
            Text(event.title).font(.subheadline.weight(.semibold))
            Text(time).font(.caption.monospacedDigit())
            if let location = event.location { Text(location).font(.caption).lineLimit(1) }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.sm)
        .padding(.vertical, Metrics.xs)
        .background(Color(calendarHex: hex) ?? .blue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topTrailing) { if showsSource { SourceTag(text: "Google", color: ink.opacity(0.8)).padding(6) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(time)\(event.location.map { ", \($0)" } ?? ""), Google Calendar")
    }
}

/// Apple Calendar's look: a color bar beside the event on a light tint.
private struct AppleEventRow: View {
    let event: Commitment
    let time: String
    var showsSource = true
    static let defaultHex = "#007AFF"

    var body: some View {
        let color = Color(calendarHex: event.colorHex ?? Self.defaultHex) ?? .blue
        HStack(alignment: .top, spacing: Metrics.sm) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                Text(time).font(.caption.monospacedDigit()).foregroundStyle(Palette.textSecondary)
                if let location = event.location {
                    Label(location, systemImage: "mappin").font(.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if showsSource { SourceTag(text: "Apple", color: Palette.textSecondary) }
        }
        .padding(.vertical, Metrics.xs)
        .padding(.trailing, Metrics.xs)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(time)\(event.location.map { ", \($0)" } ?? ""), Apple Calendar")
    }
}

private struct SourceTag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(color).accessibilityHidden(true)
    }
}

struct CalendarConnectionsView: View {
    @Bindable var service: CalendarService
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var error: String?
    @State private var appleMirror = ""
    @State private var googleMirror = ""
    @State private var authority = CalendarProviderID.google
    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Calendar") {
                    Text("Aurora reads the calendars you select on this device, and moves an event only after you approve its preview. Google calendars synced to Apple can also be selected here.").font(.footnote)
                    Button("Connect Apple Calendar") {
                        Task { await perform { try await service.apple.connect() } }
                    }.disabled(busy)
                }
                Section("Google Calendar") {
                    if service.google.configured {
                        Button(service.google.connected ? "Reconnect Google" : "Connect Google directly") {
                            Task { await perform { try await service.google.connect() } }
                        }.disabled(busy)
                        if service.google.connected { Button("Disconnect Google", role: .destructive) {
                            service.google.disconnect()
                            service.selected = Set(service.selected.filter { !$0.hasPrefix("google:") })
                            Task { await service.refreshCalendars(); await service.refresh() }
                        } }
                    } else {
                        Text("Direct Google sign-in needs Aurora’s registered iOS OAuth client. Until that is configured, use a Google calendar synced through Apple. No API key is required or accepted.").font(.footnote)
                    }
                }
                Section("Include calendars") {
                    Text("If the same Google calendar appears through both connections, select its authoritative connection below. Do not select both copies.").font(.footnote)
                    ForEach(service.calendars, id: \.selfID) { calendar in
                        Toggle(isOn: Binding(get: { service.selected.contains(service.key(calendar)) }, set: { value in
                            if value != service.selected.contains(service.key(calendar)) { service.toggle(calendar) }
                        })) {
                            VStack(alignment: .leading) {
                                Text(calendar.title)
                                Text("\(calendar.provider.rawValue.capitalized) · \(calendar.writable ? "Read and review changes" : "Read-only")").font(.caption)
                            }
                        }
                    }
                }
                if service.google.connected {
                    Section("Identify a mirrored calendar") {
                        Text("Choose two connections to the same calendar, then pick the one Aurora should use. This prevents duplicate reads and writes.").font(.footnote)
                        Picker("Apple connection", selection: $appleMirror) {
                            Text("Choose calendar").tag("")
                            ForEach(service.calendars.filter { $0.provider == .apple }) { Text($0.title).tag($0.id) }
                        }
                        Picker("Google connection", selection: $googleMirror) {
                            Text("Choose calendar").tag("")
                            ForEach(service.calendars.filter { $0.provider == .google }) { Text($0.title).tag($0.id) }
                        }
                        Picker("Use this connection", selection: $authority) {
                            Text("Apple").tag(CalendarProviderID.apple)
                            Text("Google").tag(CalendarProviderID.google)
                        }
                        Button("Link these mirrored connections") {
                            service.linkMirror(appleID: appleMirror, googleID: googleMirror, authority: authority)
                            appleMirror = ""; googleMirror = ""
                        }.disabled(appleMirror.isEmpty || googleMirror.isEmpty)
                    }
                }
                if let error = error ?? service.message { Section { Text(error).foregroundStyle(Palette.destructive) } }
            }
            .navigationTitle("Calendar connections").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { Task { await service.refresh() }; dismiss() } } }
            .task { await service.refreshCalendars() }
        }
    }
    private func perform(_ action: () async throws -> Void) async {
        busy = true; defer { busy = false }
        do { try await action(); await service.refreshCalendars(); error = nil }
        catch { self.error = "Couldn't connect. Check account access and try again." }
    }
}

extension AssistantCalendar { var selfID: String { "\(provider.rawValue):\(id)" } }
