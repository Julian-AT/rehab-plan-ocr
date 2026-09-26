import Foundation

struct Values: Codable, Equatable {
  var title: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  var start_utc: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  var end_utc: String
  var timezone: String
  var location: String
  var notes: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  var reminder_minutes: Int?
}
struct OwnedRecord: Codable {
  let status: String
  let id: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  let calendar_id: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  let external_id: String?
  let approved: Values
}
