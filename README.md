# calendar_app_flutter

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## 계정별 일정 동기화

로그인한 계정의 일정은 `calendar_api`의 PostgreSQL에 저장됩니다. 로그인·앱 복귀·일정 변경 시, 그리고 앱 사용 중 15초마다 동기화합니다. 오프라인 변경은 기기에 보관했다가 재전송합니다. 게스트 일정은 로컬에 저장하며, 업데이트 전 로컬 일정은 처음 로그인하는 계정으로 한 번 이전합니다.

두 기기 모두 같은 계정과 같은 API 서버를 사용해야 합니다. 실기기에서는 `localhost` 대신 두 기기에서 접근 가능한 서버 주소로 빌드하세요.

```sh
flutter run --dart-define=API_BASE_URL=http://YOUR_SERVER_IP:3001
```

서버 변경을 적용하려면 `calendar_api`를 다시 실행해야 합니다. 시작 시 `calendar_events` 테이블을 자동 생성합니다. 같은 일정을 동시에 수정하면 수정 시각이 최신인 내용이 반영되며, 삭제는 오래된 기기의 수정·재전송보다 우선합니다. Apple 캘린더 식별자는 각 기기에만 보관합니다. 이 기능은 앱 계정의 일정 동기화이며 외부 캘린더 제공자의 동기화 설정과는 별개입니다.

## Android 에뮬레이터의 로컬 소셜 로그인

OAuth 서버의 `PUBLIC_BASE_URL=http://localhost:3001` 설정을 사용할 때는
브라우저의 콜백도 PC 서버에 도달하도록 ADB 포트 전달이 필요합니다.
앱의 API 주소를 `10.0.2.2`로 변환하는 것만으로는 OAuth 콜백이 바뀌지 않습니다.

에뮬레이터를 켠 뒤 VS Code에서 **Calendar App (Android local server)** 실행
구성을 선택하면 `emulator-5554`에 포트 전달을 자동 적용합니다.
터미널에서는 다음과 같이 실행합니다.

```sh
sh scripts/android-local-server.sh emulator-5554
flutter run -d emulator-5554
```

기기 ID가 다르면 `flutter devices`로 확인한 ID를 사용하세요. 에뮬레이터나
ADB를 재시작하면 포트 전달을 다시 적용해야 합니다. API 서버는 PC의
3001번 포트에서 실행 중이어야 합니다.

## Android 일정 실시간 업데이트

설정 → **일정 실시간 업데이트**에서 진행 중이거나 10분 이내에 시작하는 시간
지정 일정을 선택합니다. 한 번에 한 일정을 표시하며 종일 일정은 제외합니다.
알림 권한이 필요하고, 알림창에서 **실시간 업데이트 종료**를 눌러 중지할 수 있습니다.

- 일정 제목, 시작/종료 시간, 상태, 시스템 카운트다운, 일정 색상의 진행 막대를 표시합니다.
- Android 16+는 `Notification.ProgressStyle`을 사용하며, 지원되는 OS와 사용자
  설정에서는 정식 Live Update로 승격됩니다. 이전 버전은 지속 진행 알림을 사용합니다.
- 사용자가 시작한 알림만 네이티브 foreground service로 유지합니다. 초 단위
  카운트다운은 시스템이 그리며 진행률은 15초 간격으로 갱신합니다. 일정이 끝나면
  종료하며 앱을 다시 열 필요가 없습니다. 강제 종료 및 기기 재부팅은 제외합니다.
- 앱에서 선택한 일정이 수정/삭제되면 다음 동기화에서 알림에도 반영됩니다.
  알림을 종료한 뒤에는 자동으로 다시 띄우지 않습니다.

Android 정식 Live Update는 커스텀 RemoteViews를 허용하지 않으므로, Apple
실시간 현황의 정보와 색상을 시스템 알림 레이아웃에 맞춰 표시합니다.
