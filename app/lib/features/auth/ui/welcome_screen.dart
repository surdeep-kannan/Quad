import 'dart:math' as math;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/avatars.dart';
import 'brand.dart';

/// First screen for signed-out visitors. The collage is built from real UI
/// pieces (an event ticket, a community, a chat and a poll) so it shows what
/// the app does instead of a stock illustration.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..forward();

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Widget _stagger(int index, Widget child, {double rotation = 0}) {
    final start = (index * 0.12).clamp(0.0, 0.6);
    final animation = CurvedAnimation(parent: _intro, curve: Interval(start, start + 0.45, curve: Curves.easeOutBack));
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - animation.value)),
          child: Transform.rotate(angle: rotation * math.pi / 180, child: child),
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Space.md),
              const Align(alignment: Alignment.centerLeft, child: Wordmark(size: 28)),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final w = box.maxWidth;
                    final h = box.maxHeight;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          top: h * 0.08,
                          width: w * 0.74,
                          child: _stagger(0, const _TicketCard(), rotation: -5),
                        ),
                        Positioned(
                          right: 0,
                          top: h * 0.34,
                          width: w * 0.66,
                          child: _stagger(1, const _CommunityCard(), rotation: 4),
                        ),
                        Positioned(
                          left: w * 0.04,
                          top: h * 0.58,
                          width: w * 0.62,
                          child: _stagger(2, const _ChatCard(), rotation: -2),
                        ),
                        Positioned(
                          right: w * 0.02,
                          top: h * 0.03,
                          child: _stagger(3, _Sticker(color: c.accent, label: 'live'), rotation: 8),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Text('Your campus,\nall in one place.', style: context.text.displayMedium),
              const SizedBox(height: Space.md),
              Text(
                'Join communities, find events, chat with friends and share what you\'re building.',
                style: context.text.bodyLarge!.copyWith(color: c.inkMuted),
              ),
              const SizedBox(height: Space.xxl),
              AppButton(label: 'Create account', expand: true, onPressed: () => context.push('/sign-up')),
              const SizedBox(height: Space.sm + 2),
              AppButton(
                label: 'I already have an account',
                variant: ButtonVariant.ghost,
                expand: true,
                onPressed: () => context.push('/sign-in'),
              ),
              const SizedBox(height: Space.md),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg + 2),
        border: Border.all(color: c.line),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.07), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: child,
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _CardShell(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Container(
            width: 64,
            height: 84,
            decoration: BoxDecoration(
              color: Palette.at(0),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(Radii.lg + 2)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('SAT', style: context.text.labelSmall!.copyWith(color: Colors.white70)),
                Text(
                  '12',
                  style: const TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.05,
                  ),
                ),
                Text('OCT', style: context.text.labelSmall!.copyWith(color: Colors.white)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hack Night 3.0', style: context.text.titleMedium, maxLines: 1),
                  const SizedBox(height: 3),
                  Text('Coding Club · 8 PM', style: context.text.bodySmall, maxLines: 1),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const AvatarStack(people: [('Aarav M', null), ('Diya N', null), ('Kabir S', null)], size: 20),
                      const SizedBox(width: 6),
                      Text('240 going', style: context.text.labelSmall!.copyWith(color: c.inkMuted)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _CardShell(
      child: Row(
        children: [
          const CommunityAvatar(name: 'ML AI', color: 8, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ML & AI', style: context.text.titleSmall, maxLines: 1),
                Text('1.2k members', style: context.text.bodySmall, maxLines: 1),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(20)),
            child: Text('Join', style: context.text.labelMedium!.copyWith(color: c.inkInverse)),
          ),
        ],
      ),
    );
  }
}

class _ChatCard extends StatelessWidget {
  const _ChatCard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget bubble(String text, {required bool mine}) => Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: mine ? c.ink : c.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(text, style: context.text.bodySmall!.copyWith(color: mine ? c.inkInverse : c.ink)),
          ),
        );
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(AppIcons.hash, size: 14, color: c.inkMuted),
              const SizedBox(width: 4),
              Text('coding-room', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
            ],
          ),
          bubble('anyone up for a 2am build?', mine: false),
          bubble('count me in 🙌', mine: true),
        ],
      ),
    );
  }
}

class _Sticker extends StatelessWidget {
  const _Sticker({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label.toUpperCase(), style: context.text.labelSmall!.copyWith(color: Colors.white, letterSpacing: 1)),
        ],
      ),
    );
  }
}
