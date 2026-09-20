import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart' show debugPaintBaselinesEnabled;
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import 'logic/date_utils.dart' as date_utils;
import 'logic/event_dedup.dart';
import 'logic/recurrence.dart';
import 'models/calendar_event.dart';
import 'native/eventkit.dart';
import 'native/live_activity.dart';
import 'native/macos_window.dart';
import 'screens/event_sheet.dart';
import 'screens/list_view.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/search_screen.dart';
import 'screens/time_grid_view.dart';
import 'services/auth_service.dart';
import 'services/app_update_service.dart';
import 'services/backup_service.dart';
import 'storage/event_store.dart';
import 'storage/display_settings.dart';
import 'storage/account_preferences.dart';
import 'storage/imported_events.dart';
import 'sync/system_events_sync.dart';
import 'theme/app_theme.dart';
import 'screens/month_agenda.dart';
import 'screens/settings_screen.dart';
import 'widgets/top_bar.dart';
import 'widgets/macos_calendar_shell.dart';
import 'widgets/liquid_glass.dart';
import 'widgets/server_connection_monitor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      // Place this below MaterialApp so its dialog uses the root Navigator,
      // and above AuthGate so it also covers the login and consent flow.
      home: ServerConnectionMonitor(child: AuthGate(deviceZone: deviceZone)),
    );
  }
}

enum _AuthScreen { login, signup }

/// Port of App.tsx's auth gating: wait for a stored session to be restored,
/// then show login/signup, or fall straight through in guest mode.
class AuthGate extends StatefulWidget {
  final tz.Location deviceZone;
  const AuthGate({super.key, required this.deviceZone});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  AuthUser? _user;
  bool _guest = false;
  _AuthScreen _screen = _AuthScreen.login;
  int _authGeneration = 0;

  @override
  void initState() {
    super.initState();
    // Do not block the first screen on an API request. A disconnected server
    // must show the login screen and its connection alert immediately.
    _loading = false;
    unawaited(MacosWindow.showCalendar(false));
    AuthService.instance.restoreSession().then((user) {
      if (mounted && _authGeneration == 0 && user != null) {
        _acceptUser(user);
      }
    });
  }

