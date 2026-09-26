import Foundation

/// Only the current turn is held in memory. Reference time and requested new time
/// are deliberately separate; a model suggestion never becomes a calendar ID.
struct VoiceIntent: Equatable {
    var negatedChange = false
    enum Origin: String { case spoken, corrected, context, choice }
    var origins: [String: Origin] = [:]
    enum Action: String { case next, list, create, update, remove, cancel, unsupported }
    var action: Action = .unsupported
    var referenceText = ""
    var calendarName: String?
    var referenceTime: Int?
    var date: Date?
    var newDate: Date?
    var newTime: Int?
    var duration: Int?
    var title: String?
    var corrected = false
}
enum VoiceRules {
    static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "[,!?]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { let r = match.range(at: $0); return r.location == NSNotFound ? "" : ns.substring(with: r) }
        }
    }
    static func date(_ text: String, now: Date, calendar: Calendar) -> Date? {
        let text = normalized(text); let today = calendar.startOfDay(for: now)
        if text.contains("übermorgen") { return calendar.date(byAdding: .day, value: 2, to: today) }
        if text.contains("morgen") { return calendar.date(byAdding: .day, value: 1, to: today) }
        if text.contains("heute") { return today }
        if let value = matches("\\b(\\d{1,2})[./](\\d{1,2})[./](\\d{4})?", text).last,
           let day = Int(value[1]), let month = Int(value[2]) {
            let year = Int(value[3]) ?? calendar.component(.year, from: now)
            let components = DateComponents(year: year, month: month, day: day)
            guard let date = calendar.date(from: components), calendar.component(.day, from: date) == day, calendar.component(.month, from: date) == month else { return nil }
            return date
        }
        let days = ["sonntag":1,"montag":2,"dienstag":3,"mittwoch":4,"donnerstag":5,"freitag":6,"samstag":7]
        // Last named weekday wins after an explicit self-correction.
        let found = matches("\\b(sonntag|montag|dienstag|mittwoch|donnerstag|freitag|samstag)\\b", text)
        if let day = found.last.flatMap({ days[$0[1]] }) {
            var offset = (day - calendar.component(.weekday, from: today) + 7) % 7
            if text.contains("nächsten") && offset == 0 { offset = 7 }
            return calendar.date(byAdding: .day, value: offset, to: today)
        }
        return nil
    }
    static func time(_ text: String) -> Int? {
        var text = normalized(text)
        if let correction = text.range(of: " nein ", options: .backwards) { text = String(text[correction.upperBound...]) }
        let numbers = ["ein":1,"eins":1,"eine":1,"zwei":2,"drei":3,"vier":4,"fünf":5,"sechs":6,"sieben":7,"acht":8,"neun":9,"zehn":10,"elf":11,"zwölf":12,"dreizehn":13,"vierzehn":14,"fünfzehn":15,"sechzehn":16,"siebzehn":17,"achtzehn":18,"neunzehn":19,"zwanzig":20,"einundzwanzig":21,"zweiundzwanzig":22,"dreiundzwanzig":23,"dreissig":30,"vierzig":40,"fünfundvierzig":45,"fünfzig":50]
        for (word, number) in numbers { text = text.replacingOccurrences(of: "\\b\(word)\\b", with: String(number), options: .regularExpression) }
        var minutes: Int?
        if let m = matches("\\b(dreiviertel|halb|viertel) (\\d{1,2})\\b", text).last, let hour = Int(m[2]), (1...24).contains(hour) {
            minutes = (hour-1)*60 + (m[1] == "halb" ? 30 : m[1] == "dreiviertel" ? 45 : 15)
        } else if let m = matches("\\b(\\d{1,2}):(\\d{2})\\b", text).last, let h = Int(m[1]), let min = Int(m[2]), h<24, min<60 { minutes = h*60+min }
        else if let m = matches("(?:\\bum |\\bauf |^)(\\d{1,2})(?: uhr(?: (\\d{1,2}))?\\b|$)", text).last, let h = Int(m[1]), h<24, (Int(m[2]) ?? 0)<60 { minutes = h*60 + (Int(m[2]) ?? 0) }
        if let value = minutes, value < 12*60, text.contains("nachmittag") || text.contains("abends") { minutes = value + 12*60 }
        return minutes
    }
    static func duration(_ text: String) -> Int? {
        var input = normalized(text)
        for (word, value) in ["fünf":5,"zehn":10,"fünfzehn":15,"zwanzig":20,"dreissig":30,"fünfundvierzig":45,"sechzig":60,"neunzig":90] {
            input = input.replacingOccurrences(of: "\\b\(word)\\b", with: String(value), options: .regularExpression)
        }
        if let match = matches("\\b(\\d{1,3}) minuten\\b", input).last, let value = Int(match[1]), value > 0 { return value }
        return nil
    }
    static func referenceWords(_ input: String) -> [String] {
        let clean = normalized(input).replacingOccurrences(of: "(?:im|in|aus|vom) kalender .+?(?= am | um | heute| morgen|$)", with: "", options: .regularExpression)
        let ignored = Set("verschiebe verschieben ändere ändern lösche löschen entferne entfernen den der die das dem meinen mein meine meiner mir bitte termin termine behandlung um am auf von nach vor bis uhr heute morgen übermorgen nächste nächsten nächster ist wann zeige finde habe ich mich dienstag montag mittwoch donnerstag freitag samstag sonntag halb viertel dreiviertel nein keine keinen kein nicht neun zehn eins ein zwei drei vier fünf sechs sieben acht elf zwölf".split(separator: " ").map(String.init))
        return matches("[a-zäöü]+", clean).map { $0[0] }.filter { !ignored.contains($0) }
    }
    static func parse(_ input: String, now: Date = .now, calendar: Calendar = .current) -> VoiceIntent {
        let text = normalized(input); var result = VoiceIntent(); result.corrected = text.contains("nein")
        if let named = matches("(?:im|in|aus|vom) kalender (.+?)(?: am | um | auf | heute| morgen|$)", text).last { result.calendarName = named[1] }
        if !matches("\\b(medikamente|medikament|dosis|diagnose|schmerzen)\\b", text).isEmpty { return result }
        if ["stopp", "abbrechen", "gespräch beenden", "gesprach beenden", "gespräch abbrechen"].contains(text.trimmingCharacters(in: .punctuationCharacters)) { result.action = .cancel; return result }
        if matches("\\b(nicht|keine|keinen|kein)\\b", text).count > 0 && ["lösch", "entfern", "verschieb", "änder", "erstell", "eintragen"].contains(where: text.contains) { result.negatedChange = true; return result }

        if text.contains("lösch") || text.contains("entfern") { result.action = .remove }
        else if text.contains("verschieb") || text.contains("änder") { result.action = .update }
        else if text.contains("erstell") || text.contains("eintragen") || text.contains("neuen termin") || text.contains("neuer termin") || text.contains("hinzufügen") { result.action = .create }
        else if text.contains("nächst") && (text.contains("termin") || text.contains("wann")) { result.action = .next }
        else if text.contains("termin") || text.contains("wann") || text.contains("vorlesen") { result.action = .list }
        if result.action == .update, let split = text.range(of: " auf ") {
            result.referenceText = String(text[..<split.lowerBound]); let target = String(text[split.upperBound...])
            result.referenceTime = time(result.referenceText); result.date = date(result.referenceText, now: now, calendar: calendar)
            result.newDate = date(target, now: now, calendar: calendar); result.newTime = time(target)
        } else {
            result.referenceText = text; result.date = date(text, now: now, calendar: calendar)
            if result.action == .create { result.newDate = result.date; result.newTime = time(text) }
            else { result.referenceTime = time(text) }
        }
        result.duration = duration(text)
        if result.date != nil { result.origins["reference_date"] = result.corrected ? .corrected : .spoken }
        if result.referenceTime != nil { result.origins["reference_time"] = .spoken }
        if result.newDate != nil { result.origins["new_date"] = result.corrected ? .corrected : .spoken }
        if result.newTime != nil { result.origins["new_time"] = result.corrected ? .corrected : .spoken }
        if result.duration != nil { result.origins["duration"] = .spoken }
        return result
    }
}
