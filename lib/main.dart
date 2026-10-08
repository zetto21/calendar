import 'widgets/app_dialog.dart';
import 'services/desktop_notifications.dart';

import 'dart:async';
import 'dart:convert';

import 'widgets/personal_calendars.dart';

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart' show debugPaintBaselinesEnabled;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import 'logic/date_utils.dart' as date_utils;
import 'logic/event_dedup.dart';
import 'logic/event_details.dart' show wallTimeToDate;
import 'logic/quick_add.dart';
import 'logic/recurrence.dart';
import 'logic/security_urls.dart';
import 'models/calendar_event.dart';
import 'native/home_widget.dart';
import 'native/eventkit.dart';
import 'native/live_activity.dart';
import 'native/macos_window.dart';
import 'screens/event_sheet.dart';
import 'screens/list_view.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_guide.dart';
import 'screens/signup_screen.dart';
import 'screens/search_screen.dart';
import 'screens/time_grid_view.dart';
import 'services/auth_service.dart';
import 'services/app_update_service.dart';
import 'services/backup_service.dart';
import 'services/kbo_schedule.dart';
import 'services/oauth_browser.dart';
import 'storage/event_store.dart';
import 'storage/display_settings.dart';
import 'storage/account_preferences.dart';
import 'storage/imported_events.dart';
import 'sync/system_events_sync.dart';
import 'theme/app_theme.dart';
import 'screens/month_agenda.dart';
import 'screens/settings_screen.dart';
import 'widgets/top_bar.dart';
import 'widgets/command_palette.dart';
import 'widgets/macos_calendar_shell.dart';
import 'widgets/calendar_view_transition.dart';
import 'widgets/imported_calendar_group.dart';
import 'widgets/subscription_dialog.dart';
import 'widgets/liquid_glass.dart';
import 'widgets/server_connection_monitor.dart';
import 'widgets/consent_gate.dart';
import 'platform.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux) &&
      runWebViewTitleBarWidget(args)) {
    return;
  }
  assert(() {
    // Baseline guides are a Flutter Inspector aid, never application UI.
    debugPaintBaselinesEnabled = false;
    return true;
  }());
  tz_data.initializeTimeZones();
  // Phase 1 targets Korean users only; skip a native-timezone-detection
  // plugin for this single, fixed zone (see event_details.dart for where a
  // real IANA Location matters — DST-safe wall-clock conversion).
  final deviceZone = tz.getLocation('Asia/Seoul');
  final store = EventStore();
  final importedEvents = ImportedEvents();
  await AccountPreferences.instance.selectAccount(null);
  await store.load();
  await importedEvents.load();
  await DisplaySettings.instance.load();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider.value(value: importedEvents),
      ],
      child: CalendarApp(deviceZone: deviceZone),
    ),
  );
}

class CalendarApp extends StatelessWidget {
  final tz.Location deviceZone;
  const CalendarApp({super.key, required this.deviceZone});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '캘린더',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildMaterialTheme(lightTheme),
      darkTheme: buildMaterialTheme(darkTheme),
      builder: (context, child) {
        if (kIsWeb || !useDesktopLayout) {
          return child!;
        }
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(_desktopTextScale)),
          child: child!,
        );
      },
      // First-run consent precedes login, session restoration and API probes.
      home: ConsentGate(
        child: ServerConnectionMonitor(child: AuthGate(deviceZone: deviceZone)),
      ),
    );
  }
}

/// 데스크톱 전체 글자 크기 배율 (1.0 = 기본).
const double _desktopTextScale = 0.9;

enum _AuthScreen { login, signup }

/// Port of App.tsx's auth gating: wait for a stored session to be restored,
/// then show login/signup or the authenticated calendar.
class AuthGate extends StatefulWidget {
  final tz.Location deviceZone;
  const AuthGate({super.key, required this.deviceZone});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  AuthUser? _user;
  _AuthScreen _screen = _AuthScreen.login;
  int _authGeneration = 0;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    unawaited(MacosWindow.showCalendar(false));
    unawaited(_restoreSession());
  }

  Future<void> _restoreSession() async {
    try {
      final user = await AuthService.instance.restoreSession();
      if (mounted && _authGeneration == 0 && user != null) {
        await _acceptUser(user);
      }
    } catch (error) {
      debugPrint('Could not restore the saved session (${error.runtimeType})');
    } finally {
      if (mounted && _authGeneration == 0) {
        await CalendarHomeWidget.clear();
        if (mounted && _authGeneration == 0) {
          setState(() => _loading = false);
        }
      }
    }
  }

  Future<void> _acceptUser(AuthUser? user) async {
    final generation = ++_authGeneration;
    await CalendarHomeWidget.clear();
    if (!mounted || generation != _authGeneration) return;
    setState(() => _loading = true);
    final imports = context.read<ImportedEvents>();
    final events = context.read<EventStore>();
    await events.selectAccount(user?.id);
    if (!mounted || generation != _authGeneration) return;
    await events.sync();
    if (!mounted || generation != _authGeneration) return;
    await AccountPreferences.instance.selectAccount(user?.id);
    if (!mounted || generation != _authGeneration) return;
    await AccountPreferences.instance.sync();
    if (!mounted || generation != _authGeneration) return;
    await DisplaySettings.instance.load();
    if (!mounted || generation != _authGeneration) return;
    await imports.load();
    if (!mounted || generation != _authGeneration) return;
    await MacosWindow.showCalendar(user != null);
    if (!mounted || generation != _authGeneration) return;
    // Account-store notifications can enqueue updates while the old view exits.
    await CalendarHomeWidget.clear();
    if (!mounted || generation != _authGeneration) return;
    setState(() {
      _user = user;
      _loading = false;
      _screen = _AuthScreen.login;
    });
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    final generation = _authGeneration;
    var incomplete = false;
    var guestGeneration = generation;
    try {
      try {
        await LiveActivity.end();
      } catch (_) {
        incomplete = true;
      }
      if (!mounted || generation != _authGeneration) return;
      try {
        if (_user != null) await AuthService.instance.logout();
      } catch (_) {
        incomplete = true;
      }
    } finally {
      // Credential deletion or remote revocation failures must still remove
      // the authenticated calendar from the screen. A newer login wins.
      if (mounted && generation == _authGeneration) {
        guestGeneration = generation + 1;
        try {
          await _acceptUser(null);
        } catch (_) {
          incomplete = true;
          if (mounted && guestGeneration == _authGeneration) {
            setState(() {
              _user = null;
              _loading = false;
              _screen = _AuthScreen.login;
            });
          }
        }
      }
      _loggingOut = false;
    }
    if (!mounted ||
        !incomplete ||
        guestGeneration != _authGeneration ||
        _user != null) {
      return;
    }
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: const Text('로그아웃 안내'),
        content: const Text(
          '로그인 화면으로 이동했습니다. 일부 로그인 정보나 실시간 활동을 종료하지 못했을 수 있습니다. 연결 상태를 확인해 주세요.',
        ),
        actions: [
          AppDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).brightness == Brightness.dark
        ? darkTheme
        : lightTheme;
    if (_loading) {
      return Scaffold(
        backgroundColor: theme.bg,
        body: Center(
          child: Text(
            '로그인 정보를 확인하고 있습니다…',
            style: TextStyle(color: theme.textMuted),
          ),
        ),
      );
    }
    if (_user == null) {
      if (_screen == _AuthScreen.signup) {
        return SignupScreen(
          theme: theme,
          onAuthenticated: _acceptUser,
          onBack: () => setState(() => _screen = _AuthScreen.login),
        );
      }
      return LoginScreen(
        theme: theme,
        onAuthenticated: _acceptUser,
        onSignup: () => setState(() => _screen = _AuthScreen.signup),
      );
    }
    return CalendarHome(
      deviceZone: widget.deviceZone,
      user: _user,
      onLogout: _logout,
    );
  }
}

class CalendarHome extends StatefulWidget {
  final tz.Location deviceZone;
  final AuthUser? user;
  final VoidCallback onLogout;
  const CalendarHome({
    super.key,
    required this.deviceZone,
    required this.user,
    required this.onLogout,
  });

  @override
  State<CalendarHome> createState() => _CalendarHomeState();
}

