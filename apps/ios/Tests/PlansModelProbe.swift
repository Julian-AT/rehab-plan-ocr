import Foundation

// Minimal transport values let the state machine run without linking a native
// calendar. BindingProbe separately exercises the actual generated records.
struct ArchiveCursor: Equatable, Sendable {
  let importedAt: Int64
  let id: String
}
struct PlanSummary: Equatable, Sendable {
  let id: String
  let importedAt: Int64
}
struct ArchivePage: Sendable {
  let plans: [PlanSummary]
  let next: ArchiveCursor?
}

@MainActor private final class Source: ArchiveDataSource {
  var plans = (0..<45).map { PlanSummary(id: String(format: "%03d", $0), importedAt: 100) }
  var queries = 0
  var holdNext = false
  var failure = false
  var pending: CheckedContinuation<Void, Never>?
  func archivePage(after: ArchiveCursor?, limit: UInt32) async throws -> ArchivePage {
    precondition(limit == 20)
    queries += 1
    let available = plans.filter { plan in
      guard let after else { return true }
      return plan.importedAt < after.importedAt
        || (plan.importedAt == after.importedAt && plan.id > after.id)
    }
    let rows = Array(available.prefix(Int(limit)))
    let next =
      available.count > Int(limit)
      ? rows.last.map { ArchiveCursor(importedAt: $0.importedAt, id: $0.id) } : nil
    if holdNext {
      holdNext = false
      await withCheckedContinuation { pending = $0 }
    }
    if failure { throw CocoaError(.fileReadUnknown) }
    return ArchivePage(plans: rows, next: next)
  }
  func release() {
    let continuation = pending
    pending = nil
    continuation?.resume()
  }
}

@main @MainActor struct PlansModelProbe {
  private static func waitForQuery(_ source: Source) async {
    for _ in 0..<10_000 {
      if source.pending != nil { return }
      await Task.yield()
    }
    preconditionFailure("Controlled archive query never started")
  }

  static func main() async {
    await pagingAndRefreshPreserveLoadedRange()
    await supersededPagesCannotReappear()
    await refreshCoalescesAndCancellationIsSilent()
    print(
      "Archive state: pagination, retained content, errors, coalescing, stale results and cancellation passed"
    )
  }

  private static func pagingAndRefreshPreserveLoadedRange() async {
    let source = Source()
    let model = PlansModel()
    await model.refresh(source, revision: 1)
    precondition(model.loaded && model.plans.count == 20 && model.next != nil)
    await model.loadMore(source)
    precondition(model.plans.count == 40)
    await model.loadMore(source)
    precondition(model.plans.count == 45 && model.next == nil && source.queries == 3)
    await model.loadMore(source)
    precondition(source.queries == 3)
    source.plans.insert(PlanSummary(id: "new", importedAt: 200), at: 0)
    source.holdNext = true
    let refresh = Task { await model.refresh(source, revision: 2) }
    await waitForQuery(source)
    precondition(model.plans.count == 45 && model.isRefreshing)
    source.release()
    await refresh.value
    precondition(model.plans == source.plans, "Refreshing must retain the previous scroll range")
    source.failure = true
    await model.refresh(source, revision: 3)
    precondition(model.error != nil && model.plans.count == 46)
    source.failure = false
    source.plans = []
    await model.refresh(source, revision: 4)
    precondition(model.loaded && model.plans.isEmpty && model.next == nil && model.error == nil)
  }

  private static func supersededPagesCannotReappear() async {
    let source = Source()
    let model = PlansModel()
    await model.refresh(source, revision: 1)
    source.holdNext = true
    let oldPage = Task { await model.loadMore(source) }
    await waitForQuery(source)
    source.plans = [PlanSummary(id: "new", importedAt: 200)]
    await model.refresh(source, revision: 2)
    source.release()
    await oldPage.value
    precondition(model.plans == source.plans && model.next == nil && !model.isLoadingMore)
    source.holdNext = true
    let oldRefresh = Task { await model.refresh(source, revision: 3) }
    await waitForQuery(source)
    source.plans = [PlanSummary(id: "latest", importedAt: 300)]
    await model.refresh(source, revision: 4)
    source.release()
    await oldRefresh.value
    precondition(model.plans == source.plans && !model.isRefreshing)
  }

  private static func refreshCoalescesAndCancellationIsSilent() async {
    let source = Source()
    let model = PlansModel()
    source.holdNext = true
    let first = Task { await model.refresh(source, revision: 1) }
    await waitForQuery(source)
    let second = Task { await model.refresh(source, revision: 1) }
    for _ in 0..<100 { await Task.yield() }
    precondition(source.queries == 1)
    source.release()
    await first.value
    await second.value
    precondition(model.plans.count == 20 && !model.isRefreshing)
    source.holdNext = true
    let canceled = Task { await model.refresh(source, revision: 2) }
    await waitForQuery(source)
    canceled.cancel()
    source.release()
    await canceled.value
    precondition(model.error == nil && model.plans.count == 20 && !model.isRefreshing)
    await model.refresh(source, revision: 3)
    precondition(model.plans.count == 20)
  }
}
