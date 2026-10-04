import 'dart:math' as math;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/avatars.dart';
import '../../chat/ui/stickers.dart';
import '../../communities/ui/roles.dart';
import 'brand.dart';

/// What each story slide says. The art for slide i is [_SlideArt] i.
const _slides = <({String title, String body})>[
  (
    title: 'Your campus,\nall in one place.',
    body: 'Join communities, find events, chat with friends and share what you\'re building.',
  ),
  (
    title: 'Find your\npeople.',
    body: 'Clubs, departments, hackathons and hobbies. Join them, post, and help run them.',
  ),
  (title: 'Never miss\nwhat\'s on.', body: 'Register in a tap, get a reminder before it starts, and see who\'s going.'),
  (title: 'Talk, call,\nhang out.', body: 'Chat with stickers, and drop into a room\'s voice or video call any time.'),
  (title: 'Watch, share,\ncompare.', body: 'Short reels from students, and college rankings built from real activity.'),
  (title: 'Be yourself,\nor anonymous.', body: 'Go private and your community posts and comments carry a random name.'),
];

/// First screen for signed-out visitors: a short story of what Quad does,
/// built from real UI pieces, above the sign-up buttons. Slides advance on
/// their own; tap the right or left side to skip, hold to pause.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  static const _slideLength = Duration(milliseconds: 5200);

  late final AnimationController _progress = AnimationController(vsync: this, duration: _slideLength)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) _go(_index + 1);
    })
    ..forward();
  int _index = 0;

  void _go(int index) {
    setState(() => _index = index % _slides.length);
    _progress.forward(from: 0);
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final slide = _slides[_index];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Space.md),
              _StoryBars(count: _slides.length, index: _index, progress: _progress),
              const SizedBox(height: Space.md),
              const Align(alignment: Alignment.centerLeft, child: Wordmark(size: 28)),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) => _go(details.localPosition.dx < box.maxWidth / 3 ? _index - 1 : _index + 1),
                    onLongPressStart: (_) => _progress.stop(),
                    onLongPressEnd: (_) => _progress.forward(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 350),
                            child: _SlideArt(key: ValueKey(_index), index: _index),
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(animation),
                              child: child,
                            ),
                          ),
                          child: Column(
                            key: ValueKey(_index),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(slide.title, style: context.text.displayMedium),
                              const SizedBox(height: Space.md),
                              Text(slide.body, style: context.text.bodyLarge!.copyWith(color: c.inkMuted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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

/// Instagram-style progress bars: done, filling, waiting.
class _StoryBars extends StatelessWidget {
  const _StoryBars({required this.count, required this.index, required this.progress});

  final int count;
  final int index;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Story ${index + 1} of $count',
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, _) => Row(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: i < index ? 1 : (i == index ? progress.value : 0),
                    minHeight: 3,
                    backgroundColor: c.line,
                    color: c.ink,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The illustration for one slide: a few real UI pieces that float in.
class _SlideArt extends StatefulWidget {
  const _SlideArt({super.key, required this.index});

  final int index;

  @override
  State<_SlideArt> createState() => _SlideArtState();
}

class _SlideArtState extends State<_SlideArt> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..forward();

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Widget _stagger(int order, Widget child, {double rotation = 0}) {
    final start = (order * 0.14).clamp(0.0, 0.6);
    final animation = CurvedAnimation(
      parent: _intro,
      curve: Interval(start, start + 0.45, curve: Curves.easeOutBack),
    );
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
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        // Each piece: (left, top, width) as fractions, plus tilt and widget.
        final pieces = switch (widget.index) {
          0 => [
            (0.0, 0.08, 0.74, -5.0, const _TicketCard() as Widget),
            (0.34, 0.36, 0.66, 4.0, const _CommunityCard(name: 'ML & AI', members: '1.2k members', color: 8)),
            (0.04, 0.6, 0.62, -2.0, const _ChatCard()),
            (0.72, 0.02, null, 8.0, _Pill(color: c.accent, label: 'live')),
          ],
          1 => [
            (0.0, 0.06, 0.8, -3.0, const _CommunityCard(name: 'Coding Club', members: '860 members', color: 7)),
            (0.18, 0.32, 0.8, 2.0, const _CommunityCard(name: 'Shutterbugs', members: '412 members', color: 10)),
            (0.04, 0.58, 0.78, -2.0, const _RolesCard()),
          ],
          2 => [
            (0.04, 0.08, 0.86, -4.0, const _TicketCard()),
            (0.36, 0.42, 0.6, 3.0, const _ReminderCard()),
            (0.0, 0.66, null, -6.0, _Pill(color: Palette.at(4), label: 'going ✓')),
          ],
          3 => [(0.0, 0.04, 0.7, -3.0, const _StickerChatCard()), (0.3, 0.5, 0.7, 3.0, const _VoiceCard())],
          4 => [
            (0.04, 0.02, 0.44, -4.0, const _ReelCard()),
            (0.46, 0.3, 0.54, 4.0, const _RankCard()),
            (0.5, 0.06, null, 6.0, _Pill(color: c.accent, label: '2.4k views')),
          ],
          _ => [(0.0, 0.08, 0.84, -3.0, const _PrivacyCard()), (0.12, 0.44, 0.84, 2.0, const _AnonCommentCard())],
        };
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < pieces.length; i++)
              Positioned(
                left: w * pieces[i].$1,
                top: h * pieces[i].$2,
                width: pieces[i].$3 == null ? null : w * pieces[i].$3!,
                child: _stagger(i, pieces[i].$5, rotation: pieces[i].$4),
              ),
          ],
        );
      },
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
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.07),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
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
                const Text(
                  '12',
                  style: TextStyle(
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
  const _CommunityCard({required this.name, required this.members, required this.color});

  final String name;
  final String members;
  final int color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _CardShell(
      child: Row(
        children: [
          CommunityAvatar(name: name, color: color, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: context.text.titleSmall, maxLines: 1),
                Text(members, style: context.text.bodySmall, maxLines: 1),
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

class _RolesCard extends StatelessWidget {
  const _RolesCard();

  @override
  Widget build(BuildContext context) {
    Widget row(String name, String role, Color color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          UserAvatar(name: name, size: 28),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: context.text.labelLarge, maxLines: 1)),
          RoleChip(name: role, color: color),
        ],
      ),
    );
    return _CardShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [row('Diya Nair', 'Moderator', Palette.at(4)), row('Kabir Singh', 'Event team', Palette.at(1))],
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _CardShell(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
            child: Icon(AppIcons.clock, size: 18, color: c.accentInk),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Starts in 1 hour', style: context.text.titleSmall),
                Text('Hack Night 3.0', style: context.text.bodySmall, maxLines: 1),
              ],
            ),
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
          const _Bubble('anyone up for a 2am build?', mine: false),
          const _Bubble('count me in 🙌', mine: true),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.text, {required this.mine});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: mine ? c.ink : c.surfaceMuted, borderRadius: BorderRadius.circular(16)),
        child: Text(text, style: context.text.bodySmall!.copyWith(color: mine ? c.inkInverse : c.ink)),
      ),
    );
  }
}

