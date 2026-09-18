import 'dart:async';

import 'package:flutter/cupertino.dart';

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

  Future<void> _showInfo(BuildContext context, String title, String message) =>
      showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('로그아웃'),
        content: const Text('이 계정에서 로그아웃할까요?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop();
      onLogout();
    }
  }

  Future<void> _confirmRestore(BuildContext context) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('데이터 복원'),
        content: const Text('현재 일정과 표시 설정이 백업 파일 내용으로 바뀝니다.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('복원'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onRestore?.call();
  }

  Future<void> _confirmBackup(BuildContext context) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('데이터 백업'),
        content: const Text('일정을 .ics와 .csv 파일로 백업할까요?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('백업'),
          ),
        ],
      ),
    );
    if (confirmed != true || onBackup == null || !context.mounted) return;

    final progress = ValueNotifier<double>(0);
    unawaited(
      showCupertinoDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, value, _) => CupertinoAlertDialog(
            title: const Text('백업 중'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                CupertinoActivityIndicator.partiallyRevealed(progress: value),
                const SizedBox(height: 12),
                Text('${(value * 100).round()}% 완료'),
              ],
            ),
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
