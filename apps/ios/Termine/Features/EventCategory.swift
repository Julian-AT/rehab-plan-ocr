import Foundation

enum EventCategory: String, CaseIterable {
  case therapy, medical, meal, organization, other
  // Exact Greens-7 swatches supplied by the user, in category order.
  // Keep these surfaces in both appearances; text contrast follows the swatch.
  var palette: (surface: UInt32, text: UInt32) {
    switch self {
    case .therapy: (0xA1D99B, 0x000000)
    case .medical: (0x74C476, 0x000000)
    case .meal: (0x41AB5D, 0x000000)
    case .organization: (0x238B45, 0x000000)
    case .other: (0x005A32, 0xFFFFFF)
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
    var color: Color { color(palette.surface) }
    var surface: Color { color }
    var text: Color { color(palette.text) }
  }
#endif
