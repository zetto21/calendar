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

  @available(iOS 17.0, *)
  @MainActor private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) async {
    let activities = Activity<CalendarActivityAttributes>.activities
    switch call.method {
    case "status":
      for activity in activities where activity.content.state.end <= Date() {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
      let active = Activity<CalendarActivityAttributes>.activities.first {
        $0.activityState == .active && $0.content.state.end > Date()
      }
      result(["supported": true, "enabled": ActivityAuthorizationInfo().areActivitiesEnabled,
              "eventID": active?.attributes.eventID as Any? ?? NSNull()])
    case "end":
      for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
      result(nil)
    case "start", "update":
      guard let args = call.arguments as? [String: Any],
            let eventID = args["eventID"] as? String, !eventID.isEmpty,
            let title = args["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let startValue = args["start"] as? NSNumber,
            let endValue = args["end"] as? NSNumber else {
        result(FlutterError(code: "invalid", message: "일정 정보를 확인해 주세요.", details: nil)); return
      }
      let start = Date(timeIntervalSince1970: startValue.doubleValue)
      let end = Date(timeIntervalSince1970: endValue.doubleValue)
      guard start <= Date(), end > Date(), end > start else {
        result(FlutterError(code: "not_current", message: "현재 진행 중인 시간 지정 일정만 표시할 수 있습니다.", details: nil)); return
      }
      let state = CalendarActivityAttributes.ContentState(title: String(title.prefix(120)), start: start, end: end)
      let content = ActivityContent(state: state, staleDate: end)
      do {
        if let existing = activities.first(where: { $0.attributes.eventID == eventID && $0.activityState == .active }) {
          await existing.update(content)
        } else if call.method == "start" {
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
          for activity in activities where activity.id != created.id {
            await activity.end(nil, dismissalPolicy: .immediate)
          }
        }
        result(["eventID": eventID])
      } catch {
        result(FlutterError(code: "activity_failed", message: "실시간 활동을 시작하지 못했습니다. 설정과 기기 상태를 확인해 주세요.", details: nil))
      }
    default: result(FlutterMethodNotImplemented)
    }
  }
}
