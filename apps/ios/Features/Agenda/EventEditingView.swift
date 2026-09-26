import AppleServices
import RehaCore
import SwiftUI

extension NativeApplication {
  @MainActor func eventRequest<T: Decodable>(
    _ command: String, _ args: [String: Any] = [:], as type: T.Type = T.self
  ) async throws -> T {
    let data = try JSONSerialization.data(withJSONObject: args)
    let result = try await calendarRequest(
      command: command, arguments: String(decoding: data, as: UTF8.self))
    return try JSONDecoder().decode(type, from: Data(result.utf8))
  }
}
extension EventSession {
  convenience init(core: NativeApplication, origin: String = "manual") {
    self.init(
      origin: origin,
      client: EventMutationClient(
        register: { try core.registerEventSession() },
        invalidate: { _ = try? core.invalidateEventSession(session: $0) },
        preview: { try await core.previewEventMutation(request: $0) },
        confirm: { try await core.confirmEventProposal(request: $0) },
        undo: { try await core.previewEventUndo(request: $0) }),
      openSystem: { event in
        _ = try await NativeBridge.editSystemEvent(event)
      },
      confirmationStarted: { token in
        LocalDiagnostics.shared.record(.confirmation, .started, correlation: token)
      },
      describe: userMessage)
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
        if proposal.patch["reminder_minutes"] != nil {
          Text(
            "Bisherige Erinnerung: \(before.values.reminder_minutes.map { "\($0) Minuten vorher" } ?? "Aus")"
          )
        }
        if before.recurring { Text("Nur dieses einzelne Serienvorkommen.").font(.headline) }
      }
      if let after = proposal.after {
        Text("\(proposal.kind == "update" ? "Neu: " : "")\(after.spoken)")
        if proposal.patch["reminder_minutes"] != nil {
          Text("Erinnerung: \(after.reminder_minutes.map { "\($0) Minuten vorher" } ?? "Aus")")
        }
      }
      if proposal.kind == "remove" {
        Text("Das löscht den Kalendereintrag. Es ist keine Absage bei der Klinik.").foregroundStyle(
          .secondary)
      }
      if proposal.undo_of != nil && proposal.kind == "create" {
        Text(
          "Wiederherstellung als neuer Eintrag. Versendete Einladungen oder Benachrichtigungen werden nicht zurückgenommen."
        )
      }
      Button(role: proposal.kind == "remove" ? .destructive : nil, action: confirm) {
        Text(proposal.button).frame(maxWidth: .infinity).fixedSize(
          horizontal: false, vertical: true)
      }.buttonStyle(AppPrimaryButtonStyle()).disabled(busy).accessibilityIdentifier("confirm-event")
      Button("Angaben korrigieren", action: cancel).disabled(busy)
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
    self.core = core
    self.original = original
    self.changed = changed
    _model = State(initialValue: EventSession(core: core))
    _title = State(initialValue: original?.values.title ?? "")
    _start = State(initialValue: original?.values.start ?? Date())
    _end = State(initialValue: original?.values.end ?? Date())
    _place = State(initialValue: original?.values.location ?? "")
    _reminder = State(initialValue: original?.values.reminder_minutes)
  }
  var body: some View {
    NavigationStack {
      Form {
        if let proposal = model.proposal {
          ProposalCard(
            proposal: proposal, busy: model.busy,
            confirm: {
              Task {
                await model.confirm()
                changed()
              }
            }, cancel: { model.interrupt() })
        } else if let result = model.result {
          Text(result)
          AppFormAction(title: "Verlauf und Rückgängig") { history = true }
        } else {
          if original?.system_only == true {
            Text(original?.spoken ?? "")
            AppFormAction(title: "Im Systemkalender bearbeiten") {
              Task {
                if let original {
                  await model.openSystem(original)
                  changed()
                }
              }
            }
          } else {
            Section("Termin") {
              TextField("Bezeichnung", text: $title)
              DatePicker("Beginn", selection: $start)
              DatePicker("Ende", selection: $end)
              TextField("Ort", text: $place)
              Picker("Erinnerung", selection: $reminder) {
                Text("Aus").tag(nil as Int?)
                ForEach(
                  Array(
                    Set(
                      [5, 10, 15, 30, 60] + (original?.values.reminder_minutes.map { [$0] } ?? []))
                  ).sorted(), id: \.self
                ) { Text("\($0) Minuten vorher").tag($0 as Int?) }
              }
            }.disabled(original?.writable == false)
            Section("Speichern in") {
              Text(calendarName)
              if original == nil { AppFormAction(title: "Ändern") { setup = true } }
              if original?.recurring == true { Text("Änderungen gelten nur für dieses Vorkommen.") }
            }
            AppFormAction(title: "Änderung prüfen") { Task { await preview(delete: false) } }
              .disabled(
                title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || end <= start
                  || calendar.isEmpty || original?.writable == false || model.busy)
            if original != nil {
              AppFormAction(title: "Kalendereintrag löschen", role: .destructive) {
                Task { await preview(delete: true) }
              }.foregroundStyle(AppPalette.destructive).disabled(
                original?.writable == false || model.busy)
              if original?.recurring == true {
                AppFormAction(title: "Ganze Serie im Systemkalender bearbeiten") {
                  Task {
                    if let original {
                      await model.openSystem(original)
                      changed()
                    }
                  }
                }
              }
            }
          }
        }
        if model.busy { ProcessingRow(text: "Kalender prüfen …") }
        if let error = model.error { Text(error).foregroundStyle(AppPalette.destructive) }
      }.pageTitle(original == nil ? "Neuer Termin" : "Termin bearbeiten")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Fertig") { dismiss() }.disabled(model.busy)
          }
        }
        .task { await loadCalendar() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.interrupt() } }
        .onDisappear { model.interrupt() }
        .sheet(isPresented: $setup, onDismiss: { Task { await loadCalendar() } }) {
          CalendarSetupView(core: core)
        }
        .sheet(isPresented: $history) { NavigationStack { EventHistoryView(core: core) } }
    }
  }
  private func loadCalendar() async {
    do {
      if let original {
        calendar = original.calendar_id
      } else {
        calendar = try await core.preferences().calendarId
      }
      let calendars = try await core.eventCalendars()
      calendarName =
        calendars.first { $0.id == calendar }.map { "\($0.title) · \($0.source)" }
        ?? "Kalender auswählen"
    } catch { model.error = userMessage(error) }
  }
  private func preview(delete: Bool) async {
    var patch = EventEditPatch.empty
    if !delete {
      let old = original?.values
      let iso = ISO8601DateFormatter()
      if old?.title != title { patch.title = title }
      if old?.start != start { patch.startUtc = iso.string(from: start) }
      if old?.end != end { patch.endUtc = iso.string(from: end) }
      if old?.location != place { patch.location = place }
      if original == nil { patch.timezone = TimeZone.current.identifier }
      if old?.reminder_minutes != reminder {
        patch.reminder = reminder.map { .minutes(minutes: UInt32($0)) } ?? .disabled
      }
    }
    await model.preview(
      kind: delete ? .remove : original == nil ? .create : .update, calendar: calendar,
      event: original, patch: patch)
  }
}
struct EventHistoryView: View {
  @State private var reconciling = false
  @State private var reconciled = false
  @State private var acknowledging: String?
  @State private var maintenanceWarnings: [String] = []
  let core: NativeApplication
  let initialID: String?
  @Environment(\.scenePhase) private var scenePhase
  @State private var history: [EventHistoryItem] = []
  @State private var model: EventSession
  init(core: NativeApplication, initialID: String? = nil) {
    self.core = core
    self.initialID = initialID
    _model = State(initialValue: EventSession(core: core))
  }
  var body: some View {
    List {
      if let proposal = model.proposal {
        ProposalCard(
          proposal: proposal, busy: model.busy,
          confirm: {
            Task {
              await model.confirm()
              await load()
            }
          }, cancel: { model.interrupt() })
      }
      if let result = model.result { Text(result) }
      if let error = model.error { Text(error).foregroundStyle(AppPalette.destructive) }
      AppFormAction(
        title: "Schreibstatus abgleichen", systemImage: "arrow.clockwise", busy: reconciling
      ) {
        guard !reconciling else { return }
        reconciling = true
        reconciled = false
        maintenanceWarnings = []
        model.error = nil
        Task {
          defer { reconciling = false }
          do {
            let response = try await core.reconcileEventMutations()
            maintenanceWarnings = response.maintenanceWarnings
            await load()
            reconciled = model.error == nil
          } catch { model.error = userMessage(error) }
        }
      }
      if reconciled {
        Text("Schreibstatus aktualisiert.").font(.caption).foregroundStyle(AppPalette.secondaryText)
          .accessibilityIdentifier("reconcile-complete")
      }
      if !maintenanceWarnings.isEmpty {
        Text(maintenanceWarnings.joined(separator: "\n\n"))
          .foregroundStyle(AppPalette.secondaryText)
          .accessibilityIdentifier("reconcile-maintenance-warning")
      }
      ForEach(history) { item in
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
          Text(item.proposal.after?.title ?? item.proposal.before?.values.title ?? "Termin").font(
            .headline)
          Text(item.proposal.calendar_title)
          Text(eventDate(Date(timeIntervalSince1970: item.createdAt)))
          Text(
            item.status == .saved
              ? "\(item.proposal.kind == "remove" ? "Gelöscht" : "Gespeichert")\(item.undoneBy == nil ? "" : " · Rückgängig angefordert")"
              : item.status == .failed
                ? "Nicht ausgeführt"
                : item.status == .acknowledged
                  ? "Nach manueller Kalenderprüfung abgeschlossen"
                  : "Nicht sicher gespeichert – bitte abgleichen")
          if [.pending, .uncertain].contains(item.status) {
            DisclosureGroup("Manuell im Kalender prüfen") {
              Text(
                "Bitte den Termin im Systemkalender prüfen und dort bei Bedarf bereinigen. Hier wird anschließend nur der Verlauf abgeschlossen. Kein erneuter Schreibversuch und kein App-Rückgängig."
              )
              Button("Im Kalender geprüft – Verlauf abschließen") {
                guard acknowledging == nil else { return }
                acknowledging = item.id
                model.error = nil
                Task {
                  defer { acknowledging = nil }
                  do {
                    let response = try await core.resolveEventUncertainty(
                      request: ResolveEventUncertaintyRequest(id: item.id, confirmation: .button))
                    model.result = response.message
                    await load()
                  } catch { model.error = userMessage(error) }
                }
              }.disabled(acknowledging != nil || model.busy || reconciling)
            }
          }
          if item.status == .saved && item.undoneBy == nil {
            AppFormAction(title: "Rückgängig") { Task { await model.undo(item.id) } }.disabled(
              model.busy)
          }
        }
      }
    }.pageTitle("Kalenderänderungen").task { await load() }
      .onChange(of: scenePhase) { _, phase in if phase != .active { model.interrupt() } }
      .onDisappear { model.interrupt() }
  }
  private func load() async {
    do {
      if let initialID {
        guard let record = try await core.eventHistoryDetail(id: initialID) else {
          throw AppError.Validation(message: "Verlaufseintrag fehlt.")
        }
        history = [try EventHistoryItem(record)]
      } else {
        history = try await core.eventHistory().map(EventHistoryItem.init)
      }
    } catch { model.error = userMessage(error) }
  }
}
