import ActivityKit
import SwiftUI
import WidgetKit

@main
struct CalendarLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    CalendarLiveActivityWidget()
    CalendarHomeWidget()
  }
}

struct CalendarLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CalendarActivityAttributes.self) { context in
      activityCard(context, now: .now)
        .padding(16)
        .activityBackgroundTint(Color(uiColor: .secondarySystemBackground).opacity(0.88))
        .activitySystemActionForegroundColor(.primary)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.bottom) {
          activityCard(context, now: .now)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
      } compactLeading: {
        Image(systemName: "calendar").foregroundStyle(.orange)
      } compactTrailing: {
        countdown(context).monospacedDigit().frame(width: 54)
      } minimal: {
        Image(systemName: isFinished(context) ? "checkmark.circle.fill" : "calendar.badge.clock")
          .foregroundStyle(.orange)
      }
      .keylineTint(.orange)
    }
  }

  @ViewBuilder
  private func activityCard(_ context: ActivityViewContext<CalendarActivityAttributes>, now: Date) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(statusLabel(context, now: now), systemImage: statusIcon(context, now: now))
        .font(.caption.weight(.semibold))
        .foregroundStyle(statusColor(context, now: now))
        .lineLimit(1)
      HStack(alignment: .firstTextBaseline) {
        Text(context.state.title)
          .font(.headline.weight(.semibold))
          .lineLimit(1)
          .truncationMode(.tail)
          .layoutPriority(1)
        Spacer(minLength: 12)
          countdown(context, now: now)
            .font(.title2.bold())
            .monospacedDigit()
            .foregroundStyle(eventColor(context))
          .frame(width: 100, alignment: .trailing)
      }
      Label(isFinished(context, now: now) ? "일정이 종료되었습니다" : timeRange(context), systemImage: "clock")
        .font(.caption)
        .foregroundStyle(.secondary)
      elapsedProgress(context, now: now)
        .padding(.top, 4)
    }
  }

  @ViewBuilder
  private func countdown(_ context: ActivityViewContext<CalendarActivityAttributes>, now: Date = .now) -> some View {
    if isFinished(context, now: now) {
      Text("완료")
    } else if !hasStarted(context, now: now) {
      Text(timerInterval: Date.now...context.state.start, countsDown: true)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .multilineTextAlignment(.trailing)
        .accessibilityLabel("시작까지 남은 시간")
    } else {
      Text(timerInterval: context.state.start...context.state.end, countsDown: true)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .multilineTextAlignment(.trailing)
        .accessibilityLabel("종료까지 남은 시간")
    }
  }

  @ViewBuilder
  private func elapsedProgress(_ context: ActivityViewContext<CalendarActivityAttributes>, now: Date) -> some View {
    // The system advances this date-based progress even when the app is suspended.
    ProgressView(
      timerInterval: context.state.start...context.state.end,
      countsDown: false,
      label: { EmptyView() },
      currentValueLabel: { EmptyView() }
    )
    .progressViewStyle(.linear)
    .tint(isFinished(context, now: now) ? Color.green : eventColor(context))
    .accessibilityLabel("일정 경과 시간")
  }

  private func eventColor(_ context: ActivityViewContext<CalendarActivityAttributes>) -> Color {
    let hex = context.state.color.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return .blue }
    return Color(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255
    )
  }

  private func isFinished(_ context: ActivityViewContext<CalendarActivityAttributes>, now: Date = .now) -> Bool {
    context.isStale || now >= context.state.end
  }

  private func hasStarted(_ context: ActivityViewContext<CalendarActivityAttributes>, now: Date = .now) -> Bool {
    now >= context.state.start
  }

  private func statusLabel(_ context: ActivityViewContext<CalendarActivityAttributes>, now: Date) -> String {
    isFinished(context, now: now) ? "완료" : hasStarted(context, now: now) ? "진행 중" : "시작 예정"
  }

  private func statusIcon(_ context: ActivityViewContext<CalendarActivityAttributes>, now: Date) -> String {
    isFinished(context, now: now) ? "checkmark.circle.fill" : hasStarted(context, now: now) ? "calendar.badge.clock" : "calendar"
  }

  private func statusColor(_ context: ActivityViewContext<CalendarActivityAttributes>, now: Date) -> Color {
    isFinished(context, now: now) ? .green : .orange
  }

  private func timeRange(_ context: ActivityViewContext<CalendarActivityAttributes>) -> String {
    let format = Date.FormatStyle(date: .omitted, time: .shortened)
      .locale(Locale(identifier: "ko_KR"))
    return "\(context.state.start.formatted(format)) – \(context.state.end.formatted(format))"
  }
}


