import Foundation

@main struct RulesBenchmark {
  static func main() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
    let now = ISO8601DateFormatter().date(from: "2026-09-12T10:00:00Z")!
    let corpus = [
      "Wann ist mein nächster Termin?", "Morgen Termine vorlesen", "Habe ich keine Termine?",
      "Verschiebe den Termin um neun auf zehn",
      "Erstelle einen neuen Termin Dienstag, nein Mittwoch um halb zehn",
      "Lösche den Termin nicht", "Soll ich meine Medikamente ändern?",
      "Termine im Kalender Privat morgen",
      "Erstelle eine Übung übermorgen um drei Uhr nachmittags für dreißig Minuten",
      "Nicht am Dienstag, am Mittwoch", "Erstelle eine Übung am 31.02.2026 um 10:99",
      "Gespräch beenden",
    ]
    func signature(_ text: String) -> String {
      let value = VoiceRules.parse(text, now: now, calendar: calendar)
      let fields: [String: Any] = [
        "action": value.action.rawValue, "negated": value.negatedChange,
        "origins": value.origins.mapValues(\.rawValue), "reference": value.referenceText,
        "calendar": value.calendarName ?? "", "referenceTime": value.referenceTime ?? -1,
        "date": value.date?.timeIntervalSince1970 ?? -1,
        "newDate": value.newDate?.timeIntervalSince1970 ?? -1,
        "newTime": value.newTime ?? -1, "duration": value.duration ?? -1,
        "title": value.title ?? "", "corrected": value.corrected,
        "referenceWords": VoiceRules.referenceWords(text),
      ]
      return String(
        decoding: try! JSONSerialization.data(withJSONObject: fields, options: .sortedKeys),
        as: UTF8.self)
    }
    let firstStart = ContinuousClock.now
    let first = signature(corpus[0])
    let firstDuration = firstStart.duration(to: .now).components
    let cold = Double(firstDuration.seconds) * 1000 + Double(firstDuration.attoseconds) / 1e15
    let words = [
      "ein", "eins", "eine", "einen", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht",
      "neun", "zehn", "elf", "zwölf", "dreizehn", "vierzehn", "fünfzehn", "sechzehn", "siebzehn",
      "achtzehn", "neunzehn", "zwanzig", "einundzwanzig", "zweiundzwanzig", "dreiundzwanzig",
      "dreißig", "vierzig", "fünfundvierzig", "fünfzig", "sechzig", "neunzig",
    ]
    let numberCases = words.flatMap { word in
      [
        "Erstelle eine Übung um \(word) Uhr", "Erstelle eine Übung um zehn Uhr \(word)",
        "Erstelle eine Übung für \(word) Minuten", "🗓️ Übung um \(word) Uhr!",
        "Übung \(word)minuten",
      ]
    }
    let cases =
      corpus + numberCases + [
        "", "  Größe,\tÜBUNG!\n🗓️?  ", "Erstelle Übung um sieben nein um acht für neunzig Minuten",
      ]
    let signatures = Dictionary(uniqueKeysWithValues: cases.map { ($0, signature($0)) })
    var count = first.count
    var measurements: [Double] = []
    for _ in 0..<30 {
      let start = ContinuousClock.now
      for _ in 0..<10 {
        for text in corpus {
          count += signature(text).count
        }
      }
      let d = start.duration(to: .now).components
      measurements.append((Double(d.seconds) * 1000 + Double(d.attoseconds) / 1e15) / 120)
    }
    let result: [String: Any] = [
      "cold_ms": cold, "warm_ms_per_question": measurements, "signatures": signatures,
      "checksum": count,
    ]
    print(
      String(
        decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
        as: UTF8.self))
  }
}
