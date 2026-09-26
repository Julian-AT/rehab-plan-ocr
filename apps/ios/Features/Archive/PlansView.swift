import AppleServices
import RehaCore
import SwiftUI

struct PlansView: View {
  let core: NativeApplication
  let scanner: ScanModel
  let refreshID: Int
  @State private var model = PlansModel(describe: userMessage)
  var body: some View {
    List {
      if let error = model.error {
        Text(error).foregroundStyle(.secondary)
        Button("Erneut versuchen") { Task { await model.refresh(core, revision: refreshID) } }
      }
      if model.loaded {
        if model.plans.isEmpty {
          ContentUnavailableView(
            "Noch keine Pläne", systemImage: "doc.on.doc",
            description: Text("Aufgenommene Pläne erscheinen hier."))
        }
        ForEach(model.plans, id: \.id) { plan in
          NavigationLink(value: plan.id) {
            ArchiveRow(
              core: core, plan: plan,
              processing: scanner.running
                && (scanner.currentID == plan.id || plan.pageIds.contains(scanner.currentID ?? "")))
          }
          .accessibilityIdentifier("plan-\(plan.id)")
        }
        if model.next != nil && model.error == nil {
          ProcessingRow(text: "Archiv laden …")
            .task(id: model.isRefreshing ? nil : model.next) {
              guard !model.isRefreshing else { return }
              await model.loadMore(core)
            }
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
    .task(id: refreshID) { await model.refresh(core, revision: refreshID) }
    .refreshable { await model.refresh(core, revision: refreshID) }
  }
}
private struct ArchiveRow: View {
  let core: NativeApplication
  let plan: PlanSummary
  let processing: Bool
  @State private var thumbnail: UIImage?
  @Environment(\.dynamicTypeSize) private var typeSize
  private var status: String {
    if processing { return "Wird erkannt" }
    switch plan.status {
    case .reconciliationNeeded: return "Kalenderabgleich nötig"
    case .undone: return "Rückgängig gemacht"
    case .saved: return "Im Kalender"
    case .partiallySaved: return "Teilweise gespeichert"
    case .recognitionPending: return "Erkennung offen"
    case .readyForReview: return "Bereit zum Prüfen"
    }
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
        Text(planDateRange(plan.dates, fallback: plan.importedAt)).font(.body)
          .fixedSize(horizontal: false, vertical: true)
        Text("\(plan.itemCount) Termine · \(status)").font(.subheadline)
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
