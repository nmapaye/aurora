import AuroraCore
import SwiftUI

struct CalendarReviewCard: View {
    @Bindable var service: CalendarService
    var snapshot: [Commitment]? = nil
    var editable = true
    var snapshotMessage: String? = nil
    var onOutcome: ((String, Commitment?) -> Void)? = nil
    var connect: () -> Void
    @State private var proposal: CalendarChange?
    @State private var result: String?
    @State private var applying = false
    @State private var reversal: CalendarChange?

    var body: some View {
        Card {
            Text("Your commitments").font(.headline)
            if service.selected.isEmpty && editable {
                Text("Connect and select calendars to review your day.").foregroundStyle(Palette.textSecondary)
            }
            Button("Calendar connections", action: connect).buttonStyle(.auroraSecondary)
            if service.loading { ProgressView("Refreshing calendars") }
            if let message = snapshotMessage ?? (snapshot == nil ? service.message : nil) { Text(message).font(.footnote).foregroundStyle(Palette.destructive) }
            if (snapshot ?? service.commitments).isEmpty && snapshotMessage == nil {
                Text("No commitments found in the selected calendars for the next seven days.").font(.footnote)
            }
            ForEach((snapshot ?? service.commitments).sorted { $0.start < $1.start }, id: \.identity) { event in
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title).font(.subheadline.weight(.semibold))
                    Text(span(event.start, event.end, zone: event.timeZone)).font(.caption).foregroundStyle(Palette.textSecondary)
                    Text("\(event.provider.rawValue.capitalized)\(event.recurring ? " · recurring occurrence" : "")").font(.caption2).foregroundStyle(Palette.textSecondary)
                    if editable && event.canMove && event.start > .now {
                        Button("Review a later slot") {
                            reversal = nil
                            proposal = CalendarActionValidator.proposedMove(event, among: snapshot ?? service.commitments, now: .now, calendar: .current)
                            if proposal == nil { result = "No later conflict-free slot was found on this day." }
                        }.disabled(applying || service.message != nil)
                    } else {
                        Text(editable ? "Fixed · shared, all-day, past, or read-only" : "Snapshot · start a new review to propose a change").font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }.padding(.vertical, 6)
            }
            if editable, let proposal {
                Divider()
                Text("Review change: \(proposal.original.title)").font(.headline)
                Text("Before: \(span(proposal.original.start, proposal.original.end, zone: proposal.original.timeZone))")
                Text("After: \(span(proposal.newStart, proposal.newEnd, zone: proposal.original.timeZone))")
                Text("\(proposal.original.recurring ? "Only this occurrence." : "One event.") No invitations or cancellations.").font(.caption).foregroundStyle(Palette.textSecondary)
                Button(applying ? "Checking and applying…" : "Approve this change") {
                    Task { await apply(proposal) }
                }.buttonStyle(.auroraPrimary).disabled(applying).accessibilityIdentifier("calendar-approve")
                Button("Discard proposal") { self.proposal = nil }.disabled(applying)
            }
            if let result { Text(result).font(.footnote).accessibilityIdentifier("calendar-result") }
            if editable, let reversal, proposal == nil {
                Button("Review reversal") { proposal = reversal; self.reversal = nil }
                    .disabled(applying || reversal.newStart <= .now)
            }
        }
    }
    private func span(_ start: Date, _ end: Date, zone: String) -> String {
        let format = DateFormatter(); format.timeZone = TimeZone(identifier: zone); format.dateStyle = .medium; format.timeStyle = .short
        return "\(format.string(from: start)) – \(format.string(from: end)) · \(zone)"
    }
    private func apply(_ change: CalendarChange) async {
        guard !applying else { return }
        applying = true; defer { applying = false; proposal = nil }
        do {
            let updated = try await service.approve(change)
            result = "Updated ‘\(updated.title)’. This event only."
            reversal = .init(original: updated, newStart: change.original.start, newEnd: change.original.end)
            onOutcome?(result ?? "Updated event.", updated)
        } catch CalendarActionError.stale {
            result = "This event changed after the preview. Nothing was applied. Refresh and review a new proposal."
            onOutcome?(result!, nil)
        } catch CalendarActionError.conflict {
            result = "A commitment now overlaps that slot. Nothing was applied. Review a fresh proposal."
            onOutcome?(result!, nil)
        } catch {
            result = "Couldn't confirm this change. Refresh the calendar before retrying; Aurora won't repeat the write automatically."
            onOutcome?(result!, nil)
        }
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
                    Text("Selected calendars are read locally. Google calendars synced to Apple can also be selected here.").font(.footnote)
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
