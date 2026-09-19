import ActivityKit
import SwiftUI
import WidgetKit

@main
struct CalendarLiveActivityBundle: WidgetBundle {
  var body: some Widget { CalendarLiveActivityWidget() }
}

struct CalendarLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CalendarActivityAttributes.self) { context in
      TimelineView(.periodic(from: .now, by: 1)) { timeline in
        activityCard(context, now: timeline.date)
          .padding(16)
          .activityBackgroundTint(Color(uiColor: .secondarySystemBackground).opacity(0.88))
          .activitySystemActionForegroundColor(.primary)
      }
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.bottom) {
          TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: .leading, spacing: 8) {
            // Keep the status below the camera cutout, in the full-width region.
            Label(statusLabel(context, now: timeline.date), systemImage: statusIcon(context, now: timeline.date))
              .font(.caption.weight(.semibold))
              .foregroundStyle(statusColor(context, now: timeline.date))
              .lineLimit(1)
              .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline) {
              Text(context.state.title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
              Spacer(minLength: 12)
              countdown(context, now: timeline.date)
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(eventColor(context))
                .frame(width: 100, alignment: .trailing)
            }
            Label(isFinished(context, now: timeline.date) ? "일정이 종료되었습니다" : timeRange(context), systemImage: "clock")
              .font(.caption)
              .foregroundStyle(.secondary)
            elapsedProgress(context, now: timeline.date)
              .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 8)
          }
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
      Text("종료")
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
    Group {
      if isFinished(context, now: now) {
        ProgressView(value: 1.0)
      } else if !hasStarted(context, now: now) {
        ProgressView(value: 0.0)
      } else {
        ProgressView(
          timerInterval: context.state.start...context.state.end,
          countsDown: false,
          label: { EmptyView() },
          currentValueLabel: { EmptyView() }
        )
      }
    }
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
    now >= context.state.end
  }

  private func hasStarted(_ context: ActivityViewContext<CalendarActivityAttributes>, now: Date = .now) -> Bool {
    now >= context.state.start
  }

  private func statusLabel(_ context: ActivityViewContext<CalendarActivityAttributes>, now: Date) -> String {
    isFinished(context, now: now) ? "일정 종료" : hasStarted(context, now: now) ? "진행 중" : "시작 예정"
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
