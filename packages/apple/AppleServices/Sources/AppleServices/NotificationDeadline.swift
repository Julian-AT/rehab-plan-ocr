import Foundation

/// The owner queue serializes all job state. Cancellation is advisory: expired
/// operations retain their bounded slot until the adapter actually returns.
/// Repeated retries cannot accumulate an unbounded number of suspended tasks.
final class NotificationDeadline: @unchecked Sendable {
  private struct Job {
    let task: Task<Void, Never>
    let timeout: DispatchWorkItem
    let expire: @Sendable () -> Void
    var expired = false
  }
  private let queue: DispatchQueue
  private let seconds: TimeInterval
  private let maximumOperations: Int
  private var jobs: [UUID: Job] = [:]
  init(queue: DispatchQueue, seconds: TimeInterval, maximumOperations: Int = 4) {
    precondition(maximumOperations > 0 && seconds > 0 && seconds.isFinite)
    self.queue = queue
    self.seconds = seconds
    self.maximumOperations = maximumOperations
  }
  func run<Value: Sendable>(
    operation: @escaping @Sendable () async throws -> Value,
    late: (@Sendable (Result<Value, Error>) -> Void)? = nil,
    completion: @escaping @Sendable (Result<Value, Error>) -> Void
  ) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard jobs.count < maximumOperations else {
      completion(
        .failure(
          AgendaError.message(
            "Der Mitteilungsdienst bearbeitet noch frühere Aufträge. Die Kalenderreserve bleibt erhalten. Bitte später erneut versuchen."
          )))
      return
    }
    let id = UUID()
    let timeout = DispatchWorkItem { [weak self] in
      guard let self, var job = self.jobs[id], !job.expired else { return }
      job.expired = true
      self.jobs[id] = job
      job.task.cancel()
      job.expire()
    }
    // A cancelled queued work item can live until its deadline. Keep the client
    // callback in the active job so removing a completed job releases its owner.
    let expire: @Sendable () -> Void = {
      completion(
        .failure(
          AgendaError.message(
            "Mitteilungsdienst antwortet nicht rechtzeitig. Kalenderreserve bleibt erhalten; erneutes Aktualisieren ist möglich."
          )))
    }
    let task = Task {
      let result: Result<Value, Error>
      do { result = .success(try await operation()) } catch { result = .failure(error) }
      self.queue.async {
        guard let job = self.jobs.removeValue(forKey: id) else { return }
        if job.expired {
          late?(result)
          return
        }
        job.timeout.cancel()
        completion(result)
      }
    }
    jobs[id] = Job(task: task, timeout: timeout, expire: expire)
    queue.asyncAfter(deadline: .now() + seconds, execute: timeout)
  }
}
