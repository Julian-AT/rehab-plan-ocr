import AppleServices
import RehaCore
import SwiftUI

@MainActor @Observable private final class PlansModel {
  var history: History?
  var error: String?
  func refresh(_ core: NativeApplication) async {
    do {
      history = try await core.history()
      error = nil
    } catch { self.error = userMessage(error) }
  }
}

struct PlansView: View {
  let core: NativeApplication
  let scanner: ScanModel
  let refreshID: Int
  @State private var model = PlansModel()
  var body: some View {
    List {
      if let error = model.error {
        Text(error).foregroundStyle(.secondary)
        Button("Erneut versuchen") { Task { await model.refresh(core) } }
      }
      if let history = model.history {
        let plans = history.plans.filter { plan in
          plan.pageIds.contains { page in
            history.scans.contains { $0.id == page && $0.retained }
              || history.intakes.contains { $0.id == page && $0.status != "deleted" }
          }
            || history.intakes.contains { $0.id == plan.id && $0.status != "deleted" }
            || history.batches.contains { batch in
              batch.documentIds.contains { plan.pageIds.contains($0) }
            }
            || history.scans.contains { scan in
              plan.pageIds.contains(scan.id)
                && history.imports.contains { $0.scheduleId == scan.scheduleId }
            }
        }
        if plans.isEmpty {
          ContentUnavailableView(
            "Noch keine Pläne", systemImage: "doc.on.doc",
            description: Text("Aufgenommene Pläne erscheinen hier."))
        }
        ForEach(plans, id: \.id) { plan in
          NavigationLink(value: plan.id) {
            ArchiveRow(
              core: core, plan: plan, history: history,
              processing: scanner.running
                && (scanner.currentID == plan.id || plan.pageIds.contains(scanner.currentID ?? "")))
          }
          .accessibilityIdentifier("plan-\(plan.id)")
        }
      } else if model.error == nil {
        ProcessingRow(text: "Archiv laden …")
      }
    }
    .pageTitle("Archiv")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          CaptureActions(scanner: scanner, context: "archive-menu")
        } label: {
          Label("Plan hinzufügen", systemImage: "plus")
        }
      }
    }
    .task(id: refreshID) { await model.refresh(core) }
    .refreshable { await model.refresh(core) }
  }
}
private struct ArchiveRow: View {
  let core: NativeApplication
  let plan: Plan
  let history: History
  let processing: Bool
  @State private var thumbnail: UIImage?
  @Environment(\.dynamicTypeSize) private var typeSize
  private var scans: [ScanSummary] { history.scans.filter { plan.pageIds.contains($0.id) } }
  private var status: String {
    if processing { return "Wird erkannt" }
    let batches = history.batches.filter { $0.documentIds.contains { plan.pageIds.contains($0) } }
    if batches.contains(where: {
      $0.operations.contains { ["pending", "uncertain", "queued"].contains($0.status) }
    }) {
      return "Kalenderabgleich nötig"
    }
    if let latest = batches.first, latest.undoOf != nil,
      latest.operations.allSatisfy({ $0.status == "saved" || $0.status == "skipped" })
    {
      return "Rückgängig gemacht"
    }
    let records = history.imports.filter { record in
      scans.contains { $0.scheduleId == record.scheduleId }
    }
    let count = scans.reduce(0) { $0 + Int($1.itemCount) }
    if !records.isEmpty { return records.count >= count ? "Im Kalender" : "Teilweise gespeichert" }
    if scans.count < plan.pageIds.count { return "Erkennung offen" }
    return "Bereit zum Prüfen"
  }
  var body: some View {
    HStack(alignment: .top, spacing: AppSpacing.section) {
      if !typeSize.isAccessibilitySize {
        Group {
          if let thumbnail {
            Image(uiImage: thumbnail).resizable().scaledToFill()
          } else {
            Image(systemName: "doc.text").font(.title2).foregroundStyle(.secondary)
          }
        }.frame(width: 48, height: 64).clipped().clipShape(.rect(cornerRadius: 6))
          .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: AppSpacing.small) {
        Text(planDateRange(scans.flatMap(\.dates), fallback: plan.importedAt)).font(.body)
          .fixedSize(horizontal: false, vertical: true)
        Text("\(scans.reduce(0) { $0 + Int($1.itemCount) }) Termine · \(status)").font(.subheadline)
          .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }.padding(.vertical, AppSpacing.small).accessibilityElement(children: .combine)
      .task(id: plan.id) {
        guard let page = plan.pageIds.first,
          let path = try? await core.artifactPath(id: page, artifact: "page.png")
        else { return }
        thumbnail = try? await DisplayImage.load(URL(fileURLWithPath: path), maximum: 160)
      }
  }
}
func planDateRange(_ dates: [String], fallback: Int64) -> String {
  let sorted = Array(Set(dates)).sorted()
  guard let first = sorted.first, let last = sorted.last else {
    return Date(timeIntervalSince1970: Double(fallback)).formatted(
      date: .abbreviated, time: .omitted)
  }
  return first == last ? readableDay(first) : "\(readableDay(first)) – \(readableDay(last))"
}
func readableDay(_ value: String) -> String {
  let parser = DateFormatter()
  parser.locale = Locale(identifier: "en_US_POSIX")
  parser.dateFormat = "yyyy-MM-dd"
  parser.timeZone = TimeZone(secondsFromGMT: 0)
  guard let date = parser.date(from: value) else { return "Datum offen" }
  parser.locale = Locale(identifier: "de_AT")
  parser.dateFormat = "d. MMM yyyy"
  return parser.string(from: date)
}
