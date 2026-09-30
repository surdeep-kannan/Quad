import 'package:material_ui/material_ui.dart';

import '../utils/context_x.dart';
import 'app_icons.dart';

/// Unread count bubble. Hidden when [count] is zero.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.muted = false});

  final int count;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: muted ? c.inkSubtle : c.accent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: c.background, width: 1.5),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: context.text.labelSmall!.copyWith(color: c.onAccent, fontSize: 10.5, fontWeight: FontWeight.w700, height: 1),
      ),
    );
  }
}

/// A small dot for "something new".
class DotBadge extends StatelessWidget {
  const DotBadge({super.key, this.size = 9});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle, border: Border.all(color: c.background, width: 1.5)),
    );
  }
}

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 15});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Verified student',
      child: Icon(AppIcons.verified, size: size, color: context.colors.accent, semanticLabel: 'Verified'),
    );
  }
}

/// Name followed by a verified seal when applicable, ellipsized as one unit.
class NameLine extends StatelessWidget {
  const NameLine({super.key, required this.name, this.verified = false, this.style, this.maxLines = 1});

  final String name;
  final bool verified;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final textStyle = style ?? context.text.titleSmall;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(name, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: textStyle)),
        if (verified) ...[
          const SizedBox(width: 4),
          VerifiedBadge(size: (textStyle?.fontSize ?? 14) + 1),
        ],
      ],
    );
  }
}

/// Staff role marker in member lists and comments.
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (label, fg, bg) = switch (role) {
      'owner' => ('Owner', c.accentInk, c.accentSoft),
      'admin' => ('Admin', c.accentInk, c.accentSoft),
      'moderator' => ('Mod', c.success, c.successSoft),
      _ => ('', c.inkMuted, c.surfaceMuted),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(label, style: context.text.labelSmall!.copyWith(color: fg, fontSize: 10.5)),
    );
  }
}
