import Flutter
import UIKit
import WidgetKit
import CoreText

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let glassAccessibility = GlassAccessibilityStream()
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    FlutterEventChannel(name: "calendar_app/glass_accessibility",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
      .setStreamHandler(glassAccessibility)
    engineBridge.applicationRegistrar.register(LiquidGlassFactory(), withId: "calendar_app/liquid_glass")
    engineBridge.applicationRegistrar.register(
      NativeGlassButtonsFactory(messenger: engineBridge.applicationRegistrar.messenger()),
      withId: "calendar_app/native_glass_buttons")
    FlutterMethodChannel(name: "calendar_app/home_widget", binaryMessenger: engineBridge.applicationRegistrar.messenger())
      .setMethodCallHandler { call, result in
        guard call.method == "update" else { result(FlutterMethodNotImplemented); return }
        guard let args = call.arguments as? [String: Any], let snapshot = args["snapshot"] as? String,
              snapshot.utf8.count <= 2_000_000,
              let defaults = UserDefaults(suiteName: "group.com.zetto.calendarAppFlutter") else {
          result(FlutterError(code: "invalid_snapshot", message: "위젯 데이터를 확인해 주세요.", details: nil)); return
        }
        defaults.set(snapshot, forKey: "calendarWidgetSnapshot")
        WidgetCenter.shared.reloadTimelines(ofKind: "CalendarHomeWidget")
        result(nil)
      }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    EventKitChannel.register(with: engineBridge.applicationRegistrar.messenger())
    LiveActivityChannel.register(with: engineBridge.applicationRegistrar.messenger())
    FileExportChannel.register(with: engineBridge.applicationRegistrar.messenger())
  }
}

/// Presents the native Files save-location picker for exported backup files.
final class FileExportChannel: NSObject, UIDocumentPickerDelegate {
  private var result: FlutterResult?

  static func register(with messenger: FlutterBinaryMessenger) {
    let handler = FileExportChannel()
    FlutterMethodChannel(name: "calendar_app/file_export", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in handler.handle(call, result: result) }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "exportFiles" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let paths = args["paths"] as? [String], !paths.isEmpty, paths.count <= 2,
          Set(paths).count == paths.count else {
      result(FlutterError(code: "invalid_paths", message: "저장할 백업 파일을 확인해 주세요.", details: nil))
      return
    }
    guard self.result == nil else {
      result(FlutterError(code: "busy", message: "파일 저장 창이 이미 열려 있습니다.", details: nil))
      return
    }
    // Only generated backups may be shared: never a database, preferences
    // file, directory or link pointing outside the temporary export folder.
    let urls = paths.compactMap(Self.validatedBackupURL)
    guard urls.count == paths.count, Set(urls).count == urls.count else {
      result(FlutterError(code: "invalid_paths", message: "저장할 백업 파일을 확인해 주세요.", details: nil))
      return
    }
    self.result = result
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard let presenter = self.topViewController() else {
        self.finish(false)
        return
      }
      let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
      picker.delegate = self
      picker.modalPresentationStyle = .formSheet
      presenter.present(picker, animated: true)
    }
  }

  private static func validatedBackupURL(_ path: String) -> URL? {
    guard path.hasPrefix("/"), path.utf8.count <= 4096 else { return nil }
    let requested = URL(fileURLWithPath: path).standardizedFileURL
    let exportRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("calendar-exports", isDirectory: true)
      .resolvingSymlinksInPath().standardizedFileURL
    let url = requested.resolvingSymlinksInPath().standardizedFileURL
    let directory = url.deletingLastPathComponent()
    guard directory.deletingLastPathComponent() == exportRoot,
          directory.lastPathComponent.hasPrefix("backup-"),
          url.lastPathComponent.range(of: #"^calendar-backup-[0-9]{4}-[0-9]{2}-[0-9]{2}\.(ics|csv)$"#,
                                      options: .regularExpression) != nil,
          let requestedAttributes = try? FileManager.default.attributesOfItem(atPath: requested.path),
          requestedAttributes[.type] as? FileAttributeType == .typeRegular,
          let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          attributes[.type] as? FileAttributeType == .typeRegular,
          let size = attributes[.size] as? NSNumber, size.int64Value <= 20 * 1024 * 1024 else {
      return nil
    }
    return url
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(false)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finish(true)
  }

  private func finish(_ saved: Bool) {
    let callback = result
    result = nil
    callback?(saved)
  }

  private func topViewController() -> UIViewController? {
    let root = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }
      .first?.rootViewController
    var controller = root
    while let presented = controller?.presentedViewController { controller = presented }
    return controller
  }
}

