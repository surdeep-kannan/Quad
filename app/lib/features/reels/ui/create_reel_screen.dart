import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/media.dart';
import '../../../core/data/refs.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/sheets.dart';
import '../../communities/data/community.dart';
import '../../communities/providers.dart';
import '../../posts/data/post.dart';
import '../../posts/data/post_repository.dart';
import '../../posts/providers.dart';

const _reelTopics = {
  'college-life': 'College life',
  'events': 'Events',
  'projects': 'Projects',
  'hackathons': 'Hackathons',
  'achievements': 'Achievements',
  'educational': 'Educational',
  'clubs': 'Clubs',
  'sports': 'Sports',
};

class CreateReelScreen extends ConsumerStatefulWidget {
  const CreateReelScreen({super.key});

  @override
  ConsumerState<CreateReelScreen> createState() => _CreateReelScreenState();
}

class _CreateReelScreenState extends ConsumerState<CreateReelScreen> {
  PickedFile? _video;
  PickedFile? _cover;
  final _caption = TextEditingController();
  final Set<String> _topics = {};
  Community? _community;
  bool _busy = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final video = await MediaPicker.video(maxDuration: const Duration(seconds: 90));
    if (video == null) return;
    if (video.size > 50 * 1024 * 1024) {
      if (mounted) showToast(context, 'Reels can be up to 50 MB.', error: true);
      return;
    }
    setState(() => _video = video);
  }

  Future<void> _post() async {
    setState(() => _busy = true);
    try {
      final storage = ref.read(storageRepositoryProvider);
      final url = await storage.uploadMedia(_video!, folder: 'reels');
      final cover = _cover == null ? null : await storage.uploadMedia(_cover!, folder: 'reels');
      await ref.read(postRepositoryProvider).create(
            type: PostType.reel,
            communityId: _community?.id,
            body: _caption.text.trim().isEmpty ? null : _caption.text.trim(),
            media: [MediaItem(url: url, type: 'video', thumbnailUrl: cover)],
            tags: _topics.toList(),
          );
      ref.invalidate(reelsFeedProvider);
      if (mounted) {
        context.pop();
        showToast(context, 'Reel posted');
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
    final mine = ref.watch(myCommunitiesProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Close', icon: const Icon(AppIcons.close), onPressed: () => context.pop()),
        title: const Text('New reel'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AppButton(label: 'Post', size: ButtonSize.small, loading: _busy, onPressed: _video == null ? null : _post),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.xl),
        children: [
          InkWell(
            onTap: _pick,
            borderRadius: BorderRadius.circular(Radii.lg),
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                borderRadius: BorderRadius.circular(Radii.lg),
                border: Border.all(color: c.lineStrong),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_video == null ? AppIcons.video : AppIcons.checkCircle, size: 40, color: _video == null ? c.inkMuted : c.success),
                    const SizedBox(height: 10),
                    Text(_video == null ? 'Choose a video (up to 90 s)' : _video!.name, style: context.text.titleSmall, textAlign: TextAlign.center),
                    if (_video != null) Text(fileSize(_video!.size), style: context.text.bodySmall),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          TextButton.icon(
            onPressed: () async {
              final cover = await MediaPicker.image(maxSide: 1080);
              if (cover != null) setState(() => _cover = cover);
            },
            icon: const Icon(AppIcons.image, size: 18),
            label: Text(_cover == null ? 'Add a cover image (optional)' : 'Cover added'),
          ),
          const SizedBox(height: Space.md),
          AppTextField(label: 'Caption', controller: _caption, maxLines: 3, maxLength: 500),
          const SizedBox(height: Space.lg),
          Text('Topic', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _reelTopics.entries)
                PillChip(
                  label: e.value,
                  dense: true,
                  selected: _topics.contains(e.key),
                  onTap: () => setState(() => _topics.contains(e.key) ? _topics.remove(e.key) : _topics.add(e.key)),
                ),
            ],
          ),
          if (mine.isNotEmpty) ...[
            const SizedBox(height: Space.lg),
            Text('Post in a community (optional)', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final community in mine)
                  PillChip(
                    label: community.name,
                    dense: true,
                    selected: _community?.id == community.id,
                    onTap: () => setState(() => _community = _community?.id == community.id ? null : community),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
