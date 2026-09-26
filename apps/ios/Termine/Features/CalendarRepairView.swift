import RehaCore
import SwiftUI

struct CalendarRepairView: View {
  let core: NativeApplication
  let changed: () -> Void
  private struct Issue: Decodable, Identifiable {
    let id: String
    let fingerprint: String
    let title: String
    let start: String
    let end: String
    let reason: String
    enum CodingKeys: String, CodingKey {
      case id, fingerprint, title, reason
      case start = "start_utc"
      case end = "end_utc"
    }
    var date: Date? { ISO8601DateFormatter().date(from: start) }
    var explanation: String {
      switch reason {
      case "calendar_missing": "Der zugehörige Kalender ist nicht erreichbar."
      case "ambiguous": "Mehrere Termine passen zu dieser Zuordnung."
      default: "Der verknüpfte Termin wurde nicht eindeutig wiedergefunden."
      }
    }
    var interval: String {
      guard let date else { return "Datum unbekannt" }
      guard let end = ISO8601DateFormatter().date(from: end) else { return eventTime(date) }
      return
        "\(eventTime(date))–\(Calendar.current.isDate(date, inSameDayAs: end) ? eventTime(end) : eventDate(end))"
    }
  }
  private struct Report: Decodable {
    let issues: [Issue]
    let missingCalendarIDs: [String]
    let relinked: Int
    let removed: Int
    let blocked: Bool
    let warning: String?
    enum CodingKeys: String, CodingKey {
      case issues
      case missingCalendarIDs = "missing_calendar_ids"
      case relinked = "relinked_count"
      case removed = "removed_count"
      case blocked = "cleanup_blocked"
      case warning = "refresh_warning"
    }
  }
  @State private var report: Report?
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
        if report.relinked > 0 || report.removed > 0 {
          Section("Ergebnis") {
            if report.relinked > 0 {
              Text("Wiederhergestellte Zuordnungen: \(report.relinked)")
            }
            if report.removed > 0 { Text("Entfernte Zuordnungen: \(report.removed)") }
          }
        }
        if report.blocked {
          Section {
            Text(
              "Bitte zuerst die ungeklärten Schreibvorgänge im Kalenderstatus prüfen. Danach ist die Bereinigung möglich."
            )
          }
        }
        if !report.missingCalendarIDs.isEmpty {
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
              report.missingCalendarIDs.isEmpty
                ? "Keine offenen Terminzuordnungen gefunden."
                : "Keine einzelnen Terminzuordnungen zu bereinigen.")
          }
        } else {
          Section {
            Button(selection.count == report.issues.count ? "Auswahl aufheben" : "Alle auswählen") {
              selection = selection.count == report.issues.count ? [] : Set(report.issues.map(\.id))
            }.disabled(report.blocked || busy)
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
              ForEach((days[day] ?? []).sorted { $0.start < $1.start }) { issue in
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
                .disabled(report.blocked || busy)
                .accessibilityAddTraits(selection.contains(issue.id) ? .isSelected : [])
                .accessibilityIdentifier("repair-issue-\(issue.id)")
              }
            }
          }
          Section {
            Button("Ausgewählte Zuordnungen entfernen (\(selection.count))", role: .destructive) {
              confirming = true
            }.disabled(selection.isEmpty || report.blocked || busy)
              .accessibilityIdentifier("confirm-calendar-repair")
          }
        }
        if let warning = report.warning {
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
      var arguments: [String: Any] = [:]
      if confirm {
        arguments = [
          "confirmation": "button",
          "selection": (report?.issues ?? [])
            .filter { selection.contains($0.id) }
            .map { ["id": $0.id, "fingerprint": $0.fingerprint] },
        ]
      }
      report = try await core.eventRequest(
        confirm ? "confirmCalendarRepair" : "inspectCalendarRepair", arguments, as: Report.self)
      selection = []
      changed()
    } catch { self.error = userMessage(error) }
  }
}
