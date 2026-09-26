import RehaCore
import SwiftUI

/// Secondary tools. Everyday saves happen directly on the plan screen.
struct CalendarView: View {
  let core: NativeApplication
  let original: ReviewSnapshot
  @Environment(\.dismiss) private var dismiss
  @State private var pages: [ReviewSnapshot]
  @State private var assessment: DraftAssessment?
  @State private var proposal: Proposal?
  @State private var complete = false
  @State private var approveRemovals = false
  @State private var busy = false
  @State private var error: String?
  @State private var exportURL: URL?
  @State private var outcome: SaveOutcome?
  @State private var previousScans: [ScanSummary] = []
  @State private var previousID = ""
  @State private var history = false
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
          if let exportURL { ShareLink("Kalenderdatei teilen", item: exportURL) }
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
        if let proposal {
          Section("Ersetzung") {
            ForEach(proposal.operations, id: \.id) { op in
              VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(op.after?.title ?? op.before?.title ?? "Termin")
                Text(operationTitle(op.kind)).foregroundStyle(.secondary)
                if let before = op.before { Text("Bisher: \(before.startUtc)").font(.subheadline) }
                if let after = op.after { Text("Plan: \(after.startUtc)").font(.subheadline) }
                if op.requiresResolution {
                  Text(op.reason).font(.subheadline)
                  Button("Kalenderstand behalten") { resolve(op, "keep") }
                  if op.kind == .conflict { Button("Planwerte verwenden") { resolve(op, "paper") } }
                  if op.kind == .ambiguous {
                    Button("Zusätzlichen Termin speichern") { resolve(op, "new") }
                    ForEach(
                      proposal.operations.filter {
                        $0.kind == .keep && $0.after == nil && $0.before != nil
                      }, id: \.id
                    ) { old in
                      Button("Zuordnen: \(old.before?.title ?? "Termin")") {
                        resolve(op, "match:\(old.id)")
                      }
                    }
                  }
                }
              }
            }
            if proposal.operations.contains(where: { $0.kind == .remove }) {
              Toggle("Angezeigte Löschungen erlauben", isOn: $approveRemovals)
            }
            Button("Ersetzung speichern") { Task { await write() } }
              .disabled(
                busy || proposal.operations.contains(where: \.requiresResolution)
                  || (proposal.operations.contains { $0.kind == .remove } && !approveRemovals))
          }
        }
        if let outcome {
          Text(
            "\(outcome.results.filter { $0.status == .saved }.count) Änderungen gespeichert · \(outcome.results.filter { $0.status != .saved }.count) offen"
          )
          Button("Rückgängig") { history = true }
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
        .onChange(of: complete) {
          proposal = nil
          approveRemovals = false
        }
        .onChange(of: previousID) {
          proposal = nil
          approveRemovals = false
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
    guard let assessment else { return }
    busy = true
    defer { busy = false }
    do {
      let preferences = try await core.preferences()
      let content = try await core.exportDraftIcs(
        id: original.document.id, revision: assessment.revision, timezone: original.timezone,
        reminder: preferences.reminder, selection: assessment.readyIds)
      exportURL = try await Task.detached {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
          "Termine-\(UUID().uuidString).ics")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
      }.value
      error = nil
      await load()
    } catch {
      self.error = userMessage(error)
      await load()
    }
  }
  private func compareReplacement() async {
    busy = true
    defer { busy = false }
    proposal = nil
    approveRemovals = false
    do {
      if !previousID.isEmpty {
        try await core.associateRecheck(id: original.document.id, previous: previousID)
      }
      let ids = try await core.pageGroup(id: original.document.id)
      for id in ids {
        let page = try await core.loadScan(id: id)
        _ = try await core.saveReview(
          id: id, revision: page.revision, appointments: page.appointments, complete: complete,
          selection: [])
      }
      let preferences = try await core.preferences()
      guard !preferences.calendarId.isEmpty else {
        throw AppError.Validation(message: "Kalender zuerst beim Plan einrichten.")
      }
      let preview = try await core.previewReplacement(
        id: original.document.id, calendarId: preferences.calendarId, timezone: original.timezone,
        reminder: preferences.reminder)
      assessment = preview.assessment
      proposal = preview.proposal
      error = nil
    } catch { self.error = userMessage(error) }
  }
  private func resolve(_ op: CalendarOperation, _ choice: String) {
    guard let proposal else { return }
    Task {
      busy = true
      defer { busy = false }
      do {
        self.proposal = try await core.resolveProposal(
          token: proposal.token, eventId: op.id, choice: choice)
        approveRemovals = false
      } catch { self.error = userMessage(error) }
    }
  }
  private func write() async {
    guard let proposal, let assessment else { return }
    busy = true
    defer { busy = false }
    do {
      outcome = try await core.acceptAndSave(
        token: proposal.token, selection: assessment.readyIds, approveRemovals: approveRemovals)
      self.proposal = nil
      error = nil
      await load()
    } catch { self.error = userMessage(error) }
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
        Button("Löschung wurde ausgeführt", role: .destructive) { resolve(true) }
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
