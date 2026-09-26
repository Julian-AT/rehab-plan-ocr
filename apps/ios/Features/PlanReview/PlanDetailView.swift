import EventKit
import RehaCore
import SwiftUI

extension PlanModel {
  convenience init(core: NativeApplication, id: String) {
    self.init(
      core: core, id: id,
      calendarAccess: { EKEventStore.authorizationStatus(for: .event) == .fullAccess },
      calendars: {
        try await CalendarDestinations(
          calendars: core.eventCalendars().filter(\.writable).map {
            CalendarDestinations.Destination(
              id: $0.id, title: $0.title, source: $0.source, writable: $0.writable,
              color_components: $0.colorComponents)
          })
      })
  }
}

private struct PlanEditorItem: Identifiable {
  let id: String
  let appointment: Appointment
  let model: ReviewModel
}
private struct QuestionItem: Identifiable {
  let id: String
  let question: ReadinessQuestion
}
struct ReviewView: View {
  let core: NativeApplication
  let scanner: ScanModel
  let id: String
  let changed: () -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var model: PlanModel
  @State private var editor: PlanEditorItem?
  @State private var question: QuestionItem?
  @State private var originals = false
  @State private var tools = false
  @State private var setup = false
  @State private var history = false
  @State private var delete = false
  @State private var deleting = false
  @State private var deletionError: String?
  @State private var diagnostics = false
  @State private var correction = false
  @State private var export = false
  init(core: NativeApplication, scanner: ScanModel, id: String, changed: @escaping () -> Void) {
    self.core = core
    self.scanner = scanner
    self.id = id
    self.changed = changed
    _model = State(initialValue: PlanModel(core: core, id: id))
  }
  private var processing: Bool {
    scanner.running
      && (scanner.currentID == id
        || scanner.presentedID?.replacingOccurrences(of: "plan:", with: "") == id
        || model.pages.contains { $0.id == scanner.activePageID })
  }
  var body: some View {
    List {
      if deleting { ProcessingRow(text: "Originale werden gelöscht …") }
      if let deletionError {
        Section("Originale konnten nicht gelöscht werden") {
          Text(deletionError).foregroundStyle(AppPalette.destructive)
          Button("Erneut versuchen") { delete = true }
        }
      }
      if processing {
        Section {
          ProcessingRow(
            text: scanner.progress?.stage
              ?? (scanner.sourceStored ? "Plan wird erkannt …" : "Aufnahme speichern …"))
          Button("Abbrechen", role: .cancel) { scanner.cancel() }
        }
      } else if let error = (scanner.currentID == id ? scanner.error : nil) ?? model.retainedError {
        Section {
          Text("Erkennung nicht abgeschlossen.")
          Button("Erneut versuchen") { scanner.retry(id) }
          DisclosureGroup("Details") { Text(error).font(.subheadline).foregroundStyle(.secondary) }
        }
      }
      if model.loading && !processing { ProcessingRow(text: "Plan und Kalender abgleichen …") }
      if let error = model.error {
        Section {
          Text("Kalenderaktion nicht abgeschlossen.")
          Button("Erneut versuchen") { Task { await model.load() } }.disabled(
            model.loading || model.saving)
          DisclosureGroup("Details") { Text(error).font(.subheadline).foregroundStyle(.secondary) }
        }
      }
      if model.total > 0 {
        Section {
          Text(
            "\(model.total) \(model.total == 1 ? "Termin" : "Termine") erkannt"
              + (model.openCount > 0
                ? " · \(model.openCount) \(model.openCount == 1 ? "Angabe" : "Angaben") offen" : "")
          ).font(.headline).accessibilityIdentifier("plan-summary")
          if let outcome = model.outcome {
            Label(
              "\(outcome.results.filter { $0.status == .saved }.count) Termine in \(model.savedCalendarName) gespeichert",
              systemImage: "calendar.badge.checkmark")
            if !outcome.existingIds.isEmpty {
              Text("\(outcome.existingIds.count) bereits vorhanden")
            }
            if outcome.results.contains(where: { $0.status != .saved }) {
              Text(
                "\(outcome.results.filter { $0.status != .saved }.count) nicht sicher gespeichert"
              ).foregroundStyle(.orange)
            }
            if !outcome.remainingIds.isEmpty {
              Text("\(outcome.remainingIds.count) Angaben noch offen").foregroundStyle(.secondary)
            }
            if outcome.results.contains(where: { !$0.maintenanceWarnings.isEmpty }) {
              Text("Erinnerungen und Widgets konnten noch nicht aktualisiert werden.")
                .foregroundStyle(.secondary)
            }
            if outcome.results.contains(where: { $0.status == .saved }) {
              Button("Rückgängig", systemImage: "arrow.uturn.backward") { history = true }
                .accessibilityIdentifier("undo-save")
            }
          } else if !model.hasWrites && model.proposal != nil && model.openCount == 0 {
            Label("Bereits im Kalender", systemImage: "checkmark.circle").foregroundStyle(
              .secondary)
          }
        }
      }
      if let assessment = model.assessment, !assessment.questions.isEmpty {
        Section("Offene Angaben") {
          ForEach(assessment.questions, id: \.id) { item in
            Button {
              question = QuestionItem(id: item.id, question: item)
            } label: {
              VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(
                  questionTitle(item.field)
                    + (item.appointmentIds.count > 1
                      ? " · \(item.appointmentIds.count) Termine" : "")
                ).foregroundStyle(.tint)
                if item.appointmentIds.count == 1,
                  let appointment = model.appointments.first(where: {
                    item.appointmentIds.contains($0.id)
                  })
                {
                  Text(
                    [appointment.start ?? "", appointment.title].filter { !$0.isEmpty }.joined(
                      separator: " · ")
                  ).font(.subheadline).foregroundStyle(.secondary).fixedSize(
                    horizontal: false, vertical: true)
                }
              }
            }.buttonStyle(.plain)
          }
        }
      }
      if let proposal = model.proposal {
        let conflicts = proposal.operations.filter(\.requiresResolution)
        if !conflicts.isEmpty {
          Section("Kalenderkonflikte") {
            ForEach(conflicts, id: \.id) { op in
              VStack(alignment: .leading, spacing: AppSpacing.medium) {
                Text(op.after?.title ?? op.before?.title ?? "Termin")
                Text(op.reason).font(.subheadline).foregroundStyle(.secondary)
                if let before = op.before {
                  Text("Kalender: \(before.startUtc) · \(before.location)").font(.subheadline)
                }
                if let after = op.after {
                  Text("Plan: \(after.startUtc) · \(after.location)").font(.subheadline)
                }
                Button("Kalenderstand behalten") {
                  Task { await model.resolve(op, choice: "keep") }
                }
                if op.kind == .conflict {
                  Button("Planwerte verwenden") {
                    Task { await model.resolve(op, choice: "paper") }
                  }
                }
                if op.kind == .ambiguous {
                  Button("Zusätzlichen Termin speichern") {
                    Task { await model.resolve(op, choice: "new") }
                  }
                }
                Text("Ohne Entscheidung bleibt dieser Termin für später.").font(.subheadline)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
        if let overlaps = proposal.overlaps, !overlaps.isEmpty {
          DisclosureGroup("\(overlaps.count) zeitliche Überschneidungen") {
            ForEach(overlaps, id: \.externalId) { overlap in
              Text("\(overlap.title) · \(overlap.startUtc)").font(.subheadline)
            }
          }
        }
      }
      let days = Array(Set(model.appointments.map { $0.date ?? "" })).sorted()
      ForEach(days, id: \.self) { day in
        Section(day.isEmpty ? "Datum offen" : readableDay(day)) {
          ForEach(model.appointments.filter { ($0.date ?? "") == day }, id: \.id) { appointment in
            Button {
              openEditor(appointment)
            } label: {
              PlanAppointmentRow(
                appointment: appointment,
                attention: model.assessment?.appointments.first { $0.id == appointment.id }?.state
                  == .attention)
            }.buttonStyle(.plain).accessibilityIdentifier("appointment-\(appointment.id)")
          }
        }
      }
      if let assessment = model.assessment, !assessment.unprocessedPageIds.isEmpty && !processing {
        let remainingPages = assessment.unprocessedPageIds.filter {
          $0 != id || model.retainedError == nil
        }
        if !remainingPages.isEmpty {
          Section("Weitere Seiten") {
            ForEach(remainingPages, id: \.self) { page in
              Button("Seite erneut erkennen", systemImage: "arrow.clockwise") {
                scanner.retry(page)
              }.disabled(scanner.running)
            }
          }
        }
      }
      if model.appointments.isEmpty && !processing && !model.loading && model.error == nil {
        ContentUnavailableView(
          "Noch keine Termine erkannt", systemImage: "doc.text.viewfinder",
          description: Text("Das Original bleibt erhalten."))
      }
      if typeSize.isAccessibilitySize { Section { saveControls } }
    }
    .disabled(deleting)
    .pageTitle("Plan")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("Originale", systemImage: "photo") { originals = true }
          Menu("Seite hinzufügen") { CaptureActions(scanner: scanner, parentID: id) }
          Button("Seiten verwalten", systemImage: "doc.on.doc") { tools = true }
          Button("Termin ergänzen", systemImage: "plus") { addAppointment() }.disabled(
            model.pages.isEmpty)
          Button("Foto korrigieren", systemImage: "crop.rotate") { correction = true }.disabled(
            scanner.running || model.pages.isEmpty)
          Button("Export und Ersetzen", systemImage: "square.and.arrow.up") { export = true }
            .disabled(model.pages.isEmpty)
          Button("Importverlauf", systemImage: "clock.arrow.circlepath") { history = true }
          Button("Diagnose", systemImage: "info.circle") { diagnostics = true }
          Button {
            delete = true
          } label: {
            Label {
              Text("Originale löschen").foregroundStyle(.primary)
            } icon: {
              Image(systemName: "trash").foregroundStyle(AppPalette.destructive)
            }
          }.disabled(scanner.running || deleting || model.saving)
        } label: {
          Label("Planaktionen", systemImage: "ellipsis")
        }.disabled(deleting).accessibilityIdentifier("plan-actions")
      }
    }
    .safeAreaInset(edge: .bottom) {
      if !typeSize.isAccessibilitySize { saveControls.disabled(deleting) }
    }
    .task(id: id) { await model.load(compare: !processing) }
    .onChange(of: scanner.running) { _, running in
      if !running {
        Task {
          await model.load()
          changed()
        }
      }
    }
    .onChange(of: scanner.finishedID) { _, result in
      if let result, result != id && !processing && model.pages.isEmpty {
        Task { await model.load() }
      }
    }
    .sheet(
      item: $editor,
      onDismiss: {
        Task {
          model.outcome = nil
          await model.load()
          changed()
        }
      }
    ) { item in
      AppointmentEditor(core: core, review: item.model, original: item.appointment) { changed() }
    }
    .sheet(
      item: $question,
      onDismiss: {
        Task {
          await model.load()
          changed()
        }
      }
    ) { item in
      if let assessment = model.assessment {
        DraftQuestionView(
          core: core, planID: id, assessment: assessment, question: item.question,
          timezone: model.timezone)
      }
    }
    .sheet(isPresented: $setup, onDismiss: { Task { await model.load() } }) {
      CalendarSetupView(core: core, planID: id)
    }
    .sheet(isPresented: $originals) { OriginalPagesView(core: core, id: id) }
    .sheet(
      isPresented: $tools,
      onDismiss: {
        Task {
          await model.load()
          changed()
        }
      }
    ) {
      NavigationStack {
        PlanPagesView(core: core, scanner: scanner, id: id)
          .navigationDestination(for: String.self) { page in
            PlanDestination(core: core, scanner: scanner, id: page, changed: changed)
          }
      }
    }
    .sheet(
      isPresented: $history,
      onDismiss: {
        Task {
          model.outcome = nil
          await model.load()
          changed()
        }
      }
    ) { ImportHistoryView(core: core, documentID: id, initialBatchID: model.outcome?.batchId) }
    .sheet(isPresented: $diagnostics) {
      NavigationStack {
        DiagnosticsView(core: core, id: model.pages.first?.id ?? id).toolbar {
          ToolbarItem(placement: .confirmationAction) { Button("Fertig") { diagnostics = false } }
        }
      }
    }
    .sheet(isPresented: $correction) {
      if let page = model.pages.first?.review {
        CorrectionView(
          core: core, scanner: scanner, id: page.document.id, width: page.document.width,
          height: page.document.height)
      }
    }
    .sheet(
      isPresented: $export,
      onDismiss: {
        Task {
          await model.load()
          changed()
        }
      }
    ) {
      if let first = model.pages.first?.review {
        CalendarView(core: core, original: first, pages: model.pages.compactMap(\.review))
      }
    }
    .confirmationDialog(
      "Originale und Prüfdaten löschen? Kalendertermine bleiben erhalten.", isPresented: $delete,
      titleVisibility: .visible
    ) {
      Button("Originale löschen", role: .destructive) {
        guard !deleting else { return }
        deleting = true
        deletionError = nil
        Task {
          defer { deleting = false }
          do {
            try await core.deleteScan(id: id)
            changed()
            dismiss()
          } catch { deletionError = userMessage(error) }
        }
      }.foregroundStyle(AppPalette.destructive)
    }
  }
  @ViewBuilder private var saveControls: some View {
    if !processing && model.total > 0
      && (model.needsCalendar || model.hasWrites || model.loading || model.saving)
    {
      VStack(spacing: AppSpacing.small) {
        let layout =
          typeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.small))
          : AnyLayout(HStackLayout(spacing: AppSpacing.small))
        layout {
          Text("Speichern in: \(model.calendarName)").fixedSize(horizontal: false, vertical: true)
          if !model.targetLocked {
            Button {
              setup = true
            } label: {
              Text("Ändern").frame(minWidth: 44, minHeight: 44).contentShape(.rect)
            }.disabled(model.saving || model.loading)
          }
        }
        if model.saving {
          ProcessingRow(text: "Im Kalender speichern …")
        } else if model.needsCalendar {
          Button("Kalender einrichten") { setup = true }.buttonStyle(AppPrimaryButtonStyle())
            .controlSize(.large)
        } else {
          Button {
            Task {
              await model.save()
              changed()
            }
          } label: {
            Text(model.saveLabel)
              .frame(maxWidth: .infinity).fixedSize(
                horizontal: false, vertical: true)
          }.buttonStyle(AppPrimaryButtonStyle()).controlSize(.large).accessibilityIdentifier(
            "save-plan"
          )
          .disabled(model.loading || model.selected.isEmpty || !model.hasWrites)
        }
      }.frame(maxWidth: .infinity).padding().background(.bar)
    }
  }
  private func openEditor(_ appointment: Appointment) {
    guard
      let page = model.pages.first(where: {
        $0.review?.appointments.contains { $0.id == appointment.id } == true
      })
    else { return }
    editor = PlanEditorItem(id: appointment.id, appointment: appointment, model: page)
  }
  private func addAppointment() {
    guard let page = model.pages.first else { return }
    do {
      let a = try newAppointment(date: model.appointments.first?.date)
      editor = PlanEditorItem(id: a.id, appointment: a, model: page)
    } catch { model.error = userMessage(error) }
  }
}
private struct PlanAppointmentRow: View {
  let appointment: Appointment
  let attention: Bool
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric private var timeWidth = 62.0
  var body: some View {
    let layout =
      typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.small))
      : AnyLayout(HStackLayout(alignment: .top, spacing: AppSpacing.section))
    layout {
      Text(appointment.start ?? "–").monospacedDigit().frame(
        minWidth: timeWidth, alignment: .leading)
      VStack(alignment: .leading, spacing: AppSpacing.small) {
        Text(appointment.title.isEmpty ? "Bezeichnung fehlt" : appointment.title).foregroundStyle(
          .primary
        ).fixedSize(horizontal: false, vertical: true)
        let metadata = [
          appointment.end.map { "bis \($0)" } ?? appointment.durationMinutes.map { "\($0) Min." }
            ?? "", appointment.location, appointment.therapist,
        ].filter { !$0.isEmpty }
        if !metadata.isEmpty {
          Text(metadata.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if !appointment.included {
          Text("Für später").font(.subheadline).foregroundStyle(.secondary)
        } else if attention {
          Label("Angabe offen", systemImage: "exclamationmark.circle").font(.subheadline)
            .foregroundStyle(.orange)
        }
      }
    }.font(.body).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(.rect).padding(.vertical, AppSpacing.small).accessibilityElement(
        children: .combine)
  }
}
func questionTitle(_ field: String) -> String {
  if field.hasPrefix("issue:") { return "Termin prüfen" }
  return switch field {
  case "date": "Datum prüfen"
  case "start": "Beginn prüfen"
  case "end", "end_date", "duration_minutes": "Dauer prüfen"
  case "cancellation": "Findet der Termin statt?"
  default: "Bezeichnung prüfen"
  }
}
