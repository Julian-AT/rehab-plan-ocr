import Foundation

enum EventCategory: String, CaseIterable {
  case therapy, medical, meal, organization, other
  var palette: (lightAccent: UInt32, darkAccent: UInt32, lightSurface: UInt32, darkSurface: UInt32)
  {
    switch self {
    case .therapy: (0x4D7C68, 0x8EB49E, 0xE8EFE9, 0x1E3028)
    case .medical: (0x5C7892, 0x95AFCA, 0xE8EEF3, 0x202C37)
    case .meal: (0x9A7A47, 0xCBB17D, 0xF3EBDD, 0x342C20)
    case .organization: (0x857095, 0xB8A2C8, 0xEEE8F2, 0x2E2635)
    case .other: (0x77817D, 0xA3ADA8, 0xEBEDEA, 0x272C2B)
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
#if canImport(UIKit)
  import SwiftUI
  import UIKit
  extension EventCategory {
    private func adaptive(light: UInt32, dark: UInt32) -> Color {
      Color(
        uiColor: UIColor { traits in
          let rgb = traits.userInterfaceStyle == .dark ? dark : light
          return UIColor(
            red: CGFloat((rgb >> 16) & 255) / 255,
            green: CGFloat((rgb >> 8) & 255) / 255,
            blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }
    var color: Color { adaptive(light: palette.lightAccent, dark: palette.darkAccent) }
    var surface: Color { adaptive(light: palette.lightSurface, dark: palette.darkSurface) }
  }
#endif