class _StickerChatCard extends StatelessWidget {
  const _StickerChatCard();

  @override
  Widget build(BuildContext context) {
    return const _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Bubble('submitted the project 😮‍💨', mine: false),
          Align(
            alignment: Alignment.centerRight,
            child: StickerView(id: 'campus/ship-it', size: 86, animate: false),
          ),
        ],
      ),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  const _VoiceCard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget person(String name, {bool speaking = false}) => Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: speaking ? c.online : Colors.transparent, width: 2.5),
      ),
      child: UserAvatar(name: name, size: 34),
    );
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(AppIcons.waveform, size: 16, color: c.online),
              const SizedBox(width: 6),
              Text('#study-room · 4 in voice', style: context.text.labelMedium),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: [
              person('Meera Iyer', speaking: true),
              person('Aarav Mehta'),
              person('Rohan Das'),
              person('Ananya Rao'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReelCard extends StatelessWidget {
  const _ReelCard();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.lg + 2),
          gradient: LinearGradient(
            colors: [Palette.at(8), Palette.at(10)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 24, offset: const Offset(0, 10)),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Spacer(),
            Center(child: Icon(AppIcons.play, color: Colors.white, size: 40)),
            Spacer(),
            Row(
              children: [
                Icon(AppIcons.heartFill, color: Colors.white, size: 14),
                SizedBox(width: 4),
                Text(
                  '1.8k',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              'robotics club demo day 🤖',
              maxLines: 2,
              style: TextStyle(color: Colors.white, fontSize: 12, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  const _RankCard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget row(String rank, String name, String score, {bool top = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(rank, style: context.text.titleSmall!.copyWith(color: top ? c.accentInk : c.inkMuted)),
          ),
          Expanded(child: Text(name, style: context.text.labelLarge, maxLines: 1)),
          Text(score, style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
        ],
      ),
    );
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(AppIcons.ranking, size: 16, color: c.inkMuted),
              const SizedBox(width: 6),
              Text('Most active', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
            ],
          ),
          const SizedBox(height: 6),
          row('1', 'IIT Madras', '92', top: true),
          row('2', 'NIT Trichy', '88'),
          row('3', 'BITS Pilani', '85'),
        ],
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _CardShell(
      child: Row(
        children: [
          Icon(AppIcons.lock, color: c.ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Private profile', style: context.text.titleSmall),
                Text('Only people you follow see your profile', style: context.text.bodySmall, maxLines: 2),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 44,
            height: 26,
            padding: const EdgeInsets.all(3),
            alignment: Alignment.centerRight,
            decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(13)),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: c.inkInverse, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnonCommentCard extends StatelessWidget {
  const _AnonCommentCard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _CardShell(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AnonymousAvatar(alias: 'anonymous_quiet_otter_421', size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'anonymous_quiet_otter_421',
                  style: context.text.labelLarge!.copyWith(color: c.inkMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text('honestly the placement prep sessions helped a lot', style: context.text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.label});

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
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label.toUpperCase(), style: context.text.labelSmall!.copyWith(color: Colors.white, letterSpacing: 1)),
        ],
      ),
    );
  }
}
