import Cocoa
import FlutterMacOS
import Security
import UserNotifications

class MainFlutterWindow: NSWindow {
  private var notificationChannel: FlutterMethodChannel?
  private var sessionChannel: FlutterMethodChannel?
  private var windowChannel: FlutterMethodChannel?
  private var calendarFrame: NSRect?
  private var currentScreen = "login"
  private var fullscreenObserver: NSObjectProtocol?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    contentViewController = flutterViewController
    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()

    notificationChannel = FlutterMethodChannel(
      name: "calendar/desktop_notifications",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    notificationChannel?.setMethodCallHandler { call, result in
      guard call.method == "show" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let id = args["id"] as? Int,
            let title = args["title"] as? String,
            let body = args["body"] as? String else {
        result(FlutterError(code: "invalid_arguments", message: "Missing notification content", details: nil))
        return
      }
      let center = UNUserNotificationCenter.current()
      center.requestAuthorization(options: [.alert, .sound]) { granted, error in
        guard granted, error == nil else {
          DispatchQueue.main.async { result(false) }
          return
        }
        // Replace outdated connectivity notices when the connection changes.
        if id == 4101 || id == 4102 {
          let stale = ["calendar.4101", "calendar.4102"]
          center.removePendingNotificationRequests(withIdentifiers: stale)
          center.removeDeliveredNotifications(withIdentifiers: stale)
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
          identifier: "calendar.\(id)", content: content, trigger: nil
        )
        center.add(request) { error in
          DispatchQueue.main.async { result(error == nil) }
        }
      }
    }

    sessionChannel = FlutterMethodChannel(
      name: "calendar_app/session",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    sessionChannel?.setMethodCallHandler { call, result in
      guard let arguments = call.arguments as? [String: String],
            let account = arguments["account"] else {
        result(FlutterError(code: "invalid_arguments", message: "Missing account", details: nil))
        return
      }
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "calendar_app") + ".session",
        kSecAttrAccount as String: account,
      ]
      var status: OSStatus
      switch call.method {
      case "read":
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { result(nil); return }
        if status == errSecSuccess, let data = item as? Data {
          result(String(data: data, encoding: .utf8))
          return
        }
      case "write":
        guard let value = arguments["value"], let data = value.data(using: .utf8) else {
          result(FlutterError(code: "invalid_value", message: "Missing session", details: nil))
          return
        }
        status = SecItemUpdate(query as CFDictionary,
          [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
          var item = query
          item[kSecValueData as String] = data
          status = SecItemAdd(item as CFDictionary, nil)
        }
      case "delete":
        status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound { status = errSecSuccess }
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      if status == errSecSuccess {
        result(nil)
      } else {
        result(FlutterError(code: "keychain_\(status)",
          message: "Unable to access saved session", details: nil))
      }
    }

    // Start compact, before Flutter restores the account or draws the login form.
    applyScreen("login", animated: false)
    windowChannel = FlutterMethodChannel(
      name: "calendar_app/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    windowChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setScreen" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let screen = call.arguments as? String,
            screen == "login" || screen == "calendar" else {
        result(FlutterError(code: "invalid_screen", message: "Unknown screen", details: nil))
        return
      }
      self?.switchScreen(screen)
      result(nil)
    }
  }

  private func switchScreen(_ screen: String) {
    guard currentScreen != screen else { return }
    if currentScreen == "calendar" && !styleMask.contains(.fullScreen) {
      calendarFrame = frame
    }
    currentScreen = screen
    if styleMask.contains(.fullScreen) {
      if fullscreenObserver == nil {
        fullscreenObserver = NotificationCenter.default.addObserver(
          forName: NSWindow.didExitFullScreenNotification, object: self, queue: .main
        ) { [weak self] _ in
          guard let self = self else { return }
          if let observer = self.fullscreenObserver {
            NotificationCenter.default.removeObserver(observer)
            self.fullscreenObserver = nil
          }
          self.applyScreen(self.currentScreen, animated: true)
        }
        toggleFullScreen(nil)
      }
      return
    }
    applyScreen(screen, animated: true)
  }

  private func applyScreen(_ screen: String, animated: Bool) {
    let calendar = screen == "calendar"
    let visible = self.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    // Release the login constraints before restoring the calendar frame.
    contentMinSize = .zero
    contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
    if calendar {
      styleMask.insert(.resizable)
      collectionBehavior.remove(.fullScreenNone)
      collectionBehavior.insert(.fullScreenPrimary)
    } else {
      styleMask.remove(.resizable)
      collectionBehavior.remove(.fullScreenPrimary)
      collectionBehavior.insert(.fullScreenNone)
    }
    standardWindowButton(.zoomButton)?.isEnabled = calendar
    let contentSize = NSSize(width: calendar ? 1280 : 520, height: calendar ? 840 : 720)
    var target = calendar ? (calendarFrame ?? frameRect(forContentRect:
      NSRect(origin: .zero, size: contentSize))) : frameRect(forContentRect:
      NSRect(origin: .zero, size: contentSize))
    target.size.width = min(target.width, visible.width)
    target.size.height = min(target.height, visible.height)
    if !calendar || calendarFrame == nil {
      target.origin = NSPoint(x: visible.midX - target.width / 2,
                              y: visible.midY - target.height / 2)
    }
    target.origin.x = max(visible.minX, min(target.minX, visible.maxX - target.width))
    target.origin.y = max(visible.minY, min(target.minY, visible.maxY - target.height))
    setFrame(target, display: true, animate: animated)
    if calendar {
      contentMinSize = NSSize(width: min(800, visible.width),
                              height: min(560, visible.height - 40))
    } else {
      let fixedSize = contentRect(forFrameRect: target).size
      contentMinSize = fixedSize
      contentMaxSize = fixedSize
    }
  }

  deinit {
    if let observer = fullscreenObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }
}
