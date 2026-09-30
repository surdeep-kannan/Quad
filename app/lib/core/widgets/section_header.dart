import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../utils/context_x.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.sm, Space.sm),
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: context.text.bodySmall),
                ],
              ],
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: context.colors.inkMuted,
                textStyle: context.text.labelMedium,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// Large screen title used at the top of each tab.
class TabHeader extends StatelessWidget {
  const TabHeader({super.key, required this.title, this.actions = const [], this.leading, this.bottom});

  final String title;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: context.safePadding.top),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: Space.gutter),
                if (leading != null) ...[leading!, const SizedBox(width: 10)],
                Expanded(child: Text(title, style: context.text.displaySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ...actions,
                const SizedBox(width: 6),
              ],
            ),
          ),
          ?bottom,
        ],
      ),
    );
  }
}
