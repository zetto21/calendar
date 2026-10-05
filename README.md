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
flutter run --dart-define=API_BASE_URL=https://YOUR_API_HOST
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

## 보안 설정과 배포

Release 빌드의 `API_BASE_URL`은 경로·쿼리·사용자 정보 없는 HTTPS 출처여야 합니다. 기본값은 `https://api.ilsangcal.com`입니다. API 요청은 리디렉션을 거부하고 응답 크기·JSON 중첩·시간을 제한하며, 시간 초과 시 실제 전송을 취소합니다. Debug의 API 요청은 HTTP를 허용하지만 Android 네이티브 정책은 localhost·127.0.0.1·::1·10.0.2.2만 예외로 둡니다. OAuth 브라우저의 HTTP 예외도 이 개발 주소에 한정합니다.

소셜 로그인은 앱이 만든 일회성 verifier와 서버가 보관하는 SHA-256 challenge를 결합합니다. `calendar_api`의 `client_challenge`/`clientVerifier` 지원을 **먼저 배포한 뒤 앱을 배포**하세요. 서버 시작 시 관련 DB 열을 자동 추가합니다. 업데이트된 서버는 이전 앱의 로그인도 지원하지만, 이전 서버는 새 앱의 교환 요청을 처리하지 못합니다. 공급자 클라이언트 시크릿과 DB 접속 정보는 앱에 넣지 않습니다.

웹 로그인은 해당 popup의 출처와 창 식별자를 모두 확인합니다. 인증 코드는 저장소에 쓰지 않고 콜백 URL에서 즉시 제거합니다. Bearer 세션은 탭의 `sessionStorage`에만 저장하며, 예전 `localStorage` 세션은 삭제하므로 업데이트 후 다시 로그인해야 합니다. 새 세션은 같은 탭의 새로고침에는 유지됩니다. 이 저장소도 JavaScript에서 접근 가능하므로 웹 배포의 스크립트와 호스팅을 함께 보호해야 합니다. 웹의 외부 캘린더 연결은 현재 서버가 네이티브 콜백만 제공하므로 지원하지 않습니다.

macOS 세션은 Data Protection Keychain의 잠금 해제 상태·현재 기기 전용 항목으로 보관합니다. 기존 항목은 새 항목 저장이 성공한 뒤 이전하며 동기화를 사용하지 않습니다. 다른 네이티브 플랫폼의 세션은 현재 메모리에만 보관합니다. 로그아웃·계정 변경 이후 늦게 도착한 로그인, 동기화, 편집, 가져오기 결과는 계정 세대로 검사하여 이전 계정 자료가 새 계정에 적용되지 않도록 합니다. 로컬 세션 삭제 실패에도 서버 세션 폐기를 시도합니다.

백업 복원은 파일 8MiB·10,000건·JSON 깊이 32로 제한하고 날짜·시간·기간·색상·필드 형식을 검증합니다. 원본 Apple 캘린더 식별자는 복원하지 않아 백업이 기존 기기 일정을 임의로 수정할 수 없도록 합니다. CSV 수식과 ICS 줄 삽입을 처리하고, 복원 시 수정 시각을 현재 시각으로 설정합니다. 내보내기는 임시 `calendar-exports/backup-*` 폴더의 파일당 20MiB로 제한합니다. iOS 파일 공유 채널은 이 폴더의 일반 파일만 허용하고 경로 이탈과 심볼릭 링크를 거부합니다. 현재 네이티브 파일 내보내기 채널은 iOS에만 구현되어 있습니다.

Android는 앱 자료의 자동 백업과 기기 이전을 차단하며 Release의 평문 HTTP를 차단합니다. Release는 debug 키로 서명하지 않습니다. 배포 서명은 저장소에 넣지 않는 `android/key.properties`로 설정하세요. 이 파일이 없으면 빌드는 서명되지 않은 산출물을 생성합니다.

```properties
storeFile=/absolute/path/to/your-release-keystore.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

`storeFile`의 상대 경로는 `android` 디렉터리를 기준으로 합니다. `key.properties`와 keystore는 git에서 제외되어 있습니다. 기존 배포 앱을 업데이트할 때는 기존 배포 서명 키를 사용하세요.

## 보안 변경 검증

```sh
dart analyze
flutter test --no-pub
flutter test --no-pub --platform chrome test/oauth_browser_web_test.dart test/web_session_security_test.dart
node test/web_auth_callback_test.mjs
python3 tool/check_native_security.py
flutter build web --release --dart-define=API_BASE_URL=https://api.example.com
```

네이티브 검사 도구는 Android 정책과 Swift의 파일 경로·EventKit 입력·Keychain 이전/실패 동작을 모의 환경에서 검사하며 실제 사용자 Keychain을 변경하지 않습니다. Android Release APK(서명 없음), macOS Debug와 iOS Simulator Debug(코드 서명 없음)의 빌드도 확인했습니다. 실제 공급자 계정으로 하는 OAuth와 실기기의 Keychain·공유 동작, 배포용 서명은 별도 기기 검증이 필요합니다. 2026-10-04 OSV의 Pub 생태계 조회에서는 잠금 파일의 hosted 패키지 95개에 대해 알려진 보안 권고가 발견되지 않았습니다.
