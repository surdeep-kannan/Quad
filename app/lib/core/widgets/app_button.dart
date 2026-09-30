import 'package:material_ui/material_ui.dart';

import '../utils/context_x.dart';

enum ButtonVariant { primary, accent, secondary, outline, ghost, danger }

enum ButtonSize { small, medium, large }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.variant = ButtonVariant.primary,
    this.size = ButtonSize.large,
    this.loading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final ButtonVariant variant;
  final ButtonSize size;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (Color bg, Color fg, BorderSide side) = switch (variant) {
      ButtonVariant.primary => (c.ink, c.inkInverse, BorderSide.none),
      ButtonVariant.accent => (c.accent, c.onAccent, BorderSide.none),
      ButtonVariant.secondary => (c.surfaceMuted, c.ink, BorderSide.none),
      ButtonVariant.outline => (Colors.transparent, c.ink, BorderSide(color: c.lineStrong)),
      ButtonVariant.ghost => (Colors.transparent, c.ink, BorderSide.none),
      ButtonVariant.danger => (c.dangerSoft, c.danger, BorderSide.none),
    };
    final (double height, double padding, double iconSize, TextStyle style) = switch (size) {
      ButtonSize.small => (34.0, 14.0, 16.0, context.text.labelMedium!),
      ButtonSize.medium => (42.0, 18.0, 18.0, context.text.labelLarge!.copyWith(fontSize: 14)),
      ButtonSize.large => (52.0, 22.0, 20.0, context.text.labelLarge!),
    };
    final enabled = onPressed != null && !loading;

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox.square(
            dimension: iconSize - 2,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icon != null)
          Icon(icon, size: iconSize, color: fg),
        if (loading || icon != null) SizedBox(width: size == ButtonSize.small ? 6 : 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(color: fg),
          ),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: 6),
          Icon(trailingIcon, size: iconSize, color: fg),
        ],
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: onPressed == null ? 0.4 : 1,
        child: Material(
          color: bg,
          shape: StadiumBorder(side: side),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            splashColor: fg.withValues(alpha: 0.12),
            highlightColor: fg.withValues(alpha: 0.06),
            child: Container(
              height: height,
              padding: EdgeInsets.symmetric(horizontal: padding),
              alignment: Alignment.center,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// Text-only link button, e.g. "Forgot password?".
class LinkButton extends StatelessWidget {
  const LinkButton({super.key, required this.label, required this.onPressed, this.color});

  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: color ?? context.colors.ink,
      ),
      child: Text(label),
    );
  }
}
