import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/media.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/context_x.dart';
import '../../core/utils/debouncer.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/avatars.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../auth/data/auth_repository.dart';
import '../colleges/data/college.dart';
import '../colleges/data/college_repository.dart';
import '../colleges/providers.dart';
import '../profile/data/profile.dart';
import '../profile/data/profile_repository.dart';
import '../profile/providers.dart';

const _departments = [
  'Computer Science', 'Information Technology', 'Electronics', 'Electrical', 'Mechanical', 'Civil',
  'Chemical', 'Data Science', 'AI & ML', 'Biotechnology', 'Design', 'Management', 'Commerce', 'Economics',
  'Physics', 'Mathematics', 'Medicine', 'Law', 'Arts',
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _steps = 5;
  final _page = PageController();
  int _step = 0;
  bool _saving = false;

  final _name = TextEditingController();
  final _username = TextEditingController();
  final _department = TextEditingController();
  final _bio = TextEditingController();
  final _skillInput = TextEditingController();
  final _usernameDebounce = Debouncer(const Duration(milliseconds: 450));

  String? _usernameError;
  bool _usernameChecking = false;
  College? _college;
  int? _year;
  final Set<String> _interests = {};
  final List<String> _skills = [];
  PickedFile? _photo;

  @override
  void initState() {
    super.initState();
    final me = ref.read(myProfileProvider).value;
    _name.text = me?.fullName ?? '';
    _username.text = me?.username ?? '';
  }

  @override
  void dispose() {
    _page.dispose();
    _name.dispose();
    _username.dispose();
    _department.dispose();
    _bio.dispose();
    _skillInput.dispose();
    _usernameDebounce.dispose();
    super.dispose();
  }

  void _checkUsername(String value) {
    final formatError = Validators.username(value);
    setState(() {
      _usernameError = formatError;
      _usernameChecking = formatError == null;
    });
    if (formatError != null) return;
    _usernameDebounce(() async {
      final available = await ref.read(profileRepositoryProvider).isUsernameAvailable(value.trim());
      if (!mounted || _username.text.trim() != value.trim()) return;
      setState(() {
        _usernameChecking = false;
        _usernameError = available ? null : 'That username is taken';
      });
    });
  }

  bool get _canContinue => switch (_step) {
        0 => Validators.name(_name.text) == null && _usernameError == null && !_usernameChecking && _username.text.isNotEmpty,
        1 => true,
        2 => true,
        3 => _interests.length >= 3,
        _ => true,
      };

  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    if (_step < _steps - 1) {
      setState(() => _step++);
      await _page.animateToPage(_step, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
      return;
    }
    await _finish();
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step--);
    _page.animateToPage(_step, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      String? avatarUrl;
      if (_photo != null) avatarUrl = await ref.read(storageRepositoryProvider).uploadAvatar(_photo!);
      await ref.read(myProfileProvider.notifier).save({
        'full_name': _name.text.trim(),
        'username': _username.text.trim(),
        'college_id': _college?.id,
        'department': _department.text.trim().isEmpty ? null : _department.text.trim(),
        'year_of_study': _year,
        'interests': _interests.toList(),
        'skills': _skills,
        'bio': _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        'avatar_url': ?avatarUrl,
        'onboarded': true,
      });
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, Space.lg, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: _step == 0 ? 'Sign out' : 'Back',
                    icon: Icon(_step == 0 ? AppIcons.signOut : AppIcons.back),
                    onPressed: _step == 0 ? () => ref.read(authRepositoryProvider).signOut() : _back,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 0; i < _steps; i++) ...[
                          if (i > 0) const SizedBox(width: 5),
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              height: 4,
                              decoration: BoxDecoration(
                                color: i <= _step ? c.ink : c.surfaceSunken,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _Step(
                    title: 'What should we call you?',
                    subtitle: 'Your name and username are how classmates find you.',
                    child: Column(
                      children: [
                        AppTextField(
                          label: 'Full name',
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Username',
                          controller: _username,
                          prefixIcon: AppIcons.at,
                          onChanged: _checkUsername,
                          suffix: _usernameChecking
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                )
                              : _usernameError == null && _username.text.isNotEmpty
                                  ? Icon(AppIcons.checkCircle, color: c.success, size: 20)
                                  : null,
                          helper: _usernameError ?? 'Lowercase letters, numbers, dots and underscores',
                        ),
                      ],
                    ),
                  ),
                  _Step(
                    title: 'Where do you study?',
                    subtitle: 'We\'ll show you your campus communities and events.',
                    child: _CollegePicker(selected: _college, onSelected: (college) => setState(() => _college = college)),
                  ),
                  _Step(
                    title: 'Your course',
                    subtitle: 'Helps us suggest classmates and department groups.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppTextField(
                          label: 'Department or major',
                          controller: _department,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: Space.md),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final d in _departments.take(10))
                              PillChip(
                                label: d,
                                dense: true,
                                selected: _department.text == d,
                                onTap: () => setState(() => _department.text = d),
                              ),
                          ],
                        ),
                        const SizedBox(height: Space.xxl),
                        Text('Year', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
                        const SizedBox(height: Space.sm),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (var y = 1; y <= 5; y++)
                              PillChip(
                                label: y == 5 ? '5th+' : '${y}${const {1: 'st', 2: 'nd', 3: 'rd'}[y] ?? 'th'} year',
                                selected: _year == y,
                                onTap: () => setState(() => _year = y),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _Step(
                    title: 'What are you into?',
                    subtitle: 'Pick at least 3. Your feed and suggestions start here.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final entry in Interests.all.entries)
                              PillChip(
                                label: entry.value,
                                selected: _interests.contains(entry.key),
                                onTap: () => setState(() {
                                  if (!_interests.remove(entry.key)) _interests.add(entry.key);
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: Space.xxl),
                        AppTextField(
                          label: 'Skills (optional)',
                          hint: 'e.g. Flutter, Python, Figma',
                          controller: _skillInput,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (value) {
                            final skill = value.trim();
                            if (skill.isNotEmpty && !_skills.contains(skill) && _skills.length < 15) {
                              setState(() => _skills.add(skill));
                            }
                            _skillInput.clear();
                          },
                        ),
                        if (_skills.isNotEmpty) ...[
                          const SizedBox(height: Space.md),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final skill in _skills)
                                PillChip(
                                  label: skill,
                                  icon: AppIcons.close,
                                  dense: true,
                                  onTap: () => setState(() => _skills.remove(skill)),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  _Step(
                    title: 'Put a face to the name',
                    subtitle: 'Optional, but people are more likely to say hi.',
                    child: Column(
                      children: [
                        Center(
                          child: GestureDetector(
                            onTap: () async {
                              final photo = await MediaPicker.image(maxSide: 1024);
                              if (photo != null) setState(() => _photo = photo);
                            },
                            child: Stack(
                              children: [
                                _photo == null
                                    ? UserAvatar(name: _name.text.isEmpty ? '?' : _name.text, size: 112)
                                    : ClipOval(
                                        child: Image.memory(_photo!.bytes, width: 112, height: 112, fit: BoxFit.cover),
                                      ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: c.ink,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: c.background, width: 3),
                                    ),
                                    child: Icon(AppIcons.camera, size: 18, color: c.inkInverse),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: Space.xxl),
                        AppTextField(
                          label: 'Bio (optional)',
                          hint: 'What are you working on? What should people ask you about?',
                          controller: _bio,
                          maxLines: 3,
                          maxLength: 280,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.sm, Space.xl, Space.lg),
              child: AppButton(
                label: _step == _steps - 1 ? 'Finish' : (_step == 1 && _college == null ? 'Skip for now' : 'Continue'),
                expand: true,
                loading: _saving,
                onPressed: _canContinue ? _next : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.xxl, Space.xl, Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.displaySmall),
          const SizedBox(height: Space.sm),
          Text(subtitle, style: context.text.bodyLarge!.copyWith(color: context.colors.inkMuted)),
          const SizedBox(height: Space.xxl),
          child,
        ],
      ),
    );
  }
}

class _CollegePicker extends ConsumerStatefulWidget {
  const _CollegePicker({required this.selected, required this.onSelected});

  final College? selected;
  final ValueChanged<College?> onSelected;

  @override
  ConsumerState<_CollegePicker> createState() => _CollegePickerState();
}

class _CollegePickerState extends ConsumerState<_CollegePicker> {
  final _debounce = Debouncer(const Duration(milliseconds: 300));
  String _query = '';

  @override
  void dispose() {
    _debounce.dispose();
    super.dispose();
  }

  Future<void> _addCollege() async {
    final added = await showAppSheet<College>(context, builder: (_) => const _AddCollegeSheet());
    if (added != null) widget.onSelected(added);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final results = ref.watch(collegeSearchProvider(_query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchField(
          hint: 'Search your college',
          onChanged: (value) => _debounce(() => setState(() => _query = value)),
        ),
        const SizedBox(height: Space.md),
        results.when(
          loading: () => const ListSkeleton(count: 4, itemBuilder: _collegeSkeleton),
          error: (error, _) => ErrorState(error: error, compact: true, onRetry: () => ref.invalidate(collegeSearchProvider(_query))),
          data: (colleges) => Column(
            children: [
              for (final college in colleges.take(12))
                _CollegeTile(
                  college: college,
                  selected: widget.selected?.id == college.id,
                  onTap: () => widget.onSelected(widget.selected?.id == college.id ? null : college),
                ),
              if (colleges.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.lg),
                  child: Text('No colleges match "$_query".', style: context.text.bodyMedium!.copyWith(color: c.inkMuted)),
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

class _AddCollegeSheet extends ConsumerStatefulWidget {
  const _AddCollegeSheet();

  @override
  ConsumerState<_AddCollegeSheet> createState() => _AddCollegeSheetState();
}

class _AddCollegeSheetState extends ConsumerState<_AddCollegeSheet> {
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
      final college = await ref.read(collegeRepositoryProvider).add(
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
                Expanded(child: AppTextField(label: 'City', controller: _city, textCapitalization: TextCapitalization.words)),
                const SizedBox(width: Space.md),
                Expanded(child: AppTextField(label: 'State', controller: _state, textCapitalization: TextCapitalization.words)),
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
