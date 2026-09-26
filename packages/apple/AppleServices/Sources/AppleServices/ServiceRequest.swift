import Foundation

/// A shell-independent request envelope. Completion is delivered at most once.
final class ServiceRequest: @unchecked Sendable {
  private let arguments: Data
  var argumentsData: Data { arguments }
  private let lock = NSLock()
  private var completion: (@Sendable (Result<Data, Error>) -> Void)?
  init(arguments: Data, completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
    self.arguments = arguments
    self.completion = completion
  }
  func parseArgs<T: Decodable>(_ type: T.Type) throws -> T {
    try JSONDecoder().decode(type, from: arguments)
  }
  private func finish(_ result: Result<Data, Error>) {
    lock.lock()
    let callback = completion
    completion = nil
    lock.unlock()
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
