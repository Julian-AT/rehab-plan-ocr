import RehaCore
import SwiftUI

extension ActivityRecord {
  fileprivate var title: String {
    switch kind {
    case "capture": "Erfassung"
    case "recognition": "Erkennung"
    case "import": "Kalenderimport"
    case "create": "Termin erstellt"
    case "update": "Terminänderung"
    case "remove": "Terminlöschung"
    case "undo": "Rücknahme"
    default: "Vorgang"
    }
  }
  fileprivate var outcome: String {
    switch status {
    case "saved", "completed": "Abgeschlossen"
    case "failed", "conflict": "Prüfung erforderlich"
    case "pending", "uncertain", "queued": "Schreibstatus ungeklärt"
    case "interrupted": "Unterbrochen"
    case "acknowledged": "Manuell geprüft"
    case "deleted": "Original gelöscht"
    default: "Erfassung gespeichert"
    }
  }
}

struct ActivityView: View {
  let core: NativeApplication
  @State private var items: [ActivityRecord] = []
  @State private var cursor: String?
  @State private var filter: ActivitySource?
  @State private var loading = false
  @State private var error: String?
  @State private var generation = UUID()
  var body: some View {
    List {
      Picker("Vorgänge", selection: $filter) {
        Text("Alle").tag(nil as ActivitySource?)
        Text("Erfassungen").tag(ActivitySource.capture)
        Text("Erkennungen").tag(ActivitySource.recognition)
        Text("Importe").tag(ActivitySource.calendarImport)
        Text("Terminänderungen").tag(ActivitySource.eventMutation)
      }.accessibilityIdentifier("activity-filter")
      ForEach(items, id: \.id) { item in
        NavigationLink {
          if item.source == .eventMutation {
            EventHistoryView(core: core, initialID: item.sourceId)
          } else if item.source == .calendarImport, let document = item.documentId {
            ImportHistoryView(core: core, documentID: document, initialBatchID: item.sourceId)
          } else {
            ActivityCaptureDetail(core: core, item: item)
          }
        } label: {
          VStack(alignment: .leading, spacing: 6) {
            Text(item.title).foregroundStyle(.primary)
            Text(
              Date(timeIntervalSince1970: Double(item.createdAt)).formatted(
                date: .abbreviated, time: .shortened)
            ).font(.subheadline)
            Text(
              item.outcome + (item.source == .calendarImport ? " · \(item.count) Änderungen" : "")
            )
            .font(.subheadline)
          }.foregroundStyle(.secondary).padding(.vertical, 4)
        }.accessibilityIdentifier("activity-record-\(item.id)")
      }
      if loading { ProcessingRow(text: "Verlauf laden …") }
      if let error {
        Text(error).foregroundStyle(AppPalette.destructive)
        Button("Erneut versuchen") { Task { await load(reset: items.isEmpty) } }
      }
      if !loading && items.isEmpty && error == nil {
        Text("Keine aufgezeichneten Vorgänge.").foregroundStyle(.secondary)
      }
      if cursor != nil {
        Button("Weitere Vorgänge laden") { Task { await load(reset: false) } }.disabled(loading)
      }
    }.pageTitle("Verlauf")
      .task(id: filter) { await load(reset: true) }
  }
  private func load(reset: Bool) async {
    if reset {
      generation = UUID()
      items = []
      cursor = nil
    } else if loading {
      return
    }
    let request = generation
    loading = true
    error = nil
    defer { if generation == request { loading = false } }
    do {
      let page = try await core.activityPage(
        cursor: reset ? nil : cursor, limit: 50, source: filter)
      guard request == generation, !Task.isCancelled else { return }
      let known = Set(items.map(\.id))
      items += page.items.filter { !known.contains($0.id) }
      cursor = page.nextCursor
    } catch { if request == generation, !Task.isCancelled { self.error = userMessage(error) } }
  }
}

