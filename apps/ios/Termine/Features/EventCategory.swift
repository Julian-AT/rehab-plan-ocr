import Foundation

enum EventCategory: String, CaseIterable {
  case therapy, medical, meal, organization, other
  // Original Greens-7 swatches remain visible in the narrow accents and legend.
  // Card fills use transparency so the native background stays visible.
  static let surfaceOpacity = (light: 0.18, dark: 0.22)
  var rgb: UInt32 {
    switch self {
    case .therapy: 0xA1D99B
    case .medical: 0x74C476
    case .meal: 0x41AB5D
    case .organization: 0x238B45
    case .other: 0x005A32
    }
  }
  var title: String {
    switch self {
    case .therapy: "Therapie"
    case .medical: "Ärztliche Termine"
    case .meal: "Mahlzeiten"
    case .organization: "Organisatorische Termine"
    case .other: "Sonstige Termine"
    }
  }
  static func classify(_ title: String) -> Self {
    let text = title.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_AT"))
    let rules: [(Self, String)] = [
      (
        .medical,
        #"\b(visite|arztgesprach|arzttermin|arztliche\s+untersuchung|arztliches\s+gesprach|blutabnahme|ekg|laboruntersuchung)\b"#
      ),
      (.meal, #"\b(fruhstuck|mittagessen|abendessen|jause)\b"#),
      (
        .therapy,
        #"\b(physiotherapie|ergotherapie|logopadie|psychotherapie|therapie|einzeltherapie|gruppentherapie|ruckengymnastik|fruhgymnastik|heilgymnastik|atemgymnastik|funktionstraining|heilmassage|fussreflexzonenmassage|ergo\s+kreativgruppe|gangschule|massage|lymphdrainage|bewegungstherapie|wassertherapie|behandlung)\b"#
      ),
      (
        .organization,
        #"\b(aufnahme|anmeldung|entlassung|planung|organisatorisches|information|einfuhrung)\b"#
      ),
    ]
    let matches = rules.filter { text.range(of: $0.1, options: .regularExpression) != nil }
    return matches.count == 1 ? matches[0].0 : .other
  }
}
#if canImport(SwiftUI)
  import SwiftUI
  extension EventCategory {
    private func color(_ rgb: UInt32) -> Color {
      Color(
        .sRGB,
        red: Double((rgb >> 16) & 255) / 255,
        green: Double((rgb >> 8) & 255) / 255,
        blue: Double(rgb & 255) / 255, opacity: 1)
    }
    var color: Color { color(rgb) }
    func surface(in scheme: ColorScheme) -> Color {
      color.opacity(scheme == .dark ? Self.surfaceOpacity.dark : Self.surfaceOpacity.light)
    }
    func secondaryText(in scheme: ColorScheme) -> Color {
      // Includes elevated grouped backgrounds used by sheets and the day list.
      Color(.sRGB, white: scheme == .dark ? 0.78 : 0.30, opacity: 1)
    }
  }
#endif
