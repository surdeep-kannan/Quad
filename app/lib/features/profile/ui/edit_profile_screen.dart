import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/media.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/sheets.dart';
import '../data/profile.dart';
import '../data/profile_repository.dart';
import '../providers.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final Profile _me = ref.read(myProfileProvider).value!;
  late final _name = TextEditingController(text: _me.fullName);
  late final _username = TextEditingController(text: _me.username);
  late final _bio = TextEditingController(text: _me.bio);
  late final _department = TextEditingController(text: _me.department);
  late final _skills = TextEditingController(text: _me.skills.join(', '));
  late int? _year = _me.yearOfStudy;
  late final Set<String> _interests = {..._me.interests};
  PickedFile? _photo;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    _department.dispose();
    _skills.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final username = _username.text.trim();
      if (username != _me.username && !await ref.read(profileRepositoryProvider).isUsernameAvailable(username)) {
        if (mounted) showToast(context, 'That username is taken', error: true);
        return;
      }
      String? avatar;
      if (_photo != null) avatar = await ref.read(storageRepositoryProvider).uploadAvatar(_photo!);
      await ref.read(myProfileProvider.notifier).save({
        'full_name': _name.text.trim(),
        'username': username,
        'bio': _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        'department': _department.text.trim().isEmpty ? null : _department.text.trim(),
        'year_of_study': _year,
        'interests': _interests.toList(),
        'skills': _skills.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).take(20).toList(),
        'avatar_url': ?avatar,
      });
      if (mounted) {
        context.pop();
        showToast(context, 'Profile updated');
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Close', icon: const Icon(AppIcons.close), onPressed: () => context.pop()),
        title: const Text('Edit profile'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AppButton(label: 'Save', size: ButtonSize.small, loading: _busy, onPressed: _save),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(Space.xl),
          children: [
            Center(
              child: GestureDetector(
                onTap: () async {
                  final photo = await MediaPicker.image(maxSide: 1024);
                  if (photo != null) setState(() => _photo = photo);
                },
                child: Column(
                  children: [
                    _photo == null
                        ? UserAvatar(name: _me.fullName, url: _me.avatarUrl, size: 96)
                        : ClipOval(child: Image.memory(_photo!.bytes, width: 96, height: 96, fit: BoxFit.cover)),
                    const SizedBox(height: 8),
                    Text('Change photo', style: context.text.labelLarge!.copyWith(color: c.accentInk)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.xl),
            AppTextField(label: 'Name', controller: _name, validator: Validators.name),
            const SizedBox(height: Space.lg),
            AppTextField(label: 'Username', controller: _username, prefixIcon: AppIcons.at, validator: Validators.username),
            const SizedBox(height: Space.lg),
            AppTextField(label: 'Bio', controller: _bio, maxLines: 3, maxLength: 280),
            const SizedBox(height: Space.lg),
            AppTextField(label: 'Department', controller: _department),
            const SizedBox(height: Space.lg),
            Text('Year', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: 8,
              children: [
                for (var y = 1; y <= 5; y++)
                  PillChip(label: y == 5 ? '5th+' : 'Year $y', dense: true, selected: _year == y, onTap: () => setState(() => _year = y)),
              ],
            ),
            const SizedBox(height: Space.lg),
            AppTextField(label: 'Skills', hint: 'Comma separated, e.g. Flutter, Python', controller: _skills),
            const SizedBox(height: Space.lg),
            Text('Interests', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in Interests.all.entries)
                  PillChip(
                    label: e.value,
                    dense: true,
                    selected: _interests.contains(e.key),
                    onTap: () => setState(() => _interests.contains(e.key) ? _interests.remove(e.key) : _interests.add(e.key)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
