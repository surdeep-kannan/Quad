import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/media.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/sheets.dart';
import '../../profile/data/profile.dart';
import '../../profile/providers.dart';
import '../data/community.dart';
import '../data/community_repository.dart';
import '../providers.dart';

class CreateCommunityScreen extends ConsumerStatefulWidget {
  const CreateCommunityScreen({super.key});

  @override
  ConsumerState<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends ConsumerState<CreateCommunityScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _tagline = TextEditingController();
  final _description = TextEditingController();
  String _category = 'club';
  bool _private = false;
  bool _linkCollege = true;
  int _color = 0;
  PickedFile? _icon;
  final Set<String> _tags = {};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _tagline.dispose();
    _description.dispose();
    super.dispose();
  }

  String get _slug {
    final base = _name.text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return base.length > 36 ? base.substring(0, 36).replaceAll(RegExp(r'-+$'), '') : base;
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final repo = ref.read(communityRepositoryProvider);
    try {
      var slug = _slug;
      if (slug.length < 3) slug = '$slug-club';
      if (await repo.isSlugTaken(slug)) slug = '$slug-${DateTime.now().millisecondsSinceEpoch % 1000}';
      String? iconUrl;
      if (_icon != null) iconUrl = await ref.read(storageRepositoryProvider).uploadMedia(_icon!, folder: 'communities');
      final me = ref.read(myProfileProvider).value;
      final created = await repo.create(
        slug: slug,
        name: _name.text.trim(),
        category: _category,
        visibility: _private ? 'private' : 'public',
        color: _color,
        tagline: _tagline.text.trim().isEmpty ? null : _tagline.text.trim(),
        description: _description.text.trim().isEmpty ? null : _description.text.trim(),
        collegeId: _linkCollege ? me?.collegeId : null,
        avatarUrl: iconUrl,
        tags: _tags.toList(),
        rules: const [
          CommunityRule(title: 'Be kind', body: 'Critique ideas, not people.'),
          CommunityRule(title: 'No spam', body: 'Share your work with context, not link dumps.'),
        ],
      );
      ref.invalidate(myCommunitiesProvider);
      if (!mounted) return;
      context.pushReplacement('/c/$created');
      showToast(context, 'Community created. Invite people to join!');
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final me = ref.watch(myProfileProvider).value;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Close', icon: const Icon(AppIcons.close), onPressed: () => context.pop()),
        title: const Text('New community'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.sm, Space.xl, Space.xxxl),
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    final icon = await MediaPicker.image(maxSide: 512);
                    if (icon != null) setState(() => _icon = icon);
                  },
                  child: Stack(
                    children: [
                      _icon == null
                          ? CommunityAvatar(name: _name.text.isEmpty ? 'Q' : _name.text, color: _color, size: 72)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: Image.memory(_icon!.bytes, width: 72, height: 72, fit: BoxFit.cover),
                            ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle, border: Border.all(color: c.background, width: 2)),
                          child: Icon(AppIcons.camera, size: 13, color: c.inkInverse),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < Palette.colors.length; i++)
                        GestureDetector(
                          onTap: () => setState(() => _color = i),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: Palette.at(i),
                              shape: BoxShape.circle,
                              border: Border.all(color: _color == i ? c.ink : Colors.transparent, width: 2.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.xl),
            AppTextField(
              label: 'Name',
              controller: _name,
              textCapitalization: TextCapitalization.words,
              maxLength: 60,
              onChanged: (_) => setState(() {}),
              validator: (v) => (v?.trim().length ?? 0) < 3 ? 'At least 3 characters' : null,
              helper: _slug.isEmpty ? null : 'quad.app/c/$_slug',
            ),
            const SizedBox(height: Space.lg),
            AppTextField(label: 'Tagline', hint: 'One line on what this is about', controller: _tagline, maxLength: 120),
            const SizedBox(height: Space.lg),
            AppTextField(label: 'Description', controller: _description, maxLines: 4, maxLength: 2000),
            const SizedBox(height: Space.lg),
            Text('Category', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in CommunityCategories.all.entries)
                  PillChip(
                    label: entry.value,
                    icon: CommunityCategories.icon(entry.key),
                    dense: true,
                    selected: _category == entry.key,
                    onTap: () => setState(() => _category = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: Space.xl),
            Text('Topics', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in Interests.all.entries)
                  PillChip(
                    label: entry.value,
                    dense: true,
                    selected: _tags.contains(entry.key),
                    onTap: () => setState(() {
                      if (!_tags.remove(entry.key) && _tags.length < 5) _tags.add(entry.key);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: Space.lg),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _private,
              onChanged: (v) => setState(() => _private = v),
              title: const Text('Private community'),
              subtitle: const Text('People request to join and only members see posts and rooms.'),
            ),
            if (me?.college != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _linkCollege,
                onChanged: (v) => setState(() => _linkCollege = v),
                title: Text('Part of ${me!.college!.label}'),
                subtitle: const Text('Shows up in your college\'s page and counts toward its ranking.'),
              ),
            const SizedBox(height: Space.xl),
            AppButton(label: 'Create community', expand: true, loading: _busy, onPressed: _create),
          ],
        ),
      ),
    );
  }
}