private struct HomeEvent: Decodable {
  let date: String
  let title: String
  let time: String?
}
private struct HomeSnapshot: Decodable {
  let signedIn: Bool
  let events: [HomeEvent]
}
private struct HomeEntry: TimelineEntry {
  let date: Date
  let snapshot: HomeSnapshot
}
private struct HomeProvider: TimelineProvider {
  func placeholder(in context: Context) -> HomeEntry {
    HomeEntry(date: .now, snapshot: HomeSnapshot(signedIn: true, events: []))
  }
  func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> Void) { completion(entry(.now)) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) {
    let now = Date()
    let entries = (0..<8).compactMap { offset -> HomeEntry? in
      guard let day = Calendar.current.date(byAdding: .day, value: offset, to: now) else { return nil }
      return entry(offset == 0 ? now : Calendar.current.startOfDay(for: day))
    }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(1800))))
  }
  private func entry(_ date: Date) -> HomeEntry {
    let raw = UserDefaults(suiteName: "group.com.zetto.calendarAppFlutter")?.string(forKey: "calendarWidgetSnapshot") ?? ""
    let snapshot = raw.data(using: .utf8).flatMap { try? JSONDecoder().decode(HomeSnapshot.self, from: $0) }
    return HomeEntry(date: date, snapshot: snapshot ?? HomeSnapshot(signedIn: false, events: []))
  }
}
struct CalendarHomeWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "CalendarHomeWidget", provider: HomeProvider()) { entry in
      HomeWidgetView(entry: entry)
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }
    .configurationDisplayName("일상 캘린더")
    .description("오늘과 다가오는 일정을 확인하세요.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
private struct HomeWidgetView: View {
  let entry: HomeEntry
  @Environment(\.widgetFamily) private var family
  private var today: String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: entry.date)
  }
  private var events: [HomeEvent] {
    guard entry.snapshot.signedIn else { return [] }
    return entry.snapshot.events.filter { $0.date >= today }.sorted {
      $0.date == $1.date ? ($0.time ?? "") < ($1.time ?? "") : $0.date < $1.date
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("일상 캘린더").font(.caption.bold()).foregroundStyle(.orange)
      Text(entry.date, format: .dateTime.month().day().weekday()).font(.headline)
      if !entry.snapshot.signedIn {
        Text("앱을 열어 로그인해 주세요").font(.caption).foregroundStyle(.secondary)
      } else if events.isEmpty {
        Text("예정된 일정이 없어요").font(.caption).foregroundStyle(.secondary)
      } else {
        ForEach(Array(events.prefix(family == .systemLarge ? 6 : family == .systemSmall ? 2 : 3).enumerated()), id: \.offset) { _, event in
          VStack(alignment: .leading, spacing: 2) {
            Text("\(event.date == today ? "오늘" : String(event.date.suffix(5)).replacingOccurrences(of: "-", with: "/")) · \(event.time?.isEmpty == false ? event.time! : "종일")")
              .font(.caption2).foregroundStyle(.secondary)
            Text(event.title).font(.subheadline.weight(.medium)).lineLimit(1)
          }
        }
      }
      Spacer(minLength: 0)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
