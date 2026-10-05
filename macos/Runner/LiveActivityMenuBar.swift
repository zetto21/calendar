import Cocoa
import FlutterMacOS

/// Mirrors the iOS Live Activity / Android live-update notification as a
/// menu bar item: a colored dot, the event title and the time remaining,
/// ticking without Dart involvement.
final class LiveActivityMenuBar: NSObject {
  static let shared = LiveActivityMenuBar()

  private static let lingerInterval: TimeInterval = 180
  private static let doneColor = NSColor(hex: "#34C759") ?? .systemGreen

  private var statusItem: NSStatusItem?
  private var timer: Timer?
  private var eventID: String?
  private var eventTitle = ""
  private var colorHex = "#3B82F6"
  private var start = Date()
  private var end = Date()

  func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "calendar_app/live_activity", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        self?.handle(call, result: result)
      }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      result([
        "supported": true,
        "enabled": true,
        "eventIDs": eventID.map { [$0] } ?? [],
      ])
    case "start", "update":
      guard let args = call.arguments as? [String: Any],
            let newID = args["eventID"] as? String, !newID.isEmpty, newID.utf8.count <= 512,
            let newTitle = args["title"] as? String,
            !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, newTitle.utf8.count <= 4096,
            let startValue = args["start"] as? NSNumber,
            let endValue = args["end"] as? NSNumber,
            startValue.doubleValue.isFinite, endValue.doubleValue.isFinite,
            startValue.doubleValue >= -62135596800, endValue.doubleValue <= 253402300799 else {
        result(FlutterError(code: "invalid", message: "일정 정보를 확인해 주세요.", details: nil))
        return
      }
      let newStart = Date(timeIntervalSince1970: startValue.doubleValue)
      let newEnd = Date(timeIntervalSince1970: endValue.doubleValue)
      guard newStart.addingTimeInterval(-600) <= Date(), newEnd > Date(), newEnd > newStart else {
        result(FlutterError(code: "not_current",
          message: "현재 진행 중이거나 10분 안에 시작하는 시간 지정 일정만 표시할 수 있습니다.", details: nil))
        return
      }
      if call.method == "update" && eventID != newID {
        // Not the event the person picked on this device; ignore quietly.
        result(nil)
        return
      }
      eventID = newID
      eventTitle = String(newTitle.prefix(120))
      colorHex = String((args["color"] as? String ?? "#3B82F6").prefix(16))
      start = newStart
      end = newEnd
      ensureStatusItem()
      tick()
      result(nil)
    case "end":
      endActivity()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func ensureStatusItem() {
    guard statusItem == nil else { return }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.imagePosition = .imageLeft
    let menu = NSMenu()
    menu.addItem(withAction: "캘린더 열기", target: self, selector: #selector(openApp))
    menu.addItem(.separator())
    menu.addItem(withAction: "실시간 현황 종료", target: self, selector: #selector(stopFromMenu))
    item.menu = menu
    statusItem = item
  }

  @objc private func openApp() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.windows.first?.makeKeyAndOrderFront(nil)
  }

  @objc private func stopFromMenu() {
    endActivity()
  }

  private func tick() {
    guard let button = statusItem?.button else { return }
    let now = Date()
    let lingerUntil = end.addingTimeInterval(Self.lingerInterval)
    if now >= lingerUntil {
      endActivity()
      return
    }
    let started = now >= start
    let finished = now >= end
    button.image = dotImage(hex: finished ? nil : colorHex, color: finished ? Self.doneColor : nil)
    if finished {
      button.title = " \(eventTitle) · 종료"
    } else if started {
      let minutes = max(0, Int(end.timeIntervalSince(now) / 60))
      button.title = " \(eventTitle) · \(minutes)분 남음"
    } else {
      let minutes = max(0, Int(start.timeIntervalSince(now) / 60))
      button.title = " \(eventTitle) · \(minutes)분 후 시작"
    }
    let nextBoundary = now < start ? start : (now < end ? end : lingerUntil)
    let interval = min(15, max(1, nextBoundary.timeIntervalSince(now)))
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
      self?.tick()
    }
  }

  private func endActivity() {
    timer?.invalidate()
    timer = nil
    eventID = nil
    if let item = statusItem {
      NSStatusBar.system.removeStatusItem(item)
    }
    statusItem = nil
  }

  private func dotImage(hex: String?, color: NSColor?) -> NSImage {
    let resolved = color ?? NSColor(hex: hex ?? "") ?? .systemBlue
    let size = NSSize(width: 10, height: 10)
    let image = NSImage(size: size)
    image.lockFocus()
    resolved.setFill()
    NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
    image.unlockFocus()
    image.isTemplate = false
    return image
  }
}

private extension NSMenu {
  func addItem(withAction title: String, target: AnyObject, selector: Selector) {
    let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
    item.target = target
    addItem(item)
  }
}

private extension NSColor {
  convenience init?(hex: String) {
    let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "#", with: "")
    guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
    self.init(
      srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: 1
    )
  }
}
