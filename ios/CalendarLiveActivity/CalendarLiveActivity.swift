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
      TimelineView(.periodic(from: .now, by: 1)) { _ in
        activityCard(context)
          .padding(16)
          .activityBackgroundTint(Color(uiColor: .secondarySystemBackground).opacity(0.88))
          .activitySystemActionForegroundColor(.primary)
      }
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.bottom) {
          TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 8) {
            // Keep the status below the camera cutout, in the full-width region.
            Label(statusLabel(context), systemImage: statusIcon(context))
              .font(.caption.weight(.semibold))
              .foregroundStyle(statusColor(context))
              .lineLimit(1)
              .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline) {
              Text(context.state.title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
              Spacer(minLength: 12)
              countdown(context)
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(eventColor(context))
                .frame(width: 100, alignment: .trailing)
            }
            Label(isFinished(context) ? "일정이 종료되었습니다" : timeRange(context), systemImage: "clock")
              .font(.caption)
              .foregroundStyle(.secondary)
            elapsedProgress(context)
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
  private func activityCard(_ context: ActivityViewContext<CalendarActivityAttributes>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(statusLabel(context), systemImage: statusIcon(context))
        .font(.caption.weight(.semibold))
        .foregroundStyle(statusColor(context))
        .lineLimit(1)
      HStack(alignment: .firstTextBaseline) {
        Text(context.state.title)
          .font(.headline.weight(.semibold))
          .lineLimit(1)
          .truncationMode(.tail)
          .layoutPriority(1)
        Spacer(minLength: 12)
          countdown(context)
            .font(.title2.bold())
            .monospacedDigit()
            .foregroundStyle(eventColor(context))
          .frame(width: 100, alignment: .trailing)
      }
      Label(isFinished(context) ? "일정이 종료되었습니다" : timeRange(context), systemImage: "clock")
        .font(.caption)
        .foregroundStyle(.secondary)
      elapsedProgress(context)
        .padding(.top, 4)
    }
  }

  @ViewBuilder
  private func countdown(_ context: ActivityViewContext<CalendarActivityAttributes>) -> some View {
    if isFinished(context) {
      Text("종료")
    } else if !hasStarted(context) {
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
  private func elapsedProgress(_ context: ActivityViewContext<CalendarActivityAttributes>) -> some View {
    Group {
      if isFinished(context) {
        ProgressView(value: 1.0)
      } else if !hasStarted(context) {
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
    .tint(isFinished(context) ? Color.green : eventColor(context))
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

  private func isFinished(_ context: ActivityViewContext<CalendarActivityAttributes>) -> Bool {
    Date.now >= context.state.end
  }

  private func hasStarted(_ context: ActivityViewContext<CalendarActivityAttributes>) -> Bool {
    Date.now >= context.state.start
  }

  private func statusLabel(_ context: ActivityViewContext<CalendarActivityAttributes>) -> String {
    isFinished(context) ? "일정 종료" : hasStarted(context) ? "진행 중" : "시작 예정"
  }

  private func statusIcon(_ context: ActivityViewContext<CalendarActivityAttributes>) -> String {
    isFinished(context) ? "checkmark.circle.fill" : hasStarted(context) ? "calendar.badge.clock" : "calendar"
  }

  private func statusColor(_ context: ActivityViewContext<CalendarActivityAttributes>) -> Color {
    isFinished(context) ? .green : .orange
  }

  private func timeRange(_ context: ActivityViewContext<CalendarActivityAttributes>) -> String {
    let format = Date.FormatStyle(date: .omitted, time: .shortened)
      .locale(Locale(identifier: "ko_KR"))
    return "\(context.state.start.formatted(format)) – \(context.state.end.formatted(format))"
  }
}
