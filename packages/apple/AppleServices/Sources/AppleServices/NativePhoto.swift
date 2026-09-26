import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Binary decoder shared by the native callback and the compatibility JSON API.
/// Inspect encoded dimensions before requesting any full-size pixel allocation.
public enum NativePhoto {
  static let maximumBytes = 40 * 1024 * 1024
  static let maximumPixels = 50_000_000

  public static func decode(_ bytes: Data) throws -> Data {
    guard !bytes.isEmpty, bytes.count <= maximumBytes,
      let source = CGImageSourceCreateWithData(
        bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { throw NativeServiceError.invalidInput("Foto nicht lesbar oder zu groß.") }
    let index = CGImageSourceGetPrimaryImageIndex(source)
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= maximumPixels / height
    else { throw NativeServiceError.invalidInput("Foto nicht lesbar oder zu groß.") }
    guard
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, index,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: max(width, height),
          kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    else { throw NativeServiceError.invalidInput("Foto konnte nicht dekodiert werden.") }
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output, UTType.png.identifier as CFString, 1, nil)
    else { throw NativeServiceError.storage("PNG-Ausgabe konnte nicht erstellt werden.") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw NativeServiceError.storage("Foto konnte nicht als PNG gespeichert werden.")
    }
    return output as Data
  }
}
