# Windows 위젯과 바탕화면 미니 창

앱 설정의 **Windows 위젯 → 공식 위젯 및 바탕화면 미니 창**에서 오늘 일정,
월간 달력, 다가오는 일정 창을 열 수 있다. 미니 창은 별도 프로세스로 실행되어
본 앱을 닫아도 유지된다. 제목 표시줄로 이동·크기 변경, 핀 버튼으로 항상 위에
표시할 수 있다. 창 위치와 크기는 종류별로 보관되며 모니터를 바꾸면 화면 안으로
다시 배치된다. 같은 종류를 다시 열면 기존 창을 활성화한다.

공식 위젯은 Windows 11 위젯 보드(Win+W)의 **위젯 추가**에서
`일상 캘린더 · 오늘 일정`, `월간 달력`, `다가오는 일정`을 선택한다.
오늘 일정과 다가오는 일정은 소형·중형·대형, 월간 달력은 중형·대형을 지원한다.
Windows Web Experience Pack과 Microsoft Windows App Runtime 2.3.1 이상이 필요하다.

## 빌드와 설치

Flutter 앱은 기존 Windows 빌드로 실행한다. 공식 위젯 공급자는 별도 C# MSIX
패키지이며 Microsoft 로그인을 추가하지 않는다. .NET 8 SDK와 Windows SDK의
`makeappx.exe`가 필요하다. 공급자에는 .NET 런타임이 포함된다.

```powershell
flutter build windows
powershell -NoProfile -ExecutionPolicy Bypass -File tool/build_windows_widgets.ps1 -Install
# PATH에 dotnet이 없으면 -DotNet C:/path/to/dotnet.exe 추가
```

스크립트는 `build/windows-widgets/IlsangCalendar.Widgets.msix`를 검증하여 만들고,
`-Install`이면 개발자 모드에서 현재 사용자에게 loose package로 등록한다.
인증서 저장소를 바꾸지 않는다. 설치 위치는
`%LOCALAPPDATA%/IlsangCalendar/WindowsWidgetsPackage/<version>`이다.
업데이트마다 버전을 올려 실행 중인 공급자의 파일 잠금을 피한다.
다른 PC에 MSIX로 배포하려면 서명된 패키지와 위 Windows App Runtime이 필요하다.

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
내보내는 읽기 전용 표시 데이터를 두 화면이 공유한다. 로그인 계정의 표시 대상
개인 일정과 가져온 일정을 합치고 이번 달과 다음 달의 반복 일정을 확장한다.
날짜, 제목(최대 120자), 시간, 길이, 색만 최대 500개 저장한다.
계정 ID, 인증 토큰, 설명, 위치는 내보내지 않는다. 현재·미래 일정을 먼저 보관한다.
공식 위젯은 약 3초, 미니 창은 약 5초 내 변경을 반영한다.
계정 전환·로그아웃·세션 복원 실패 시 표시 데이터를 비운다.

앱이 종료되면 마지막 데이터로 표시한다. 두 화면에서 서버 동기화를 따로 하지
않으므로 최신 일정은 본 앱을 열어 동기화해야 한다. 스냅샷 범위 밖의 달에는
날짜만 표시된다. 앱에서 일정 이름을 수정하거나 삭제하면 다음 반영 시 갱신된다.
이 PC에 같은 Windows 사용자로 로그인한 프로세스는 표시 데이터에 접근할 수 있다.

공식 위젯에서 **캘린더 열기**는 기존 본 앱을 활성화하거나 마지막으로 실행한
앱을 연다. 본 앱을 옮겼다면 새 위치에서 한 번 실행하면 연결이 갱신된다.

구현 기준: [Microsoft 공식 공급자 문서](https://learn.microsoft.com/en-us/windows/apps/develop/widgets/implement-widget-provider-cs),
[패키지 매니페스트](https://learn.microsoft.com/en-us/windows/apps/develop/widgets/widget-provider-manifest).
