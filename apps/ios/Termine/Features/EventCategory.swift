import Foundation

enum EventCategory: String, CaseIterable {
  case therapy, medical, meal, organization, other
  // Zitrus & Olive, selected from docs/preview/termin-farbpaletten.html at 32%.
  // Dark accents match the preview's 16% white mix; fills remain transparent.
  static let surfaceOpacity = (light: 0.32, dark: 0.36)
  var rgb: UInt32 {
    switch self {
    case .therapy: 0x85A832
    case .medical: 0x41A58B
    case .meal: 0xEABC21
    case .organization: 0xE8883F
    case .other: 0xC97086
    }
  }
  var darkRGB: UInt32 {
    switch self {
    case .therapy: 0x99B653
    case .medical: 0x5FB39E
    case .meal: 0xEDC745
    case .organization: 0xEC9B5E
    case .other: 0xD28799
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
    func color(in scheme: ColorScheme) -> Color {
      color(scheme == .dark ? darkRGB : rgb)
    }
    func surface(in scheme: ColorScheme) -> Color {
      color(in: scheme).opacity(
        scheme == .dark ? Self.surfaceOpacity.dark : Self.surfaceOpacity.light)
    }
    func secondaryText(in scheme: ColorScheme) -> Color {
      // Includes elevated grouped backgrounds used by sheets and the day list.
      color(scheme == .dark ? 0xECECEC : 0x3B3B3B)
    }
  }
#endif
