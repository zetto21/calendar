import ActivityKit
import Flutter
import UIKit

final class LiveActivityChannel {
  private static var instance: LiveActivityChannel?
  private var busy = false

  static func register(with messenger: FlutterBinaryMessenger) {
    let handler = LiveActivityChannel()
    instance = handler
    FlutterMethodChannel(name: "calendar_app/live_activity", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard #available(iOS 17.0, *) else {
          if call.method == "status" { result(["supported": false, "enabled": false]); return }
          result(FlutterError(code: "unsupported", message: "iOS 17 이상에서 사용할 수 있습니다.", details: nil)); return
        }
        guard !handler.busy else {
          result(FlutterError(code: "busy", message: "실시간 활동을 갱신 중입니다. 잠시 후 다시 시도해 주세요.", details: nil)); return
        }
        handler.busy = true
        Task { @MainActor in
          defer { handler.busy = false }
          await handler.handle(call, result: result)
        }
      }
  }

  private var scheduledStartSupported: Bool {
    if #available(iOS 26.0, *) { return true }
    return false
  }

  @available(iOS 17.0, *)
  @MainActor private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) async {
    let activities = Activity<CalendarActivityAttributes>.activities
    switch call.method {
    case "status":
      for activity in activities where activity.content.state.end.addingTimeInterval(180) <= Date() {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
      let active = Activity<CalendarActivityAttributes>.activities.filter {
        if $0.activityState == .active { return $0.content.state.end > Date() }
        if #available(iOS 26.0, *), $0.activityState == .pending {
          return $0.content.state.end > Date()
        }
        return false
      }
      result(["supported": true, "enabled": ActivityAuthorizationInfo().areActivitiesEnabled,
              "scheduledStartSupported": scheduledStartSupported, "eventIDs": active.map(\.attributes.eventID)])
    case "end":
      for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
      result(nil)
    case "start", "update", "schedule":
      guard let args = call.arguments as? [String: Any],
            let eventID = args["eventID"] as? String, !eventID.isEmpty, eventID.utf8.count <= 512,
            let title = args["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            title.utf8.count <= 4096, let color = args["color"] as? String, color.utf8.count <= 16,
            let startValue = args["start"] as? NSNumber,
            let endValue = args["end"] as? NSNumber,
            startValue.doubleValue.isFinite, endValue.doubleValue.isFinite,
            startValue.doubleValue >= -62135596800, endValue.doubleValue <= 253402300799 else {
        result(FlutterError(code: "invalid", message: "일정 정보를 확인해 주세요.", details: nil)); return
      }
      let start = Date(timeIntervalSince1970: startValue.doubleValue)
      let end = Date(timeIntervalSince1970: endValue.doubleValue)
      let displayStart = start.addingTimeInterval(-600)
      let scheduling = call.method == "schedule"
      guard end > Date(), end > start,
            scheduling ? displayStart > Date() : displayStart <= Date() else {
        result(FlutterError(code: "not_current", message: "현재 진행 중이거나 10분 안에 시작하는 시간 지정 일정만 표시할 수 있습니다.", details: nil)); return
      }
      let state = CalendarActivityAttributes.ContentState(title: String(title.prefix(120)), color: color, start: start, end: end, displayStart: displayStart)
      let content = ActivityContent(state: state, staleDate: end.addingTimeInterval(180))
      do {
        var activatePending = false
        if #available(iOS 26.0, *), !scheduling, let pending = activities.first(where: {
          $0.attributes.eventID == eventID && $0.activityState == .pending
        }) {
          // Migrate reservations made by an older build at the actual event start.
          await pending.end(nil, dismissalPolicy: .immediate)
          activatePending = true
        }
        if scheduling {
          guard #available(iOS 26.0, *) else {
            result(FlutterError(code: "scheduled_start_unsupported", message: "예약 시작은 iOS 26 이상에서 사용할 수 있습니다.", details: nil)); return
          }
          guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            result(FlutterError(code: "disabled", message: "설정에서 이 앱의 실시간 현황을 허용해 주세요.", details: nil)); return
          }
          let existing = activities.first(where: {
            $0.attributes.eventID == eventID && ($0.activityState == .pending || $0.activityState == .active)
          })
          var shouldRequest = true
          if let existing {
            if existing.activityState == .pending && existing.content.state.displayStart != displayStart {
              await existing.end(nil, dismissalPolicy: .immediate)
              shouldRequest = true
            } else if existing.content.state != state {
              await existing.update(content)
              shouldRequest = false
            } else {
              shouldRequest = false
            }
          }
          if shouldRequest {
            _ = try Activity.request(
              attributes: CalendarActivityAttributes(eventID: eventID),
              content: content,
              pushType: nil,
              style: .standard,
              alertConfiguration: AlertConfiguration(
                title: "일정 시작 예정",
                body: "\(String(title.prefix(80))) 일정이 10분 후 시작됩니다.",
                sound: .default
              ),
              start: displayStart
            )
          }
        } else if let existing = activities.first(where: { $0.attributes.eventID == eventID && $0.activityState == .active }) {
          await existing.update(content)
        } else if call.method == "start" || activatePending {
          guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            result(FlutterError(code: "disabled", message: "설정에서 이 앱의 실시간 현황을 허용해 주세요.", details: nil)); return
          }
          guard UIApplication.shared.applicationState == .active else {
            result(FlutterError(code: "background", message: "앱을 연 상태에서 시작해 주세요.", details: nil)); return
          }
          let created = try Activity.request(attributes: CalendarActivityAttributes(eventID: eventID), content: content, pushType: nil)
          // A manually started calendar activity is useful only if the person
          // can immediately find it. Ask ActivityKit to present its standard
          // alert while the system decides the Dynamic Island presentation.
          await created.update(
            content,
            alertConfiguration: AlertConfiguration(
              title: "현재 일정",
              body: "일정이 진행 중입니다.",
              sound: .default
            )
          )
        }
        result(["eventID": eventID])
      } catch {
        result(FlutterError(code: "activity_failed", message: "실시간 활동을 시작하지 못했습니다. 설정과 기기 상태를 확인해 주세요.", details: nil))
      }
    default: result(FlutterMethodNotImplemented)
    }
  }
}
