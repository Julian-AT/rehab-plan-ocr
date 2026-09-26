import Foundation
import os

enum AgendaError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    if case .message(let message) = self { return message }
    return nil
  }
}

/// A shell-independent request envelope. Completion is delivered at most once.
final class ServiceRequest: Sendable {
  private typealias Completion = @Sendable (Result<Data, Error>) -> Void
  private let arguments: Data
  var argumentsData: Data { arguments }
  private let completion: OSAllocatedUnfairLock<Completion?>
  init(arguments: Data, completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
    self.arguments = arguments
    self.completion = OSAllocatedUnfairLock(initialState: completion)
  }
  func parseArgs<T: Decodable>(_ type: T.Type) throws -> T {
    try JSONDecoder().decode(type, from: arguments)
  }
  private func finish(_ result: Result<Data, Error>) {
    let callback = completion.withLock { value in
      defer { value = nil }
      return value
    }
    // Execute outside the lock: a client may synchronously re-enter this request.
    callback?(result)
  }
  func resolve() { finish(.success(Data("null".utf8))) }
  func resolve(_ value: [String: Any]) {
    do { finish(.success(try JSONSerialization.data(withJSONObject: value))) } catch {
      finish(.failure(error))
    }
  }
  func reject(_ message: String) { finish(.failure(AgendaError.message(message))) }
}