/// Shares the system preference with Flutter-rendered glass surfaces too.
final class GlassAccessibilityStream: NSObject, FlutterStreamHandler {
  private var observer: NSObjectProtocol?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    stopObserving()
    observer = NotificationCenter.default.addObserver(
      forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      object: nil, queue: .main
    ) { _ in events(UIAccessibility.isReduceTransparencyEnabled) }
    events(UIAccessibility.isReduceTransparencyEnabled)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stopObserving()
    return nil
  }

  private func stopObserving() {
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
  }

  deinit { stopObserving() }
}

/// UIKit owns the optical material; Flutter owns the accessible controls above it.
final class LiquidGlassFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
              arguments args: Any?) -> FlutterPlatformView {
    LiquidGlassPlatformView(frame: frame, arguments: args as? [String: Any] ?? [:])
  }
}

final class LiquidGlassPlatformView: NSObject, FlutterPlatformView {
  private let effectView: UIVisualEffectView

  init(frame: CGRect, arguments: [String: Any]) {
    effectView = UIVisualEffectView(frame: frame)
    super.init()
    effectView.overrideUserInterfaceStyle = arguments["dark"] as? Bool == true ? .dark : .light
    effectView.layer.cornerRadius = CGFloat((arguments["radius"] as? NSNumber)?.doubleValue ?? 24)
    effectView.layer.cornerCurve = .continuous
    effectView.clipsToBounds = true
    effectView.isUserInteractionEnabled = false
    effectView.isAccessibilityElement = false
    effectView.accessibilityElementsHidden = true
    updateEffect()
    NotificationCenter.default.addObserver(self, selector: #selector(updateEffect),
      name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
  }

  @objc private func updateEffect() {
    if UIAccessibility.isReduceTransparencyEnabled {
      effectView.effect = nil
      effectView.backgroundColor = .secondarySystemBackground
    } else {
      effectView.backgroundColor = .clear
      if #available(iOS 26.0, *) {
        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.isInteractive = true
        effectView.effect = glassEffect
      } else {
        effectView.effect = UIBlurEffect(style: .systemMaterial)
      }
    }
  }

  deinit { NotificationCenter.default.removeObserver(self) }
  func view() -> UIView { effectView }
}

final class NativeGlassButtonsFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
  func create(withFrame frame: CGRect, viewIdentifier id: Int64, arguments: Any?) -> FlutterPlatformView {
    NativeGlassButtonsView(frame: frame, id: id, messenger: messenger,
      arguments: arguments as? [String: Any] ?? [:])
  }
}

/// UIKit owns the entire hit-test path, including the system's held-touch effect.
final class NativeGlassButtonsView: NSObject, FlutterPlatformView {
  private let channel: FlutterMethodChannel
  private let control: UIView
  private static var fonts: [String: CGFont] = [:]

