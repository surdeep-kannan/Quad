import 'package:material_ui/material_ui.dart';

import '../utils/context_x.dart';
import '../utils/errors.dart';
import 'app_button.dart';
import 'app_icons.dart';

export 'skeleton.dart';

/// Shown when a list has nothing in it yet. Always says what to do next.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32, vertical: compact ? 24 : 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 52 : 64,
                height: compact ? 52 : 64,
                decoration: BoxDecoration(color: c.surfaceMuted, shape: BoxShape.circle),
                child: Icon(icon, size: compact ? 24 : 28, color: c.inkMuted),
              ),
              SizedBox(height: compact ? 12 : 16),
              Text(title, textAlign: TextAlign.center, style: context.text.titleMedium),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(message!, textAlign: TextAlign.center, style: context.text.bodySmall!.copyWith(height: 1.45)),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                AppButton(label: actionLabel!, onPressed: onAction, size: ButtonSize.medium),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry, this.compact = false});

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final message = friendlyError(error);
    final offline = message.contains('offline');
    return EmptyState(
      icon: offline ? AppIcons.wifiOff : AppIcons.warning,
      title: offline ? 'No connection' : 'Couldn\'t load this',
      message: message,
      actionLabel: onRetry == null ? null : 'Try again',
      onAction: onRetry,
      compact: compact,
    );
  }
}

class CenteredLoader extends StatelessWidget {
  const CenteredLoader({super.key, this.padding = 32});

  final double padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(padding),
      child: const Center(
        child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.2)),
      ),
    );
  }
}
