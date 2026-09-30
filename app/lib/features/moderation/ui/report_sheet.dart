import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/sheets.dart';
import '../data/moderation_repository.dart';

/// Reports a post, comment, message, event, community or person.
Future<void> showReportSheet(BuildContext context, {required String targetType, required String targetId, required String what}) {
  return showAppSheet<void>(context, builder: (_) => _ReportSheet(targetType: targetType, targetId: targetId, what: what));
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.targetType, required this.targetId, required this.what});

  final String targetType;
  final String targetId;
  final String what;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  ReportReason? _reason;
  final _details = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref.read(moderationRepositoryProvider).report(
            targetType: widget.targetType,
            targetId: widget.targetId,
            reason: _reason!,
            details: _details.text.trim().isEmpty ? null : _details.text.trim(),
          );
      if (mounted) {
        Navigator.of(context).pop();
        showToast(context, 'Thanks. Moderators will review it.', icon: AppIcons.shield);
      }
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Report ${widget.what}', style: context.text.headlineSmall),
          const SizedBox(height: 4),
          Text('Reports are anonymous. If someone is in danger, contact local emergency services.', style: context.text.bodySmall),
          const SizedBox(height: Space.lg),
          for (final reason in ReportReason.values)
            RadioListTile<ReportReason>(
              value: reason,
              // ignore: deprecated_member_use
              groupValue: _reason,
              // ignore: deprecated_member_use
              onChanged: (value) => setState(() => _reason = value),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(reason.label, style: context.text.titleSmall),
              subtitle: reason.hint.isEmpty ? null : Text(reason.hint, style: context.text.bodySmall),
              activeColor: c.ink,
            ),
          const SizedBox(height: Space.md),
          AppTextField(
            label: 'Anything else? (optional)',
            controller: _details,
            maxLines: 3,
            maxLength: 1000,
          ),
          const SizedBox(height: Space.xl),
          AppButton(
            label: 'Submit report',
            variant: ButtonVariant.primary,
            expand: true,
            loading: _busy,
            onPressed: _reason == null ? null : _submit,
          ),
        ],
      ),
    );
  }
}
