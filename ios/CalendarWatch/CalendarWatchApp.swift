import SwiftUI
import WatchConnectivity

struct WatchEvent: Codable, Identifiable {
    let date: String
    let title: String
    let time: String?
    let duration: Int?
    let color: String?
    var id: String { "\(date)|\(time ?? "")|\(title)|\(duration ?? 0)" }
    var timeLabel: String { time?.isEmpty == false ? time! : "종일" }
    var tint: Color {
        let hex = (color ?? "#7657FF").replacingOccurrences(of: "#", with: "")
        let value = UInt32(hex, radix: 16) ?? 0x7657FF
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
struct WatchSnapshot: Codable {
    let signedIn: Bool
    let events: [WatchEvent]
}

final class WatchSchedule: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot: WatchSnapshot?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var status = "아이폰에서 일상 캘린더를 열어 주세요."
    private var revision: Double = 0
    private let cacheKey = "watch-calendar-context"

    override init() {
        super.init()
        if let context = UserDefaults.standard.dictionary(forKey: cacheKey) { receive(context) }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    func refresh() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            status = "아이폰 앱을 열면 최신 일정이 동기화됩니다."
            return
        }
        status = "동기화 중…"
        session.sendMessage(["request": "schedule"], replyHandler: { context in
            DispatchQueue.main.async { self.receive(context) }
        }, errorHandler: { _ in
            DispatchQueue.main.async { self.status = "아이폰 연결을 확인해 주세요." }
        })
    }
    private func receive(_ context: [String: Any]) {
        guard let value = context["revision"] as? Double, value >= revision,
              let json = context["snapshot"] as? String, let data = json.data(using: .utf8),
              data.count <= 60_000, let decoded = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return }
        revision = value
        snapshot = decoded
        updatedAt = Date(timeIntervalSince1970: value)
        status = decoded.signedIn ? "" : "아이폰에서 로그인해 주세요."
        UserDefaults.standard.set(context, forKey: cacheKey)
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.receive(session.receivedApplicationContext)
            self.refresh()
        }
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { self.receive(applicationContext) }
    }
}

@main
struct CalendarWatchApp: App {
    @StateObject private var schedule = WatchSchedule()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            WatchCalendarView(schedule: schedule)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { schedule.refresh() }
                }
        }
    }
}

struct WatchCalendarView: View {
    @ObservedObject var schedule: WatchSchedule
    @State private var upcoming = false
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private var days: [(String, [WatchEvent])] {
        let today = Self.dayFormatter.string(from: Date())
        let last = Self.dayFormatter.string(from: Calendar.current.date(byAdding: .day, value: 7, to: Date())!)
        let events = (schedule.snapshot?.signedIn == true ? schedule.snapshot?.events : nil) ?? []
        let filtered = events.filter { upcoming ? $0.date >= today && $0.date <= last : $0.date == today }
        return Dictionary(grouping: filtered, by: \.date).sorted { $0.key < $1.key }.map { date, values in
            (date, values.sorted { ($0.time ?? "") < ($1.time ?? "") })
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Picker("일정 범위", selection: $upcoming) {
                    Text("오늘").tag(false)
                    Text("다가오는 일정").tag(true)
                }
                if schedule.snapshot == nil || schedule.snapshot?.signedIn == false {
                    Text(schedule.status).font(.footnote).foregroundStyle(.secondary)
                } else if days.isEmpty {
                    Label(upcoming ? "다가오는 일정이 없어요" : "오늘 일정이 없어요", systemImage: "calendar.badge.checkmark")
                        .font(.footnote)
                }
                ForEach(days, id: \.0) { day, events in
                    Section(day.replacingOccurrences(of: "-", with: ".")) {
                        // Index identity also preserves two otherwise identical events.
                        ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                            NavigationLink {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(event.title).font(.headline)
                                    Label(event.date, systemImage: "calendar")
                                    Label(event.timeLabel, systemImage: "clock")
                                    if let duration = event.duration, event.time != nil {
                                        Text("\(duration)분").foregroundStyle(.secondary)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding()
                            } label: {
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 2).fill(event.tint).frame(width: 3)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.title).font(.headline).lineLimit(2)
                                        Text(event.timeLabel).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                    Button("동기화", systemImage: "arrow.clockwise") { schedule.refresh() }
                    if !schedule.status.isEmpty, schedule.snapshot?.signedIn == true {
                        Text(schedule.status).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let date = schedule.updatedAt {
                        Text("마지막 동기화 \(date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("일상 캘린더")
        }
    }
}
