import EventKit
import EventKitUI
import UIKit
import Flutter
import Foundation

/// Native Apple event editor and calendar synchronization bridge.
class EventKitChannel: NSObject, EKEventEditViewDelegate {
  private var editorResult: FlutterResult?
  private let store = EKEventStore()
  private let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
  private let isoFormatterNoFraction: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "calendar_app/eventkit", binaryMessenger: messenger)
    let instance = EventKitChannel()
    channel.setMethodCallHandler { call, result in
      instance.handle(call, result: result)
    }
  }

  private func parseISO(_ value: String) -> Date? {
    isoFormatter.date(from: value) ?? isoFormatterNoFraction.date(from: value)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "isAvailable":
      result(true)
    case "requestAccess":
      requestAccess(result: result)
    case "presentEventEditor":
      presentEventEditor(args, result: result)
    case "createEvent":
      createEvent(args, result: result)
    case "updateEvent":
      updateEvent(args, result: result)
    case "deleteEvent":
      deleteEvent(args, result: result)
    case "fetchEvents":
      fetchEvents(args, result: result)
    case "fetchCalendars":
      fetchCalendars(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func hasCalendarAccess() -> Bool {
    let status = EKEventStore.authorizationStatus(for: .event)
    if #available(iOS 17.0, *) {
      return status == .fullAccess
    }
    return status == .authorized
  }

  private func requestAccess(result: @escaping FlutterResult) {
    if #available(iOS 17.0, *) {
      store.requestFullAccessToEvents { granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
    } else {
      store.requestAccess(to: .event) { granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
    }
  }

  private func presentEventEditor(_ args: [String: Any], result: @escaping FlutterResult) {
    guard editorResult == nil else {
      result(FlutterError(code: "editor_busy", message: "일정 추가 화면이 이미 열려 있습니다.", details: nil))
      return
    }
    if #available(iOS 17.0, *) {
      // Apple UI can save even when this app has no calendar read access.
    } else if !hasCalendarAccess() {
      result(FlutterError(code: "access_denied", message: "설정에서 캘린더 접근을 허용해 주세요.", details: nil))
      return
    }
    guard let times = eventTimes(args) else {
      result(FlutterError(code: "invalid_args", message: "일정 날짜를 확인해 주세요.", details: nil))
      return
    }
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive }),
      var presenter = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "no_presenter", message: "일정 추가 화면을 열 수 없습니다.", details: nil))
      return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    let event = EKEvent(eventStore: store)
    event.startDate = times.start
    event.endDate = times.end
    event.isAllDay = times.isAllDay
    if hasCalendarAccess() { event.calendar = store.defaultCalendarForNewEvents }
    let editor = EKEventEditViewController()
    editor.eventStore = store
    editor.event = event
    editor.editViewDelegate = self
    editor.isModalInPresentation = true
    editorResult = result
    presenter.present(editor, animated: true)
  }

  func eventEditViewController(_ controller: EKEventEditViewController,
                               didCompleteWith action: EKEventEditViewAction) {
    var response: [String: Any] = ["saved": action == .saved]
    if action == .saved, hasCalendarAccess(), let event = controller.event,
       event.eventIdentifier != nil {
      response["event"] = mapEvent(event)
    }
    let completion = editorResult
    controller.dismiss(animated: true) {
      self.editorResult = nil
      completion?(response)
    }
  }

  private func mapEvent(_ event: EKEvent) -> [String: Any] {
    // Include a local calendar date explicitly, especially for all-day events.
    let local = DateFormatter()
    local.locale = Locale(identifier: "en_US_POSIX")
    local.timeZone = TimeZone.current
    local.dateFormat = "yyyy-MM-dd"
    let date = local.string(from: event.startDate)
    local.dateFormat = "HH:mm"
    return [
      "systemEventId": event.eventIdentifier ?? "",
      "systemCalendarId": event.calendar?.calendarIdentifier ?? "",
      "title": event.title ?? "",
      "location": event.location ?? "",
      "notes": event.notes ?? "",
      "url": event.url?.absoluteString ?? "",
      "isAllDay": event.isAllDay,
      "date": date,
      "time": local.string(from: event.startDate),
      "startsAt": isoFormatter.string(from: event.startDate),
      "endsAt": isoFormatter.string(from: event.endDate),
      "updatedAt": isoFormatter.string(from: event.lastModifiedDate ?? event.creationDate ?? .distantPast),
      "durationMinutes": Int(event.endDate.timeIntervalSince(event.startDate) / 60),
    ]
  }

  private func eventTimes(_ args: [String: Any]) -> (start: Date, end: Date, isAllDay: Bool)? {
    let isAllDay = args["isAllDay"] as? Bool ?? false
    if isAllDay {
      guard let dateKey = args["date"] as? String else { return nil }
      let parts = dateKey.split(separator: "-").compactMap { Int($0) }
      guard parts.count == 3 else { return nil }
      var components = DateComponents()
      components.year = parts[0]
      components.month = parts[1]
      components.day = parts[2]
      guard let start = Calendar.current.date(from: components) else { return nil }
      let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
      return (start, end, true)
    }
    guard let startsAt = args["startsAt"] as? String, let start = parseISO(startsAt) else { return nil }
    let duration = (args["duration"] as? NSNumber)?.doubleValue ?? 60
    let end: Date
    if let endsAt = args["endsAt"] as? String, let parsedEnd = parseISO(endsAt) {
      end = parsedEnd
    } else {
      end = start.addingTimeInterval(duration * 60)
    }
    return (start, end, false)
  }

  private func applyRecurrence(_ event: EKEvent, frequency: String?, until: String?) {
    guard let frequency = frequency else {
      event.recurrenceRules = nil
      return
    }
    let ruleFrequency: EKRecurrenceFrequency
    var interval = 1
    switch frequency {
    case "daily": ruleFrequency = .daily
    case "weekly": ruleFrequency = .weekly
    case "biweekly": ruleFrequency = .weekly; interval = 2
    case "monthly": ruleFrequency = .monthly
    case "yearly": ruleFrequency = .yearly
    default: event.recurrenceRules = nil; return
    }
    var end: EKRecurrenceEnd?
    if let until = until, let untilDate = parseISO(until + "T23:59:59Z") {
      end = EKRecurrenceEnd(end: untilDate)
    }
    event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: ruleFrequency, interval: interval, end: end)]
  }

  private func createEvent(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let times = eventTimes(args) else {
      result(FlutterError(code: "invalid_args", message: "missing start time", details: nil))
      return
    }
    let event = EKEvent(eventStore: store)
    event.calendar = store.defaultCalendarForNewEvents
    event.title = args["title"] as? String ?? ""
    event.location = args["location"] as? String
    event.notes = args["notes"] as? String
    if let urlString = args["url"] as? String, let url = URL(string: urlString) {
      event.url = url
    }
    event.isAllDay = times.isAllDay
    event.startDate = times.start
    event.endDate = times.end
    applyRecurrence(event, frequency: args["recurrenceFrequency"] as? String, until: args["recurrenceUntil"] as? String)
    do {
      try store.save(event, span: .thisEvent)
      result(event.eventIdentifier)
    } catch {
      result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func updateEvent(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let identifier = args["systemEventId"] as? String, let event = store.event(withIdentifier: identifier) else {
      result(false)
      return
    }
    guard let times = eventTimes(args) else {
      result(FlutterError(code: "invalid_args", message: "missing start time", details: nil))
      return
    }
    event.title = args["title"] as? String ?? ""
    event.location = args["location"] as? String
    event.notes = args["notes"] as? String
    if let urlString = args["url"] as? String, let url = URL(string: urlString) {
      event.url = url
    } else {
      event.url = nil
    }
    event.isAllDay = times.isAllDay
    event.startDate = times.start
    event.endDate = times.end
    applyRecurrence(event, frequency: args["recurrenceFrequency"] as? String, until: args["recurrenceUntil"] as? String)
    do {
      try store.save(event, span: .thisEvent)
      result(true)
    } catch {
      result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func deleteEvent(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let identifier = args["systemEventId"] as? String, let event = store.event(withIdentifier: identifier) else {
      result(false)
      return
    }
    do {
      try store.remove(event, span: .thisEvent)
      result(true)
    } catch {
      result(FlutterError(code: "delete_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func fetchEvents(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let startString = args["start"] as? String, let endString = args["end"] as? String,
          let start = parseISO(startString), let end = parseISO(endString) else {
      result(FlutterError(code: "invalid_args", message: "missing range", details: nil))
      return
    }
    if !hasCalendarAccess() {
      result([])
      return
    }
    let ids = args["calendarIds"] as? [String] ?? []
    let calendars = ids.isEmpty ? nil : store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
    let events = store.events(matching: predicate)
    result(events.map { mapEvent($0) })
  }

  private func fetchCalendars(result: @escaping FlutterResult) {
    guard hasCalendarAccess() else {
      result([])
      return
    }
    result(store.calendars(for: .event).map { calendar in
      [
        "id": calendar.calendarIdentifier,
        "title": calendar.title,
        "source": calendar.source.title,
        "color": "#3B82F6"
      ]
    })
  }
}
