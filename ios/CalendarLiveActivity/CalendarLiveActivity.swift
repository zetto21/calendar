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
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: context.isStale ? "checkmark.circle.fill" : "calendar.badge.clock")
          .font(.title2)
          .foregroundStyle(context.isStale ? .green : .blue)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 7) {
          Text(context.state.title)
            .font(.headline.weight(.semibold))
            .lineLimit(1)
          Label {
            Text(context.isStale ? "일정이 종료되었습니다" : "진행 중 · \(timeRange(context))")
          } icon: {
            Image(systemName: "clock")
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 5) {
          Text(context.isStale ? "완료" : "남은 시간")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
          countdown(context)
            .font(.title2.bold())
            .monospacedDigit()
        }
      }
      .padding(16)
      .activityBackgroundTint(Color(uiColor: .secondarySystemBackground).opacity(0.88))
      .activitySystemActionForegroundColor(.primary)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label(context.isStale ? "일정 종료" : "진행 중", systemImage: "calendar.badge.clock")
            .font(.caption.weight(.semibold))
            .foregroundStyle(context.isStale ? .green : .blue)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 8) {
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
                .foregroundStyle(.blue)
                .frame(width: 100, alignment: .trailing)
            }
            Label(context.isStale ? "일정이 종료되었습니다" : timeRange(context), systemImage: "clock")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 4)
          .padding(.bottom, 8)
        }
      } compactLeading: {
        Image(systemName: "calendar").foregroundStyle(.blue)
      } compactTrailing: {
        countdown(context).monospacedDigit().frame(width: 54)
      } minimal: {
        Image(systemName: context.isStale ? "checkmark.circle.fill" : "calendar.badge.clock")
          .foregroundStyle(.blue)
      }
      .keylineTint(.blue)
    }
  }

  @ViewBuilder
  private func countdown(_ context: ActivityViewContext<CalendarActivityAttributes>) -> some View {
    if context.isStale {
      Text("종료")
    } else {
      Text(timerInterval: context.state.start...context.state.end, countsDown: true)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .multilineTextAlignment(.trailing)
        .accessibilityLabel("종료까지 남은 시간")
    }
  }

  private func timeRange(_ context: ActivityViewContext<CalendarActivityAttributes>) -> String {
    "\(context.state.start.formatted(date: .omitted, time: .shortened)) – \(context.state.end.formatted(date: .omitted, time: .shortened))"
  }
}
