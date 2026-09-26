import Foundation

/// A callback that never arrives cannot retain the reconciliation state forever.
/// Cancellation is advisory: late results are handled separately on the owner queue.
final class NotificationDeadline: @unchecked Sendable {
    private struct Job { let task: Task<Void, Never>; let timeout: DispatchWorkItem }
    private let queue: DispatchQueue
    private let seconds: TimeInterval
    private var jobs: [UUID: Job] = [:]
    init(queue: DispatchQueue, seconds: TimeInterval) { self.queue = queue; self.seconds = seconds }
    func run<Value: Sendable>(operation: @escaping @Sendable () async throws -> Value,
                    late: (@Sendable (Result<Value, Error>) -> Void)? = nil,
                    completion: @escaping @Sendable (Result<Value, Error>) -> Void) {
        let id = UUID()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, let job = self.jobs.removeValue(forKey: id) else { return }
            job.task.cancel()
            completion(.failure(AgendaError.message("Mitteilungsdienst antwortet nicht rechtzeitig. Kalenderreserve bleibt erhalten; erneutes Aktualisieren ist möglich.")))
        }
        let task = Task {
            let result: Result<Value, Error>
            do { result = .success(try await operation()) } catch { result = .failure(error) }
            self.queue.async {
                guard let job = self.jobs.removeValue(forKey: id) else { late?(result); return }
                job.timeout.cancel()
                completion(result)
            }
        }
        jobs[id] = Job(task: task, timeout: timeout)
        queue.asyncAfter(deadline: .now() + seconds, execute: timeout)
    }
}
