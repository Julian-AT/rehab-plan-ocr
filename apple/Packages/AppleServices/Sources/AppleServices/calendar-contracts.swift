import Foundation

struct Values: Codable, Equatable {
  var title: String
  var start_utc: String
  var end_utc: String
  var timezone: String
  var location: String
  var notes: String
  var reminder_minutes: Int?
}
struct OwnedRecord: Codable {
  let status: String
  let id: String
  let calendar_id: String
  let external_id: String?
  let approved: Values
}
