import EventKit
import RehaCore
import SwiftUI

/// Secondary tools. Everyday saves happen directly on the plan screen.
struct CalendarView: View {
  let core: NativeApplication
  let original: ReviewSnapshot
  @Environment(\.dismiss) private var dismiss
  @State private var pages: [ReviewSnapshot]
  @State private var assessment: DraftAssessment?
  @State private var replacement = ReplacementPreviewState<Proposal>()
  @State private var complete = false
  @State private var busy = false
  @State private var error: String?
  @State private var exportedFile = TemporaryCalendarExport()
  @State private var outcome: SaveOutcome?
  @State private var previousScans: [ScanSummary] = []
  @State private var previousID = ""
  @State private var history = false
  private var replacementInputs: ReplacementPreviewState<Proposal>.Inputs {
    .init(previousID: previousID, complete: complete)
  }
  init(core: NativeApplication, original: ReviewSnapshot, pages: [ReviewSnapshot]? = nil) {
    self.core = core
    self.original = original
    _pages = State(initialValue: pages ?? [original])
  }
  var body: some View {
    NavigationStack {
      List {
        Section("Kalenderdatei") {
          Button(
            "\(assessment?.readyIds.count ?? 0) Termine als ICS exportieren",
            systemImage: "square.and.arrow.up"
          ) { Task { await export() } }
          .disabled(busy || assessment?.readyIds.isEmpty != false)
          if let exportURL = exportedFile.url { ShareLink("Kalenderdatei teilen", item: exportURL) }
        }
        Section {
          DisclosureGroup("Bisherigen Plan ersetzen") {
            Text(
              "Entfernt auf Wunsch bisherige Termine, die auf dem vollständigen neuen Plan fehlen."
            ).foregroundStyle(.secondary)
            Picker("Bisheriger Plan", selection: $previousID) {
              Text("Aktuelle Zuordnung").tag("")
              ForEach(previousScans, id: \.id) { scan in
                Text(planDateRange(scan.dates, fallback: scan.importedAt)).tag(scan.id)
              }
            }
            Toggle("Alle gedruckten Termine aller Seiten erfasst", isOn: $complete)
            Button("Ersetzung vergleichen") { Task { await compareReplacement() } }.disabled(
              busy || !complete)
          }
        }
        if let proposal = replacement.current(inputs: replacementInputs) {
          Section("Ersetzung") {
            ForEach(proposal.operations, id: \.id) { op in
              VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(op.after?.title ?? op.before?.title ?? "Termin")
                Text(operationTitle(op.kind)).foregroundStyle(.secondary)
                if let before = op.before { Text("Bisher: \(before.startUtc)").font(.subheadline) }
                if let after = op.after { Text("Plan: \(after.startUtc)").font(.subheadline) }
                if op.requiresResolution {
                  Text(op.reason).font(.subheadline)
                  Button("Kalenderstand behalten") { resolve(op, "keep") }.disabled(busy)
                  if op.kind == .conflict {
                    Button("Planwerte verwenden") { resolve(op, "paper") }.disabled(busy)
                  }
                  if op.kind == .ambiguous {
                    Button("Zusätzlichen Termin speichern") { resolve(op, "new") }.disabled(busy)
                    ForEach(
                      proposal.operations.filter {
                        $0.kind == .keep && $0.after == nil && $0.before != nil
                      }, id: \.id
                    ) { old in
                      Button("Zuordnen: \(old.before?.title ?? "Termin")") {
                        resolve(op, "match:\(old.id)")
                      }.disabled(busy)
                    }
                  }
                }
              }
            }
            if proposal.operations.contains(where: { $0.kind == .remove }) {
              Toggle("Angezeigte Löschungen erlauben", isOn: $replacement.removalsApproved)
            }
            Button("Ersetzung speichern") { Task { await write() } }
              .disabled(
                busy || proposal.operations.contains(where: \.requiresResolution)
                  || (proposal.operations.contains { $0.kind == .remove }
                    && !replacement.removalsApproved)
              )
          }
        }
        if let outcome {
          Text(
            "\(outcome.results.filter { $0.status == .saved }.count) Änderungen gespeichert · \(outcome.results.filter { $0.status != .saved }.count) offen"
          )
          Button("Rückgängig") { history = true }
          if outcome.results.contains(where: { !$0.maintenanceWarnings.isEmpty }) {
            Text("Erinnerungen und Widgets konnten noch nicht aktualisiert werden.")
              .foregroundStyle(.secondary)
          }
        }
        if let error { Text(error).foregroundStyle(AppPalette.destructive) }
        if busy { ProcessingRow(text: "Wird vorbereitet …") }
      }.pageTitle("Export und Ersetzen")
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Fertig") { dismiss() }.disabled(busy)
          }
        }
        .task { await load() }
        .onChange(of: complete) { replacement.invalidate() }
        .onChange(of: previousID) { replacement.invalidate() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
          replacement.invalidate()
        }
        .onDisappear {
          replacement.invalidate()
          Task { await exportedFile.close() }
        }
        .sheet(isPresented: $history) {
          ImportHistoryView(
            core: core, documentID: original.document.id, initialBatchID: outcome?.batchId)
        }
    }
  }
  private func load() async {
    do {
      assessment = try await core.assessDraft(id: original.document.id, timezone: original.timezone)
      previousScans = try await core.history().scans.filter {
        $0.scheduleId != nil && $0.id != original.document.id
      }
    } catch { self.error = userMessage(error) }
  }
  private func export() async {
    guard !busy, let assessment else { return }
    busy = true
    defer { busy = false }
    do {
      try await exportedFile.write {
        let preferences = try await core.preferences()
        return try await core.exportDraftIcs(
          id: original.document.id, revision: assessment.revision, timezone: original.timezone,
          reminder: preferences.reminder, selection: assessment.readyIds)
      }
      error = nil
      await load()
    } catch {
      self.error = userMessage(error)
      await load()
    }
  }
  private func compareReplacement() async {
    guard !busy, complete else { return }
    busy = true
    defer { busy = false }
    let request = replacement.begin(inputs: replacementInputs)
    do {
      if !request.inputs.previousID.isEmpty {
        try await core.associateRecheck(
          id: original.document.id, previous: request.inputs.previousID)
      }
      guard replacement.accepts(request, inputs: replacementInputs) else { return }
      let ids = try await core.pageGroup(id: original.document.id)
      guard replacement.accepts(request, inputs: replacementInputs) else { return }
      for id in ids {
        let page = try await core.loadScan(id: id)
        guard replacement.accepts(request, inputs: replacementInputs) else { return }
        _ = try await core.saveReview(
          id: id, revision: page.revision, appointments: page.appointments,
          complete: request.inputs.complete,
          selection: [])
        guard replacement.accepts(request, inputs: replacementInputs) else { return }
      }
      let preferences = try await core.preferences()
      guard replacement.accepts(request, inputs: replacementInputs) else { return }
      guard !preferences.calendarId.isEmpty else {
        throw AppError.Validation(message: "Kalender zuerst beim Plan einrichten.")
      }
      let preview = try await core.previewReplacement(
        id: original.document.id, calendarId: preferences.calendarId, timezone: original.timezone,
        reminder: preferences.reminder)
      guard replacement.finish(request, inputs: replacementInputs, value: preview.proposal) else {
        return
      }
      assessment = preview.assessment
      error = nil
    } catch {
      guard replacement.accepts(request, inputs: replacementInputs) else { return }
      replacement.invalidate()
      self.error = userMessage(error)
    }
  }
  private func resolve(_ op: CalendarOperation, _ choice: String) {
    guard let proposal = replacement.current(inputs: replacementInputs), !busy else { return }
    busy = true
    let request = replacement.begin(inputs: replacementInputs, retainingValue: true)
    Task {
      defer { busy = false }
      do {
        let resolved = try await core.resolveProposal(
          token: proposal.token, eventId: op.id, choice: choice)
        guard replacement.finish(request, inputs: replacementInputs, value: resolved) else {
          return
        }
        error = nil
      } catch {
        guard replacement.accepts(request, inputs: replacementInputs) else { return }
        replacement.invalidate()
        self.error = userMessage(error)
      }
    }
  }
  private func write() async {
    guard let proposal = replacement.current(inputs: replacementInputs), let assessment, !busy
    else {
      return
    }
    busy = true
    defer { busy = false }
    do {
      outcome = try await core.acceptAndSave(
        token: proposal.token, selection: assessment.readyIds,
        approveRemovals: replacement.removalsApproved)
      replacement.invalidate()
      error = nil
      await load()
    } catch {
      replacement.invalidate()
      self.error = userMessage(error)
    }
  }
}
func operationTitle(_ kind: OperationKind) -> String {
  switch kind {
  case .create: "Neu erstellen"
  case .update: "Ändern"
  case .remove: "Löschen"
  case .unchanged: "Unverändert"
  case .keep: "Behalten"
  case .protected: "Geschützt"
  case .ambiguous: "Zuordnung klären"
  default: "Konflikt klären"
  }
}
struct RecoveryView: View {
  let core: NativeApplication
  let changed: () -> Void
  @State private var pending: [PendingWrite] = []
  @State private var error: String?
  @State private var busy = false
  @State private var resolution: PendingWrite?
  var body: some View {
    Form {
      Section {
        Text("Zuerst abgleichen. Ein unklarer Schreibvorgang wird dabei nicht erneut ausgeführt.")
        Button("Kalender abgleichen") { Task { await reconcile() } }.disabled(busy)
      }
      if let error { Text(error).foregroundStyle(AppPalette.destructive) }
      ForEach(pending, id: \.attemptId) { item in
        VStack(alignment: .leading) {
          Text(item.operation.after?.title ?? item.operation.before?.title ?? "Termin").font(
            .headline)
          Text(operationTitle(item.operation.kind))
          Button("Nach Prüfung im Kalender manuell auflösen") { resolution = item }.disabled(busy)
        }
      }
      if pending.isEmpty { Text("Keine unklaren Schreibvorgänge.") }
    }
    .pageTitle("Kalenderabgleich")
    .task { await load() }
    .confirmationDialog(
      "Ergebnis im Kalender geprüft?",
      isPresented: Binding(get: { resolution != nil }, set: { if !$0 { resolution = nil } }),
      titleVisibility: .visible
    ) {
      Button("Änderung wurde nicht ausgeführt") { resolve(false) }
      if resolution?.operation.kind == .remove {
        Button("Löschung wurde ausgeführt", role: .destructive) { resolve(true) }.foregroundStyle(
          AppPalette.destructive)
      }
      Button("Abbrechen", role: .cancel) {}
    }
  }
  private func load() async {
    do { pending = try await core.history().pending } catch { self.error = userMessage(error) }
  }
  private func reconcile() async {
    busy = true
    defer { busy = false }
    do {
      _ = try await core.reconcileCalendar()
      await load()
      changed()
    } catch { self.error = userMessage(error) }
  }
  private func resolve(_ removed: Bool) {
    guard let resolution else { return }
    Task {
      do {
        try await core.resolvePending(attemptId: resolution.attemptId, removalApplied: removed)
        await load()
        changed()
      } catch { self.error = userMessage(error) }
    }
  }
}
