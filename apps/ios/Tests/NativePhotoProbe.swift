import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main struct NativePhotoProbe {
  static func encode(_ image: CGImage, type: UTType, orientation: Int = 1) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(
      destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
  }
  static func pixels(_ image: CGImage) -> [[UInt8]] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes { buffer in
      let context = CGContext(
        data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return stride(from: 0, to: bytes.count, by: 4).map { Array(bytes[$0..<($0 + 3)]) }
  }
  static func rejects(_ input: Data) {
    do {
      _ = try NativePhoto.decode(input)
      preconditionFailure("Invalid or oversized photo accepted")
    } catch NativeServiceError.invalidInput {} catch {
      preconditionFailure("Wrong photo failure: \(error)")
    }
  }
  static func main() throws {
    let colors: [[UInt8]] = [
      [255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0], [255, 0, 255], [0, 255, 255],
    ]
    let bytes = Data(colors.flatMap { $0 + [255] })
    let image = CGImage(
      width: 3, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 12,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: bytes as CFData)!, decode: nil, shouldInterpolate: false,
      intent: .defaultIntent)!
    let expected = [
      [0, 1, 2, 3, 4, 5], [2, 1, 0, 5, 4, 3], [5, 4, 3, 2, 1, 0], [3, 4, 5, 0, 1, 2],
      [0, 3, 1, 4, 2, 5], [3, 0, 4, 1, 5, 2], [5, 2, 4, 1, 3, 0], [2, 5, 1, 4, 0, 3],
    ]
    for orientation in 1...8 {
      let encoded = encode(image, type: .tiff, orientation: orientation)
      let output = try NativePhoto.decode(encoded)
      let source = CGImageSourceCreateWithData(output as CFData, nil)!
      let result = CGImageSourceCreateImageAtIndex(source, 0, nil)!
      precondition(result.width == (orientation >= 5 ? 2 : 3))
      precondition(result.height == (orientation >= 5 ? 3 : 2))
      precondition(
        pixels(result) == expected[orientation - 1].map { colors[$0] },
        "Orientation \(orientation) changed pixel placement")
      let normalizedAgain = try NativePhoto.decode(output)
      precondition(
        pixels(result)
          == pixels(
            CGImageSourceCreateImageAtIndex(
              CGImageSourceCreateWithData(normalizedAgain as CFData, nil)!, 0, nil)!),
        "Normalized photo rotated a second time")
    }
    let multiImage = try Data(
      contentsOf: URL(
        fileURLWithPath:
          "ml/evaluation/fixtures/heic/multiple-images.heic"))
    let primaryOutput = try NativePhoto.decode(multiImage)
    let primary = CGImageSourceCreateImageAtIndex(
      CGImageSourceCreateWithData(primaryOutput as CFData, nil)!, 0, nil)!
    precondition(primary.width == 32 && primary.height == 48)
    let middle = pixels(primary)[24 * 32 + 16]
    precondition(
      middle[2] > 220 && middle[0] < 40 && middle[1] < 40,
      "HEIF primary photo must be selected rather than image zero")
    rejects(Data())
    rejects(Data("corrupt photo".utf8))
    rejects(Data(repeating: 0, count: NativePhoto.maximumBytes + 1))
    // A small PNG whose header claims >50M pixels must fail before pixel decoding.
    var oversized = encode(image, type: .png)
    let width = UInt32(NativePhoto.maximumPixels + 1)
    for index in 0..<4 {
      oversized[16 + index] = UInt8(truncatingIfNeeded: width >> ((3 - index) * 8))
      oversized[20 + index] = index == 3 ? 1 : 0
    }
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in oversized[12..<29] {
      crc ^= UInt32(byte)
      for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB8_8320 : 0) }
    }
    crc ^= 0xFFFF_FFFF
    for index in 0..<4 {
      oversized[29 + index] = UInt8(truncatingIfNeeded: crc >> ((3 - index) * 8))
    }
    rejects(oversized)
    print(
      "Binary photo: eight orientations, HEIF primary photo, normalization, malformed input and byte/pixel limits passed"
    )
  }
}
