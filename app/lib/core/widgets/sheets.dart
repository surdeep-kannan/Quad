import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../utils/context_x.dart';
import 'app_button.dart';
import 'app_icons.dart';

/// Opens a bottom sheet with the app's shape, drag handle and safe area.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool expand = false,
  bool useRootNavigator = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: useRootNavigator,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * (expand ? 0.92 : 0.86)),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: builder(context),
    ),
  );
}

class SheetAction {
  const SheetAction({required this.icon, required this.label, required this.onTap, this.destructive = false, this.subtitle});

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;
}

/// A list of actions in a bottom sheet (the "..." menu everywhere).
Future<void> showActionSheet(BuildContext context, {String? title, required List<SheetAction> actions}) {
  return showAppSheet<void>(
    context,
    builder: (sheetContext) {
      final c = sheetContext.colors;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
                  child: Text(title, style: sheetContext.text.titleMedium),
                ),
              for (final action in actions)
                ListTile(
                  leading: Icon(action.icon, color: action.destructive ? c.danger : c.ink, size: 22),
                  title: Text(
                    action.label,
                    style: sheetContext.text.titleSmall!.copyWith(
                      fontSize: 15,
                      color: action.destructive ? c.danger : c.ink,
                    ),
                  ),
                  subtitle: action.subtitle == null ? null : Text(action.subtitle!),
                  contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
                  minLeadingWidth: 28,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    HapticFeedback.selectionClick();
                    action.onTap();
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Asks before destructive or irreversible actions.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.medium,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        AppButton(
          label: confirmLabel,
          variant: destructive ? ButtonVariant.danger : ButtonVariant.primary,
          size: ButtonSize.medium,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Short confirmation or error message at the bottom of the screen.
void showToast(BuildContext context, String message, {bool error = false, IconData? icon}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final c = context.colors;
  final fg = context.isDark ? c.ink : c.inkInverse;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: Duration(milliseconds: error ? 3800 : 2400),
        content: Row(
          children: [
            if (icon != null || error) ...[
              Icon(icon ?? AppIcons.warning, size: 18, color: error ? c.danger : fg),
              const SizedBox(width: 10),
            ],
            Expanded(child: Text(message, style: context.text.bodyMedium!.copyWith(color: fg))),
          ],
        ),
      ),
    );
}
