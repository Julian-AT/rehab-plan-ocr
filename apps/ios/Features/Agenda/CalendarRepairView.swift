import RehaCore
import SwiftUI

struct CalendarRepairView: View {
  let core: NativeApplication
  let changed: () -> Void
  @State private var report: CalendarRepairReport?
  @State private var selection = Set<String>()
  @State private var busy = false
  @State private var confirming = false
  @State private var error: String?
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Form {
      Section {
        Text(
          "Die App sucht die verknüpften Termine erneut und stellt eindeutige Zuordnungen wieder her."
        )
        Text(
          "Nicht wiedergefundene Einträge kannst du unten auswählen. Entfernt wird nur ihre Zuordnung in der App. Kalendertermine und Originale im Archiv bleiben erhalten."
        )
        .foregroundStyle(AppPalette.secondaryText)
      }
      if busy { ProcessingRow(text: "Kalender prüfen …") }
      if let report {
        if report.relinkedCount > 0 || report.removedCount > 0 {
          Section("Ergebnis") {
            if report.relinkedCount > 0 {
              Text("Wiederhergestellte Zuordnungen: \(report.relinkedCount)")
            }
            if report.removedCount > 0 { Text("Entfernte Zuordnungen: \(report.removedCount)") }
          }
        }
        if report.cleanupBlocked {
          Section {
            Text(
              "Bitte zuerst die ungeklärten Schreibvorgänge im Kalenderstatus prüfen. Danach ist die Bereinigung möglich."
            )
          }
        }
        if !report.missingCalendarIds.isEmpty {
          Section("Nicht erreichbare Kalender") {
            Text(
              "Mindestens ein ausgewählter Kalender ist nicht erreichbar. Betroffene Tage lassen sich deshalb nicht vollständig bestimmen."
            )
            NavigationLink("Kalenderauswahl bearbeiten") { CalendarPreferencesView(core: core) }
          }
        }
        if report.issues.isEmpty {
          Section {
            Text(
              report.missingCalendarIds.isEmpty
                ? "Keine offenen Terminzuordnungen gefunden."
                : "Keine einzelnen Terminzuordnungen zu bereinigen.")
          }
        } else {
          Section {
            Button(selection.count == report.issues.count ? "Auswahl aufheben" : "Alle auswählen") {
              selection = selection.count == report.issues.count ? [] : Set(report.issues.map(\.id))
            }.disabled(report.cleanupBlocked || busy)
          } footer: {
            Text(
              "Die folgenden Angaben zeigen den zuletzt bekannten Stand. Eine fehlende Zuordnung bedeutet nicht, dass der Termin abgesagt wurde."
            )
          }
          let days = Dictionary(grouping: report.issues) { issue in
            issue.date.map { Calendar.current.startOfDay(for: $0) } ?? .distantPast
          }
          ForEach(days.keys.sorted(), id: \.self) { day in
            Section(day == .distantPast ? "Datum unbekannt" : eventDay(day)) {
              ForEach((days[day] ?? []).sorted { $0.startUtc < $1.startUtc }, id: \.id) { issue in
                Button {
                  if selection.contains(issue.id) {
                    selection.remove(issue.id)
                  } else {
                    selection.insert(issue.id)
                  }
                } label: {
                  HStack(alignment: .top, spacing: 12) {
                    Image(
                      systemName: selection.contains(issue.id) ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundStyle(AppPalette.tint).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                      Text(issue.title).font(.body)
                      Text(issue.interval).font(.subheadline)
                      Text(issue.explanation).font(.footnote).foregroundStyle(
                        AppPalette.secondaryText)
                    }.fixedSize(horizontal: false, vertical: true)
                  }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(
                    .rect)
                }
                .buttonStyle(.plain)
                .disabled(report.cleanupBlocked || busy)
                .accessibilityAddTraits(selection.contains(issue.id) ? .isSelected : [])
                .accessibilityIdentifier("repair-issue-\(issue.id)")
              }
            }
          }
          Section {
            Button("Ausgewählte Zuordnungen entfernen (\(selection.count))", role: .destructive) {
              confirming = true
            }.disabled(selection.isEmpty || report.cleanupBlocked || busy)
              .accessibilityIdentifier("confirm-calendar-repair")
          }
        }
        if let warning = report.refreshWarning {
          Section {
            Text(
              "Zuordnungen geprüft. Der Kalender konnte anschließend nicht vollständig aktualisiert werden: \(warning)"
            )
          }
        }
      }
      if let error { Section { Text(error).foregroundStyle(AppPalette.destructive) } }
      Section {
        AppFormAction(title: "Erneut prüfen", systemImage: "arrow.clockwise", busy: busy) {
          Task { await inspect() }
        }
      }
    }
    .pageTitle("Kalender bereinigen")
    .confirmationDialog(
      "Ausgewählte Zuordnungen entfernen?", isPresented: $confirming, titleVisibility: .visible
    ) {
      Button("\(selection.count) Zuordnungen entfernen", role: .destructive) {
        Task { await inspect(confirm: true) }
      }
      Button("Abbrechen", role: .cancel) {}
    } message: {
      Text(
        "Die Auswahl wird erneut geprüft. Wieder erreichbare Termine behalten ihre Zuordnung. Es werden keine Termine aus dem Kalender gelöscht."
      )
    }
    .task { await inspect() }
    .onChange(of: scenePhase) { _, phase in if phase != .active { confirming = false } }
  }

  private func inspect(confirm: Bool = false) async {
    guard !busy else { return }
    busy = true
    error = nil
    defer { busy = false }
    do {
      if confirm {
        report = try await core.confirmCalendarRepair(
          selection: (report?.issues ?? [])
            .filter { selection.contains($0.id) }
            .map { CalendarRepairSelection(id: $0.id, fingerprint: $0.fingerprint) },
          confirmation: .button)
      } else {
        report = try await core.inspectCalendarRepair()
      }
      selection = []
      changed()
    } catch { self.error = userMessage(error) }
  }
}

extension CalendarRepairIssue {
  fileprivate var date: Date? { ISO8601DateFormatter().date(from: startUtc) }
  fileprivate var explanation: String {
    switch reason {
    case "calendar_missing": "Der zugehörige Kalender ist nicht erreichbar."
    case "ambiguous": "Mehrere Termine passen zu dieser Zuordnung."
    default: "Der verknüpfte Termin wurde nicht eindeutig wiedergefunden."
    }
  }
  fileprivate var interval: String {
    guard let date else { return "Datum unbekannt" }
    guard let end = ISO8601DateFormatter().date(from: endUtc) else { return eventTime(date) }
    return
      "\(eventTime(date))–\(Calendar.current.isDate(date, inSameDayAs: end) ? eventTime(end) : eventDate(end))"
  }
}
