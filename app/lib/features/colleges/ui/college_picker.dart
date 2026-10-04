import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/debouncer.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../data/college.dart';
import '../data/college_repository.dart';
import '../providers.dart';

/// Search the college list, pick one (tap it again to clear), or add a
/// missing college. Used in onboarding and when editing your profile.
class CollegePicker extends ConsumerStatefulWidget {
  const CollegePicker({super.key, required this.selectedId, required this.onSelected});

  final String? selectedId;
  final ValueChanged<College?> onSelected;

  @override
  ConsumerState<CollegePicker> createState() => _CollegePickerState();
}

class _CollegePickerState extends ConsumerState<CollegePicker> {
  final _debounce = Debouncer(const Duration(milliseconds: 300));
  String _query = '';

  @override
  void dispose() {
    _debounce.dispose();
    super.dispose();
  }

  Future<void> _addCollege() async {
    final added = await showAppSheet<College>(context, builder: (_) => const AddCollegeSheet());
    if (added != null) widget.onSelected(added);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final results = ref.watch(collegeSearchProvider(_query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchField(hint: 'Search your college', onChanged: (value) => _debounce(() => setState(() => _query = value))),
        const SizedBox(height: Space.md),
        results.when(
          loading: () => const ListSkeleton(count: 4, itemBuilder: _collegeSkeleton),
          error: (error, _) =>
              ErrorState(error: error, compact: true, onRetry: () => ref.invalidate(collegeSearchProvider(_query))),
          data: (colleges) => Column(
            children: [
              for (final college in colleges.take(12))
                _CollegeTile(
                  college: college,
                  selected: widget.selectedId == college.id,
                  onTap: () => widget.onSelected(widget.selectedId == college.id ? null : college),
                ),
              if (colleges.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.lg),
                  child: Text(
                    'No colleges match "$_query".',
                    style: context.text.bodyMedium!.copyWith(color: c.inkMuted),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.sm),
        AppButton(
          label: 'Can\'t find it? Add your college',
          icon: AppIcons.plus,
          variant: ButtonVariant.secondary,
          size: ButtonSize.medium,
          onPressed: _addCollege,
        ),
      ],
    );
  }
}

Widget _collegeSkeleton(int _) => const RowSkeleton(avatarSize: 40, square: true);

class _CollegeTile extends StatelessWidget {
  const _CollegeTile({required this.college, required this.selected, required this.onTap});

  final College college;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? c.accentSoft : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md + 2),
          side: BorderSide(color: selected ? c.accent : c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Row(
              children: [
                CommunityAvatar(name: college.label, color: college.name.length, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(college.name, style: context.text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (college.location.isNotEmpty) Text(college.location, style: context.text.bodySmall),
                    ],
                  ),
                ),
                if (selected) Icon(AppIcons.checkCircle, color: c.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AddCollegeSheet extends ConsumerStatefulWidget {
  const AddCollegeSheet({super.key});

  @override
  ConsumerState<AddCollegeSheet> createState() => _AddCollegeSheetState();
}

class _AddCollegeSheetState extends ConsumerState<AddCollegeSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _state.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final college = await ref
          .read(collegeRepositoryProvider)
          .add(
            name: _name.text,
            city: _city.text.trim().isEmpty ? null : _city.text.trim(),
            state: _state.text.trim().isEmpty ? null : _state.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(college);
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add your college', style: context.text.headlineSmall),
            const SizedBox(height: 4),
            Text('It shows as unverified until our team checks it.', style: context.text.bodySmall),
            const SizedBox(height: Space.xl),
            AppTextField(
              label: 'College name',
              controller: _name,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v?.trim().length ?? 0) < 3 ? 'Enter the full name' : null,
            ),
            const SizedBox(height: Space.lg),
            Row(
              children: [
                Expanded(
                  child: AppTextField(label: 'City', controller: _city, textCapitalization: TextCapitalization.words),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: AppTextField(label: 'State', controller: _state, textCapitalization: TextCapitalization.words),
                ),
              ],
            ),
            const SizedBox(height: Space.xxl),
            AppButton(label: 'Add college', expand: true, loading: _busy, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

/// Opens the picker in a sheet. Returns null if dismissed; otherwise a record
/// whose college is the new choice, or null when the person cleared it.
Future<({College? college})?> pickCollege(BuildContext context, {String? currentId}) {
  return showAppSheet<({College? college})>(
    context,
    expand: true,
    builder: (sheetContext) => ListView(
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
      children: [
        Text('Your college', style: sheetContext.text.headlineSmall),
        const SizedBox(height: 4),
        Text('Tap your college. Tap it again to remove it.', style: sheetContext.text.bodySmall),
        const SizedBox(height: Space.lg),
        CollegePicker(
          selectedId: currentId,
          onSelected: (college) => Navigator.of(sheetContext).pop((college: college)),
        ),
      ],
    ),
  );
}
