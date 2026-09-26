#if DEBUG && targetEnvironment(simulator)
import Foundation
import RehaCore

@MainActor enum CalendarToolProbe {
    static func run(_ core: NativeApplication, day: Date) async throws {
        let store = CalendarConversation(core: core), token = UUID()
        await store.begin(token)
        func object(_ text: String) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        }
        func require(_ test: Bool, _ name: String) throws {
            guard test else { throw LocalSpeechError.message("Werkzeugprüfung fehlgeschlagen: " + name) }
        }
        let first = try object(await store.query(date: CalendarConversation.day(day), days: 1, offset: 0, token: token))
        try require(first["total"] as? Int == 12 && first["has_more"] as? Bool == true, "pagination")
        let events = first["events"] as! [[String: Any]]
        try require(events.count == 10 && events[1]["title"] as? String == "Prüftermin 2", "order")
        let detail = try object(await store.detail(reference: "", ordinal: 2, token: token))
        try require(detail["therapist"] as? String == "Therapeut: Anna Beispiel" && detail["location"] as? String != nil, "verified detail")
        let badOrdinal = try object(await store.detail(reference: "", ordinal: Int.min, token: token))
        try require(badOrdinal["error"] != nil, "invalid ordinal")
        let invalid = try object(await store.query(date: "2026-02-31", days: 1, offset: 0, token: token))
        try require(invalid["error"] != nil, "invalid date")
        let second = try object(await store.query(date: CalendarConversation.day(day), days: 1, offset: 10, token: token))
        try require((second["events"] as? [[String: Any]])?.count == 2 && second["has_more"] as? Bool == false, "last page")
        let reference = events[1]["reference"] as! String
        let proposal = CalendarProposalTool.Arguments(action: "remove", reference: reference, title: nil, date: nil, time: nil, duration: nil)
        _ = try await store.propose(proposal, token: token)
        let draft = await store.takeDraft(token)
        try require(draft?.event?.values.title == "Prüftermin 2", "proposal reference")
        let unchanged = try object(await store.query(date: CalendarConversation.day(day), days: 1, offset: 0, token: token))
        try require(unchanged["total"] as? Int == 12, "no writes without form confirmation")
        await store.invalidate()
        do { _ = try await store.query(date: CalendarConversation.day(day), days: 1, offset: 0, token: token); throw LocalSpeechError.message("Stale tool request accepted") }
        catch is CancellationError { }
        let fresh = UUID(); await store.begin(fresh)
        await store.invalidate(token); await store.clear(token) // Late cleanup must not stop a newer turn.
        let emptyDay = Calendar.current.date(byAdding: .day, value: 3, to: day)!
        let empty = try object(await store.query(date: CalendarConversation.day(emptyDay), days: 1, offset: 0, token: fresh))
        try require(empty["total"] as? Int == 0, "empty day")
        let forged = CalendarProposalTool.Arguments(action: "remove", reference: "forged", title: nil, date: nil, time: nil, duration: nil)
        try require(try object(await store.propose(forged, token: fresh))["error"] != nil, "forged reference")
        let missing = CalendarProposalTool.Arguments(action: "create", reference: nil, title: "Test", date: nil, time: nil, duration: nil)
        try require(try object(await store.propose(missing, token: fresh))["missing"] != nil, "missing fields")
        try Data("Calendar tools: integration checks passed; no calendar writes from proposals.\n".utf8).write(to: URL.documentsDirectory.appendingPathComponent("preview-calendar-tools.txt"))
    }
}
#endif
