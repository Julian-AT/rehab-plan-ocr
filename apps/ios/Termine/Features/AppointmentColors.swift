import Foundation

/// Presentation-only preferences. No core writes, calendar access or reminder work.
struct AppointmentColors: Codable, Equatable {
  static let storageKey = "agenda.colors.v1"
  var version = 1
  var strength = 0.35
  var colors: [String: UInt32] = [:]
  init(rawValue: String = "") {
    if let data = rawValue.data(using: .utf8),
      let decoded = try? JSONDecoder().decode(Self.self, from: data), decoded.version == 1
    {
      self = decoded
      strength = strength.isFinite ? min(0.7, max(0.1, strength)) : 0.35
      colors = colors.filter { $0.value <= 0xFFFFFF }
    }
  }
  var rawValue: String { String(decoding: try! JSONEncoder().encode(self), as: UTF8.self) }
  func rgb(_ category: EventCategory) -> UInt32 {
    if let custom = colors[category.rawValue] { return custom }
    switch category {
    case .therapy: return 0x009640
    case .medical: return 0x007AFF
    case .meal: return 0xFF9500
    case .organization: return 0xAF52DE
    case .other: return 0x8E8E93
    }
  }
  func surface(_ category: EventCategory, dark: Bool) -> [Double] {
    let rgb = rgb(category)
    let background = dark ? 0.0 : 1.0
    return [16, 8, 0].map {
      Double((rgb >> $0) & 255) / 255 * strength + background * (1 - strength)
    }
  }
  static func luminance(_ components: [Double]) -> Double {
    let linear = components.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
    return zip(linear, [0.2126, 0.7152, 0.0722]).reduce(0) { $0 + $1.0 * $1.1 }
  }
  func usesWhiteText(_ category: EventCategory, dark: Bool) -> Bool {
    let light = Self.luminance(surface(category, dark: dark))
    return 1.05 / (light + 0.05) > (light + 0.05) / 0.05
  }
}

#if canImport(UIKit)
  import SwiftUI
  import UIKit

  extension AppointmentColors {
    func color(_ category: EventCategory) -> Color {
      let rgb = rgb(category)
      return Color(
        red: Double((rgb >> 16) & 255) / 255,
        green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
    mutating func setColor(_ color: Color, for category: EventCategory) {
      var r: CGFloat = 0
      var g: CGFloat = 0
      var b: CGFloat = 0
      var a: CGFloat = 0
      guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a),
        [r, g, b].allSatisfy(\.isFinite)
      else { return }
      let channels = [r, g, b].map { UInt32((min(1, max(0, $0)) * 255).rounded()) }
      colors[category.rawValue] = (channels[0] << 16) | (channels[1] << 8) | channels[2]
    }
    func palette(for category: EventCategory, dark: Bool) -> (surface: Color, text: Color) {
      let rgb = surface(category, dark: dark)
      return (
        Color(red: rgb[0], green: rgb[1], blue: rgb[2]),
        usesWhiteText(category, dark: dark) ? .white : .black
      )
    }
  }

  struct AppointmentColorsView: View {
    @SwiftUI.AppStorage(AppointmentColors.storageKey) private var raw = ""
    @Environment(\.colorScheme) private var scheme
    private var settings: AppointmentColors { AppointmentColors(rawValue: raw) }
    var body: some View {
      Form {
        Section {
          ForEach(EventCategory.allCases, id: \.rawValue) { category in
            ColorPicker(
              category.title,
              selection: Binding(
                get: { settings.color(category) },
                set: { color in
                  var next = settings
                  next.setColor(color, for: category)
                  raw = next.rawValue
                }
              ), supportsOpacity: false
            ).frame(minHeight: 44)
          }
        }
        Section {
          HStack {
            LabeledContent(
              "Farbstärke",
              value: settings.strength.formatted(.percent.precision(.fractionLength(0))))
            ContextHelp(
              "Farbstärke",
              "Die Terminflächen mischen deine Farben deckend mit dem Hintergrund. Die Schrift bleibt schwarz oder weiß und gut lesbar."
            )
          }
          Slider(
            value: Binding(
              get: { settings.strength },
              set: {
                var next = settings
                next.strength = $0
                raw = next.rawValue
              }), in: 0.1...0.7, step: 0.01
          ) { Text("Farbstärke") }
          .frame(minHeight: 44).accessibilityIdentifier("appointment-color-strength")
        }
        Section("Vorschau und Legende") {
          ForEach(EventCategory.allCases, id: \.rawValue) { category in
            let palette = settings.palette(for: category, dark: scheme == .dark)
            VStack(alignment: .leading, spacing: 4) {
              Text(category.title).font(.headline)
              Text("09:00–09:30").font(.subheadline).monospacedDigit()
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
              .foregroundStyle(palette.text).background(palette.surface, in: .rect(cornerRadius: 8))
          }
        }
        Button("Zurücksetzen") { raw = "" }.frame(minHeight: 44)
          .accessibilityIdentifier("reset-appointment-colors")
      }.pageTitle("Terminfarben")
    }
  }
#endif
