import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../native/live_activity.dart';
import '../theme/app_theme.dart';

/// A three-step, first-run walkthrough shown once per account: connecting
/// external calendars, enabling notifications/live status, and a quick tour
/// of the main screen layout.
class OnboardingGuide extends StatefulWidget {
  const OnboardingGuide({
    super.key,
    required this.theme,
    required this.onManageCalendars,
    required this.onOpenSettings,
    required this.onFinish,
  });

  final AppTheme theme;
  final VoidCallback onManageCalendars;
  final VoidCallback onOpenSettings;
  final VoidCallback onFinish;

  @override
  State<OnboardingGuide> createState() => _OnboardingGuideState();
}

class _OnboardingGuideState extends State<OnboardingGuide> {
  static const _pageCount = 3;
  final _controller = PageController();
  int _page = 0;

  void _next() {
    if (_page == _pageCount - 1) {
      widget.onFinish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() {
    _controller.previousPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  String get _liveActivityDescription {
    if (LiveActivity.isIOS) {
      return '진행 중인 일정을 잠금 화면과 다이나믹 아일랜드에서 실시간으로 확인할 수 있어요. 알림을 허용하면 바로 시작할 수 있습니다.';
    }
    if (LiveActivity.isAndroid) {
      return '오늘의 진행 중인 일정과 다음 일정을 자동으로 표시해요. 알림 권한을 허용하면 알림창과 지원 기기의 Now Bar에서 확인할 수 있습니다.';
    }
    if (LiveActivity.isMacOS) {
      return '진행 중인 일정을 메뉴 막대에서 실시간으로 확인할 수 있어요. 설정의 "실시간 현황"에서 원하는 일정을 선택해 보세요.';
    }
    return '일정 알림을 허용하면 중요한 일정을 놓치지 않을 수 있어요.';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                Text(
                  '시작하기 가이드',
                  style: TextStyle(
                    color: theme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (_page < _pageCount - 1)
                  TextButton(
                    onPressed: widget.onFinish,
                    child: const Text('건너뛰기'),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 420,
            child: PageView(
              controller: _controller,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (page) => setState(() => _page = page),
              children: [
                _OnboardingPage(
                  theme: theme,
                  icon: CupertinoIcons.link,
                  color: CupertinoColors.systemBlue,
                  title: '캘린더를 연동하세요',
                  description: '구글, 네이버 등 다른 캘린더의 일정을 가져와 이 앱에서 한눈에 볼 수 있어요. 설정에서 언제든 추가하거나 해제할 수 있습니다.',
                  actionLabel: '지금 연동하기',
                  onAction: widget.onManageCalendars,
                ),
                _OnboardingPage(
                  theme: theme,
                  icon: CupertinoIcons.bolt_fill,
                  color: CupertinoColors.systemOrange,
                  title: '알림 & 실시간 현황',
                  description: _liveActivityDescription,
                  actionLabel: '설정에서 확인하기',
                  onAction: widget.onOpenSettings,
                ),
                _OnboardingPage(
                  theme: theme,
                  icon: CupertinoIcons.square_grid_2x2,
                  color: CupertinoColors.systemGreen,
                  title: '기본 화면 둘러보기',
                  description: '월간·주간 보기를 오가며 일정을 확인하고, 사이드바에서 캘린더 전환과 설정, 검색에 빠르게 접근할 수 있어요.',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                for (var i = 0; i < _pageCount; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _page ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _page ? theme.accent : theme.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                const Spacer(),
                if (_page > 0) ...[
                  TextButton(onPressed: _back, child: const Text('이전')),
                  const SizedBox(width: 4),
                ],
                FilledButton(
                  onPressed: _next,
                  child: Text(_page == _pageCount - 1 ? '시작하기' : '다음'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.theme,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final AppTheme theme;
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 34),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.text,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
