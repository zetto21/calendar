import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var windowChannel: FlutterMethodChannel?
  private var calendarFrame: NSRect?
  private var currentScreen = "login"
  private var fullscreenObserver: NSObjectProtocol?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    contentViewController = flutterViewController
    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()

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
