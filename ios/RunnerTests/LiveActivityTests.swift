import ActivityKit
import XCTest
@testable import Runner

final class LiveActivityTests: XCTestCase {
  @MainActor
  func testStartUpdateAndEnd() async throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Requires iOS 17") }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      throw XCTSkip("Live Activities disabled on this device")
    }
    let id = "live-activity-test-\(UUID().uuidString)"
    let start = Date().addingTimeInterval(-60)
    let end = Date().addingTimeInterval(600)
    let initial = CalendarActivityAttributes.ContentState(title: "실시간 활동 테스트", color: "#3B82F6", start: start, end: end)
    let activity = try Activity.request(
      attributes: CalendarActivityAttributes(eventID: id),
      content: ActivityContent(state: initial, staleDate: end), pushType: nil)
    XCTAssertEqual(activity.attributes.eventID, id)
    XCTAssertEqual(activity.activityState, .active)
    // Used only for an on-demand simulator preview. Normal CI runs do not
    // provide this variable and remain fast.
    if let seconds = ProcessInfo.processInfo.environment["LIVE_ACTIVITY_PREVIEW_SECONDS"],
       let duration = TimeInterval(seconds), duration > 0 {
      try await Task.sleep(for: .seconds(duration))
    }
    let changed = CalendarActivityAttributes.ContentState(title: "변경된 일정", color: "#F0654F", start: start, end: end.addingTimeInterval(60))
    await activity.update(ActivityContent(state: changed, staleDate: changed.end))
    XCTAssertEqual(activity.content.state.title, "변경된 일정")
    await activity.end(nil, dismissalPolicy: .immediate)
    XCTAssertTrue(activity.activityState == .ended || activity.activityState == .dismissed)
  }
}
