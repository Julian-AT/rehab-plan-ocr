import SwiftUI
import RehaCore

struct EventProposalView: Codable, Identifiable, Sendable {
    let token: String; let session: String; let revision: UInt64; let kind: String; let calendar_id: String; let calendar_title: String
    let before: CalendarEvent?; let patch: [String: JSONValue]; let undo_of: String?
    var id: String { token }
    var button: String { kind == "create" ? "Termin speichern" : kind == "remove" ? "Diesen Kalendereintrag löschen" : "Änderung speichern" }
    var after: CalendarEventValues? {
        guard kind != "remove" else { return nil }
        var values = before?.values ?? CalendarEventValues(title: "", start_utc: "", end_utc: "", timezone: "Europe/Vienna", location: "", reminder_minutes: nil)
        for (key, value) in patch {
            switch (key, value) {
            case ("title", .string(let v)): values.title = v
            case ("start_utc", .string(let v)): values.start_utc = v
            case ("end_utc", .string(let v)): values.end_utc = v
            case ("timezone", .string(let v)): values.timezone = v
            case ("location", .string(let v)): values.location = v
            case ("reminder_minutes", .number(let v)): values.reminder_minutes = Int(v)
            case ("reminder_minutes", .null): values.reminder_minutes = nil
            default: break
            }
        }
        return values
    }
    var spoken: String {
        let action = kind == "remove" ? "Diesen Kalendereintrag löschen: \(before?.values.spoken ?? "")" : kind == "update" ? "Bisher: \(before?.values.spoken ?? "") Neu: \(after?.spoken ?? "")" : "Neuer Termin: \(after?.spoken ?? "")"
        return "\(action) Kalender \(calendar_title). \(before?.recurring == true ? "Nur dieses Serienvorkommen." : "") Zum Bestätigen bitte die große Schaltfläche antippen."
    }
}
struct EventResponse: Decodable { var proposal: EventProposalView?; var system_editor: CalendarEvent?; var status: String?; var message: String? }
struct EventHistoryItem: Decodable, Identifiable { let id: String; let created_at: Double; let proposal: EventProposalView; let status: String; let undone_by: String? }
@MainActor func jsonObject<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
extension NativeApplication {
    @MainActor func eventRequest<T: Decodable>(_ command: String, _ args: [String: Any] = [:], as type: T.Type = T.self) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: args)
        let result = try await calendarRequest(command: command, arguments: String(decoding: data, as: UTF8.self))
        return try JSONDecoder().decode(type, from: Data(result.utf8))
    }
}
@MainActor @Observable final class EventSession {
    let core: NativeApplication
    private(set) var session = UUID().uuidString
    private(set) var revision: UInt64 = 0
    var proposal: EventProposalView?
    var systemEvent: CalendarEvent?
    var busy = false
    var error: String?
    var result: String?
    init(core: NativeApplication) { self.core = core }
    func preview(kind: String, calendar: String, event: CalendarEvent?, patch: [String: JSONValue]) async {
        guard !busy else { return }; busy = true
        revision += 1; let revision = revision; let session = session; proposal = nil; result = nil
        defer { if self.session == session { busy = false } }
        do {
            let response: EventResponse = try await core.eventRequest("previewEventMutation", ["kind": kind, "calendar_id": calendar, "event": try event.map(jsonObject) ?? NSNull(), "patch": try jsonObject(patch), "session": session, "revision": revision])
            guard self.session == session, self.revision == revision else { return }
            proposal = response.proposal; systemEvent = response.system_editor; error = nil
        } catch { if self.session == session { self.error = userMessage(error) } }
    }
    func confirm() async {
        guard let proposal, !busy else { return }; busy = true; self.proposal = nil
        let current = session
        defer { if session == current { busy = false } }
        do {
            let response: EventResponse = try await core.eventRequest("confirmProposal", ["token": proposal.token, "session": session, "revision": revision, "confirmation": "button"])
            guard session == current else { return }
            result = response.status == "saved" ? "\(proposal.kind == "remove" ? "Kalendereintrag gelöscht" : "Gespeichert") in \(proposal.calendar_title)." : response.message ?? "Schreibstatus unklar. Kalender abgleichen."
            error = nil
        } catch { if session == current { self.error = userMessage(error) } }
    }
    func undo(_ id: String) async {
        guard !busy else { return }; busy = true; revision += 1
        let current = session
        defer { if session == current { busy = false } }
        do {
            let response: EventResponse = try await core.eventRequest("previewEventUndo", ["id": id, "session": session, "revision": revision])
            guard session == current else { return }
            proposal = response.proposal; error = nil
        } catch { if session == current { self.error = userMessage(error) } }
    }
    func interrupt() {
        let old = session; session = UUID().uuidString; revision += 1; proposal = nil; systemEvent = nil
        busy = false; error = nil; result = nil
        Task { let _: [String: JSONValue]? = try? await core.eventRequest("invalidateEventSession", ["session": old]) }
    }
    func openSystem(_ event: CalendarEvent) async {
        interrupt()
        let current = session
        do {
            _ = try await NativeBridge.request("editSystemEvent", ["event": try jsonObject(event)])
            guard session == current else { return }
            result = "Kalenderbearbeitung beendet. Termine neu laden. Diese Änderung steht nicht im App-Rückgängig zur Verfügung."
        } catch { if session == current { self.error = "\(userMessage(error)) Suche nach \(event.values.title), \(eventDate(event.values.start))." } }
    }
}
struct ProposalCard: View {
    let proposal: EventProposalView
    let busy: Bool
    let confirm: () -> Void
    let cancel: () -> Void
    var body: some View {
        Section("Bitte prüfen") {
            Text(proposal.calendar_title).font(.headline)
            if let before = proposal.before {
                Text(proposal.kind == "remove" ? before.values.spoken : "Bisher: \(before.values.spoken)")
                if proposal.patch["reminder_minutes"] != nil { Text("Bisherige Erinnerung: \(before.values.reminder_minutes.map { "\($0) Minuten vorher" } ?? "Aus")") }
                if before.recurring { Text("Nur dieses einzelne Serienvorkommen.").font(.headline) }
            }
            if let after = proposal.after {
                Text("\(proposal.kind == "update" ? "Neu: " : "")\(after.spoken)")
                if proposal.patch["reminder_minutes"] != nil { Text("Erinnerung: \(after.reminder_minutes.map { "\($0) Minuten vorher" } ?? "Aus")") }
            }
            if proposal.kind == "remove" { Text("Das löscht den Kalendereintrag. Es ist keine Absage bei der Klinik.").foregroundStyle(.secondary) }
            if proposal.undo_of != nil && proposal.kind == "create" { Text("Wiederherstellung als neuer Eintrag. Versendete Einladungen oder Benachrichtigungen werden nicht zurückgenommen.") }
            Button(action: confirm) { Text(proposal.button).frame(maxWidth: .infinity).controlHeight().fixedSize(horizontal: false, vertical: true) }.buttonStyle(PrimaryActionStyle()).disabled(busy).accessibilityIdentifier("confirm-event")
            Button("Angaben korrigieren", action: cancel).controlHeight().disabled(busy)
        }
    }
}
struct EventEditorView: View {
    let core: NativeApplication
    let original: CalendarEvent?
    let changed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: EventSession
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var place: String
    @State private var reminder: Int?
    @State private var calendar = ""
    @State private var calendarName = ""
    @State private var setup = false
    @State private var history = false
    init(core: NativeApplication, original: CalendarEvent? = nil, changed: @escaping () -> Void) {
        self.core = core; self.original = original; self.changed = changed
        _model = State(initialValue: EventSession(core: core))
        _title = State(initialValue: original?.values.title ?? "")
        _start = State(initialValue: original?.values.start ?? Date())
        _end = State(initialValue: original?.values.end ?? Date())
        _place = State(initialValue: original?.values.location ?? "")
        _reminder = State(initialValue: original?.values.reminder_minutes)
    }
    var body: some View {
        NavigationStack {
            List {
                if let proposal = model.proposal { ProposalCard(proposal: proposal, busy: model.busy, confirm: { Task { await model.confirm(); changed() } }, cancel: { model.interrupt() }) }
                else if let result = model.result {
                    Text(result)
                    Button("Verlauf und Rückgängig") { history = true }.controlHeight()
                } else {
                    if original?.system_only == true {
                        Text(original?.spoken ?? "")
                        Button("Im Systemkalender bearbeiten") { Task { if let original { await model.openSystem(original); changed() } } }.controlHeight()
                    } else {
                        Section("Termin") {
                            TextField("Bezeichnung", text: $title)
                            DatePicker("Beginn", selection: $start)
                            DatePicker("Ende", selection: $end)
                            TextField("Ort", text: $place)
                            Picker("Erinnerung", selection: $reminder) {
                                Text("Aus").tag(nil as Int?)
                                ForEach(Array(Set([5,10,15,30,60] + (original?.values.reminder_minutes.map { [$0] } ?? []))).sorted(), id: \.self) { Text("\($0) Minuten vorher").tag($0 as Int?) }
                            }
                        }.disabled(original?.writable == false)
                        Section("Speichern in") {
                            Text(calendarName)
                            if original == nil { Button("Ändern") { setup = true }.controlHeight() }
                            if original?.recurring == true { Text("Änderungen gelten nur für dieses Vorkommen.") }
                        }
                        Button("Änderung prüfen") { Task { await preview(delete: false) } }.controlHeight().disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || end <= start || calendar.isEmpty || original?.writable == false || model.busy)
                        if original != nil {
                            Button("Kalendereintrag löschen", role: .destructive) { Task { await preview(delete: true) } }.controlHeight().disabled(original?.writable == false || model.busy)
                            if original?.recurring == true { Button("Ganze Serie im Systemkalender bearbeiten") { Task { if let original { await model.openSystem(original); changed() } } }.controlHeight() }
                        }
                    }
                }
                if model.busy { ProcessingRow(text: "Kalender prüfen …") }
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }.pageTitle(original == nil ? "Neuer Termin" : "Termin bearbeiten")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() }.disabled(model.busy) } }
                .task { await loadCalendar() }
                .onChange(of: scenePhase) { _, phase in if phase != .active { model.interrupt() } }
                .onDisappear { model.interrupt() }
                .sheet(isPresented: $setup, onDismiss: { Task { await loadCalendar() } }) { CalendarSetupView(core: core) }
                .sheet(isPresented: $history) { NavigationStack { EventHistoryView(core: core) } }
        }
    }
    private func loadCalendar() async {
        do {
            if let original { calendar = original.calendar_id } else { calendar = try await core.preferences().calendarId }
            let calendars = try JSONDecoder().decode(CalendarDestinations.self, from: await NativeBridge.request("eventCalendars"))
            calendarName = calendars.calendars.first { $0.id == calendar }.map { "\($0.title) · \($0.source)" } ?? "Kalender auswählen"
        } catch { model.error = userMessage(error) }
    }
    private func preview(delete: Bool) async {
        var patch: [String: JSONValue] = [:]
        if !delete {
            let old = original?.values; let iso = ISO8601DateFormatter()
            if old?.title != title { patch["title"] = .string(title) }
            if old?.start != start { patch["start_utc"] = .string(iso.string(from: start)) }
            if old?.end != end { patch["end_utc"] = .string(iso.string(from: end)) }
            if old?.location != place { patch["location"] = .string(place) }
            if original == nil { patch["timezone"] = .string(TimeZone.current.identifier) }
            if old?.reminder_minutes != reminder { patch["reminder_minutes"] = reminder.map { .number(Double($0)) } ?? .null }
        }
        await model.preview(kind: delete ? "remove" : original == nil ? "create" : "update", calendar: calendar, event: original, patch: patch)
    }
}
struct EventHistoryView: View {
    let core: NativeApplication
    @Environment(\.scenePhase) private var scenePhase
    @State private var history: [EventHistoryItem] = []
    @State private var model: EventSession
    init(core: NativeApplication) { self.core = core; _model = State(initialValue: EventSession(core: core)) }
    var body: some View {
        List {
            if let proposal = model.proposal { ProposalCard(proposal: proposal, busy: model.busy, confirm: { Task { await model.confirm(); await load() } }, cancel: { model.interrupt() }) }
            if let result = model.result { Text(result) }
            if let error = model.error { Text(error).foregroundStyle(.red) }
            Button("Schreibstatus abgleichen") { Task { do { let _: [String: JSONValue] = try await core.eventRequest("reconcileEventMutations"); await load() } catch { model.error = userMessage(error) } } }.controlHeight()
            ForEach(history) { item in
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    Text(item.proposal.after?.title ?? item.proposal.before?.values.title ?? "Termin").font(.headline)
                    Text(item.proposal.calendar_title)
                    Text(eventDate(Date(timeIntervalSince1970: item.created_at)))
                    Text(item.status == "saved" ? "\(item.proposal.kind == "remove" ? "Gelöscht" : "Gespeichert")\(item.undone_by == nil ? "" : " · Rückgängig angefordert")" : item.status == "failed" ? "Nicht ausgeführt" : item.status == "acknowledged" ? "Nach manueller Kalenderprüfung abgeschlossen" : "Nicht sicher gespeichert – bitte abgleichen")
                    if ["pending", "uncertain"].contains(item.status) {
                        DisclosureGroup("Manuell im Kalender prüfen") {
                            Text("Prüfe den Termin im Systemkalender und bereinige ihn dort bei Bedarf. Hier wird anschließend nur der Verlauf abgeschlossen. Kein erneuter Schreibversuch und kein App-Rückgängig.")
                            Button("Im Kalender geprüft – Verlauf abschließen") { Task {
                                do { let _: EventResponse = try await core.eventRequest("resolveEventUncertainty", ["id": item.id, "confirmation": "button"]); await load() }
                                catch { model.error = userMessage(error) }
                            } }.controlHeight()
                        }
                    }
                    if item.status == "saved" && item.undone_by == nil { Button("Rückgängig") { Task { await model.undo(item.id) } }.controlHeight().disabled(model.busy) }
                }
            }
        }.pageTitle("Kalenderänderungen").task { await load() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { model.interrupt() } }
            .onDisappear { model.interrupt() }
    }
    private func load() async {
        struct Response: Decodable { let history: [EventHistoryItem] }
        do { history = try await core.eventRequest("eventHistory", as: Response.self).history } catch { model.error = userMessage(error) }
    }
}