  init(frame: CGRect, id: Int64, messenger: FlutterBinaryMessenger, arguments: [String: Any]) {
    channel = FlutterMethodChannel(name: "calendar_app/native_glass_buttons/\(id)", binaryMessenger: messenger)
    let actions = arguments["actions"] as? [[String: Any]] ?? []
    if actions.count > 1 {
      let effect: UIVisualEffect
      if #available(iOS 26.0, *) {
        let glass = UIGlassEffect(style: .regular)
        glass.isInteractive = true
        effect = glass
      } else {
        effect = UIBlurEffect(style: .systemMaterial)
      }
      control = NativeGlassCapsule(effect: effect)
      control.frame = frame
    } else {
      let button = UIButton(type: .system)
      button.frame = frame
      control = button
    }
    super.init()
    control.clipsToBounds = false
    control.isUserInteractionEnabled = true
    control.showsLargeContentViewer = false
    if let button = control as? UIButton {
      button.addTarget(self, action: #selector(buttonPressed), for: .touchUpInside)
    }
    configure(arguments)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "configure", let args = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented); return
      }
      self?.configure(args)
      result(nil)
    }
  }

  private func configure(_ args: [String: Any]) {
    let actions = args["actions"] as? [[String: Any]] ?? []
    let iconSize = CGFloat((args["iconSize"] as? NSNumber)?.doubleValue ?? 20)
    let value = (args["color"] as? NSNumber)?.uint32Value ?? 0xFF000000
    let color = UIColor(red: CGFloat((value >> 16) & 255) / 255,
      green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255,
      alpha: CGFloat((value >> 24) & 255) / 255)
    control.tintColor = color
    control.overrideUserInterfaceStyle = args["dark"] as? Bool == true ? .dark : .light
    if let button = control as? UIButton, let action = actions.first {
      var config: UIButton.Configuration
      if #available(iOS 26.0, *) { config = .glass() } else { config = .plain() }
      config.cornerStyle = .capsule
      config.contentInsets = .zero
      config.baseForegroundColor = color
      config.image = Self.icon(action, size: iconSize)
      button.configuration = config
      button.accessibilityLabel = action["label"] as? String
    } else if let capsule = control as? NativeGlassCapsule {
      if capsule.buttons.count != actions.count {
        capsule.buttons.forEach { $0.removeFromSuperview() }
        capsule.buttons = actions.indices.map { index in
          let button = UIButton(type: .system)
          button.tag = index
          button.addTarget(self, action: #selector(capsulePressed(_:)), for: .touchUpInside)
          capsule.contentView.addSubview(button)
          return button
        }
      }
      for (button, action) in zip(capsule.buttons, actions) {
        var config = UIButton.Configuration.plain()
        config.contentInsets = .zero
        config.baseForegroundColor = color
        config.image = Self.icon(action, size: iconSize)
        button.configuration = config
        button.accessibilityLabel = action["label"] as? String
        button.showsLargeContentViewer = false
      }
      capsule.setNeedsLayout()
    }
  }

  // Draw the existing Flutter icon glyphs, retaining their shape and weight.
  private static func icon(_ action: [String: Any], size: CGFloat) -> UIImage? {
    let name = action["font"] as? String ?? "material"
    if fonts[name] == nil {
      let relative = name == "cupertino" ? "packages/cupertino_icons/assets/CupertinoIcons.ttf" : "fonts/MaterialIcons-Regular.otf"
      let url = Bundle.main.bundleURL.appendingPathComponent("Frameworks/App.framework/flutter_assets/\(relative)")
      if let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider) {
        CTFontManagerRegisterGraphicsFont(font, nil)
        fonts[name] = font
      }
    }
    guard let font = fonts[name], let postscript = font.postScriptName,
          let uiFont = UIFont(name: postscript as String, size: size),
          let code = action["codePoint"] as? NSNumber,
          let scalar = UnicodeScalar(code.uint32Value) else {
      return UIImage(systemName: action["symbol"] as? String ?? "circle")
    }
    let text = String(scalar) as NSString
    let attributes: [NSAttributedString.Key: Any] = [.font: uiFont, .foregroundColor: UIColor.white]
    let textSize = text.size(withAttributes: attributes)
    return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
      text.draw(at: CGPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2), withAttributes: attributes)
    }.withRenderingMode(.alwaysTemplate)
  }

  @objc private func buttonPressed() { channel.invokeMethod("press", arguments: 0) }
  @objc private func capsulePressed(_ button: UIButton) { channel.invokeMethod("press", arguments: button.tag) }
  deinit { channel.setMethodCallHandler(nil) }
  func view() -> UIView { control }
}

/// One continuous glass capsule with two independent tap targets.
final class NativeGlassCapsule: UIVisualEffectView {
  var buttons: [UIButton] = []

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = bounds.height / 2
    layer.cornerCurve = .continuous
    clipsToBounds = true
    guard !buttons.isEmpty else { return }
    let width = bounds.width / CGFloat(buttons.count)
    for (index, button) in buttons.enumerated() {
      button.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
    }
  }
}
