import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';

/// A sticker the app knows how to draw. Messages store only [id].
class Sticker {
  const Sticker(this.pack, this.name, this.emoji, {this.label, this.color = 0xFF2E8BFF});

  final String pack;
  final String name;
  final String emoji;

  /// Text on campus stickers; reaction stickers are just a big emoji.
  final String? label;
  final int color;

  String get id => '$pack/$name';
}

class StickerPack {
  const StickerPack(this.id, this.title, this.icon, this.stickers);

  final String id;
  final String title;
  final String icon;
  final List<Sticker> stickers;
}

abstract final class Stickers {
  static const packs = <StickerPack>[
    StickerPack('campus', 'Campus', '🎓', [
      Sticker('campus', 'ship-it', '🚀', label: 'Ship it', color: 0xFF3D5AFE),
      Sticker('campus', 'lgtm', '✅', label: 'LGTM', color: 0xFF17A673),
      Sticker('campus', 'exam-mode', '📚', label: 'Exam mode', color: 0xFFEC4F8B),
      Sticker('campus', 'placement', '💼', label: 'Placement szn', color: 0xFF475467),
      Sticker('campus', 'canteen', '🍟', label: 'Canteen?', color: 0xFFFF9F1C),
      Sticker('campus', 'omw', '🏃', label: 'On my way', color: 0xFF0FA3B1),
      Sticker('campus', 'bunk', '👀', label: 'Bunk?', color: 0xFF7B5CFF),
      Sticker('campus', 'lab-done', '🧪', label: 'Lab done', color: 0xFF6DB33F),
      Sticker('campus', 'hack-mode', '⚡', label: 'Hack mode', color: 0xFFF2B705),
      Sticker('campus', 'proxy', '🙏', label: 'Proxy pls', color: 0xFFC04FDB),
      Sticker('campus', 'deadline', '😭', label: 'Deadline', color: 0xFFFF6B4A),
      Sticker('campus', 'gg', '🎮', label: 'GG', color: 0xFF2E8BFF),
      Sticker('campus', 'goat', '🐐', label: 'Legend', color: 0xFF16151B),
      Sticker('campus', 'no-sleep', '☕', label: 'No sleep', color: 0xFF8D5524),
      Sticker('campus', 'done', '🎉', label: 'Done done', color: 0xFF17A673),
      Sticker('campus', 'help', '🆘', label: 'Help!', color: 0xFFE5383B),
    ]),
    StickerPack('react', 'Reactions', '🔥', [
      Sticker('react', 'lol', '😂'),
      Sticker('react', 'fire', '🔥'),
      Sticker('react', 'dead', '💀'),
      Sticker('react', 'salute', '🫡'),
      Sticker('react', 'eyes', '👀'),
      Sticker('react', 'pray', '🙏'),
      Sticker('react', 'heart', '❤️'),
      Sticker('react', 'cry', '😭'),
      Sticker('react', 'smile-tear', '🥲'),
      Sticker('react', 'deal', '🤝'),
      Sticker('react', 'sparkles', '✨'),
      Sticker('react', 'party', '🥳'),
      Sticker('react', 'mind-blown', '🤯'),
      Sticker('react', 'cool', '😎'),
      Sticker('react', 'think', '🤔'),
      Sticker('react', 'clap', '👏'),
      Sticker('react', 'hundred', '💯'),
      Sticker('react', 'goat', '🐐'),
    ]),
  ];

  static final Map<String, Sticker> _byId = {
    for (final pack in packs)
      for (final sticker in pack.stickers) sticker.id: sticker,
  };

  static Sticker? byId(String? id) => id == null ? null : _byId[id];
}

/// Draws a sticker: campus stickers are die-cut labels with a white edge,
/// reaction stickers a big emoji. Pops in the first time it appears.
class StickerView extends StatelessWidget {
  const StickerView({super.key, required this.id, this.size = 132, this.animate = true});

