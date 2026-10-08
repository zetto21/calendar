import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct CalendarActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var title: String
    var color: String
    var start: Date
    var end: Date
    var displayStart: Date? = nil
    var phase: String? = nil

    func phase(at now: Date) -> String {
      now >= end ? "completed" : now >= start ? "ongoing" : "upcoming"
    }
  }
  var eventID: String
}
