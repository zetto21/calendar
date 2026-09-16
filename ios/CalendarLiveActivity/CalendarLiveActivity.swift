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
      activityCard(context)
      .padding(16)
      .activityBackgroundTint(Color(uiColor: .secondarySystemBackground).opacity(0.88))
      .activitySystemActionForegroundColor(.primary)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 8) {
            // Keep the status below the camera cutout, in the full-width region.
            Label(context.isStale ? "일정 종료" : "진행 중", systemImage: "calendar.badge.clock")
              .font(.caption.weight(.semibold))
              .foregroundStyle(context.isStale ? .green : .blue)
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
                .foregroundStyle(.blue)
                .frame(width: 100, alignment: .trailing)
            }
            Label(context.isStale ? "일정이 종료되었습니다" : timeRange(context), systemImage: "clock")
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
  private func activityCard(_ context: ActivityViewContext<CalendarActivityAttributes>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(context.isStale ? "일정 종료" : "진행 중", systemImage: "calendar.badge.clock")
        .font(.caption.weight(.semibold))
        .foregroundStyle(context.isStale ? .green : .blue)
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
          .foregroundStyle(.blue)
          .frame(width: 100, alignment: .trailing)
      }
      Label(context.isStale ? "일정이 종료되었습니다" : timeRange(context), systemImage: "clock")
        .font(.caption)
        .foregroundStyle(.secondary)
      elapsedProgress(context)
        .padding(.top, 4)
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

  @ViewBuilder
  private func elapsedProgress(_ context: ActivityViewContext<CalendarActivityAttributes>) -> some View {
    Group {
      if context.isStale {
        ProgressView(value: 1.0)
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
    .tint(context.isStale ? Color.green : Color.blue)
    .accessibilityLabel("일정 경과 시간")
  }

  private func timeRange(_ context: ActivityViewContext<CalendarActivityAttributes>) -> String {
    let format = Date.FormatStyle(date: .omitted, time: .shortened)
      .locale(Locale(identifier: "ko_KR"))
    return "\(context.state.start.formatted(format)) – \(context.state.end.formatted(format))"
  }
}
