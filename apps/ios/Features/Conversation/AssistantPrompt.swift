import Foundation

/// Qwen's pinned no-thinking template. Model facts remain outside its output;
/// source references are data and are checked again against live calendars.
struct AssistantPrompt {
  private struct Page: Decodable { let reference: String }
  private struct Context: Decodable {
    let today: String
    let timezone: String
    let lastPage: [Page]
    let lastDiscussedDate: String?
    enum CodingKeys: String, CodingKey {
      case today, timezone
      case lastPage = "last_page"
      case lastDiscussedDate = "last_discussed_date"
    }
  }
  let references: [String]
  let timezone: String
  private let today: String
  private let discussedDate: String?
  private let text: String
  private let system: String

  init(request: InterpretationRequest, system: String) throws {
    try request.validate()
    let context = try JSONDecoder().decode(Context.self, from: Data(request.context.utf8))
    guard let zone = TimeZone(identifier: context.timezone), !system.isEmpty,
      system.utf8.count <= 16_384, !request.text.contains("<|"), !system.contains("<|"),
      zone == request.calendar.timeZone
    else { throw InterpretationError.invalidRequest }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    guard context.today == CalendarConversation.day(request.now, calendar: calendar) else {
      throw InterpretationError.invalidRequest
    }
    let references = context.lastPage.map(\.reference)
    guard references.count <= 64, Set(references).count == references.count,
      references.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 && !$0.contains("<|") })
    else { throw InterpretationError.invalidRequest }
    if let value = context.lastDiscussedDate, !value.isEmpty {
      guard CalendarConversation.civilDate(value, calendar: calendar) != nil else {
        throw InterpretationError.invalidRequest
      }
      discussedDate = value
    } else {
      discussedDate = nil
    }
    self.references = references
    timezone = context.timezone
    today = context.today
    text = request.text
    self.system = system
  }

  func render(history: [[String: String]]) throws -> String {
    var context: [String: Any] = [
      "today": today, "timezone": timezone, "visible_references": references,
    ]
    if references.count == 1 { context["selected"] = references[0] }
    if let discussedDate { context["last_discussed_date"] = discussedDate }
    if !history.isEmpty {
      guard
        history.allSatisfy({
          Set($0.keys).isSubset(of: ["user", "spoken_answer", "displayed_answer"])
            && $0["user"] != nil && $0.count == 2
        })
      else { throw InterpretationError.invalidRequest }
      context["history"] = history
    }
    // Match Python's ensure_ascii=False / sort_keys JSON used by the recorded
    // training/export template. Spaces are added only outside quoted strings.
    let compact = String(
      decoding: try JSONSerialization.data(
        withJSONObject: context,
        options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    var json = ""
    var quoted = false
    var escaped = false
    for character in compact {
      json.append(character)
      if escaped {
        escaped = false
      } else if quoted && character == "\\" {
        escaped = true
      } else if character == "\"" {
        quoted.toggle()
      } else if !quoted && (character == ":" || character == ",") {
        json.append(" ")
      }
    }
    // JSON escaping retains the history's value while preventing literal chat
    // delimiters in prior user/model text from creating extra template roles.
    json = json.replacingOccurrences(of: "<|", with: "\\u003c|")
    return
      "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(json)\n\(text)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
  }
}