private struct ActivityCaptureDetail: View {
  let core: NativeApplication
  let item: ActivityRecord
  @State private var detail: RecognitionActivityDetail?
  @State private var error: String?
  var body: some View {
    Form {
      LabeledContent("Ergebnis", value: item.outcome)
      if let message = detail?.error {
        Text(message).foregroundStyle(AppPalette.destructive)
          .accessibilityIdentifier("recognition-activity-error")
      }
      if let document = item.documentId {
        NavigationLink("Erkennungsdetails und Quellen") {
          DiagnosticsView(core: core, id: document)
        }
      }
      if let error { Text(error).foregroundStyle(AppPalette.destructive) }
    }.pageTitle(item.title)
      .task(id: item.id) {
        guard item.source == .recognition else { return }
        do {
          let result = try await core.recognitionActivityDetail(id: item.sourceId)
          guard !Task.isCancelled else { return }
          detail = result
        } catch {
          if !Task.isCancelled { self.error = userMessage(error) }
        }
      }
  }
}

struct CalendarStatusView: View {
  let core: NativeApplication
  let changed: () -> Void
  @State private var status: CalendarAdministrationStatus?
  @State private var busy = false
  @State private var error: String?
  var body: some View {
    Form {
      if let status {
        Section("Zugriff und Auswahl") {
          LabeledContent(
            "Kalenderzugriff",
            value: status.platform.access == .fullAccess
              ? "Vollzugriff" : status.platform.access == .denied ? "Verweigert" : "Nicht verfügbar"
          )
          .accessibilityElement(children: .ignore)
          .accessibilityIdentifier("calendar-access")
          .accessibilityLabel("Kalenderzugriff")
          .accessibilityValue(
            status.platform.access == .fullAccess
              ? "Vollzugriff" : status.platform.access == .denied ? "Verweigert" : "Nicht verfügbar"
          )
          NavigationLink("Kalenderauswahl bearbeiten") { CalendarPreferencesView(core: core) }
          if status.unavailableCount > 0 {
            LabeledContent(
              "Kalender mit nicht lesbaren Daten", value: String(status.unavailableCount))
          }
          NavigationLink("Kalender bereinigen") {
            CalendarRepairView(core: core) {
              Task {
                await load()
                changed()
              }
            }
          }.accessibilityIdentifier("calendar-repair")
        }
        Section {
          LabeledContent(
            "Letzter erfolgreicher Lesevorgang",
            value: status.platform.lastReadAt.flatMap { ISO8601DateFormatter().date(from: $0) }?
              .formatted(
                date: .abbreviated, time: .standard) ?? "Noch nicht beobachtet")
        } header: {
          AppSectionHeader(
            title: "Gelesener Kalenderstand",
            help:
              "Zeigt den lokal gelesenen Stand. Der iCloud-Abgleich ist hier nicht prüfbar."
          )
        }
        Section("Ungeklärte Schreibvorgänge") {
          LabeledContent("Importe", value: String(status.pendingImports))
          LabeledContent("Terminänderungen", value: String(status.pendingEvents))
          if status.pendingImports > 0 {
            NavigationLink("Importvorgänge prüfen") { RecoveryView(core: core, changed: changed) }
          }
          if status.pendingEvents > 0 {
            NavigationLink("Terminänderungen prüfen") { EventHistoryView(core: core) }
          }
        }
        if status.pendingBookkeeping > 0 {
          Section("Lokaler Planstand") {
            Text(
              "Bestätigte Kalenderänderungen bleiben erhalten. Der lokale Planstand braucht noch einen Abgleich."
            )
            .foregroundStyle(AppPalette.secondaryText)
            AppFormAction(
              title: "Lokalen Stand abgleichen", systemImage: "arrow.clockwise", busy: busy
            ) { Task { await repairLocalState() } }
            .accessibilityIdentifier("repair-calendar-bookkeeping")
          }
        }
      }
      Section {
        AppFormAction(title: "Aktualisieren", systemImage: "arrow.clockwise", busy: busy) {
          Task { await load() }
        }.accessibilityIdentifier("refresh-calendar-status")
      }
      if let error { Text(error).foregroundStyle(AppPalette.destructive) }
    }.pageTitle("Kalenderstatus").task { await load() }
  }
  private func load() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      status = try await core.calendarStatus()
      error = nil
    } catch { self.error = userMessage(error) }
  }
  private func repairLocalState() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      _ = try await core.reconcileCalendarBookkeeping()
      status = try await core.calendarStatus()
      error = nil
      changed()
    } catch { self.error = userMessage(error) }
  }
}
