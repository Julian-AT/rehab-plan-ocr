import Foundation

@main struct VoiceRulesProbe {
  static func main() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
    let now = ISO8601DateFormatter().date(from: "2026-09-12T10:00:00Z")!
    func parse(_ text: String) -> VoiceIntent {
      VoiceRules.parse(text, now: now, calendar: calendar)
    }
    let times = [
      "halb zehn": 570, "dreiviertel zehn": 585, "viertel zehn": 555, "um neun Uhr": 540,
      "um 09:30": 570, "neun": 540, "um neun nein um zehn": 600, "um drei Uhr nachmittags": 900,
      "um 09:30, ich meine um zehn": 600, "nicht um neun, sondern zehn": 600,
      "um neun nein um zehn nein halb elf": 630,
    ]
    for (text, expected) in times {
      precondition(VoiceRules.time(text) == expected, "Time: \(text)")
    }
    let move = parse("Verschiebe den Termin um neun auf zehn")
    precondition(move.action == .update && move.referenceTime == 540 && move.newTime == 600)
    let correction = parse("Erstelle einen neuen Termin Dienstag, nein Mittwoch um halb zehn")
    precondition(
      correction.corrected && calendar.component(.weekday, from: correction.newDate!) == 4)
    precondition(correction.newTime == 570 && correction.duration == nil)
    precondition(parse("Lösche den Termin nicht").negatedChange)
    precondition(parse("Nein").action != .cancel)
    precondition(parse("ja").action == .unsupported)
    precondition(parse("Morgen Termine vorlesen").action == .list)
    precondition(parse("Wann ist mein nächster Termin").action == .next)
    precondition(parse("Soll ich meine Medikamente ändern?").action != .create)
    precondition(VoiceRules.date("31.02.2026", now: now, calendar: calendar) == nil)
    for invalid in ["31.02.2026", "29.02.2025", "12.09.202", "12.09.20261"] {
      precondition(VoiceRules.hasInvalidDate(invalid, now: now, calendar: calendar), invalid)
    }
    for invalid in [
      "31. Februar", "am einunddreissigsten April", "29. Februar 2025", "0. Mai",
      "12. September 202", "12. September 20261", "32. Januar",
    ] {
      precondition(VoiceRules.hasInvalidDate(invalid, now: now, calendar: calendar), invalid)
      precondition(VoiceRules.date(invalid, now: now, calendar: calendar) == nil, invalid)
    }
    for (input, day, month) in [
      ("am ersten Oktober", 1, 10), ("am 14. September 2026", 14, 9),
      ("am einundzwanzigsten September", 21, 9), ("am fünften März", 5, 3),
      ("am 29. Februar 2028", 29, 2), ("31. Februar, ich meine 14. September", 14, 9),
      ("31. Februar nein morgen nein am 14. September", 14, 9),
      ("nicht morgen, sondern am 14. September", 14, 9),
    ] {
      guard let date = VoiceRules.date(input, now: now, calendar: calendar) else {
        preconditionFailure(input)
      }
      precondition(calendar.component(.day, from: date) == day, input)
      precondition(calendar.component(.month, from: date) == month, input)
      precondition(!VoiceRules.hasInvalidDate(input, now: now, calendar: calendar), input)
    }
    precondition(VoiceRules.date("nicht morgen", now: now, calendar: calendar) == nil)
    precondition(
      VoiceRules.date("am 14. September doch nicht", now: now, calendar: calendar) == nil)
    precondition(VoiceRules.time("nicht um neun") == nil)
    precondition(VoiceRules.time("um neun doch nicht") == nil)
    precondition(VoiceRules.time("um neun nein um 25:00") == nil)
    precondition(VoiceRules.duration("keine dreissig Minuten") == nil)
    precondition(VoiceRules.duration("dreissig Minuten nein zwanzig Minuten") == 20)
    precondition(parse("Erstelle einen Termin morgen um 09:30 ich meine um zehn").corrected)
    for (input, day) in [
      ("morgen nein heute", 12), ("übermorgen nein morgen", 13), ("morgen nein am 14.09.2026", 14),
      ("31.02.2026 nein morgen", 13),
    ] {
      precondition(
        calendar.component(.day, from: VoiceRules.date(input, now: now, calendar: calendar)!)
          == day, input)
      precondition(!VoiceRules.hasInvalidDate(input, now: now, calendar: calendar), input)
    }
    precondition(VoiceRules.date("vormorgen", now: now, calendar: calendar) == nil)
    precondition(VoiceRules.time("25:30") == nil)
    precondition(VoiceRules.time("10:99") == nil)
    precondition(VoiceRules.time("um zehn Uhr dreißig") == 630)
    precondition(VoiceRules.duration("dreißig Minuten") == 30)
    precondition(
      VoiceRules.referenceWords("Lösche meine Physiotherapie morgen") == ["physiotherapie"])
    precondition(
      VoiceRules.referenceWords("Lösche meine Physiotherapie am einundzwanzigsten September")
        == ["physiotherapie"])
    precondition(parse("Termine im Kalender Privat morgen").calendarName == "privat")
    precondition(calendar.component(.day, from: parse("Termine übermorgen").date!) == 14)
    precondition(parse("Habe ich keine Termine?").action == .list)
    precondition(parse("Nicht am Dienstag, am Mittwoch").action != .cancel)
    precondition(parse("Gespräch beenden").action == .cancel)
    precondition(VoiceRules.normalized("  Größe,\tÜBUNG!\n🗓️?  ") == "grösse übung 🗓️")
    precondition(VoiceRules.time("🗓️ um fünf Uhr fünfundvierzig") == 345)
    precondition(VoiceRules.time("um einundzwanzig Uhr zwei") == 1262)
    precondition(VoiceRules.time("um eine Uhr") == 60)
    precondition(VoiceRules.time("um eins Uhr") == 60)
    precondition(VoiceRules.time("um einen Uhr") == nil)
    precondition(VoiceRules.duration("🗓️ neunzig Minuten") == 90)
    precondition(VoiceRules.duration("neunzigminuten") == nil)
    precondition(VoiceRules.matches("[", "ungültig").isEmpty)
    DispatchQueue.concurrentPerform(iterations: 256) { index in
      // Distinct patterns exercise cache saturation while common rules are in use.
      precondition(VoiceRules.matches("^probe\(index)$", "probe\(index)") == [["probe\(index)"]])
      precondition(VoiceRules.time("halb zehn") == 570)
      precondition(VoiceRules.duration("dreißig Minuten") == 30)
      precondition(VoiceRules.normalized("  Nächster Termin!?  ") == "nächster termin")
    }
    print("Voice rules: dates, times, corrections, negations and explicit cancellation passed")
  }
}
