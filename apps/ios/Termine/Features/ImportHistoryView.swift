import RehaCore
import SwiftUI

struct ImportHistoryView: View {
  let core: NativeApplication
  var documentID: String?
  var initialBatchID: String?
  @State private var pageIDs: [String] = []
  @Environment(\.dismiss) private var dismiss
  @State private var history: History?
  @State private var proposal: Proposal?
  @State private var approveRemovals = false
  @State private var busy = false
  @State private var error: String?
  @State private var results: [CalendarResult] = []
  var body: some View {
    NavigationStack {
      List {
        if let error { Section { Text(error).foregroundStyle(AppPalette.destructive) } }
        if busy { ProgressView("Kalender wird abgeglichen …") }
        if let proposal {
          Section("Rücknahme prüfen") {
            ForEach(proposal.operations, id: \.id) { op in
              VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(op.after?.title ?? op.before?.title ?? "Termin").font(.headline)
                Text(operationTitle(op.kind))
                Text(op.reason).font(.subheadline)
                if op.requiresResolution {
                  Button("Aktuellen Kalenderstand behalten") {
                    Task {
                      do {
                        self.proposal = try await core.resolveProposal(
                          token: proposal.token, eventId: op.id, choice: "keep")
                      } catch { self.error = userMessage(error) }
                    }
                  }.disabled(busy)
                }
              }
            }
            if proposal.operations.contains(where: { $0.kind == .remove }) {
              Toggle("Entfernen der angezeigten Termine bestätigen", isOn: $approveRemovals)
            }
            Button("Rücknahme ausführen", role: .destructive) { Task { await undo() } }
              .foregroundStyle(AppPalette.destructive)
              .disabled(
                busy || proposal.operations.contains(where: \.requiresResolution)
                  || (proposal.operations.contains { $0.kind == .remove } && !approveRemovals))
          }
        }
        if !results.isEmpty {
          Section {
            Text(
              "\(results.filter { $0.status == .saved }.count) Änderungen rückgängig gemacht · \(results.filter { $0.status != .saved }.count) offen oder fehlgeschlagen"
            )
          }
        }
        if let history {
          let batches = history.batches.filter {
            documentID == nil || $0.documentIds.contains { pageIDs.contains($0) }
          }
          if batches.isEmpty {
            Text(
              "Für ältere Importe ist keine eindeutige Rücknahme gespeichert. Kalenderzuordnungen bleiben erhalten."
            )
          }
          ForEach(batches, id: \.id) { batch in
            Section {
              Text(Date(timeIntervalSince1970: Double(batch.createdAt)), style: .date)
              Text(
                "\(batch.operations.filter { $0.status == "saved" }.count) Änderungen gespeichert · \(batch.operations.filter { $0.status != "saved" }.count) offen oder fehlgeschlagen"
              )
              ForEach(batch.operations, id: \.attemptId) { item in
                VStack(alignment: .leading) {
                  Text(item.operation.after?.title ?? item.operation.before?.title ?? "Termin")
                  Text("\(operationTitle(item.operation.kind)) · \(status(item.status))").font(
                    .subheadline
                  ).foregroundStyle(.secondary)
                }
              }
              if batch.undoOf == nil
                && (batch.undoneBy == nil
                  || history.batches.contains(where: {
                    $0.id == batch.undoneBy
                      && $0.operations.contains(where: {
                        ["failed", "conflict"].contains($0.status)
                      })
                  }))
                && batch.operations.contains(where: { $0.status == "saved" })
              {
                Button("Import rückgängig machen", systemImage: "arrow.uturn.backward") {
                  Task { await prepare(batch.id) }
                }.disabled(busy)
              } else if batch.undoneBy != nil {
                Text("Rücknahme im Importverlauf erfasst.").font(.subheadline)
              }
            } header: {
              Text(batch.undoOf == nil ? "Kalenderimport" : "Rücknahme")
            }
          }
        }

      }
      .pageTitle("Importverlauf")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Fertig") { dismiss() }.disabled(busy)
        }
      }
      .task {
        if let documentID { pageIDs = (try? await core.pageGroup(id: documentID)) ?? [documentID] }
        await refresh()
        if let initialBatchID { await prepare(initialBatchID) }
      }
    }
  }
  private func status(_ value: String) -> String {
    switch value {
    case "saved": "Gespeichert"
    case "failed": "Fehlgeschlagen"
    case "conflict": "Konflikt"
    default: "Abgleich nötig"
    }
  }
  private func refresh() async {
    do { history = try await core.history() } catch { self.error = userMessage(error) }
  }
  private func prepare(_ id: String) async {
    busy = true
    error = nil
    proposal = nil
    results = []
    approveRemovals = false
    defer { busy = false }
    do { proposal = try await core.prepareUndo(batchId: id) } catch {
      self.error = userMessage(error)
    }
  }
  private func undo() async {
    guard let proposal else { return }
    busy = true
    error = nil
    defer { busy = false }
    do {
      results = try await core.approveCalendar(
        token: proposal.token, approveRemovals: approveRemovals)
      self.proposal = nil
      await refresh()
    } catch { self.error = userMessage(error) }
  }
}