  Future<void> _acceptUser(AuthUser? user, {bool guest = false}) async {
    final generation = ++_authGeneration;
    setState(() => _loading = true);
    final imports = context.read<ImportedEvents>();
    final events = context.read<EventStore>();
    await events.selectAccount(user?.id);
    await events.sync();
    await AccountPreferences.instance.selectAccount(user?.id);
    await AccountPreferences.instance.sync();
    await DisplaySettings.instance.load();
    await imports.load();
    if (!mounted || generation != _authGeneration) return;
    await MacosWindow.showCalendar(user != null || guest);
    if (!mounted || generation != _authGeneration) return;
    setState(() {
      _user = user;
      _guest = guest;
      _loading = false;
      _screen = _AuthScreen.login;
    });
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
    if (_user == null && !_guest) {
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
        onContinueAsGuest: () => _acceptUser(null, guest: true),
      );
    }
    return CalendarHome(
      deviceZone: widget.deviceZone,
      user: _user,
      onLogout: () async {
        await LiveActivity.end();
        if (_user != null) await AuthService.instance.logout();
        if (mounted) await _acceptUser(null);
      },
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
  ViewMode _view = ViewMode.month;
  bool _showPersonalCalendar = true;
  DateTime _anchorDate = DateTime.now();
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
  Timer? _eventSyncTimer;
  VoidCallback _collapseAgenda = () {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _eventStore = context.read<EventStore>();
    _sync = SystemEventsSync(_eventStore);
    _eventStore.syncSucceeded.addListener(_showEventSyncStatus);
    _eventSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_eventStore.sync());
        unawaited(_refreshLiveActivity());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _showEventSyncStatus());
    AccountPreferences.instance.syncSucceeded.addListener(
      _showSettingsSyncStatus,
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showSettingsSyncStatus(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSync());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadHolidays(_anchorDate.year),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshImported());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLiveActivity());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForAppUpdate());
  }

  Future<void> _checkForAppUpdate() async {
    final update = await AppUpdateService.check();
    if (!mounted || update == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('업데이트가 필요합니다'),
        content: Text('새 버전 ${update.version}이 출시되었습니다. 최신 버전으로 업데이트해 주세요.'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('나중에'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            textStyle: const TextStyle(color: CupertinoColors.systemBlue),
            onPressed: () async {
              final url = update.updateUrl;
              if (url == null) return;
              final uri = Uri.tryParse(url);
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

  void _showEventSyncStatus() {
    if (!mounted ||
        widget.user == null ||
        _eventStore.syncSucceeded.value != false) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('일정은 이 기기에 저장됐습니다. 서버 연결 후 다른 기기에 동기화됩니다.')),
    );
  }

  void _showSettingsSyncStatus() {
    if (!mounted ||
        widget.user == null ||
        AccountPreferences.instance.syncSucceeded.value != false) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('설정은 이 기기에 저장됐습니다. 서버 연결 후 계정에 동기화됩니다.')),
    );
  }

  Future<void> _restoreSettings() async {
    final imports = context.read<ImportedEvents>();
    if (!await AccountPreferences.instance.sync() || !mounted) return;
    await DisplaySettings.instance.load();
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

  List<LiveCalendarEvent> _liveActivityCandidates() => liveActivityCandidates(
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
    try {
      final status = await LiveActivity.status();
      if (!mounted) return;
      if (!status.enabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('일정 실시간 업데이트를 사용하려면 알림을 허용해 주세요.'),
            action: SnackBarAction(
              label: '알림 설정',
              onPressed: () {
                unawaited(LiveActivity.openNotificationSettings());
              },
            ),
          ),
        );
        return;
      }
      final candidates = _liveActivityCandidates();
      final selected = await showModalBottomSheet<String>(
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
                const Text('선택한 일정의 남은 시간과 진행 상태를 잠금 화면과 알림창에서 확인하세요.'),
                const SizedBox(height: 16),
                if (candidates.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('진행 중이거나 10분 이내에 시작하는 일정이 없습니다.'),
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
                        : const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(sheetContext, event.id),
                  ),
                if (status.eventIDs.isNotEmpty) ...[
                  const Divider(),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(sheetContext, '__end__'),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('실시간 업데이트 종료'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
      if (!mounted || selected == null) return;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              selected == '__end__'
                  ? '실시간 업데이트를 종료했습니다.'
                  : '알림창에 일정 실시간 업데이트를 표시합니다.',
            ),
          ),
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? '실시간 업데이트를 시작하지 못했습니다.')),
        );
      }
    }
  }

  Future<void> _refreshLiveActivity() async {
    if (!mounted || !LiveActivity.isSupportedPlatform) return;
    try {
      final status = await LiveActivity.status();
      if (!mounted) return;
      final candidates = _liveActivityCandidates();
      final activeIDs = status.eventIDs.toSet();
      if (LiveActivity.isAndroid) {
        // Android tracks only the event explicitly selected by the user.
        // Stopping or dismissing the notification must not restart it.
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
        if (activeIDs.contains(event.id)) {
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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('백업 데이터를 복원했습니다.')));
      }
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('백업 파일을 복원하지 못했습니다.')));
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('표시 설정을 저장하지 못했습니다. 다시 시도해 주세요.')),
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
    _eventStore.syncSucceeded.removeListener(_showEventSyncStatus);
    AccountPreferences.instance.syncSucceeded.removeListener(
      _showSettingsSyncStatus,
    );
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
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('캘린더 연동 실패'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
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
    try {
      if (provider == 'apple' || provider == 'naver') {
        if (!await EventKit.requestAccess()) {
          throw AuthException('Apple 캘린더 접근을 허용해 주세요.');
        }
        final deviceCalendars = await EventKit.fetchCalendars();
        final selectedCalendars = await _pickDeviceCalendars(deviceCalendars);
        if (selectedCalendars == null || selectedCalendars.isEmpty) return;
        final (from, to) = _range;
        final native = await EventKit.fetchEvents(
          date_utils.parseDateKey(from),
          date_utils.parseDateKey(to),
          calendarIds: selectedCalendars
              .map((calendar) => calendar.id)
              .toList(),
        );
        final imported = <String, List<CalendarEvent>>{};
        for (final event in native) {
          (imported[event.date] ??= []).add(
            event.copyWith(
              id: 'import:$provider:${event.systemEventId ?? event.id}',
              systemCalendarId:
                  '$provider|${event.systemCalendarId ?? selectedCalendars.first.id}',
              description:
                  '${provider == 'naver' ? '네이버/CalDAV' : 'Apple'} · 읽기 전용',
            ),
          );
        }
        if (!mounted) return;
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
        importedEvents.replaceProvider(provider, imported);
        if (mounted && provider == 'naver') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('iPhone 설정에 추가된 네이버 CalDAV 일정을 가져왔습니다.'),
            ),
          );
        }
        return;
      }
      final url = await AuthService.instance.calendarImportStart(provider);
      final result = await FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: 'calendar',
      );
      final callback = Uri.parse(result);
      if (callback.queryParameters['result'] != 'success') {
        throw AuthException(callback.queryParameters['error'] ?? '연결하지 못했습니다.');
      }
      if (!mounted) return;
      final calendars = await AuthService.instance.importCalendars(provider);
      if (!mounted) return;
      await _pickAndImport(provider, calendars);
    } on AuthException catch (error) {
      if (mounted) await _showCalendarImportError(error.message);
    } catch (_) {
      if (mounted) await _showCalendarImportError('캘린더 연결을 완료하지 못했습니다.');
    }
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
                        title: calendar.title.split(' · ').first,
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
    if (choices == null || choices.isEmpty || !mounted) return;
    final (from, to) = _range;
    final imports = context.read<ImportedEvents>();
    final options = <_ImportEventOption>[];
    try {
      for (final calendar in choices) {
        final events = await AuthService.instance.importEvents(
          provider,
          calendar.id,
          date_utils.parseDateKey(from),
          date_utils.parseDateKey(to),
        );
        options.addAll(
          events.map((event) => _ImportEventOption(calendar, event)),
        );
      }
    } on AuthException catch (error) {
      if (mounted) await _showCalendarImportError(error.message);
      return;
    }
    if (options.isEmpty) {
      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('가져올 일정이 없습니다'),
          content: const Text('선택한 기간에 새로 가져올 일정이 없습니다.'),
          actions: [
            CupertinoDialogAction(
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
    if (selectedEvents == null || !mounted) return;
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
        return date_utils.formatWeekTitle(_anchorDate);
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
        _anchorDate = date_utils.addDays(_anchorDate, -7);
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
        _anchorDate = date_utils.addDays(_anchorDate, 7);
      }
      if (_view == ViewMode.day) {
        _anchorDate = date_utils.addDays(_anchorDate, 1);
      }
    });
    _refreshHolidays();
  }

  void _goToday() {
    setState(() {
      _anchorDate = DateTime.now();
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
    await _openSheet(draft: null, date: date, time: time);
  }

  Future<void> _openEdit(CalendarEvent event) async {
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
        onBeforeSave: () =>
            context.read<ImportedEvents>().hideImportedEvent(event),
        onDelete: () async {
          await context.read<ImportedEvents>().hideImportedEvent(event);
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
        if (resolved.systemEventId != null) {
          await EventKit.deleteEvent(resolved.systemEventId!);
        }
        await store.deleteEvent(resolved.date, resolved.id);
        await _refreshLiveActivity();
      },
    );
  }

  Future<void> _openSheet({
    required CalendarEvent? draft,
    required DateTime date,
    String? time,
    bool syncToSystem = true,
    Future<void> Function()? onBeforeSave,
    Future<void> Function()? onDelete,
  }) async {
    _collapseAgenda();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final store = context.read<EventStore>();
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
            alignment: !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
                ? Alignment.center
                : Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth:
                    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
                    ? 580
                    : double.infinity,
              ),
              child: Material(
                color: Colors.transparent,
                child: EventSheet(
                  theme: Theme.of(context).brightness == Brightness.dark
                      ? darkTheme
                      : lightTheme,
                  draft: draft,
                  isEditing: draft != null,
                  initialDate: date,
                  initialTime: time,
                  onSave: (event) async {
                    await onBeforeSave?.call();
                    final saved = await store.saveEvent(event);
                    if (syncToSystem) await _syncToEventKit(store, saved);
                    await _refreshLiveActivity();
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  onDelete: onDelete == null
                      ? null
                      : () async {
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
    if (!_sync.isSupported) return;
    if (!await EventKit.isAvailable()) return;
    if (!await EventKit.requestAccess()) return;
    if (event.systemEventId != null) {
      await EventKit.updateEvent(event);
    } else {
      final identifier = await EventKit.createEvent(event);
      if (identifier != null) {
        await store.saveEvent(event.copyWith(systemEventId: identifier));
      }
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          theme: Theme.of(context).brightness == Brightness.dark
              ? darkTheme
              : lightTheme,
          accountLabel: widget.user?.email ?? '게스트',
          onLogout: widget.onLogout,
          onBackup: _backupData,
          onRestore: _restoreData,
          onLiveActivities: LiveActivity.isSupportedPlatform
              ? _showLiveActivities
              : null,
        ),
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
    final (from, to) = _range;
    final expanded = expandEvents(
      _combineEvents(
        !kIsWeb &&
                defaultTargetPlatform == TargetPlatform.macOS &&
                !_showPersonalCalendar
            ? const {}
            : store.events,
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
        onSettings: () {
          _scaffoldKey.currentState?.closeDrawer();
          _openSettings();
        },
      ),
      body: SafeArea(
        bottom: false,
        child: !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
            ? MacosCalendarShell(
                theme: theme,
                title: _title,
                account: widget.user?.email ?? '게스트',
                selectedDate: _anchorDate,
                onDateSelected: (date) {
                  setState(() {
                    _anchorDate = date;
                    _selectedKey = date_utils.toDateKey(date);
                  });
                  _refreshHolidays();
                },
                onConnect: _showCalendarConnections,
                onSettings: _openSettings,
                calendarControls: [
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: theme.accent,
                    title: const Text('내 캘린더', style: TextStyle(fontSize: 13)),
                    value: _showPersonalCalendar,
                    onChanged: (value) =>
                        setState(() => _showPersonalCalendar = value!),
                  ),
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: const Color(0xFFFF604E),
                    title: const Text(
                      '대한민국 공휴일',
                      style: TextStyle(fontSize: 13),
                    ),
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
                    activeColor: const Color(0xFFAA50C0),
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
                    title: const Text('음력 표시', style: TextStyle(fontSize: 13)),
                    value: _showLunar,
                    onChanged: (value) => _setDisplaySetting(
                      DisplaySetting.lunar,
                      value!,
                      () => _showLunar = value,
                    ),
                  ),
                  for (final source in imported.sources.entries)
                    for (final calendar in source.value)
                      CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: colorFromHex(calendar.color),
                        title: Text(
                          calendar.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        value: imported.isVisible(source.key, calendar.id),
                        onChanged: (value) => imported.setVisible(
                          source.key,
                          calendar.id,
                          value!,
                        ),
                      ),
                ],
                view: _view,
                onViewChanged: (view) => setState(() => _view = view),
                onPrevious: _goPrev,
                onNext: _goNext,
                onToday: _goToday,
                onCreate: () => _openCreate(
                  _view == ViewMode.month
                      ? date_utils.parseDateKey(_selectedKey)
                      : _anchorDate,
                ),
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
                    ? _buildView(theme, expanded)
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
                    onViewChanged: (view) => setState(() => _view = view),
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
                                child: _buildView(theme, expanded),
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

  Widget _buildView(AppTheme theme, EventMap expanded) {
    switch (_view) {
      case ViewMode.month:
        return MonthAgenda(
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
          theme: theme,
          days: date_utils.getWeekDays(_anchorDate),
          events: expanded,
          onSlotPress: (date, hour) =>
              _openCreate(date, '${hour.toString().padLeft(2, '0')}:00'),
          onEventPress: _openEdit,
        );
      case ViewMode.day:
        return TimeGridView(
          theme: theme,
          days: [_anchorDate],
          events: expanded,
          onSlotPress: (date, hour) =>
              _openCreate(date, '${hour.toString().padLeft(2, '0')}:00'),
          onEventPress: _openEdit,
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
  final VoidCallback onSettings;
  const _AccountDrawer({
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              if (imports.sources.isNotEmpty) ...[
                _sectionTitle('표시할 캘린더'),
                const SizedBox(height: 6),
                for (final entry in imports.sources.entries)
                  for (final calendar in entry.value)
                    _importedCalendarToggle(entry.key, calendar),
              ],
              _displayCheckbox(
                label: '법정 기념일',
                value: showAnniversaries,
                onChanged: onAnniversariesChanged,
                subscription: true,
              ),
              const SizedBox(height: 28),
              _sectionTitle('기능 표시'),
              const SizedBox(height: 10),
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

  Widget _importedCalendarToggle(String provider, ImportCalendar calendar) =>
      _displayCheckbox(
        label: calendar.title,
        value: imports.isVisible(provider, calendar.id),
        selectedColor: colorFromHex(calendar.color),
        onChanged: (value) => imports.setVisible(provider, calendar.id, value),
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
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        decoration: BoxDecoration(
          color: theme.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '캘린더 연동',
              style: TextStyle(
                color: theme.text,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
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
            _connectionSection('이 기기', [
              _ConnectionInfo(
                'apple',
                'Apple 캘린더',
                CupertinoIcons.calendar,
                '기기에 등록된 캘린더 일정 가져오기',
              ),
              _ConnectionInfo(
                'naver',
                '네이버 캘린더',
                CupertinoIcons.cloud,
                'iPhone CalDAV에 등록된 네이버 일정',
              ),
            ]),
            const SizedBox(height: 22),
            _connectionSection('계정 연결', [
              _ConnectionInfo(
                'google',
                'Google 캘린더',
                CupertinoIcons.globe,
                'Google 계정에서 캘린더 선택',
              ),
              _ConnectionInfo(
                'kakao',
                '카카오 캘린더',
                CupertinoIcons.chat_bubble_2,
                '카카오톡 캘린더 일정 가져오기',
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
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('연동 해제'),
        content: Text('${calendar.title} 캘린더 연동을 해제할까요?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
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
