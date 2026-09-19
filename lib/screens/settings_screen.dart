import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

import '../services/backup_service.dart';
import '../theme/app_theme.dart';
import '../widgets/liquid_glass.dart';

class SettingsScreen extends StatelessWidget {
  final AppTheme theme;
  final String accountLabel;
  final VoidCallback onLogout;
  final VoidCallback? onLiveActivities;
  final Future<List<String>> Function(ValueChanged<double> onProgress)?
  onBackup;
  final Future<void> Function()? onRestore;

  const SettingsScreen({
    super.key,
    required this.theme,
    required this.accountLabel,
    required this.onLogout,
    this.onLiveActivities,
    this.onBackup,
    this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    if (_isAndroid) return _buildAndroid(context);
    return CupertinoTheme(
      data: CupertinoThemeData(
        brightness: theme.isDark ? Brightness.dark : Brightness.light,
        primaryColor: theme.accent,
        scaffoldBackgroundColor: theme.isDark
            ? CupertinoColors.black
            : theme.bg,
        barBackgroundColor: theme.isDark
            ? CupertinoColors.black
            : theme.surface,
      ),
      child: CupertinoPageScaffold(
        backgroundColor: theme.isDark
            ? CupertinoColors.black
            : CupertinoColors.systemGroupedBackground.resolveFrom(context),
        navigationBar: CupertinoNavigationBar(
          backgroundColor: theme.isDark ? CupertinoColors.black : theme.bg,
          border: null,
          automaticBackgroundVisibility: false,
          leading: SizedBox(
            width: 38,
            height: 38,
            child: LiquidGlass(
              useNative: false,
              radius: 19,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).maybePop(),
                child: Icon(CupertinoIcons.back, color: theme.accent, size: 24),
              ),
            ),
          ),
          middle: const Text('설정'),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 28),
            children: [
              CupertinoListSection.insetGrouped(
                header: const Text('계정'),
                children: [
                  CupertinoListTile.notched(
                    leading: _icon(
                      CupertinoIcons.person_fill,
                      CupertinoColors.systemGrey,
                    ),
                    title: const Text('로그인 계정'),
                    subtitle: Text(
                      accountLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  CupertinoListTile.notched(
                    leading: _icon(
                      CupertinoIcons.square_arrow_right,
                      CupertinoColors.systemRed,
                    ),
                    title: const Text(
                      '로그아웃',
                      style: TextStyle(color: CupertinoColors.systemRed),
                    ),
                    onTap: () => _confirmLogout(context),
                  ),
                ],
              ),
              if (onLiveActivities != null) ...[
                CupertinoListSection.insetGrouped(
                  header: const Text('실시간 현황'),
                  children: [
                    CupertinoListTile.notched(
                      leading: _icon(
                        CupertinoIcons.bolt_fill,
                        CupertinoColors.systemOrange,
                      ),
                      title: const Text('Live Activity 요청 보내기'),
                      trailing: const CupertinoListTileChevron(),
                      onTap: onLiveActivities,
                    ),
                  ],
                ),
              ],
              if (onBackup != null || onRestore != null)
                CupertinoListSection.insetGrouped(
                  header: const Text('데이터 관리'),
                  children: [
                    if (onBackup != null)
                      CupertinoListTile.notched(
                        leading: _icon(
                          CupertinoIcons.arrow_up_doc_fill,
                          CupertinoColors.systemBlue,
                        ),
                        title: const Text('데이터 백업하기'),
                        trailing: const CupertinoListTileChevron(),
                        onTap: () => _confirmBackup(context),
                      ),
                    if (onRestore != null)
                      CupertinoListTile.notched(
                        leading: _icon(
                          CupertinoIcons.arrow_down_doc_fill,
                          CupertinoColors.systemGreen,
                        ),
                        title: const Text('데이터 복원하기'),
                        trailing: const CupertinoListTileChevron(),
                        onTap: () => _confirmRestore(context),
                      ),
                  ],
                ),
              CupertinoListSection.insetGrouped(
                header: const Text('법률 정보 및 이용 약관'),
                children: [
                  CupertinoListTile.notched(
                    leading: _icon(
                      CupertinoIcons.doc_text_fill,
                      CupertinoColors.systemBlue,
                    ),
                    title: const Text('이용약관'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => _showInfo(
                      context,
                      '이용약관',
                      '캘린더 서비스 이용에 관한 약관입니다. 서비스 이용 전 내용을 확인해 주세요.',
                    ),
                  ),
                  CupertinoListTile.notched(
                    leading: _icon(
                      CupertinoIcons.lock_shield_fill,
                      CupertinoColors.systemGreen,
                    ),
                    title: const Text('개인정보 처리방침'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => _showInfo(
                      context,
                      '개인정보 처리방침',
                      '서비스 제공에 필요한 정보만 처리하며, 개인정보 보호 관련 내용을 안내합니다.',
                    ),
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('프로그램 정보'),
                children: [
                  CupertinoListTile.notched(
                    leading: _icon(
                      CupertinoIcons.calendar,
                      CupertinoColors.systemRed,
                    ),
                    title: Text('캘린더'),
                    additionalInfo: const Text('0.1.0 베타'),
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('안내'),
                children: [
                  CupertinoListTile.notched(
                    leading: _icon(
                      CupertinoIcons.bell_fill,
                      CupertinoColors.systemRed,
                    ),
                    title: const Text('공시사항'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () =>
                        _showInfo(context, '공시사항', '현재 등록된 공시사항이 없습니다.'),
                  ),
                  CupertinoListTile.notched(
                    leading: _icon(
                      CupertinoIcons.chat_bubble_2_fill,
                      CupertinoColors.systemGreen,
                    ),
                    title: const Text('고객센터'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () =>
                        _showInfo(context, '고객센터', '문의 사항은 고객센터를 통해 접수해 주세요.'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  Widget _buildAndroid(BuildContext context) {
    final materialTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: theme.accent,
        brightness: theme.isDark ? Brightness.dark : Brightness.light,
      ),
    );
    return Theme(
      data: materialTheme,
      child: Builder(
        builder: (context) {
          final colors = Theme.of(context).colorScheme;
          Widget section(String title, List<Widget> tiles) => Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: colors.primary),
                  ),
                ),
                Card.filled(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: tiles),
                ),
              ],
            ),
          );
          Widget tile(
            IconData icon,
            String title, {
            String? subtitle,
            VoidCallback? onTap,
            bool destructive = false,
          }) => ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 6,
            ),
            leading: Icon(
              icon,
              color: destructive ? colors.error : colors.onSurfaceVariant,
            ),
            title: Text(
              title,
              style: destructive ? TextStyle(color: colors.error) : null,
            ),
            subtitle: subtitle == null ? null : Text(subtitle),
            trailing: onTap == null ? null : const Icon(Icons.chevron_right),
            onTap: onTap,
          );
          return Scaffold(
            appBar: AppBar(title: const Text('설정'), centerTitle: false),
            body: SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  section('계정', [
                    tile(
                      Icons.account_circle_outlined,
                      '로그인 계정',
                      subtitle: accountLabel,
                    ),
                    const Divider(height: 1, indent: 60),
                    tile(
                      Icons.logout,
                      '로그아웃',
                      destructive: true,
                      onTap: () => _confirmLogout(context),
                    ),
                  ]),
                  if (onBackup != null || onRestore != null)
                    section('데이터 관리', [
                      if (onBackup != null)
                        tile(
                          Icons.backup_outlined,
                          '데이터 백업하기',
                          subtitle: '일정을 ICS 및 CSV 파일로 저장',
                          onTap: () => _confirmBackup(context),
                        ),
                      if (onRestore != null)
                        tile(
                          Icons.restore,
                          '데이터 복원하기',
                          subtitle: '백업 파일에서 일정과 설정 복원',
                          onTap: () => _confirmRestore(context),
                        ),
                    ]),
                  section('법률 정보 및 이용 약관', [
                    tile(
                      Icons.description_outlined,
                      '이용약관',
                      onTap: () => _showInfo(
                        context,
                        '이용약관',
                        '캘린더 서비스 이용에 관한 약관입니다. 서비스 이용 전 내용을 확인해 주세요.',
                      ),
                    ),
                    tile(
                      Icons.privacy_tip_outlined,
                      '개인정보 처리방침',
                      onTap: () => _showInfo(
                        context,
                        '개인정보 처리방침',
                        '서비스 제공에 필요한 정보만 처리하며, 개인정보 보호 관련 내용을 안내합니다.',
                      ),
                    ),
                  ]),
                  section('프로그램 정보', [
                    tile(
                      Icons.calendar_month_outlined,
                      '캘린더',
                      subtitle: '0.1.0 베타',
                    ),
                  ]),
                  section('안내', [
                    tile(
                      Icons.notifications_outlined,
                      '공시사항',
                      onTap: () =>
                          _showInfo(context, '공시사항', '현재 등록된 공시사항이 없습니다.'),
                    ),
                    tile(
                      Icons.support_agent,
                      '고객센터',
                      onTap: () => _showInfo(
                        context,
                        '고객센터',
                        '문의 사항은 고객센터를 통해 접수해 주세요.',
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool?> _dialog(
    BuildContext context,
    String title,
    String message, {
    String action = '확인',
    bool confirm = false,
    bool destructive = false,
  }) {
    if (_isAndroid) {
      return showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            if (confirm)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('취소'),
              ),
            TextButton(
              style: destructive
                  ? TextButton.styleFrom(
                      foregroundColor: Theme.of(dialogContext)
                          .colorScheme
                          .error,
                    )
                  : null,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(action),
            ),
          ],
        ),
      );
    }
    return showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          if (confirm)
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            isDefaultAction: confirm && !destructive,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  Future<void> _showInfo(
    BuildContext context,
    String title,
    String message,
  ) async {
    await _dialog(context, title, message);
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await _dialog(
      context,
      '로그아웃',
      '이 계정에서 로그아웃할까요?',
      action: '로그아웃',
      confirm: true,
      destructive: true,
    );
    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop();
      onLogout();
    }
  }

  Future<void> _confirmRestore(BuildContext context) async {
    final confirmed = await _dialog(
      context,
      '데이터 복원',
      '현재 일정과 표시 설정이 백업 파일 내용으로 바뀝니다.',
      action: '복원',
      confirm: true,
      destructive: true,
    );
    if (confirmed == true) await onRestore?.call();
  }

  Future<void> _confirmBackup(BuildContext context) async {
    final confirmed = await _dialog(
      context,
      '데이터 백업',
      '일정을 .ics와 .csv 파일로 백업할까요?',
      action: '백업',
      confirm: true,
      destructive: false,
    );
    if (confirmed != true || onBackup == null || !context.mounted) return;

    final progress = ValueNotifier<double>(0);
    unawaited(
      (_isAndroid ? showDialog<void> : showCupertinoDialog<void>)(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, value, _) {
              final content = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  if (_isAndroid)
                    LinearProgressIndicator(value: value)
                  else
                    CupertinoActivityIndicator.partiallyRevealed(
                      progress: value,
                    ),
                  const SizedBox(height: 16),
                  Text('${(value * 100).round()}% 완료'),
                ],
              );
              return _isAndroid
                  ? AlertDialog(title: const Text('백업 중'), content: content)
                  : CupertinoAlertDialog(
                      title: const Text('백업 중'),
                      content: content,
                    );
            },
          ),
        ),
      ),
    );
    List<String>? files;
    try {
      await WidgetsBinding.instance.endOfFrame;
      files = await onBackup!((value) => progress.value = value);
    } catch (_) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      progress.dispose();
      if (context.mounted) {
        await _showInfo(context, '백업 실패', '백업 파일을 만들지 못했습니다. 다시 시도해 주세요.');
      }
      return;
    }
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
    if (!context.mounted) return;
    try {
      final saved = await BackupService.saveExportedFiles(files);
      if (saved && context.mounted) {
        await _showInfo(context, '백업 완료', '.ics 및 .csv 파일을 선택한 위치에 저장했습니다.');
      }
    } catch (_) {
      if (context.mounted) {
        await _showInfo(context, '저장 실패', '파일 저장 창을 열지 못했습니다. 다시 시도해 주세요.');
      }
    }
  }

  Widget _icon(IconData icon, Color color) => Container(
    width: 29,
    height: 29,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Icon(icon, color: CupertinoColors.white, size: 17),
  );
}
