import Darwin
import Foundation
import SwiftUI

struct ArtifactThumbnailRequest: Equatable {
  let page: String?
  let refresh: Int
  let processing: Bool
}

/// File metadata identifies a rewritten artifact without reading or hashing its
/// image bytes. Nanosecond timestamps also cover writes to the same inode.
private struct ArtifactThumbnailRevision: Hashable, Sendable {
  let url: URL
  let device: Int32
  let inode: UInt64
  let size: Int64
  let modified: Int
  let modifiedNanoseconds: Int
  let changed: Int
  let changedNanoseconds: Int

  @concurrent static func read(_ url: URL) async throws -> Self {
    try Task.checkCancellation()
    var value = stat()
    guard stat(url.path, &value) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    try Task.checkCancellation()
    return Self(
      url: url, device: value.st_dev, inode: value.st_ino, size: value.st_size,
      modified: value.st_mtimespec.tv_sec, modifiedNanoseconds: value.st_mtimespec.tv_nsec,
      changed: value.st_ctimespec.tv_sec, changedNanoseconds: value.st_ctimespec.tv_nsec)
  }
}

/// The mounted row retains its identity while source discovery and decoding use
/// different task keys: a refresh checks metadata; only new image bytes decode.
struct ArtifactThumbnail<Value, Content: View>: View {
  let request: ArtifactThumbnailRequest
  let locate: @MainActor (String) async throws -> URL
  let load: @MainActor (URL) async throws -> Value
  @ViewBuilder let content: (Value?) -> Content
  @State private var artifact: ArtifactThumbnailRevision?
  @State private var value: Value?

  var body: some View {
    content(value)
      .task(id: request) {
        do {
          let next: ArtifactThumbnailRevision?
          if let page = request.page {
            let url = try await locate(page)
            next = try await ArtifactThumbnailRevision.read(url)
          } else {
            next = nil
          }
          try Task.checkCancellation()
          if next?.url != artifact?.url { value = nil }
          artifact = next
        } catch {
          guard !Task.isCancelled else { return }
          artifact = nil
          value = nil
        }
      }
      .task(id: artifact) {
        guard let requested = artifact else { return }
        do {
          let loaded = try await load(requested.url)
          try Task.checkCancellation()
          guard artifact == requested else { return }
          value = loaded
        } catch {
          guard !Task.isCancelled, artifact == requested else { return }
          value = nil
        }
      }
  }
}