  final String id;
  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final sticker = Stickers.byId(id);
    Widget child;
    if (sticker == null) {
      child = SizedBox.square(
        dimension: size,
        child: Center(child: Text('Sticker', style: context.text.labelMedium)),
      );
    } else if (sticker.label == null) {
      child = SizedBox.square(
        dimension: size,
        child: Center(
          child: Text(
            sticker.emoji,
            style: TextStyle(
              fontSize: size * 0.72,
              height: 1,
              shadows: const [Shadow(blurRadius: 10, color: Colors.black26)],
            ),
          ),
        ),
      );
    } else {
      child = _LabelSticker(sticker: sticker, size: size);
    }
    if (!animate) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.elasticOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: child,
    );
  }
}

class _LabelSticker extends StatelessWidget {
  const _LabelSticker({required this.sticker, required this.size});

  final Sticker sticker;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(sticker.color);
    // A small, stable tilt per sticker so a row of them doesn't look stamped.
    final tilt = ((sticker.name.hashCode % 7) - 3) * math.pi / 180;
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: Transform.rotate(
          angle: tilt,
          child: Container(
            constraints: BoxConstraints(maxWidth: size),
            padding: EdgeInsets.fromLTRB(size * 0.09, size * 0.07, size * 0.09, size * 0.08),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(size * 0.16),
              border: Border.all(color: Colors.white, width: size * 0.035),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: size * 0.08,
                  offset: Offset(0, size * 0.03),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(sticker.emoji, style: TextStyle(fontSize: size * 0.3, height: 1.1)),
                SizedBox(height: size * 0.02),
                Text(
                  sticker.label!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.13,
                    height: 1.05,
                    letterSpacing: -0.2,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The stickers you used most recently, remembered on this device.
final recentStickersProvider = NotifierProvider<RecentStickers, List<String>>(RecentStickers.new);

class RecentStickers extends Notifier<List<String>> {
  static const _key = 'recent_stickers';

  @override
  List<String> build() {
    SharedPreferences.getInstance()
        .then((prefs) {
          final saved = prefs.getStringList(_key);
          if (saved != null && ref.mounted)
            state = [
              for (final id in saved)
                if (Stickers.byId(id) != null) id,
            ];
        })
        .catchError((_) {});
    return const [];
  }

  void used(String id) {
    state = [id, ...state.where((s) => s != id)].take(16).toList();
    SharedPreferences.getInstance().then((prefs) => prefs.setStringList(_key, state)).catchError((_) => false);
  }
}

/// The sticker keyboard shown under the message box.
class StickerPanel extends ConsumerStatefulWidget {
  const StickerPanel({super.key, required this.onPick});

  final ValueChanged<String> onPick;

  @override
  ConsumerState<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends ConsumerState<StickerPanel> {
  late int _tab = ref.read(recentStickersProvider).isEmpty ? 1 : 0;

  void _pick(String id) {
    HapticFeedback.selectionClick();
    ref.read(recentStickersProvider.notifier).used(id);
    widget.onPick(id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final recent = ref.watch(recentStickersProvider);
    final tabs = <(String, List<String>)>[
      ('🕘', recent),
      for (final pack in Stickers.packs) (pack.icon, [for (final s in pack.stickers) s.id]),
    ];
    final ids = tabs[_tab].$2;
    return Container(
      height: 290,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      onTap: () => setState(() => _tab = i),
                      child: Container(
                        width: 44,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _tab == i ? c.surfaceMuted : null,
                          borderRadius: BorderRadius.circular(Radii.sm),
                        ),
                        child: Text(tabs[i].$1, style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ids.isEmpty
                ? Center(child: Text('Stickers you send show up here', style: context.text.bodySmall))
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 92),
                    itemCount: ids.length,
                    itemBuilder: (_, i) => InkWell(
                      borderRadius: BorderRadius.circular(Radii.md),
                      onTap: () => _pick(ids[i]),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: FittedBox(child: StickerView(id: ids[i], size: 132, animate: false)),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
