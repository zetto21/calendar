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
