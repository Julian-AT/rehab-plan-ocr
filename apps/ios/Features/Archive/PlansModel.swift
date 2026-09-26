import Foundation
import Observation

#if canImport(RehaCore)
  import RehaCore
#endif

@MainActor protocol ArchiveDataSource {
  func archivePage(after: ArchiveCursor?, limit: UInt32) async throws -> ArchivePage
}

#if canImport(RehaCore)
  extension NativeApplication: ArchiveDataSource {}
#endif

/// Keep the loaded range visible while refreshing and reject superseded pages.
@MainActor @Observable final class PlansModel {
  private(set) var plans: [PlanSummary] = []
  private(set) var next: ArchiveCursor?
  private(set) var loaded = false
  private(set) var isRefreshing = false
  private(set) var isLoadingMore = false
  private(set) var error: String?
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var refreshRevision: Int?
  @ObservationIgnored private var refreshTask: Task<Void, Never>?
  private let describe: (Error) -> String

  init(describe: @escaping (Error) -> String = { $0.localizedDescription }) {
    self.describe = describe
  }

  func refresh(_ source: any ArchiveDataSource, revision: Int) async {
    guard !Task.isCancelled else { return }
    // A previous view task can be cancelled while its source is still draining.
    // A new waiter needs fresh work even when the archive revision is unchanged.
    if let refreshTask, refreshRevision == revision, !refreshTask.isCancelled {
      await withTaskCancellationHandler {
        await refreshTask.value
      } onCancel: {
        refreshTask.cancel()
      }
      return
    }
    refreshTask?.cancel()
    let request = UUID()
    generation = request
    refreshRevision = revision
    isRefreshing = true
    isLoadingMore = false
    let oldest = plans.last.map { ArchiveCursor(importedAt: $0.importedAt, id: $0.id) }
    let task = Task { await readFirst(source, request: request, through: oldest) }
    refreshTask = task
    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
    if generation == request {
      refreshTask = nil
      isRefreshing = false
    }
  }

  private func readFirst(
    _ source: any ArchiveDataSource, request: UUID, through oldest: ArchiveCursor?
  ) async {
    do {
      var refreshed: [PlanSummary] = []
      var cursor: ArchiveCursor?
      repeat {
        let page = try await source.archivePage(after: cursor, limit: 20)
        guard generation == request, !Task.isCancelled else { return }
        refreshed.append(contentsOf: page.plans)
        cursor = page.next
        guard let oldest, let last = refreshed.last else { break }
        // Refresh through the previous last row, including any newly prepended
        // plans, so an existing scroll anchor never drops merely due to paging.
        if last.importedAt < oldest.importedAt
          || (last.importedAt == oldest.importedAt && last.id >= oldest.id)
        {
          break
        }
      } while cursor != nil
      plans = refreshed
      next = cursor
      loaded = true
      error = nil
    } catch {
      guard generation == request, !Task.isCancelled else { return }
      self.error = describe(error)
    }
  }

  func loadMore(_ source: any ArchiveDataSource) async {
    guard !Task.isCancelled, !isRefreshing, !isLoadingMore, let cursor = next else { return }
    let request = generation
    isLoadingMore = true
    defer { if generation == request { isLoadingMore = false } }
    do {
      let page = try await source.archivePage(after: cursor, limit: 20)
      guard generation == request, !Task.isCancelled else { return }
      let existing = Set(plans.map(\.id))
      plans.append(contentsOf: page.plans.filter { !existing.contains($0.id) })
      next = page.next
      error = nil
    } catch {
      guard generation == request, !Task.isCancelled else { return }
      self.error = describe(error)
    }
  }
}
