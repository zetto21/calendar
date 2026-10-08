# Windows 공식 위젯

앱 설정의 **Windows 위젯 → 공식 Windows 위젯**에서 추가 방법을 확인할 수 있다.

공식 위젯은 Windows 11 위젯 보드(Win+W)의 **위젯 추가**에서
`일상 캘린더 · 오늘 일정`, `월간 달력`, `다가오는 일정`을 선택한다.
오늘 일정과 다가오는 일정은 소형·중형·대형, 월간 달력은 중형·대형을 지원한다.
Windows Web Experience Pack과 Microsoft Windows App Runtime 2.3.1 이상이 필요하다.

## 빌드와 설치

설치 패키지는 Flutter 본 앱과 C# 공식 위젯 공급자를 함께 포함한다. 설치된 앱과
시작 메뉴에는 `일상 캘린더`, 제작사에는 `zetto`를 표시한다. 공급자만 실행하는
위젯 항목은 시작 메뉴에서 숨긴다. Microsoft 로그인을 추가하지 않는다. .NET 8 SDK와 Windows SDK의
`makeappx.exe`가 필요하다. 공급자에는 .NET 런타임이 포함된다.

```powershell
flutter build windows --release
powershell -NoProfile -ExecutionPolicy Bypass -File tool/build_windows_widgets.ps1 -Install
# PATH에 dotnet이 없으면 -DotNet C:/path/to/dotnet.exe 추가
# 다른 경로에서 빌드했다면 -AppDirectory C:/path/to/runner/Release 추가
```

스크립트는 `build/windows-widgets/IlsangCalendar.Widgets.msix`를 검증하여 만들고,
`-Install`이면 개발자 모드에서 현재 사용자에게 loose package로 등록한다.
인증서 저장소를 바꾸지 않는다. 설치 위치는
`%LOCALAPPDATA%/IlsangCalendar/WindowsWidgetsPackage/<version>`이다.
업데이트마다 버전을 올려 실행 중인 공급자의 파일 잠금을 피한다.
다른 PC에 MSIX로 배포하려면 서명된 패키지와 위 Windows App Runtime이 필요하다.
버전은 `pubspec.yaml`의 앱 버전에 설치 리비전을 붙여 사용한다(예: `0.1.1.5`).
기존 위젯 연결을 보존하기 위해 내부 패키지 ID와 게시자 인증서 식별자는 유지한다.
첫 통합 설치에서는 이전 공급자 버전 `1.0.0.x`를 앱 버전으로 맞추기 위해
`-ForceUpdateFromAnyVersion`을 사용한다. Windows의 설치 앱 목록에서 버전 표시
위치는 OS가 정하며, 본 앱 설정의 프로그램 정보에서는 실행 중인 실제 버전을 읽는다.

```powershell
# 카드 생성·날짜 배치·로그아웃 확인
build/windows-widgets/package/Provider/IlsangWidgets.exe --self-test
# 설치된 COM 공급자가 실제로 활성화되는지 확인
build/windows-widgets/package/Provider/IlsangWidgets.exe --probe
Get-Content "$env:LOCALAPPDATA/IlsangCalendar/widgets/self-test.txt"
Get-Content "$env:LOCALAPPDATA/IlsangCalendar/widgets/probe.txt"
flutter test test/home_widget_test.dart test/windows_widgets_test.dart
```

제거는 `Get-AppxPackage IlsangCalendar.Widgets | Remove-AppxPackage`로 한다.
이 명령은 일상 캘린더의 위젯 패키지만 제거한다.

## 일정 데이터

본 앱이 `%LOCALAPPDATA%/IlsangCalendar/widgets/snapshot.json`에 원자적으로
내보내는 읽기 전용 표시 데이터를 공식 위젯이 읽는다. 로그인 계정의 표시 대상
개인 일정과 가져온 일정을 합치고 이번 달과 다음 달의 반복 일정을 확장한다.
날짜, 제목(최대 120자), 시간, 길이, 색만 최대 500개 저장한다.
계정 ID, 인증 토큰, 설명, 위치는 내보내지 않는다. 현재·미래 일정을 먼저 보관한다.
공식 위젯은 3초마다 변경을 확인해 자동으로 반영한다. 새로고침 버튼은 표시하지
않으며, Windows 호스트가 갱신을 거절하면 다음 주기에 다시 시도한다.
계정 전환·로그아웃·세션 복원 실패 시 표시 데이터를 비운다.

앱이 종료되면 마지막 데이터로 표시한다. 공식 위젯에서 서버 동기화를 따로 하지
않으므로 최신 일정은 본 앱을 열어 동기화해야 한다.
앱에서 일정 이름을 수정하거나 삭제하면 다음 반영 시 갱신된다.
이 PC에 같은 Windows 사용자로 로그인한 프로세스는 표시 데이터에 접근할 수 있다.

공식 위젯에서 **캘린더 열기**는 기존 본 앱을 활성화하거나 마지막으로 실행한
앱을 연다. 본 앱을 옮겼다면 새 위치에서 한 번 실행하면 연결이 갱신된다.

구현 기준: [Microsoft 공식 공급자 문서](https://learn.microsoft.com/en-us/windows/apps/develop/widgets/implement-widget-provider-cs),
[패키지 매니페스트](https://learn.microsoft.com/en-us/windows/apps/develop/widgets/widget-provider-manifest).
