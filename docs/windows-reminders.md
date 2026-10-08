# Windows 일정 알림

설정 → 알림 → 일정 시작 알림에서 이 PC의 현재 계정에 대해 켜거나 끈다.
기본값은 켜짐이며 시작 10분 전 알림과 Windows의 5분 다시 알림을 제공한다.
설정의 알림 테스트로 Windows 배너 표시를 확인할 수 있다.

화면에 표시되는 개인·구독 일정 중 시간이 지정된 일정이 대상이다. 하루 종일
일정과 공휴일·절기·기념일은 제외한다. 반복 일정을 확장하여 앞으로 7일간,
최대 256개를 Windows에 예약한다. 이미 알림 시각이 지난 일정은 새로 알리지 않는다.
앱 실행 중 변경·삭제·숨김과 로그아웃에 맞춰 예약 및 알림 기록을 정리한다.
내용이 같은 예약은 다시 등록하지 않는다. 계정별 켜짐 설정은 기기에 저장한다.

Windows 예약 알림을 사용하므로 예약 후 앱을 닫아도 알림이 전달된다. PC가 꺼져
있거나 Windows 알림/방해 금지 설정이 적용되면 배너가 표시되지 않을 수 있다.
앱이 닫혀 있는 동안 다른 기기에서 한 수정과 7일 이후 일정은 다시 실행할 때
반영된다. 네트워크 폴링을 위해 앱을 백그라운드에 상주시킬 필요는 없다.

Win32 시작 메뉴 바로가기에 AppUserModelID를 지정하고 Windows.UI.Notifications의
ScheduledToastNotification을 사용한다. 예약 제목·시간은 Windows가 로컬에 보관한다.
일정 원문은 XML 텍스트로 이스케이프하고 알림 식별자는 계정·일정의 해시를 사용한다.
기존 macOS 및 모바일 알림 구현은 변경하지 않는다.

검증:

```powershell
flutter test test/windows_event_reminders_test.dart
# 앱을 종료한 상태에서 예약·중복 방지·시간 수정·취소를 검사한다. 테스트 알림은 표시하지 않는다.
calendar_app_flutter.exe --reminders-smoke-test
```

구현 기준: [Windows 예약 알림](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/app-notifications-scheduled),
[Win32 알림 ID](https://learn.microsoft.com/en-us/windows/win32/shell/enable-desktop-toast-with-appusermodelid),
[시스템 다시 알림](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/adaptive-interactive-toasts).
