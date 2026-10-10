import Foundation
import WatchConnectivity

/// Shares only display data; never login credentials or account identifiers.
final class WatchCalendarSync: NSObject, WCSessionDelegate {
    static let shared = WatchCalendarSync()
    private let defaults = UserDefaults(suiteName: "group.com.zetto.calendarAppFlutter")
    private var latest: [String: Any] = [:]

    func activate() {
        guard WCSession.isSupported() else { return }
        if let json = defaults?.string(forKey: "calendarWidgetSnapshot") { prepare(json) }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    func update(_ json: String) {
        prepare(json)
        publish()
    }
    private func prepare(_ json: String) {
        guard let data = json.data(using: .utf8),
              var snapshot = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        // A small latest-state payload fits WatchConnectivity's context limit.
        var events = Array((snapshot["events"] as? [[String: Any]] ?? []).prefix(100))
        while true {
            snapshot["events"] = events
            guard let compact = try? JSONSerialization.data(withJSONObject: snapshot) else { return }
            if compact.count <= 50_000 {
                latest = ["snapshot": String(decoding: compact, as: UTF8.self), "revision": Date().timeIntervalSince1970]
                break
            }
            guard !events.isEmpty else { return }
            events.removeLast()
        }
    }
    private func publish() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled, !latest.isEmpty else { return }
        do { try session.updateApplicationContext(latest) }
        catch { /* Retain the latest context and retry when the Watch connects. */ }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.publish() }
    }
    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.publish() }
    }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async { replyHandler(message["request"] as? String == "schedule" ? self.latest : [:]) }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
