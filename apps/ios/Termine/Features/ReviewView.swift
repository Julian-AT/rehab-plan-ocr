import RehaCore
import SwiftUI

@MainActor @Observable final class ReviewModel {
  let core: NativeApplication
  let id: String
  var review: ReviewSnapshot?
  var error: String?
  var saving = false
  init(core: NativeApplication, id: String) {
    self.core = core
    self.id = id
  }
  func load() async {
    do {
      review = try await core.loadScan(id: id)
      error = nil
    } catch { self.error = userMessage(error) }
  }
  func save(_ appointment: Appointment) async -> Bool {
    guard let review, !saving else { return false }
    saving = true
    defer { saving = false }
    var values = review.appointments
    if let index = values.firstIndex(where: { $0.id == appointment.id }) {
      values[index] = appointment
    } else {
      values.append(appointment)
    }
    do {
      self.review = try await core.saveReview(
        id: id, revision: review.revision, appointments: values,
        complete: review.completePageConfirmed, selection: [])
      error = nil
      return true
    } catch {
      self.error = userMessage(error)
      return false
    }
  }
}
struct AppointmentEditor: View {
  let core: NativeApplication
  @Bindable var review: ReviewModel
  let original: Appointment
  let changed: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var draft: Appointment
  @State private var discard = false
  @State private var source = false
  init(
    core: NativeApplication, review: ReviewModel, original: Appointment,
    changed: @escaping () -> Void
  ) {
    self.core = core
    self.review = review
    self.original = original
    self.changed = changed
    _draft = State(initialValue: original)
  }
  private var dirty: Bool { draft != original }
  private func optional(_ key: WritableKeyPath<Appointment, String?>) -> Binding<String> {
    Binding(
      get: { draft[keyPath: key] ?? "" }, set: { draft[keyPath: key] = $0.isEmpty ? nil : $0 })
  }
  var body: some View {
    NavigationStack {
      List {
        Section {
          TextField("Bezeichnung", text: $draft.title)
          TextField("Datum (JJJJ-MM-TT)", text: optional(\.date)).keyboardType(
            .numbersAndPunctuation)
          TextField("Beginn (HH:MM)", text: optional(\.start)).keyboardType(.numbersAndPunctuation)
          TextField("Ende (HH:MM)", text: optional(\.end)).keyboardType(.numbersAndPunctuation)
          TextField("Enddatum bei Tageswechsel", text: optional(\.endDate)).keyboardType(
            .numbersAndPunctuation)
          TextField(
            "Dauer in Minuten",
            text: Binding(
              get: { draft.durationMinutes.map(String.init) ?? "" },
              set: { draft.durationMinutes = UInt32($0) })
          ).keyboardType(.numberPad)
          TextField("Raum", text: $draft.location)
          TextField("Therapeut:in", text: $draft.therapist)
          TextField("Notizen", text: $draft.notes, axis: .vertical)
          Toggle("In diesen Plan aufnehmen", isOn: $draft.included)
        }
        DisclosureGroup("Weitere Angaben") {
          TextField("Einrichtung", text: $draft.metadata.clinic)
          TextField("Abteilung", text: $draft.metadata.department)
          TextField("Adresse", text: $draft.metadata.address)
          TextField("Kontakt", text: $draft.metadata.contact)
          TextField("Behandlungscode", text: $draft.metadata.treatmentCode)
          TextField("Vorbereitung", text: $draft.metadata.preparation, axis: .vertical)
          TextField("Dokumentverweis", text: $draft.metadata.documentReference)
          TextField("Terminnotizen", text: $draft.metadata.appointmentNotes, axis: .vertical)
        }
        if !draft.suggestions.filter({ $0.status == "pending" }).isEmpty {
          Section("Ergänzungsvorschläge") {
            ForEach(draft.suggestions.filter { $0.status == "pending" }, id: \.id) { suggestion in
              VStack(alignment: .leading) {
                Text("\(suggestion.field): \(fieldDescription(suggestion.value))")
                Text(suggestion.source).font(.subheadline).foregroundStyle(.secondary)
                HStack {
                  Button("Übernehmen") { suggestionAction(suggestion, true) }
                  Button("Verwerfen") { suggestionAction(suggestion, false) }
                }.buttonStyle(.bordered)
              }
            }
          }
        }
        DisclosureGroup("Hinweise und Quelle") {
          Button("Quelle und Feldmarkierungen", systemImage: "viewfinder") { source = true }
          ForEach(
            (try? appointmentIssues(
              appointment: draft, timezone: review.review?.timezone ?? "Europe/Vienna")) ?? [],
            id: \.self
          ) { issue in
            Label(issue.message, systemImage: "exclamationmark.circle").font(.callout)
          }
        }
        if let error = review.error { Text(error).foregroundStyle(AppPalette.destructive) }
      }
      .pageTitle("Termin bearbeiten")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Abbrechen") { if dirty { discard = true } else { dismiss() } }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Speichern") { Task { await save() } }.disabled(review.saving)
        }
      }
      .interactiveDismissDisabled(dirty || review.saving)
      .confirmationDialog("Änderungen verwerfen?", isPresented: $discard, titleVisibility: .visible)
      {
        Button("Änderungen verwerfen", role: .destructive) { dismiss() }.foregroundStyle(
          AppPalette.destructive)
        Button("Weiter bearbeiten") { discard = false }
      }
      .sheet(isPresented: $source) {
        SourceView(
          core: core, id: review.id,
          polygons: draft.fields.values.map(\.polygon).filter { !$0.isEmpty })
      }
    }
  }
  private func suggestionAction(_ suggestion: CompletionSuggestion, _ accept: Bool) {
    do {
      draft = try acceptSuggestion(appointment: draft, suggestionId: suggestion.id, accept: accept)
    } catch { review.error = userMessage(error) }
  }
  private func save() async {
    if await review.save(draft) {
      changed()
      dismiss()
    }
  }
}
func fieldDescription(_ value: FieldValue) -> String {
  switch value {
  case .empty: "—"
  case .text(let value): value
  case .integer(let value): value.formatted()
  case .unsigned(let value): value.formatted()
  case .number(let value): value.formatted()
  case .boolean(let value): value ? "Ja" : "Nein"
  }
}

private func appointmentStatus(_ appointment: Appointment) -> String {
  guard appointment.included else { return "Ausgeschlossen" }
  guard let approval = appointment.approval else { return "Ungeprüfter Entwurf" }
  if appointment.calendarSavedHash == approval.valuesHash { return "Im Kalender gespeichert" }
  if appointment.icsExportedHash == approval.valuesHash { return "Als Kalenderdatei exportiert" }
  return "Bestätigt · noch nicht gespeichert"
}