class _CalendarHomeState extends State<CalendarHome>
    with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  Widget? _eventSidePanel;
  ViewMode _view = ViewMode.month;
  bool _showPersonalCalendar = true;
  List<PersonalCalendar> _personalCalendars = [PersonalCalendar.initial];
  static const _personalCalendarsKey = 'calendar.personal.lists.v1';

  Future<void> _loadPersonalCalendars() async {
    final raw = await AccountPreferences.instance.get(_personalCalendarsKey);
    if (!mounted || raw is! String) return;
    final calendars = (jsonDecode(raw) as List)
        .map(
          (item) =>
              PersonalCalendar.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    if (!calendars.any((calendar) => calendar.id == 'personal')) {
      calendars.insert(0, PersonalCalendar.initial);
    }
    setState(() => _personalCalendars = calendars);
  }

  Future<void> _savePersonalCalendar(PersonalCalendar calendar) async {
    final calendars = [..._personalCalendars];
    final index = calendars.indexWhere((item) => item.id == calendar.id);
    if (index < 0) {
      calendars.add(calendar);
    } else {
      calendars[index] = calendar;
    }
    await AccountPreferences.instance.set(
      _personalCalendarsKey,
      jsonEncode(calendars.map((item) => item.toJson()).toList()),
    );
    if (mounted) setState(() => _personalCalendars = calendars);
  }

  Future<void> _deletePersonalCalendar(PersonalCalendar calendar) async {
    if (calendar.id == 'personal') return;
    final calendars = _personalCalendars
        .where((item) => item.id != calendar.id)
        .toList();
    await AccountPreferences.instance.set(
      _personalCalendarsKey,
      jsonEncode(calendars.map((item) => item.toJson()).toList()),
    );
    if (mounted) setState(() => _personalCalendars = calendars);
  }

  Widget _personalCalendarControls() => PersonalCalendars(
    calendars: _personalCalendars,
    onSave: _savePersonalCalendar,
    onDelete: _deletePersonalCalendar,
    personalVisible: _showPersonalCalendar,
    onPersonalVisibilityChanged: (value) {
      setState(() => _showPersonalCalendar = value);
      _refreshHomeWidget();
    },
  );
  DateTime _anchorDate = DateTime.now();
  DateTime? _rollingWeekStart;
  int get _weekDayCount => useDesktopLayout ? 7 : 3;
  List<DateTime> get _visibleWeekDays => List.generate(
    _weekDayCount,
    (i) => date_utils.addDays(
      _rollingWeekStart ??
          (useDesktopLayout
              ? date_utils.startOfWeek(_anchorDate)
              : _anchorDate),
      i,
    ),
  );

  void _changeView(ViewMode view) {
    setState(() {
      _view = view;
      _rollingWeekStart = null;
    });
  }

  void _shiftVisibleDays(int days) {
    setState(() {
      if (_view == ViewMode.week) {
        _rollingWeekStart = date_utils.addDays(_visibleWeekDays.first, days);
      }
      _anchorDate = date_utils.addDays(_anchorDate, days);
      _selectedKey = date_utils.toDateKey(_anchorDate);
    });
    _refreshHolidays();
  }

  String _selectedKey = date_utils.toDateKey(DateTime.now());
  bool _showHolidays = DisplaySettings.instance.enabled(
    DisplaySetting.holidays,
  );
  bool _showLunar = DisplaySettings.instance.enabled(DisplaySetting.lunar);
  bool _showSolarTerms = DisplaySettings.instance.enabled(
    DisplaySetting.solarTerms,
  );
  bool _showAnniversaries = DisplaySettings.instance.enabled(
    DisplaySetting.anniversaries,
  );
  Map<String, String> _apiHolidays = const {};
  Map<String, String> _apiSolarTerms = const {};
  Map<String, List<String>> _apiAnniversaries = const {};
  int? _apiHolidaysYear;
  late SystemEventsSync _sync;
  late EventStore _eventStore;
  late ImportedEvents _widgetImports;
  Timer? _eventSyncTimer;
  VoidCallback _collapseAgenda = () {};
  CalendarEvent? _hoveredEvent;
  String? _lastEventId;
  static const _defaultEventHour = 9;
  String? _lastMacCalendarMenuSignature;
  static const _macMenuChannel = MethodChannel('calendar_app/menu');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _eventStore = context.read<EventStore>();
    _widgetImports = context.read<ImportedEvents>();
    _eventStore.addListener(_refreshHomeWidget);
    _widgetImports.addListener(_refreshHomeWidget);
    _sync = SystemEventsSync(_eventStore);
    unawaited(_loadPersonalCalendars());
    _eventStore.syncSucceeded.addListener(_showEventSyncStatus);
    _eventSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_syncEventsAndLiveActivity());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _showEventSyncStatus());
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSync());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadHolidays(_anchorDate.year),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshImported());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLiveActivity());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkForAppUpdate();
      if (mounted) await _maybeShowOnboarding();
    });
    if (LiveActivity.isMacOS) {
      _macMenuChannel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'liveActivities':
            await _showLiveActivities();
          case 'openSettings':
            _openSettings();
          case 'toggleCalendarVisibility':
            final args = Map<String, dynamic>.from(call.arguments as Map);
            await _toggleMenuCalendar(
              args['id'] as String,
              args['visible'] as bool,
            );
          case 'checkForUpdates':
            await _checkForAppUpdate(manual: true);
        }
      });
    }
  }

  Future<void> _toggleMenuCalendar(String id, bool visible) async {
    if (id == 'personal') {
      setState(() => _showPersonalCalendar = visible);
      _refreshHomeWidget();
      return;
    }
    if (id.startsWith('setting:')) {
      switch (id.substring(8)) {
        case 'anniversaries':
          await _setDisplaySetting(
            DisplaySetting.anniversaries,
            visible,
            () => _showAnniversaries = visible,
          );
        case 'holidays':
          await _setDisplaySetting(
            DisplaySetting.holidays,
            visible,
            () => _showHolidays = visible,
          );
        case 'lunar':
          await _setDisplaySetting(
            DisplaySetting.lunar,
            visible,
            () => _showLunar = visible,
          );
        case 'solarTerms':
          await _setDisplaySetting(
            DisplaySetting.solarTerms,
            visible,
            () => _showSolarTerms = visible,
          );
      }
      return;
    }
    if (!id.startsWith('import:')) return;
    final parts = id.substring(7).split('|');
    if (parts.length != 2) return;
    await context.read<ImportedEvents>().setVisible(
      parts[0],
      parts[1],
      visible,
    );
  }

  void _syncMacCalendarMenu(ImportedEvents imported) {
    if (!LiveActivity.isMacOS) return;
    final items = <Map<String, Object>>[
      {'id': 'section:calendars', 'title': '캘린더', 'header': true},
      {
        'id': 'personal',
        'title': _personalCalendars
            .firstWhere((calendar) => calendar.id == 'personal')
            .title,
        'visible': _showPersonalCalendar,
      },
      for (final source in imported.sources.entries)
        for (final calendar in source.value)
          {
            'id': 'import:${source.key}|${calendar.id}',
            'title': '${_calendarProviderName(source.key)} · ${calendar.title}',
            'visible': imported.isVisible(source.key, calendar.id),
          },
      {'id': 'section:features', 'title': '기능 표시', 'header': true},
      {
        'id': 'setting:anniversaries',
        'title': '법정 기념일',
        'visible': _showAnniversaries,
      },
      {'id': 'setting:holidays', 'title': '공휴일', 'visible': _showHolidays},
      {'id': 'setting:lunar', 'title': '음력', 'visible': _showLunar},
      {'id': 'setting:solarTerms', 'title': '절기', 'visible': _showSolarTerms},
    ];
    final signature = items.toString();
    if (_lastMacCalendarMenuSignature == signature) return;
    _lastMacCalendarMenuSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _macMenuChannel.invokeMethod<void>('updateCalendarMenu', items);
      }
    });
  }

  String _calendarProviderName(String provider) => switch (provider) {
    'google' => 'Google 캘린더',
    'device' => '기기 캘린더',
    'notion' => 'Notion',
    'kbo' => 'KBO 야구',
    _ => provider,
  };

  Future<void> _checkForAppUpdate({bool manual = false}) async {
    final update = await AppUpdateService.check();
    if (!mounted) return;
    if (update == null) {
      if (!manual) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: const Text('최신 버전입니다'),
          content: const Text('이미 최신 버전을 사용하고 있습니다.'),
          actions: [
            AppDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AppDialog(
        title: const Text('업데이트가 필요합니다'),
        content: Text('새 버전 ${update.version}이 출시되었습니다. 최신 버전으로 업데이트해 주세요.'),
        actions: [
          AppDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('나중에'),
          ),
          AppDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              final url = update.updateUrl;
              if (url == null) return;
              final uri = secureHttpsUri(url);
              if (uri != null) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('업데이트'),
          ),
        ],
      ),
    );
  }

  Future<void> _showStatusNotice(int id, String title, String message) async {
    if (!mounted) return;
    if (DesktopNotifications.supported) {
      // Respect macOS notification settings without displaying a bottom bar.
      await DesktopNotifications.show(id: id, title: title, body: message);
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showEventSyncStatus() {
    if (!mounted ||
        widget.user == null ||
        _eventStore.syncSucceeded.value != false) {
      return;
    }
    unawaited(
      _showStatusNotice(
        4201,
        '일정 동기화 대기',
        '일정은 이 기기에 저장됐습니다. 서버 연결 후 다른 기기에 동기화됩니다.',
      ),
    );
  }

  Future<void> _restoreSettings() async {
    final imports = context.read<ImportedEvents>();
    if (!await AccountPreferences.instance.sync() || !mounted) return;
    await DisplaySettings.instance.load();
    await _loadPersonalCalendars();
    await imports.load();
    if (!mounted) return;
    setState(() {
      _showHolidays = DisplaySettings.instance.enabled(DisplaySetting.holidays);
      _showLunar = DisplaySettings.instance.enabled(DisplaySetting.lunar);
      _showSolarTerms = DisplaySettings.instance.enabled(
        DisplaySetting.solarTerms,
      );
      _showAnniversaries = DisplaySettings.instance.enabled(
        DisplaySetting.anniversaries,
      );
    });
    await _refreshImported();
  }

  List<LiveCalendarEvent> _currentLiveEvents() => currentLiveEvents(
    _combineEvents(
      context.read<EventStore>().events,
      context.read<ImportedEvents>().events,
    ),
    widget.deviceZone,
    DateTime.now(),
  );

  List<LiveCalendarEvent> _liveActivityCandidates({
    Duration lookAhead = const Duration(minutes: 10),
  }) => liveActivityCandidates(
    _combineEvents(
      context.read<EventStore>().events,
      context.read<ImportedEvents>().events,
    ),
    widget.deviceZone,
    DateTime.now(),
    lookAhead: lookAhead,
  );

  List<LiveCalendarEvent> _automaticLiveEvents() => automaticLiveEvents(
    _combineEvents(
      context.read<EventStore>().events,
      context.read<ImportedEvents>().events,
    ),
    widget.deviceZone,
    DateTime.now(),
  );

  Future<void> _showLiveActivities() async {
    _scaffoldKey.currentState?.closeDrawer();
    if (LiveActivity.isAndroid) {
      await _showAndroidLiveUpdates();
      return;
    }
    if (LiveActivity.isMacOS) {
      await _showMacLiveUpdates();
      return;
    }
    try {
      final status = await LiveActivity.status();
      if (!mounted) return;
      if (!status.supported || !status.enabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !status.supported
                  ? 'iOS 17 이상에서 사용할 수 있습니다. 앱 업데이트 후 다시 실행해 주세요.'
                  : '설정에서 일상 캘린더의 실시간 현황을 허용해 주세요.',
            ),
          ),
        );
        return;
      }
      final events = _currentLiveEvents();
      if (events.length == 1) {
        await LiveActivity.start(events.single);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('잠금 화면에 실시간 활동을 표시합니다.')),
          );
        }
        return;
      }
      final selected = await showCupertinoModalPopup<String>(
        context: context,
        builder: (context) => CupertinoActionSheet(
          title: const Text('현재 일정 실시간 활동'),
          message: Text(
            events.isEmpty
                ? '현재 진행 중인 시간 지정 일정이 없습니다. 종일 일정은 표시하지 않습니다.'
                : '잠금 화면과 Dynamic Island에 일정 제목과 종료까지 남은 시간을 표시합니다.',
          ),
          actions: [
            for (final event in events)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(context, event.id),
                child: Text(
                  '${event.event.title} · ${event.end.difference(DateTime.now()).inMinutes.clamp(0, 99999)}분 남음',
                ),
              ),
            if (status.eventIDs.isNotEmpty)
              CupertinoActionSheetAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.pop(context, '__end__'),
                child: const Text('실시간 활동 종료'),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ),
      );
      if (selected == null || !mounted) return;
      if (selected == '__end__') {
        await LiveActivity.end();
      } else {
        final matches = _currentLiveEvents().where(
          (event) => event.id == selected,
        );
        if (matches.isEmpty) return;
        await LiveActivity.start(matches.first);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              selected == '__end__'
                  ? '실시간 활동을 종료했습니다.'
                  : '잠금 화면에 실시간 활동을 표시합니다.',
            ),
          ),
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? '실시간 활동을 처리하지 못했습니다.')),
        );
      }
    }
  }

  Future<void> _showAndroidLiveUpdates() async {
    await _refreshLiveActivity();
    final status = await LiveActivity.status();
    if (!mounted) return;
    final candidates = _automaticLiveEvents();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              Text(
                '일정 실시간 업데이트',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('일정 시작 10분 전부터 자동으로 표시합니다. 다음 일정도 시작 10분 전에 표시됩니다.'),
              const SizedBox(height: 16),
              if (!status.enabled)
                FilledButton(
                  onPressed: () => LiveActivity.openNotificationSettings(),
                  child: const Text('알림 허용 설정'),
                ),
              if (status.enabled && !status.scheduledStartSupported) ...[
                const Text('앱을 닫아도 시작 10분 전에 표시하려면 알람 및 리마인더를 허용해 주세요.'),
                FilledButton(
                  onPressed: () => LiveActivity.openScheduleSettings(),
                  child: const Text('예약 알림 허용 설정'),
                ),
              ],
              if (candidates.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('오늘 표시할 시간 지정 일정이 없습니다.'),
                ),
              for (final event in candidates)
                ListTile(
                  leading: const Icon(Icons.timelapse),
                  title: Text(event.event.title),
                  subtitle: Text(
                    '${TimeOfDay.fromDateTime(event.start.toLocal()).format(sheetContext)} – ${TimeOfDay.fromDateTime(event.end.toLocal()).format(sheetContext)}',
                  ),
                  trailing: status.eventIDs.contains(event.id)
                      ? const Icon(Icons.check_circle)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMacLiveUpdates() async {
    try {
      final status = await LiveActivity.status();
      if (!mounted) return;
      final candidates = _liveActivityCandidates();
      final selected = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: const Text('일정 실시간 현황'),
          icon: Icons.bolt_rounded,
          maxWidth: 480,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('메뉴 막대에 표시할 일정을 선택하세요.'),
              const SizedBox(height: 20),
              if (candidates.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('진행 중이거나 10분 이내에 시작하는 일정이 없습니다.'),
                ),
              for (final event in candidates)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  leading: const Icon(
                    Icons.timelapse,
                    color: AppDialogStyle.accent,
                  ),
                  title: Text(event.event.title),
                  subtitle: Text(
                    '${TimeOfDay.fromDateTime(event.start.toLocal()).format(dialogContext)} – ${TimeOfDay.fromDateTime(event.end.toLocal()).format(dialogContext)} · ${event.end.difference(DateTime.now()).inMinutes.clamp(0, 99999)}분 남음',
                  ),
                  trailing: Icon(
                    status.eventIDs.contains(event.id)
                        ? Icons.check_circle_rounded
                        : Icons.chevron_right_rounded,
                  ),
                  onTap: () => Navigator.pop(dialogContext, event.id),
                ),
            ],
          ),
          actions: [
            if (status.eventIDs.isNotEmpty)
              AppDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.pop(dialogContext, '__end__'),
                child: const Text('실시간 현황 종료'),
              ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      if (selected == '__end__') {
        await LiveActivity.end();
      } else {
        final matches = _liveActivityCandidates().where(
          (event) => event.id == selected,
        );
        if (matches.isEmpty) return;
        await LiveActivity.start(matches.first);
      }
      if (mounted) {
        await _showStatusNotice(
          4202,
          '일정 실시간 현황',
          selected == '__end__'
              ? '실시간 현황을 종료했습니다.'
              : '메뉴 막대에 일정 실시간 현황을 표시합니다.',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        await _showStatusNotice(
          4202,
          '일정 실시간 현황',
          error.message ?? '실시간 현황을 처리하지 못했습니다.',
        );
      }
    }
  }

  void _refreshHomeWidget() {
    if (!mounted) return;
    final today = DateTime.now();
    final events = expandEvents(
      _combineEvents(
        _showPersonalCalendar ? _eventStore.events : const {},
        _widgetImports.events,
      ),
      date_utils.toDateKey(DateTime(today.year, today.month, 1)),
      date_utils.toDateKey(DateTime(today.year, today.month + 2, 0)),
      widget.deviceZone,
    );
    unawaited(CalendarHomeWidget.update(events, signedIn: widget.user != null));
  }

  Future<void> _refreshLiveActivity() async {
    _refreshHomeWidget();
    if (!mounted || !LiveActivity.isSupportedPlatform) return;
    try {
      final status = await LiveActivity.status();
      if (!mounted) return;
      if (LiveActivity.isAndroid) {
        if (!status.supported || !status.enabled) return;
        await LiveActivity.syncAutomatic(_automaticLiveEvents());
        return;
      }
      final candidates = LiveActivity.isIOS && status.scheduledStartSupported
          ? _liveActivityCandidates(lookAhead: const Duration(hours: 24))
          : _liveActivityCandidates();
      final activeIDs = status.eventIDs.toSet();
      if (LiveActivity.isMacOS) {
        // macOS tracks only the event explicitly selected by the
        // user. Stopping or dismissing the notification/menu bar item must
        // not restart it.
        final selected = candidates.where(
          (event) => activeIDs.contains(event.id),
        );
        if (activeIDs.isNotEmpty && selected.isEmpty) await LiveActivity.end();
        for (final event in selected) {
          await LiveActivity.update(event);
        }
        return;
      }
      for (final event in candidates) {
        if (LiveActivity.isIOS &&
            status.scheduledStartSupported &&
            event.displayStart.isAfter(DateTime.now())) {
          await LiveActivity.schedule(event);
        } else if (activeIDs.contains(event.id)) {
          await LiveActivity.update(event);
        } else {
          await LiveActivity.start(event);
        }
      }
    } on PlatformException {
      /* Retry after the next foreground update. */
    }
  }

  Future<List<String>> _backupData(ValueChanged<double> onProgress) =>
      BackupService.exportData(
        context.read<EventStore>(),
        onProgress: onProgress,
      );

  Future<void> _restoreData() async {
    try {
      final restored = await BackupService.restoreData(
        context.read<EventStore>(),
      );
      if (!restored || !mounted) return;
      await DisplaySettings.instance.load();
      setState(() {
        _showHolidays = DisplaySettings.instance.enabled(
          DisplaySetting.holidays,
        );
        _showLunar = DisplaySettings.instance.enabled(DisplaySetting.lunar);
        _showSolarTerms = DisplaySettings.instance.enabled(
          DisplaySetting.solarTerms,
        );
        _showAnniversaries = DisplaySettings.instance.enabled(
          DisplaySetting.anniversaries,
        );
      });
      await _refreshLiveActivity();
      if (mounted) {
        await _showStatusNotice(4203, '복원 완료', '백업 데이터를 복원했습니다.');
      }
    } on FormatException catch (error) {
      if (mounted) {
        await _showStatusNotice(4203, '복원 실패', error.message);
      }
    } catch (_) {
      if (mounted) {
        await _showStatusNotice(4203, '복원 실패', '백업 파일을 복원하지 못했습니다.');
      }
    }
  }

  Future<void> _setDisplaySetting(
    DisplaySetting setting,
    bool value,
    VoidCallback update,
  ) async {
    setState(update);
    try {
      await DisplaySettings.instance.setEnabled(setting, value);
    } catch (_) {
      if (!mounted) return;
      await _showStatusNotice(
        4204,
        '설정 저장 실패',
        '표시 설정을 저장하지 못했습니다. 다시 시도해 주세요.',
      );
    }
  }

  Future<void> _loadHolidays(int year) async {
    try {
      final specialDays = await AuthService.instance.specialDays(year);
      if (mounted && _anchorDate.year == year) {
        setState(() {
          _apiHolidays = specialDays.holidays;
          _apiSolarTerms = specialDays.solarTerms;
          _apiAnniversaries = specialDays.anniversaries;
          _apiHolidaysYear = year;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _eventSyncTimer?.cancel();
    _eventStore.removeListener(_refreshHomeWidget);
    _widgetImports.removeListener(_refreshHomeWidget);
    _eventStore.syncSucceeded.removeListener(_showEventSyncStatus);
    if (LiveActivity.isMacOS) _macMenuChannel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runSync();
      _restoreSettings();
      _refreshLiveActivity();
    }
  }

  (String, String) get _range {
    final from = date_utils.toDateKey(
      DateTime(_anchorDate.year, _anchorDate.month - 1, 24),
    );
    final to = date_utils.toDateKey(
      DateTime(_anchorDate.year, _anchorDate.month + 1, 7),
    );
    return (from, to);
  }

  Future<void> _runSync() async {
    await _eventStore.sync();
    if (!mounted) return;
    final (from, to) = _range;
    await _sync.sync(
      date_utils.parseDateKey(from),
      date_utils.parseDateKey(to),
    );
    await _refreshLiveActivity();
  }

  Future<void> _syncEventsAndLiveActivity() async {
    await _eventStore.sync();
    if (mounted) await _refreshLiveActivity();
  }

  Future<void> _refreshImported() async {
    final imports = context.read<ImportedEvents>();
    final (from, to) = _range;
    for (final entry in imports.sources.entries.toList()) {
      if (!mounted) return;
      try {
        await imports.refresh(
          entry.key,
          entry.value,
          date_utils.parseDateKey(from),
          date_utils.parseDateKey(to),
        );
      } catch (_) {
        // Preserve the previous import while offline or after a revoked authorization.
      }
    }
    if (mounted) await _refreshLiveActivity();
  }

  Future<void> _refreshAll() async {
    await _runSync();
    await _refreshImported();
    _refreshHolidays();
  }

  EventMap _combineEvents(EventMap local, EventMap imported) {
    return mergeAndDeduplicateEvents(
      local,
      removeSpecialDayDuplicates(
        imported,
        _apiHolidays,
        _apiSolarTerms,
        _apiAnniversaries,
      ),
    );
  }

  Future<void> _showCalendarImportError(String message) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: const Text('캘린더 연동 실패'),
        content: Text(message),
        actions: [
          AppDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _connectCalendar(String provider) async {
    final importedEvents = context.read<ImportedEvents>();
    final eventGeneration = _eventStore.accountGeneration;
    final preferencesGeneration = AccountPreferences.instance.accountGeneration;
    bool currentAccount() =>
        _accountIsCurrent(eventGeneration, preferencesGeneration);
    try {
      if (provider == 'device') {
        final granted = await EventKit.requestAccess();
        if (!currentAccount()) return;
        if (!granted) {
          throw AuthException('기기 캘린더 접근을 허용해 주세요.');
        }
        final deviceCalendars = await EventKit.fetchCalendars();
        if (!currentAccount()) return;
        final selectedCalendars = await _pickDeviceCalendars(deviceCalendars);
        if (!currentAccount() ||
            selectedCalendars == null ||
            selectedCalendars.isEmpty) {
          return;
        }
        final (from, to) = _range;
        final native = await EventKit.fetchEvents(
          date_utils.parseDateKey(from),
          date_utils.parseDateKey(to),
          calendarIds: selectedCalendars
              .map((calendar) => calendar.id)
              .toList(),
        );
        if (!currentAccount()) return;
        final imported = <String, List<CalendarEvent>>{};
        for (final event in native) {
          (imported[event.date] ??= []).add(
            event.copyWith(
              id: 'import:$provider:${event.systemEventId ?? event.id}',
              systemCalendarId:
                  '$provider|${event.systemCalendarId ?? selectedCalendars.first.id}',
              description: '기기 캘린더 · 읽기 전용',
            ),
          );
        }
        if (!currentAccount()) return;
        await importedEvents.setDeviceSources(
          provider,
          selectedCalendars
              .map(
                (calendar) => ImportCalendar(
                  id: calendar.id,
                  title: calendar.title,
                  color: '#0A84FF',
                ),
              )
              .toList(),
        );
        if (!currentAccount()) return;
        importedEvents.replaceProvider(provider, imported);
        return;
      }
      if (provider == 'kbo') {
        final (from, to) = _range;
        await importedEvents.refresh(
          provider,
          [
            for (final team in kboTeams)
              ImportCalendar(
                id: team.code,
                title: team.name,
                color: team.color,
              ),
          ],
          date_utils.parseDateKey(from),
          date_utils.parseDateKey(to),
        );
        return;
      }
      final url = await AuthService.instance.calendarImportStart(provider);
      if (!currentAccount()) return;
      final result = await authenticateOAuthBrowser(url: url);
      if (!currentAccount()) return;
      final callback = parseCalendarImportCallback(
        result,
        provider: provider,
        webOrigin: kIsWeb ? Uri.base : null,
      );
      if (!callback.success) {
        throw AuthException(callback.error ?? '연결하지 못했습니다.');
      }
      if (!currentAccount()) return;
      final calendars = await AuthService.instance.importCalendars(provider);
      if (!currentAccount()) return;
      await _pickAndImport(provider, calendars);
    } on AuthException catch (error) {
      if (currentAccount()) await _showCalendarImportError(error.message);
    } catch (_) {
      if (currentAccount()) {
        await _showCalendarImportError('캘린더 연결을 완료하지 못했습니다.');
      }
    }
  }

  Future<void> _showSubscriptionDialog() async {
    _scaffoldKey.currentState?.closeDrawer();
    final imports = context.read<ImportedEvents>();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SubscriptionDialog(
        existingTeamCodes: {
          for (final calendar in imports.sources['kbo'] ?? <ImportCalendar>[])
            calendar.id,
        },
        onToggle: (team, enabled) async {
          final calendars = {
            for (final calendar in imports.sources['kbo'] ?? <ImportCalendar>[])
              calendar.id: calendar,
          };
          if (enabled) {
            calendars[team.code] = ImportCalendar(
              id: team.code,
              title: team.name,
              color: team.color,
            );
          } else {
            calendars.remove(team.code);
          }
          if (calendars.isEmpty) {
            await imports.disconnect('kbo', team.code);
            return;
          }
          final (from, to) = _range;
          await imports.refresh(
            'kbo',
            calendars.values.toList(),
            date_utils.parseDateKey(from),
            date_utils.parseDateKey(to),
          );
        },
      ),
    );
  }

  Future<List<DeviceCalendar>?> _pickDeviceCalendars(
    List<DeviceCalendar> calendars,
  ) {
    final selected = <DeviceCalendar>{...calendars};
    return Navigator.of(
      context,
      rootNavigator: true,
    ).push<List<DeviceCalendar>>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => _ImportSelectionSheet(
            title: '가져올 캘린더 (${selected.length}개)',
            onCancel: () => Navigator.pop(dialogContext),
            onImport: () => Navigator.pop(dialogContext, selected.toList()),
            children: [
              for (final calendar in calendars)
                _CalendarImportChoice(
                  title: calendar.title,
                  subtitle: calendar.source.isEmpty ? null : calendar.source,
                  selected: selected.contains(calendar),
                  onTap: () => setDialogState(() {
                    if (selected.contains(calendar)) {
                      selected.remove(calendar);
                    } else {
                      selected.add(calendar);
                    }
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCalendarConnections() async {
    final imports = context.read<ImportedEvents>();
    if (useDesktopLayout) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _CalendarConnectionsSheet(
          theme: Theme.of(context).brightness == Brightness.dark
              ? darkTheme
              : lightTheme,
          imports: imports,
          onConnect: (provider) async {
            Navigator.of(dialogContext).pop();
            await _connectCalendar(provider);
          },
          onDisconnect: (provider, calendar) =>
              imports.disconnect(provider, calendar.id),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _CalendarConnectionsSheet(
        theme: Theme.of(context).brightness == Brightness.dark
            ? darkTheme
            : lightTheme,
        imports: imports,
        onConnect: (provider) async {
          Navigator.of(sheetContext).pop();
          await _connectCalendar(provider);
        },
        onDisconnect: (provider, calendar) =>
            imports.disconnect(provider, calendar.id),
      ),
    );
  }

  Future<void> _pickAndImport(
    String provider,
    List<ImportCalendar> calendars,
  ) async {
    final eventGeneration = _eventStore.accountGeneration;
    final preferencesGeneration = AccountPreferences.instance.accountGeneration;
    bool currentAccount() =>
        _accountIsCurrent(eventGeneration, preferencesGeneration);
    final selected = <ImportCalendar>{...calendars};
    final choices = calendars.length == 1
        ? calendars
        : await Navigator.of(
            context,
            rootNavigator: true,
          ).push<List<ImportCalendar>>(
            CupertinoPageRoute(
              fullscreenDialog: true,
              builder: (dialogContext) => StatefulBuilder(
                builder: (context, setDialogState) => _ImportSelectionSheet(
                  title: '가져올 캘린더',
                  onCancel: () => Navigator.pop(dialogContext),
                  onImport: () =>
                      Navigator.pop(dialogContext, selected.toList()),
                  children: [
                    for (final calendar in calendars)
                      _CalendarImportChoice(
                        title: calendar.title,
                        subtitle: provider == 'kakao'
                            ? switch (calendar.category) {
                                'primary' => '기본 캘린더',
                                'subscription' => '구독 캘린더',
                                'shared' => '공유 캘린더',
                                'user' => '서브 캘린더',
                                _ => null,
                              }
                            : null,
                        selected: selected.contains(calendar),
                        onTap: () => setDialogState(() {
                          if (selected.contains(calendar)) {
                            selected.remove(calendar);
                          } else {
                            selected.add(calendar);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ),
          );
    if (choices == null || choices.isEmpty || !mounted || !currentAccount()) {
      return;
    }
    final (from, to) = _range;
    final imports = context.read<ImportedEvents>();
    if (provider == 'kakao') {
      // Connect whole calendars, including calendars with no events this month.
      final connected = {
        for (final calendar in imports.sources[provider] ?? <ImportCalendar>[])
          if (calendar.id != 'all') calendar.id: calendar,
        for (final calendar in choices) calendar.id: calendar,
      };
      try {
        await imports.refresh(
          provider,
          connected.values.toList(),
          date_utils.parseDateKey(from),
          date_utils.parseDateKey(to),
        );
      } on AuthException catch (error) {
        if (currentAccount()) await _showCalendarImportError(error.message);
      }
      return;
    }
    final options = <_ImportEventOption>[];
    try {
      for (final calendar in choices) {
        final events = await AuthService.instance.importEvents(
          provider,
          calendar.id,
          date_utils.parseDateKey(from),
          date_utils.parseDateKey(to),
        );
        if (!currentAccount()) return;
        options.addAll(
          events.map((event) => _ImportEventOption(calendar, event)),
        );
      }
    } on AuthException catch (error) {
      if (currentAccount()) await _showCalendarImportError(error.message);
      return;
    }
    if (options.isEmpty) {
      if (!mounted || !currentAccount()) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: const Text('가져올 일정이 없습니다'),
          content: const Text('선택한 기간에 새로 가져올 일정이 없습니다.'),
          actions: [
            AppDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }
    final selectedEvents = await _pickEventsToImport(options);
    if (selectedEvents == null || !currentAccount()) return;
    await imports.saveEventSelection(
      provider,
      options.map(
        (option) =>
            imports.eventKey(provider, option.calendar.id, option.event.id),
      ),
      selectedEvents.map(
        (option) =>
            imports.eventKey(provider, option.calendar.id, option.event.id),
      ),
    );
    if (!currentAccount()) return;
    await imports.refresh(
      provider,
      choices,
      date_utils.parseDateKey(from),
      date_utils.parseDateKey(to),
    );
  }

  Future<List<_ImportEventOption>?> _pickEventsToImport(
    List<_ImportEventOption> options,
  ) async {
    final selected = <_ImportEventOption>{...options};
    return Navigator.of(
      context,
      rootNavigator: true,
    ).push<List<_ImportEventOption>>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => _ImportSelectionSheet(
            title: '가져올 일정 (${selected.length}개)',
            empty: options.isEmpty,
            onCancel: () => Navigator.pop(dialogContext),
            onImport: () => Navigator.pop(dialogContext, selected.toList()),
            children: [
              for (final option in options)
                _CalendarImportChoice(
                  title: option.event.title,
                  subtitle: option.detail,
                  selected: selected.contains(option),
                  onTap: () => setDialogState(() {
                    if (selected.contains(option)) {
                      selected.remove(option);
                    } else {
                      selected.add(option);
                    }
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _title {
    switch (_view) {
      case ViewMode.month:
        return '${_anchorDate.year}. ${_anchorDate.month}.';
      case ViewMode.week:
        final days = _visibleWeekDays;
        return '${days.first.month}월 ${days.first.day}일 - ${days.last.month}월 ${days.last.day}일';
      case ViewMode.list:
        return '전체 일정';
      case ViewMode.day:
        return date_utils.formatDayTitle(_anchorDate);
    }
  }

  void _goPrev() {
    setState(() {
      if (_view == ViewMode.month) {
        _anchorDate = date_utils.addMonths(_anchorDate, -1);
      }
      if (_view == ViewMode.week) {
        _rollingWeekStart = date_utils.addDays(
          _visibleWeekDays.first,
          -_weekDayCount,
        );
        _anchorDate = date_utils.addDays(_anchorDate, -_weekDayCount);
      }
      if (_view == ViewMode.day) {
        _anchorDate = date_utils.addDays(_anchorDate, -1);
      }
    });
    _refreshHolidays();
  }

  void _goNext() {
    setState(() {
      if (_view == ViewMode.month) {
        _anchorDate = date_utils.addMonths(_anchorDate, 1);
      }
      if (_view == ViewMode.week) {
        _rollingWeekStart = date_utils.addDays(
          _visibleWeekDays.first,
          _weekDayCount,
        );
        _anchorDate = date_utils.addDays(_anchorDate, _weekDayCount);
      }
      if (_view == ViewMode.day) {
        _anchorDate = date_utils.addDays(_anchorDate, 1);
      }
    });
    _refreshHolidays();
  }

  void _onEventHover(CalendarEvent? event) {
    _hoveredEvent = event;
    if (event != null) _lastEventId = event.seriesId ?? event.id;
  }

  /// Keyboard target: the event under the mouse, else the one last touched
  /// (hovered, clicked, dragged or moved), so repeated shortcuts keep working.
  CalendarEvent? _targetEvent() {
    final hovered = _hoveredEvent;
    if (hovered != null) return hovered;
    final id = _lastEventId;
    if (id == null) return null;
    for (final list in context.read<EventStore>().events.values) {
      for (final event in list) {
        if (event.id == id) return event;
      }
    }
    return null;
  }

  CalendarEvent _seriesSource(EventStore store, CalendarEvent event) {
    final seriesId = event.seriesId;
    if (seriesId == null) return event;
    return store.events.values
        .expand((e) => e)
        .firstWhere((e) => e.id == seriesId, orElse: () => event);
  }

  /// Shifts [event] to [date] (and [time] for timed events). A recurring
  /// occurrence moves the whole series by the same number of days.
  Future<void> _moveEvent(
    CalendarEvent event,
    DateTime date, {
    String? time,
    int? duration,
    bool copy = false,
  }) async {
    if (!isMovableEvent(event)) return;
    final store = context.read<EventStore>();
    final generation = store.accountGeneration;
    final source = _seriesSource(store, event);
    final delta = DateTime.utc(date.year, date.month, date.day)
        .difference(
          DateTime.utc(
            date_utils.parseDateKey(event.date).year,
            date_utils.parseDateKey(event.date).month,
            date_utils.parseDateKey(event.date).day,
          ),
        )
        .inDays;
    final newDate = date_utils.toDateKey(
      date_utils.addDays(date_utils.parseDateKey(source.date), delta),
    );
    final newTime = time ?? source.time;
    final newDuration = duration ?? source.duration;
    String? startsAt, endsAt;
    if (newTime != null) {
      try {
        final start = wallTimeToDate(newDate, newTime, widget.deviceZone);
        startsAt = start.toIso8601String();
        endsAt = start.add(Duration(minutes: newDuration)).toIso8601String();
      } catch (_) {
        return; // The local clock time does not exist at a DST transition.
      }
    }
    var moved = source.copyWith(
      date: newDate,
      time: newTime,
      duration: newDuration,
      startsAt: startsAt,
      clearStartsAt: startsAt == null,
      endsAt: endsAt,
      clearEndsAt: endsAt == null,
      clearSeriesId: true,
    );
    if (copy) {
      moved = CalendarEvent(
        id: '',
        date: moved.date,
        title: moved.title,
        location: moved.location,
        recurrence: moved.recurrence,
        url: moved.url,
        description: moved.description,
        timeZone: moved.timeZone,
        startsAt: moved.startsAt,
        endsAt: moved.endsAt,
        time: moved.time,
        duration: moved.duration,
        color: moved.color,
      );
    }
    final saved = await store.saveEvent(moved);
    if (!mounted || generation != store.accountGeneration) return;
    _hoveredEvent = null; // the hovered copy is now stale
    _lastEventId = saved.id;
    await _syncToEventKit(store, saved);
    if (!mounted || generation != store.accountGeneration) return;
    await _refreshLiveActivity();
  }

  void _selectDay(DateTime date) {
    setState(() {
      _selectedKey = date_utils.toDateKey(date);
      _anchorDate = date;
      _rollingWeekStart = null;
    });
    _refreshHolidays();
  }

  /// Left/right move one visible page in time views.
  void _navigate(int dx, int dy) {
    switch (_view) {
      case ViewMode.month:
        _selectDay(
          date_utils.addDays(
            date_utils.parseDateKey(_selectedKey),
            dx + dy * 7,
          ),
        );
      case ViewMode.week:
        if (dx != 0) _shiftVisibleDays(dx * _weekDayCount);
      case ViewMode.day:
        if (dx != 0) _shiftVisibleDays(dx);
      case ViewMode.list:
        break;
    }
  }

  void _activateSelection() {
    if (_view == ViewMode.list) return;
    _openCreate(
      _view == ViewMode.month
          ? date_utils.parseDateKey(_selectedKey)
          : _anchorDate,
      _view == ViewMode.month
          ? null
          : '${_defaultEventHour.toString().padLeft(2, '0')}:00',
    );
  }

  /// Option+arrows nudge the target event by a day (or an hour/15 minutes).
  void _nudgeHovered(int days, int minutes) {
    final event = _targetEvent();
    if (event == null || !isMovableEvent(event)) return;
    String? time;
    var date = date_utils.parseDateKey(event.date);
    if (minutes != 0 && event.time != null) {
      final total = date_utils.minutesFromTime(event.time!) + minutes;
      final dayShift = total < 0 ? -1 : (total >= 1440 ? 1 : 0);
      date = date_utils.addDays(date, dayShift);
      time = date_utils.timeFromMinutes((total % 1440 + 1440) % 1440);
    }
    date = date_utils.addDays(date, days);
    _moveEvent(event, date, time: time);
  }

  /// Cmd+D copies the target event to the selected day (and hour).
  void _duplicateHovered() {
    final event = _targetEvent();
    if (event == null || !isMovableEvent(event)) return;
    final inTimeView = _view == ViewMode.week || _view == ViewMode.day;
    final target = _view == ViewMode.month
        ? date_utils.parseDateKey(_selectedKey)
        : _anchorDate;
    _moveEvent(
      event,
      target,
      time: inTimeView && event.time != null
          ? '${_defaultEventHour.toString().padLeft(2, '0')}:00'
          : null,
      copy: true,
    );
  }

  Future<void> _createRange(DateTime date, String time, int duration) =>
      _openSheet(
        draft: null,
        date: date,
        time: time,
        newEventDuration: duration,
      );

  Future<void> _quickCreate(QuickEvent quick) async {
    final store = context.read<EventStore>();
    final generation = store.accountGeneration;
    final date = quick.date!;
    final saved = await store.saveEvent(
      CalendarEvent(
        id: '',
        date: date_utils.toDateKey(date),
        title: quick.title,
        time: quick.time,
        duration: quick.time == null ? 1440 : quick.duration,
        color: colorToHex(palette[0].value),
      ),
    );
    if (!mounted || generation != store.accountGeneration) return;
    _lastEventId = saved.id;
    _selectDay(date);
    await _syncToEventKit(store, saved);
    if (!mounted || generation != store.accountGeneration) return;
    await _refreshLiveActivity();
  }

  static String _timeLabel(String? time, int duration) => time == null
      ? '종일'
      : '${date_utils.formatTimeLabel(time)} · ${date_utils.formatDurationLabel(duration)}';

  List<PaletteItem> _paletteItems(String query) {
    final store = context.read<EventStore>();
    final imported = context.read<ImportedEvents>();
    final q = query.toLowerCase();
    bool match(String label, [String keywords = '']) =>
        q.isEmpty || '$label $keywords'.toLowerCase().contains(q);

    final items = <PaletteItem>[];

    final quick = query.isEmpty ? null : parseQuickEvent(query, DateTime.now());
    if (quick != null && quick.date != null) {
      final dayLabel =
          '${quick.date!.month}월 ${quick.date!.day}일 (${date_utils.weekdays[quick.date!.weekday % 7]})';
      if (quick.title.isNotEmpty) {
        items.add(
          PaletteItem(
            label: '"${quick.title}" 일정 만들기',
            detail: '$dayLabel · ${_timeLabel(quick.time, quick.duration)}',
            icon: CupertinoIcons.add_circled,
            shortcut: '↵',
            run: () => _quickCreate(quick),
          ),
        );
      } else if (quick.hasDate) {
        items.add(
          PaletteItem(
            label: '$dayLabel(으)로 이동',
            icon: CupertinoIcons.arrow_right_circle,
            shortcut: '↵',
            run: () => _selectDay(quick.date!),
          ),
        );
      }
    }

    final commands = <(String, String, IconData, String?, VoidCallback)>[
      (
        '새 일정',
        '만들기 추가',
        CupertinoIcons.add,
        '${desktopShortcutLabel}N',
        () => _activateCreate(),
      ),
      ('오늘로 이동', 'today', CupertinoIcons.calendar_today, 'T', _goToday),
      ('이전', 'previous', CupertinoIcons.chevron_left, 'K', _goPrev),
      ('다음', 'next', CupertinoIcons.chevron_right, 'J', _goNext),
      (
        '월간 보기',
        'month',
        CupertinoIcons.calendar,
        'M',
        () => _changeView(ViewMode.month),
      ),
      (
        '주간 보기',
        'week',
        CupertinoIcons.calendar,
        'W',
        () => _changeView(ViewMode.week),
      ),
      (
        '일간 보기',
        'day',
        CupertinoIcons.calendar,
        'D',
        () => _changeView(ViewMode.day),
      ),
      (
        '목록 보기',
        'list',
        CupertinoIcons.list_bullet,
        'L',
        () => _changeView(ViewMode.list),
      ),
      ('설정', 'settings', CupertinoIcons.gear, null, _openSettings),
      (
        '캘린더 연결',
        'connect',
        CupertinoIcons.link,
        null,
        _showCalendarConnections,
      ),
    ];
    for (final c in commands) {
      if (match(c.$1, c.$2)) {
        items.add(
          PaletteItem(label: c.$1, icon: c.$3, shortcut: c.$4, run: c.$5),
        );
      }
    }

    if (query.isNotEmpty) {
      final (from, to) = _range;
      final expanded = expandEvents(
        _combineEvents(store.events, imported.events),
        from,
        to,
        widget.deviceZone,
      );
      final found = <CalendarEvent>[
        for (final list in expanded.values)
          for (final event in list)
            if (!event.id.startsWith('holiday:') &&
                !event.id.startsWith('solarTerm:') &&
                !event.id.startsWith('anniversary:') &&
                event.title.toLowerCase().contains(q))
              event,
      ]..sort((a, b) => a.date.compareTo(b.date));
      for (final event in found.take(8)) {
        items.add(
          PaletteItem(
            label: event.title,
            detail: '${event.date} · ${_timeLabel(event.time, event.duration)}',
            icon: CupertinoIcons.doc_text_search,
            run: () {
              _selectDay(date_utils.parseDateKey(event.date));
              _openEdit(event);
            },
          ),
        );
      }
    }
    return items;
  }

  void _activateCreate() => _openCreate(
    _view == ViewMode.month
        ? date_utils.parseDateKey(_selectedKey)
        : _anchorDate,
  );

  void _openPalette() {
    showCommandPalette(
      context,
      theme: Theme.of(context).brightness == Brightness.dark
          ? darkTheme
          : lightTheme,
      itemsFor: _paletteItems,
    );
  }

  void _goToday() {
    setState(() {
      _anchorDate = DateTime.now();
      _rollingWeekStart = null;
      _selectedKey = date_utils.toDateKey(_anchorDate);
    });
    _refreshHolidays();
  }

  void _refreshHolidays() {
    if (_apiHolidaysYear != _anchorDate.year) {
      _loadHolidays(_anchorDate.year);
    }
    _refreshImported();
  }

  Future<void> _openCreate(DateTime date, [String? time]) async {
    final now = TimeOfDay.now();
    final initialTime =
        time ??
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    await _openSheet(draft: null, date: date, time: initialTime);
  }

  Future<void> _openEdit(CalendarEvent event) async {
    final eventGeneration = _eventStore.accountGeneration;
    final preferencesGeneration = AccountPreferences.instance.accountGeneration;
    bool currentAccount() =>
        _accountIsCurrent(eventGeneration, preferencesGeneration);
    _lastEventId = event.seriesId ?? event.id;
    if (event.id.startsWith('import:')) {
      final localDraft = CalendarEvent(
        id: '',
        date: event.date,
        title: event.title,
        location: event.location,
        url: event.url,
        description: event.description,
        time: event.time,
        duration: event.duration,
        color: event.color,
      );
      await _openSheet(
        draft: localDraft,
        date: date_utils.parseDateKey(localDraft.date),
        time: localDraft.time,
        syncToSystem: false,
        onBeforeSave: () async {
          if (!currentAccount()) return;
          await context.read<ImportedEvents>().hideImportedEvent(event);
        },
        onDelete: () async {
          if (!currentAccount()) return;
          await context.read<ImportedEvents>().hideImportedEvent(event);
          if (!currentAccount()) return;
          await _refreshLiveActivity();
        },
      );
      return;
    }
    final store = context.read<EventStore>();
    final seriesId = event.seriesId;
    final source = seriesId != null
        ? store.events.values
              .expand((e) => e)
              .firstWhere((e) => e.id == seriesId, orElse: () => event)
        : event;
    final resolved = source.systemEventId != null
        ? source.copyWith(id: source.id, clearSeriesId: true)
        : source;
    await _openSheet(
      draft: resolved,
      date: date_utils.parseDateKey(resolved.date),
      time: resolved.time,
      onDelete: () async {
        if (!currentAccount()) return;
        if (resolved.systemEventId != null) {
          await EventKit.deleteEvent(resolved.systemEventId!);
        }
        if (!currentAccount()) return;
        await store.deleteEvent(resolved.date, resolved.id);
        if (!currentAccount()) return;
        await _refreshLiveActivity();
      },
    );
  }

  Future<void> _openSheet({
    required CalendarEvent? draft,
    required DateTime date,
    String? time,
    int? newEventDuration,
    bool syncToSystem = true,
    Future<void> Function()? onBeforeSave,
    Future<void> Function()? onDelete,
  }) async {
    final store = context.read<EventStore>();
    final eventGeneration = store.accountGeneration;
    final preferencesGeneration = AccountPreferences.instance.accountGeneration;
    bool currentAccount() =>
        _accountIsCurrent(eventGeneration, preferencesGeneration);
    if (draft == null && newEventDuration != null) {
      draft = CalendarEvent(
        id: '',
        date: date_utils.toDateKey(date),
        title: '',
        time: time,
        duration: newEventDuration,
        color: colorToHex(palette[0].value),
      );
    }
    final editing =
        draft != null && !(newEventDuration != null && draft.id.isEmpty);
    if (useDesktopLayout) {
      final panelKey = UniqueKey();
      void closePanel() {
        if (mounted && _eventSidePanel?.key == panelKey) {
          setState(() => _eventSidePanel = null);
        }
      }

      setState(() {
        _eventSidePanel = EventSheet(
          key: panelKey,
          embedded: true,
          onClose: closePanel,
          theme: Theme.of(context).brightness == Brightness.dark
              ? darkTheme
              : lightTheme,
          draft: draft,
          isEditing: editing,
          initialDate: date,
          initialTime: time,
          onSave: (event) async {
            if (!currentAccount()) return;
            await onBeforeSave?.call();
            if (!currentAccount()) return;
            final saved = await store.saveEvent(event);
            if (!currentAccount()) return;
            if (syncToSystem) await _syncToEventKit(store, saved);
            if (!currentAccount()) return;
            await _refreshLiveActivity();
            closePanel();
          },
          onDelete: onDelete == null
              ? null
              : () async {
                  if (!currentAccount()) return;
                  await onDelete();
                  closePanel();
                },
        );
      });
      return;
    }
    _collapseAgenda();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !currentAccount()) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '일정 편집 닫기',
      barrierColor: Colors.black.withValues(alpha: 0.18),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, _, _) => Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.10)),
            ),
          ),
          Align(
            alignment: useDesktopLayout
                ? Alignment.center
                : Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: useDesktopLayout ? 580 : double.infinity,
              ),
              child: Material(
                color: Colors.transparent,
                child: EventSheet(
                  theme: Theme.of(context).brightness == Brightness.dark
                      ? darkTheme
                      : lightTheme,
                  draft: draft,
                  isEditing: editing,
                  initialDate: date,
                  initialTime: time,
                  onSave: (event) async {
                    if (!currentAccount()) return;
                    await onBeforeSave?.call();
                    if (!currentAccount()) return;
                    final saved = await store.saveEvent(event);
                    if (!currentAccount()) return;
                    if (syncToSystem) await _syncToEventKit(store, saved);
                    if (!currentAccount()) return;
                    await _refreshLiveActivity();
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  onDelete: onDelete == null
                      ? null
                      : () async {
                          if (!currentAccount()) return;
                          await onDelete();
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _syncToEventKit(EventStore store, CalendarEvent event) async {
    final generation = store.accountGeneration;
    bool currentAccount() => mounted && generation == store.accountGeneration;
    if (!_sync.isSupported) return;
    if (!await EventKit.isAvailable()) return;
    if (!currentAccount()) return;
    if (!await EventKit.hasAccess()) return;
    if (!currentAccount()) return;
    if (event.systemEventId != null) {
      await EventKit.updateEvent(event);
    } else {
      final identifier = await EventKit.createEvent(event);
      if (!currentAccount()) return;
      if (identifier != null) {
        await store.saveEvent(event.copyWith(systemEventId: identifier));
      }
    }
  }

  bool _accountIsCurrent(int eventGeneration, int preferencesGeneration) =>
      mounted &&
      eventGeneration == _eventStore.accountGeneration &&
      preferencesGeneration == AccountPreferences.instance.accountGeneration;

  static const _onboardingKey = 'onboarding.completed.v1';

  Future<void> _maybeShowOnboarding() async {
    if (!mounted) return;
    final seen = await AccountPreferences.instance.get(_onboardingKey);
    if (!mounted || seen == true) return;
    final theme = Theme.of(context).brightness == Brightness.dark
        ? darkTheme
        : lightTheme;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '시작하기 가이드',
      barrierColor: Colors.black.withValues(alpha: 0.32),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, _, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
              child: OnboardingGuide(
                theme: theme,
                onManageCalendars: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(_showCalendarConnections());
                },
                onOpenSettings: () {
                  Navigator.of(dialogContext).pop();
                  _openSettings();
                },
                onFinish: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ),
        ),
      ),
    );
    unawaited(AccountPreferences.instance.set(_onboardingKey, true));
  }

  void _openSettings() {
    final settings = SettingsScreen(
      theme: Theme.of(context).brightness == Brightness.dark
          ? darkTheme
          : lightTheme,
      accountLabel: widget.user?.email ?? '게스트',
      onCalendarConnections: _showCalendarConnections,
      onLogout: widget.onLogout,
      onBackup: _backupData,
      onRestore: _restoreData,
      onLiveActivities: LiveActivity.isSupportedPlatform
          ? _showLiveActivities
          : null,
    );
    if (!useDesktopLayout) {
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => settings));
      return;
    }
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '설정 닫기',
      barrierColor: Colors.black.withValues(alpha: 0.18),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, _, _) => Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.10)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 580,
                    maxHeight: 720,
                  ),
                  child: Material(color: Colors.transparent, child: settings),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).brightness == Brightness.dark
        ? darkTheme
        : lightTheme;
    final store = context.watch<EventStore>();
    final imported = context.watch<ImportedEvents>();
    _syncMacCalendarMenu(imported);
    final (from, to) = _range;
    final expanded = expandEvents(
      _combineEvents(
        !_showPersonalCalendar ? const {} : store.events,
        imported.events,
      ),
      from,
      to,
      widget.deviceZone,
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.bg,
      // The month agenda can contain its own expanded panel. Keep the app
      // menu visually and interactively above that panel while it is open.
      drawerScrimColor: Colors.black.withValues(alpha: 0.56),

      drawer: _AccountDrawer(
        personalCalendars: _personalCalendarControls(),
        theme: theme,
        user: widget.user,
        showHolidays: _showHolidays,
        showLunar: _showLunar,
        showSolarTerms: _showSolarTerms,
        showAnniversaries: _showAnniversaries,
        onAnniversariesChanged: (value) => _setDisplaySetting(
          DisplaySetting.anniversaries,
          value,
          () => _showAnniversaries = value,
        ),
        onHolidaysChanged: (value) => _setDisplaySetting(
          DisplaySetting.holidays,
          value,
          () => _showHolidays = value,
        ),
        onLunarChanged: (value) => _setDisplaySetting(
          DisplaySetting.lunar,
          value,
          () => _showLunar = value,
        ),
        onSolarTermsChanged: (value) => _setDisplaySetting(
          DisplaySetting.solarTerms,
          value,
          () => _showSolarTerms = value,
        ),
        imports: imported,
        onManageCalendars: _showCalendarConnections,
        onAddSubscription: _showSubscriptionDialog,
        onSettings: () {
          _scaffoldKey.currentState?.closeDrawer();
          _openSettings();
        },
      ),
      body: SafeArea(
        bottom: false,
        child: useDesktopLayout
            ? MacosCalendarShell(
                theme: theme,
                title: _title,
                account: widget.user?.email ?? '게스트',
                userName: widget.user?.name ?? '',
                selectedDate: _anchorDate,
                visibleDays: _view == ViewMode.week ? _visibleWeekDays : null,
                onDateSelected: (date) {
                  setState(() {
                    _anchorDate = date;
                    _rollingWeekStart = null;
                    _selectedKey = date_utils.toDateKey(date);
                  });
                  _refreshHolidays();
                },
                onConnect: _showCalendarConnections,
                onSettings: _openSettings,
                eventEditorOpen: _eventSidePanel != null,
                calendarControls: [_personalCalendarControls()],
                subscriptionControls: [
                  if (imported.sources.containsKey('kbo'))
                    ImportedCalendarGroup(
                      theme: theme,
                      imports: imported,
                      provider: 'kbo',
                    ),
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.add, color: theme.textSecondary),
                    title: const Text(
                      '구독 추가하기',
                      style: TextStyle(fontSize: 13),
                    ),
                    onTap: _showSubscriptionDialog,
                  ),
                ],
                importedControls: [
                  for (final source in imported.sources.entries.where(
                    (source) => source.key != 'kbo',
                  ))
                    ImportedCalendarGroup(
                      theme: theme,
                      imports: imported,
                      provider: source.key,
                    ),
                ],
                featureControls: [
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: theme.textSecondary,
                    title: const Text('법정 기념일', style: TextStyle(fontSize: 13)),
                    value: _showAnniversaries,
                    onChanged: (value) => _setDisplaySetting(
                      DisplaySetting.anniversaries,
                      value!,
                      () => _showAnniversaries = value,
                    ),
                  ),
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: theme.textMuted,
                    title: const Text('공휴일', style: TextStyle(fontSize: 13)),
                    value: _showHolidays,
                    onChanged: (value) => _setDisplaySetting(
                      DisplaySetting.holidays,
                      value!,
                      () => _showHolidays = value,
                    ),
                  ),
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: theme.textMuted,
                    title: const Text('음력', style: TextStyle(fontSize: 13)),
                    value: _showLunar,
                    onChanged: (value) => _setDisplaySetting(
                      DisplaySetting.lunar,
                      value!,
                      () => _showLunar = value,
                    ),
                  ),
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: theme.textMuted,
                    title: const Text('절기', style: TextStyle(fontSize: 13)),
                    value: _showSolarTerms,
                    onChanged: (value) => _setDisplaySetting(
                      DisplaySetting.solarTerms,
                      value!,
                      () => _showSolarTerms = value,
                    ),
                  ),
                ],
                view: _view,
                onViewChanged: _changeView,
                onPrevious: _goPrev,
                onNext: _goNext,
                onToday: _goToday,
                onCreate: () => _openCreate(
                  _view == ViewMode.month
                      ? date_utils.parseDateKey(_selectedKey)
                      : _anchorDate,
                ),
                onPalette: _openPalette,
                onNavigate: _navigate,
                onActivate: _activateSelection,
                onNudge: _nudgeHovered,
                onDuplicate: _duplicateHovered,
                onRefresh: _refreshAll,
                onManage: () => _scaffoldKey.currentState?.openDrawer(),
                onSearch: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SearchScreen(
                      rangeFrom: from,
                      rangeTo: to,
                      deviceZone: widget.deviceZone,
                      onEventPress: _openEdit,
                    ),
                  ),
                ),
                child: store.loaded
                    ? _animateView(_buildDesktopView(theme, expanded))
                    : const Center(child: CupertinoActivityIndicator()),
              )
            : Column(
                children: [
                  TopBar(
                    theme: theme,
                    title: _title,
                    selectedDate: _anchorDate,
                    onPrev: _goPrev,
                    onNext: _goNext,
                    onToday: _goToday,
                    onDateSelected: (date) {
                      setState(() {
                        _anchorDate = date;
                        _rollingWeekStart = null;
                        _selectedKey = date_utils.toDateKey(date);
                      });
                      _refreshHolidays();
                    },
                    onMenu: () {
                      _collapseAgenda();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _scaffoldKey.currentState?.openDrawer();
                      });
                    },
                    onSearch: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SearchScreen(
                          rangeFrom: from,
                          rangeTo: to,
                          deviceZone: widget.deviceZone,
                          onEventPress: _openEdit,
                        ),
                      ),
                    ),
                    view: _view,
                    onViewChanged: _changeView,
                  ),
                  Expanded(
                    child: !store.loaded
                        ? Center(
                            child: Text(
                              '일정을 불러오고 있습니다…',
                              style: TextStyle(color: theme.textMuted),
                            ),
                          )
                        : Stack(
                            children: [
                              Positioned.fill(
                                child: _animateView(
                                  _buildView(theme, expanded),
                                ),
                              ),
                              Positioned(
                                right: 20,
                                bottom:
                                    MediaQuery.viewPaddingOf(context).bottom +
                                    24,
                                child: SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: LiquidGlass(
                                    radius: 24,
                                    child: IconButton(
                                      tooltip: '일정 추가',
                                      onPressed: () => _openCreate(
                                        _view == ViewMode.month
                                            ? date_utils.parseDateKey(
                                                _selectedKey,
                                              )
                                            : _anchorDate,
                                      ),
                                      icon: Icon(
                                        Icons.add,
                                        color: theme.text,
                                        size: 26,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _animateView(Widget child) {
    if (useWindowsCalendarMotion) {
      return CalendarViewTransition(viewKey: _view, child: child);
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ClipRect(
      child: TweenAnimationBuilder<double>(
        key: ValueKey(_view),
        tween: Tween(begin: 0, end: 1),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: child,
        builder: (context, progress, child) => Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - progress)),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopView(AppTheme theme, EventMap expanded) {
    // Freeze each view's contents before layout: an outgoing transition must
    // not rebuild itself using the newly selected mode.
    final calendar = _buildView(theme, expanded);
    final editor = _eventSidePanel;
    final view = _view;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (editor == null ||
            (view == ViewMode.month && constraints.maxWidth >= 760)) {
          return calendar;
        }
        if (constraints.maxWidth < 600) return editor;
        return Row(
          children: [
            Expanded(child: calendar),
            Container(
              width: constraints.maxWidth >= 1000 ? 280 : 230,
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: theme.border)),
              ),
              child: editor,
            ),
          ],
        );
      },
    );
  }

  Widget _buildView(AppTheme theme, EventMap expanded) {
    switch (_view) {
      case ViewMode.month:
        return MonthAgenda(
          sidePanel: _eventSidePanel,
          theme: theme,
          viewDate: _anchorDate,
          events: expanded,
          selectedKey: _selectedKey,
          onPreviousMonth: _goPrev,
          onNextMonth: _goNext,
          showHolidays: _showHolidays,
          holidayNames: _apiHolidays,
          solarTermNames: _showSolarTerms ? _apiSolarTerms : const {},
          anniversaryNames: _showAnniversaries ? _apiAnniversaries : const {},
          showLunar: _showLunar,
          onEventPress: _openEdit,
          onSlotPress: (date, hour) =>
              _openCreate(date, '${hour.toString().padLeft(2, '0')}:00'),
          onCollapseReady: (collapse) => _collapseAgenda = collapse,
          onEventMove: _moveEvent,
          onEventHover: _onEventHover,
          onCreateDate: (date) {
            _selectDay(date);
            _openSheet(draft: null, date: date);
          },
          onSelectDate: (key) {
            setState(() {
              _selectedKey = key;
              _anchorDate = date_utils.parseDateKey(key);
            });
            _refreshHolidays();
          },
        );
      case ViewMode.week:
        return TimeGridView(
          onShiftDays: _shiftVisibleDays,
          onPrevious: _goPrev,
          onNext: _goNext,
          theme: theme,
          days: _visibleWeekDays,
          events: expanded,
          anniversaryNames: _showAnniversaries ? _apiAnniversaries : const {},
          onSlotPress: (date, hour) =>
              _openCreate(date, '${hour.toString().padLeft(2, '0')}:00'),
          onEventPress: _openEdit,
          onEventMove: (event, date, time) =>
              _moveEvent(event, date, time: time),
          onEventResize: (event, time, duration) => _moveEvent(
            event,
            date_utils.parseDateKey(event.date),
            time: time,
            duration: duration,
          ),
          onEventHover: _onEventHover,
          onRangeCreate: _createRange,
          selectedDate: _anchorDate,
        );
      case ViewMode.day:
        return TimeGridView(
          onShiftDays: _shiftVisibleDays,
          onPrevious: _goPrev,
          onNext: _goNext,
          theme: theme,
          days: [_anchorDate],
          events: expanded,
          anniversaryNames: _showAnniversaries ? _apiAnniversaries : const {},
          onSlotPress: (date, hour) =>
              _openCreate(date, '${hour.toString().padLeft(2, '0')}:00'),
          onEventPress: _openEdit,
          onEventMove: (event, date, time) =>
              _moveEvent(event, date, time: time),
          onEventResize: (event, time, duration) => _moveEvent(
            event,
            date_utils.parseDateKey(event.date),
            time: time,
            duration: duration,
          ),
          onEventHover: _onEventHover,
          onRangeCreate: _createRange,
          selectedDate: _anchorDate,
        );
      case ViewMode.list:
        return EventListView(
          theme: theme,
          events: expanded,
          onEventPress: _openEdit,
        );
    }
  }
}

class _ImportEventOption {
  const _ImportEventOption(this.calendar, this.event);

  final ImportCalendar calendar;
  final ImportedEvent event;

  String get detail {
    final time = event.time == null ? '종일' : event.time!;
    final calendarTitle = calendar.title.split(' · ').first;
    return '$calendarTitle · ${event.date} · $time';
  }
}

class _ImportSelectionSheet extends StatelessWidget {
  const _ImportSelectionSheet({
    required this.title,
    required this.children,
    required this.onCancel,
    required this.onImport,
    this.empty = false,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onCancel;
  final VoidCallback onImport;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: onCancel,
          child: const Text('취소'),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: onImport,
          child: const Text('가져오기'),
        ),
      ),
      child: SafeArea(
        child: empty
            ? const Center(child: Text('이 기간에 가져올 일정이 없습니다.'))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: children.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, index) => children[index],
              ),
      ),
    );
  }
}

class _CalendarImportChoice extends StatelessWidget {
  const _CalendarImportChoice({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title ${selected ? '선택됨' : '선택 안 됨'}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CupertinoColors.label,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CupertinoColors.secondaryLabel,
                          fontSize: 13,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              CupertinoCheckbox(
                value: selected,
                onChanged: (_) => onTap(),
                activeColor: CupertinoColors.activeBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountDrawer extends StatelessWidget {
  final Widget personalCalendars;
  final AppTheme theme;
  final AuthUser? user;
  final bool showHolidays;
  final bool showLunar;
  final bool showSolarTerms;
  final bool showAnniversaries;
  final ValueChanged<bool> onAnniversariesChanged;
  final ValueChanged<bool> onHolidaysChanged;
  final ValueChanged<bool> onLunarChanged;
  final ValueChanged<bool> onSolarTermsChanged;
  final ImportedEvents imports;
  final VoidCallback onManageCalendars;
  final VoidCallback onAddSubscription;
  final VoidCallback onSettings;
  const _AccountDrawer({
    required this.personalCalendars,
    required this.theme,
    required this.user,
    required this.showHolidays,
    required this.showLunar,
    required this.showSolarTerms,
    required this.showAnniversaries,
    required this.onAnniversariesChanged,
    required this.onHolidaysChanged,
    required this.onLunarChanged,
    required this.onSolarTermsChanged,
    required this.imports,
    required this.onManageCalendars,
    required this.onAddSubscription,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final email = user?.email ?? '로그인이 필요합니다';
    final name = user?.name.isNotEmpty == true
        ? user!.name
        : user?.email.split('@').first;
    return Drawer(
      elevation: 32,
      backgroundColor: theme.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: ListView(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name == null || name.isEmpty ? '사용자' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.7,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '캘린더 관리',
                    onPressed: onManageCalendars,
                    icon: Icon(
                      Icons.calendar_month_outlined,
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                    ),
                  ),
                  IconButton(
                    tooltip: '설정',
                    onPressed: onSettings,
                    icon: Icon(
                      Icons.settings_outlined,
                      color: theme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: theme.border, height: 1),
              const SizedBox(height: 20),
              _sectionTitle('내 캘린더'),
              const SizedBox(height: 6),
              personalCalendars,
              if (imports.sources.isNotEmpty) ...[
                for (final entry in imports.sources.entries.where(
                  (entry) => entry.key != 'kbo',
                ))
                  ImportedCalendarGroup(
                    theme: theme,
                    imports: imports,
                    provider: entry.key,
                  ),
              ],
              const SizedBox(height: 28),
              _sectionTitle('구독'),
              const SizedBox(height: 10),
              if (imports.sources.containsKey('kbo'))
                ImportedCalendarGroup(
                  theme: theme,
                  imports: imports,
                  provider: 'kbo',
                ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.add, size: 20, color: theme.textSecondary),
                title: const Text('구독 추가하기', style: TextStyle(fontSize: 13)),
                onTap: onAddSubscription,
              ),
              const SizedBox(height: 28),
              _sectionTitle('기능 표시'),
              const SizedBox(height: 10),
              _displayCheckbox(
                label: '법정 기념일',
                value: showAnniversaries,
                onChanged: onAnniversariesChanged,
                subscription: true,
              ),
              _displayCheckbox(
                label: '공휴일',
                value: showHolidays,
                onChanged: onHolidaysChanged,
              ),
              _displayCheckbox(
                label: '음력',
                value: showLunar,
                onChanged: onLunarChanged,
              ),
              _displayCheckbox(
                label: '절기',
                value: showSolarTerms,
                onChanged: onSolarTermsChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      title,
      style: TextStyle(
        color: theme.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _displayCheckbox({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool subscription = false,
    Color? selectedColor,
  }) {
    return Semantics(
      label: label,
      checked: value,
      onTap: () => onChanged(!value),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              Icon(
                value
                    ? CupertinoIcons.checkmark_square_fill
                    : CupertinoIcons.square,
                size: 23,
                color: value && selectedColor != null
                    ? selectedColor
                    : (subscription ? theme.textSecondary : theme.textMuted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: theme.text, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarConnectionsSheet extends StatelessWidget {
  final AppTheme theme;
  final ImportedEvents imports;
  final ValueChanged<String> onConnect;
  final Future<void> Function(String provider, ImportCalendar calendar)
  onDisconnect;
  const _CalendarConnectionsSheet({
    required this.theme,
    required this.imports,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        Text(
          '외부 일정은 이 앱에서 읽기 전용으로 표시됩니다.',
          style: TextStyle(color: theme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 3),
        Text(
          '로그인한 계정과 다른 계정의 캘린더도 연결할 수 있어요.',
          style: TextStyle(color: theme.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 24),
        // EventKit 채널은 iOS에만 있어 macOS에서는 기기 캘린더 연동을 숨긴다.
        if (kIsWeb || !useDesktopLayout) ...[
          _connectionSection('이 기기', [
            _ConnectionInfo(
              'device',
              '기기 캘린더',
              CupertinoIcons.calendar,
              'Apple·네이버 등 기기에 등록된 캘린더 일정 가져오기',
            ),
          ]),
          const SizedBox(height: 22),
        ],
        _connectionSection('계정 연결', [
          _ConnectionInfo(
            'google',
            'Google 캘린더',
            CupertinoIcons.globe,
            'Google 계정에서 캘린더 선택',
          ),
          _ConnectionInfo(
            'notion',
            'Notion',
            CupertinoIcons.doc_text,
            '날짜 속성이 있는 데이터베이스 선택',
          ),
        ]),
        if (imports.sources.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(
            '연동된 캘린더',
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 9),
          AnimatedBuilder(
            animation: imports,
            builder: (context, _) => Column(
              children: [
                for (final entry in imports.sources.entries)
                  for (final calendar in entry.value)
                    _connectedCalendarRow(context, entry.key, calendar),
              ],
            ),
          ),
        ],
      ],
    );
    if (useDesktopLayout) {
      return AppDialog(
        title: const Text('캘린더 연동'),
        icon: CupertinoIcons.calendar,
        maxWidth: 520,
        content: content,
      );
    }
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        decoration: BoxDecoration(
          color: theme.bg,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppDialogStyle.radius),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppDialogHeader(
              title: const Text('캘린더 연동'),
              onClose: () => Navigator.pop(context),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: AppDialogStyle.bodyPadding,
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectionSection(String title, List<_ConnectionInfo> items) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 9),
          for (final item in items) _connectionRow(item),
        ],
      );

  Widget _connectionRow(_ConnectionInfo item) {
    final isConnected = imports.sources.containsKey(item.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => onConnect(item.id),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.bgSecondary,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: theme.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(item.icon, color: theme.text, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        color: theme.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.detail,
                      style: TextStyle(color: theme.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isConnected)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '연동됨',
                    style: TextStyle(
                      color: Color(0xFF248A3D),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Icon(
                  CupertinoIcons.chevron_right,
                  color: theme.textMuted,
                  size: 16,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _connectedCalendarRow(
    BuildContext context,
    String provider,
    ImportCalendar calendar,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: theme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: colorFromHex(calendar.color),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              calendar.title,
              style: TextStyle(color: theme.text, fontSize: 14),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.all(6),
            minimumSize: const Size(32, 32),
            onPressed: () => _confirmDisconnect(context, provider, calendar),
            child: const Icon(
              CupertinoIcons.trash,
              color: CupertinoColors.systemRed,
              size: 19,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDisconnect(
    BuildContext context,
    String provider,
    ImportCalendar calendar,
  ) async {
    final remove = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: const Text('연동 해제'),
        content: Text('${calendar.title} 캘린더 연동을 해제할까요?'),
        actions: [
          AppDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          AppDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('해제'),
          ),
        ],
      ),
    );
    if (remove == true) await onDisconnect(provider, calendar);
  }
}

class _ConnectionInfo {
  final String id, title, detail;
  final IconData icon;
  const _ConnectionInfo(this.id, this.title, this.icon, this.detail);
}
