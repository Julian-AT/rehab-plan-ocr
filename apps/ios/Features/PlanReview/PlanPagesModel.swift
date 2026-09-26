import Foundation
import Observation

#if canImport(RehaCore)
  import RehaCore
#endif

@MainActor @Observable final class PlanPagesModel {
  struct Snapshot {
    var pageIDs: [String] = []
    var reviews: [String: ReviewSnapshot] = [:]
  }
  private(set) var snapshot = Snapshot()
  var error: String?
  private var generation = 0

  func load(core: NativeApplication, id: String) async {
    guard !Task.isCancelled else { return }
    generation += 1
    let current = generation
    do {
      let ids = try await core.pageGroup(id: id)
      guard current == generation, !Task.isCancelled else { return }
      var loaded: [String: ReviewSnapshot] = [:]
      for page in ids {
        loaded[page] = try? await core.loadScan(id: page)
        guard current == generation, !Task.isCancelled else { return }
      }
      snapshot = Snapshot(pageIDs: ids, reviews: loaded)
      error = nil
    } catch {
      if current == generation, !Task.isCancelled { self.error = userMessage(error) }
    }
  }
}
