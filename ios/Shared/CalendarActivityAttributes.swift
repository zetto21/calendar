import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct CalendarActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var title: String
    var color: String
    var start: Date
    var end: Date
  }
  var eventID: String
}
