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
    func complete(_ text: String) -> VoiceIntent? {
      VoiceRules.completeMutation(text, now: now, calendar: calendar)
    }
    for text in [
      "Erstelle einen neuen Termin", "Bitte erstellen Sie einen Termin",
      "Bitte einen neuen Termin eintragen", "Neuer Termin",
      "Erstelle einen Termin namens Sanfte Gymnastik morgen um zehn Uhr für 30 Minuten.",
      "Erstelle einen Termin mit dem Titel „Sanfte Bewegung“ am 17.05.2031 um 8 Uhr.",
    ] {
      precondition(complete(text)?.action == .create, text)
    }
    let named = complete(
      "Erstelle einen Termin namens Sanfte Gymnastik morgen um zehn Uhr für 30 Minuten.")!
    precondition(named.title == "Sanfte Gymnastik" && named.newTime == 600 && named.duration == 30)
    precondition(named.newDate == VoiceRules.date("morgen", now: now, calendar: calendar))
    for text in [
      "Verschiebe den zweiten Termin auf morgen um zehn Uhr",
      "Bitte verschieben Sie den Termin um neun Uhr auf zehn",
      "Ändere den Termin", "Verschiebe Physiotherapie heute auf morgen um halb zehn",
      "Verschiebe meine Ergotherapie auf am 17.05.2031 um 8 Uhr für 45 Minuten",
    ] {
      precondition(complete(text)?.action == .update, text)
    }
    for text in [
      "Lösche den zweiten Termin", "Bitte entfernen Sie den Termin heute um 10:00.",
      "Lösche meine Physiotherapie morgen", "Lösche den Termin",
    ] {
      precondition(complete(text)?.action == .remove, text)
    }
    // Partial parse evidence must never claim these whole requests are covered.
    for text in [
      "Bitte Gymnastik am 17.05.2031 um 8 Uhr eintragen.",
      "Erstelle einen Termin namens Gymnastik morgen um acht Uhr im Kalender Privat",
      "Erstelle einen Termin namens Gymnastik morgen um acht Uhr ohne Erinnerung",
      "Erstelle einen Termin namens Gymnastik morgen um acht Uhr und Ergotherapie um zehn Uhr",
      "Erstelle einen Termin namens Gymnastik morgen um acht Uhr nein um neun Uhr",
      "Erstelle einen Termin namens Gymnastik morgen um 25:00",
      "Erstelle einen Termin namens Gymnastik morgen für null Minuten",
      "Erstelle einen Termin namens „Halb zehn“", "Erstelle einen Termin namens „Dienstag“",
      "Erstelle einen Termin namens Gymnastik?", "Erstelle keinen Termin morgen",
      "Verschiebe den ersten oder den zweiten Termin auf morgen um zehn Uhr",
      "Verschiebe den zweiten Termin Physiotherapie auf morgen um zehn Uhr",
      "Verschiebe den Termin auf morgen und lösche den anderen",
      "Verschiebe den Termin auf morgen um zehn Uhr ohne die Dauer zu ändern",
      "Verschiebe den Termin auf morgen und übermorgen",
      "Verschiebe den Termin im Kalender Privat auf morgen",
      "Lösche den Termin für 30 Minuten", "Lösche den anderen Termin", "Lösche beide Termine",
      "Lösche Physiotherapie vor morgen", "Lösche Physiotherapie nach morgen",
      "Lösche Physiotherapie bis morgen", "Lösche Physiotherapie von morgen",
      "Lösche den Termin nicht", "Wie lösche ich den Termin?", "Stopp, lösche den Termin",
    ] {
      precondition(complete(text) == nil, text)
    }
    for (input, title) in [
      ("Nicht löschen. Ändere nur den Namen dieses Termins in Gymnastik.", "Gymnastik"),
      (
        "Bitte nicht entfernen, ändere ausschließlich den Titel dieses Termins auf „Sanfte Gymnastik“.",
        "Sanfte Gymnastik"
      ),
      (
        "Lösche diesen Termin bitte nicht; gib diesem Termin nur den Namen Atemübung.",
        "Atemübung"
      ),
      (
        "Den Termin nicht löschen, sondern benenne diesen Termin nur in Ergotherapie um.",
        "Ergotherapie"
      ),
      (
        "Bitte löschen Sie diesen Termin nicht. Ändern Sie nur den Namen dieses Termins in Spaziergang.",
        "Spaziergang"
      ),
    ] {
      let rename = parse(input)
      precondition(rename.action == .update && !rename.negatedChange, input)
      precondition(rename.title == title && rename.origins["title"] == .spoken, input)
      precondition(rename.date == nil && rename.referenceTime == nil, input)
      precondition(rename.newDate == nil && rename.newTime == nil && rename.duration == nil, input)
      precondition(VoiceRules.explicitMutation(input) == .update, input)
    }
    for input in [
      "Nicht löschen. Ändere den Namen dieses Termins in Gymnastik.",
      "Nicht löschen. Ändere nur den Namen des anderen Termins in Gymnastik.",
      "Nicht löschen. Ändere nur die Namen dieser Termine in Gymnastik.",
      "Nicht löschen. Ändere nur den Namen dieses Termins nicht in Gymnastik.",
      "Nicht löschen. Ändere nur den Namen dieses Termins in Gymnastik und die Uhrzeit auf zehn.",
      "Nicht löschen. Ändere nur den Namen dieses Termins in Gymnastik morgen.",
      "Nicht löschen. Ändere nur den Namen dieses Termins in Gymnastik, nein Atemübung.",
      "Nicht löschen. Ändere nur den Namen dieses Termins in Gymnastik oder Atemübung.",
      "Nicht löschen. Ändere nur den Namen dieses Termins in irgendwas.",
      "Nicht löschen. Ändere nur den Namen dieses Termins in anders.",
      "Nicht löschen. Ändere nur den Namen dieses Termins in neu.",
      "Nicht löschen. Ändere nur den Namen dieses Termins in „Gymnastik morgen“.",
      "Nicht löschen. Ändere nur den Namen dieses Termins in „Gymnastik“. Lösche den zweiten.",
      "Nicht löschen. Ändere nur den Namen dieses Termins in Gymnastik. Abbrechen.",
      "Nicht löschen. Ändere nur den Namen dieses Termins in Gymnastik?",
      "Wenn ich nicht löschen will, ändere nur den Namen dieses Termins in Gymnastik.",
      "Stopp. Nicht löschen. Ändere nur den Namen dieses Termins in Gymnastik.",
    ] {
      let rejected = parse(input)
      precondition(rejected.action != .update && rejected.title == nil, input)
    }
    precondition(parse("Nein").action != .cancel)
    precondition(parse("ja").action == .unsupported)
    precondition(parse("Morgen Termine vorlesen").action == .list)
    precondition(parse("Wann ist mein nächster Termin").action == .next)
    precondition(parse("Soll ich meine Medikamente ändern?").action != .create)
    for question in [
      "Wie lösche ich den Termin?", "Kann ich einen neuen Termin erstellen?",
      "Was passiert, wenn ich den Termin löschen lasse?",
      "Wo kann ich einen Termin ändern?",
    ] {
      precondition(parse(question).action == .unsupported, question)
    }
    for question in [
      "Wann wurde der Termin erstellt?", "Was ist mit dem gelöschten Termin?",
      "Ist der geänderte Termin morgen?", "Wann ist die Terminänderung?",
    ] {
      precondition(![.create, .update, .remove].contains(parse(question).action), question)
    }
    precondition(parse("Lösche den Termin und erstelle einen neuen Termin.").action == .unsupported)
    precondition(VoiceRules.date("31.02.2026", now: now, calendar: calendar) == nil)
    for invalid in ["31.02.2026", "29.02.2025", "12.09.202", "12.09.20261"] {
      precondition(VoiceRules.hasInvalidDate(invalid, now: now, calendar: calendar), invalid)
    }
    for invalid in ["2031-04-31", "2031-02-29", "0000-01-01", "20311-01-01"] {
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
    precondition(parse("Stopp, vergiss die Änderung, lass alles wie es ist.").action == .cancel)
    precondition(
      VoiceRules.date("2032-02-29", now: now, calendar: calendar)
        == Calendar(identifier: .gregorian).date(
          from: DateComponents(timeZone: calendar.timeZone, year: 2032, month: 2, day: 29)))
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
