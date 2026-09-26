import Foundation

enum EventCategory: String, CaseIterable {
    case therapy, medical, meal, organization, other
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
        let text = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_AT"))
        let rules: [(Self, String)] = [
            (.medical, #"\b(visite|arztgesprach|arzttermin|arztliche\s+untersuchung|arztliches\s+gesprach|blutabnahme|ekg|laboruntersuchung)\b"#),
            (.meal, #"\b(fruhstuck|mittagessen|abendessen|jause)\b"#),
            (.therapy, #"\b(physiotherapie|ergotherapie|logopadie|psychotherapie|therapie|einzeltherapie|gruppentherapie|ruckengymnastik|fruhgymnastik|heilgymnastik|gangschule|massage|lymphdrainage|bewegungstherapie|wassertherapie|behandlung)\b"#),
            (.organization, #"\b(aufnahme|anmeldung|entlassung|planung|organisatorisches|information|einfuhrung)\b"#)
        ]
        let matches = rules.filter { text.range(of: $0.1, options: .regularExpression) != nil }
        return matches.count == 1 ? matches[0].0 : .other
    }
}
#if canImport(SwiftUI)
import SwiftUI
extension EventCategory {
    var color: Color {
        switch self { case .therapy: .green; case .medical: .blue; case .meal: .orange; case .organization: .purple; case .other: .gray }
    }
}
#endif
