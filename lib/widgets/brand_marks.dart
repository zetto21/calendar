import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Port of components/LoginScreen.tsx's PROVIDERS table + BrandMarks.tsx.
/// Unmodified PNGs from each provider's own logo pack (assets/login/).
class SocialProviderSpec {
  final SocialProvider id;
  final String label;
  final Color background;
  final Color? border;
  final WidgetBuilder mark;
  const SocialProviderSpec({
    required this.id,
    required this.label,
    required this.background,
    this.border,
    required this.mark,
  });
}

final List<SocialProviderSpec> socialProviders = [
  SocialProviderSpec(
    id: SocialProvider.naver,
    label: '네이버',
    background: const Color(0xFF03A94D),
    mark: (context) =>
        Image.asset('assets/login/naver-icon.png', width: 44, height: 44),
  ),
  SocialProviderSpec(
    id: SocialProvider.kakao,
    label: '카카오',
    background: const Color(0xFFFEE500),
    // The supplied official asset is a wide sign-in button. Crop its speech
    // bubble at its native aspect ratio instead of squeezing the whole button
    // into the circular SNS control.
    mark: (context) => ClipRect(
      child: SizedBox(
        width: 38,
        height: 38,
        child: OverflowBox(
          maxWidth: 253,
          maxHeight: 38,
          alignment: Alignment.centerLeft,
          child: Image.asset('assets/login/kakao-button.png', height: 38),
        ),
      ),
    ),
  ),
  SocialProviderSpec(
    id: SocialProvider.google,
    label: 'Google',
    background: Colors.white,
    border: const Color(0xFF747775),
    mark: (context) => Image.asset(
      'assets/login/google-g.png',
      width: 20,
      height: 20,
      fit: BoxFit.contain,
    ),
  ),
  SocialProviderSpec(
    id: SocialProvider.apple,
    label: 'Apple',
    background: Colors.black,
    mark: (context) => const Icon(Icons.apple, color: Colors.white, size: 28),
  ),
  SocialProviderSpec(
    id: SocialProvider.microsoft,
    label: 'Microsoft',
    background: Colors.white,
    border: const Color(0xFF747775),
    mark: (context) => const MicrosoftMark(),
  ),
  SocialProviderSpec(
    id: SocialProvider.facebook,
    label: 'Facebook',
    background: const Color(0xFF0866FF),
    mark: (context) => Image.asset(
      'assets/login/facebook-white.png',
      width: 22,
      height: 22,
      fit: BoxFit.contain,
    ),
  ),
];

/// Microsoft's four-color symbol, drawn sharply at desktop display scales.
class MicrosoftMark extends StatelessWidget {
  const MicrosoftMark({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 22,
    child: Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: ColoredBox(color: Color(0xFFF25022))),
              SizedBox(width: 2),
              Expanded(child: ColoredBox(color: Color(0xFF7FBA00))),
            ],
          ),
        ),
        SizedBox(height: 2),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: ColoredBox(color: Color(0xFF00A4EF))),
              SizedBox(width: 2),
              Expanded(child: ColoredBox(color: Color(0xFFFFB900))),
            ],
          ),
        ),
      ],
    ),
  );
}
