import RehaCore

/// Existing in-app help is also the authoritative source for spoken app guidance.
enum AppHelpContent {
  static let capture =
    "Mit Plus einen Plan fotografieren oder Fotos beziehungsweise PDF-Dateien importieren. Mehrseitige Pläne können gemeinsam geprüft werden. Die Erkennung erfolgt lokal auf dem iPhone."
  static let calendars =
    "Die Wochenleiste wählt den Tag. Horizontal wischen blättert zwischen Tagen, vertikal wischen verschiebt die Uhrzeit. Heute springt zum aktuellen Tag. Ganztägige Termine und Zeiten außerhalb von 06:00–18:00 sind gesondert zugänglich. Vorbei bestätigt keine Teilnahme."
  static let voice =
    "Gespräch starten beginnt die lokale Spracherkennung. Sprechpausen beenden eine Äußerung; während der Antwort kann hineingesprochen werden. Gespräch beenden, Tabwechsel und Audio-Unterbrechungen stoppen die Sitzung. Kalenderänderungen erfordern weiterhin eine Bestätigung am Bildschirm."
  static let data =
    "Originale bleiben im Archiv bis zur gewählten Aufbewahrungsfrist oder zum Löschen. Originale löschen entfernt keine Kalendertermine. Kalenderstatus zeigt Zugriffsrechte, Auswahl und ungeklärte Schreibvorgänge. Technische Diagnose bleibt lokal und enthält standardmäßig keine Termininhalte oder Gespräche."
  static func text(for topic: AssistantHelpTopic) -> String {
    switch topic {
    case .capture: capture
    case .calendars: calendars
    case .voice: voice
    case .archive, .privacy: data
    }
  }
}
