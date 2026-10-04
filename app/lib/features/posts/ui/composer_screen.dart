import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:material_ui/material_ui.dart';

import '../../../core/data/media.dart';
import '../../../core/data/refs.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/photo_adjust.dart';
import '../../../core/widgets/sheets.dart';
import '../../communities/data/community.dart';
import '../../communities/providers.dart';
import '../../profile/data/profile.dart';
import '../../profile/providers.dart';
import '../data/post.dart';
import '../data/post_repository.dart';
import '../providers.dart';
import 'post_music.dart';

class ComposerScreen extends ConsumerStatefulWidget {
  const ComposerScreen({super.key, this.communityId, this.initialType, this.eventId});

  final String? communityId;
  final String? initialType;
  final String? eventId;

  @override
  ConsumerState<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends ConsumerState<ComposerScreen> {
  late PostType _type = PostType.from(widget.initialType ?? (widget.eventId != null ? 'event' : 'text'));
  Community? _community;
  final _title = TextEditingController();
  final _body = TextEditingController();
  final List<TextEditingController> _options = [TextEditingController(), TextEditingController()];
  final List<PickedFile> _images = [];
  PickedFile? _video;
  final Set<String> _tags = {};
  Duration _pollDuration = const Duration(days: 3);
  bool _anonymous = false;
  bool _posting = false;

  /// Background music for a photo post.
  MediaItem? _music;

  @override
  void initState() {
    super.initState();
    final communityId = widget.communityId;
    if (communityId != null) {
      final mine = ref.read(myCommunitiesProvider).value;
      if (mine != null) {
        _community = mine.where((c) => c.id == communityId).firstOrNull;
      } else {
        // Opened before the list loaded (e.g. from a link): pick it once it arrives.
        ref.read(myCommunitiesProvider.future).then((list) {
          if (mounted && _community == null)
            setState(() => _community = list.where((c) => c.id == communityId).firstOrNull);
        }, onError: (_) {});
      }
    }
    _title.addListener(_refresh);
    _body.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  /// Only community posts can be anonymous; announcements and events never are.
  bool get _canBeAnonymous => _community != null && _type != PostType.announcement && _type != PostType.event;

  bool get _isPrivate => ref.read(myProfileProvider).value?.isPrivate ?? false;

  bool get _postsAnonymously => _canBeAnonymous && (_anonymous || _isPrivate);

  bool get _needsTitle =>
      const {PostType.question, PostType.poll, PostType.announcement, PostType.achievement}.contains(_type);

  bool get _valid {
    if (_needsTitle && _title.text.trim().isEmpty) return false;
    return switch (_type) {
      PostType.poll => _options.where((c) => c.text.trim().isNotEmpty).length >= 2,
      PostType.image => _images.isNotEmpty,
      PostType.video => _video != null,
      PostType.event => widget.eventId != null,
      _ => _title.text.trim().isNotEmpty || _body.text.trim().isNotEmpty || _images.isNotEmpty,
    };
  }

  Future<void> _pickImages() async {
    final picked = await MediaPicker.images(limit: 4 - _images.length);
    if (picked.isEmpty || !mounted) return;
    // A single photo goes straight to cropping; with several, each thumbnail
    // has an Adjust button. Cancelling keeps the photo as it was.
    final photos = picked.length == 1
        ? [await adjustPhoto(context, picked.first, maxSide: 2048) ?? picked.first]
        : picked;
    if (!mounted) return;
    setState(() {
      _images.addAll(photos.take(4 - _images.length));
      if (_type == PostType.text) _type = PostType.image;
    });
  }

  Future<void> _adjust(int index) async {
    final adjusted = await adjustPhoto(context, _images[index], maxSide: 2048);
    if (adjusted != null && mounted) setState(() => _images[index] = adjusted);
  }

  Future<void> _addMusic() async {
    final music = await pickPostMusic(context, ref, current: _music);
    if (music != null && mounted) setState(() => _music = music);
  }

  Future<void> _pickVideo() async {
    final picked = await MediaPicker.video();
    if (picked == null) return;
    if (picked.size > 50 * 1024 * 1024) {
      if (mounted) showToast(context, 'Videos can be up to 50 MB.', error: true);
      return;
    }
    setState(() => _video = picked);
  }

  Future<void> _chooseDestination() async {
    List<Community> communities;
    try {
      communities = ref.read(myCommunitiesProvider).value ?? await ref.read(myCommunitiesProvider.future);
    } catch (_) {
      communities = const [];
    }
    if (!mounted) return;
    final picked = await showAppSheet<Object>(
      context,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: Space.lg),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
            child: Text('Post to', style: sheetContext.text.titleMedium),
          ),
          ListTile(
            leading: const Icon(AppIcons.user),
            title: const Text('Your profile'),
            subtitle: const Text('Visible to everyone who visits your profile'),
            onTap: () => Navigator.of(sheetContext).pop('profile'),
          ),
          for (final community in communities)
            ListTile(
              leading: CommunityAvatar(
                name: community.name,
                color: community.color,
                url: community.avatarUrl,
                size: 36,
              ),
              title: Text(community.name),
              subtitle: Text(community.isStaff ? 'You help run this community' : '${community.membersCount} members'),
              onTap: () => Navigator.of(sheetContext).pop(community),
            ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() {
      _community = picked is Community ? picked : null;
      if (_type == PostType.announcement && !(_community?.can(CommunityPermissions.postAnnouncements) ?? false))
        _type = PostType.text;
    });
  }

  Future<void> _post() async {
    setState(() => _posting = true);
    try {
      final storage = ref.read(storageRepositoryProvider);
      final media = <MediaItem>[];
      if (_type == PostType.video && _video != null) {
        final url = await storage.uploadMedia(_video!, folder: 'posts');
        media.add(MediaItem(url: url, type: 'video'));
      } else {
        for (final image in _images) {
          final url = await storage.uploadMedia(image, folder: 'posts');
          media.add(MediaItem(url: url, type: 'image', width: image.width, height: image.height));
        }
        // Music goes after the photos (it's only for photo posts).
        if (_music != null && media.isNotEmpty) media.add(_music!);
      }
      final id = await ref
          .read(postRepositoryProvider)
          .create(
            type: _type,
            communityId: _community?.id,
            title: _title.text.trim().isEmpty ? null : _title.text.trim(),
            body: _body.text.trim().isEmpty ? null : _body.text.trim(),
            media: media,
            tags: _tags.toList(),
            eventId: widget.eventId,
            pollOptions: _type == PostType.poll ? [for (final c in _options) c.text.trim()] : null,
            pollEndsAt: _type == PostType.poll ? DateTime.now().add(_pollDuration) : null,
            anonymous: _postsAnonymously,
          );
      for (final mode in FeedMode.values) {
        ref.invalidate(homeFeedProvider(mode));
      }
      if (_community != null) ref.invalidate(communityFeedProvider);
      if (!mounted) return;
      showToast(context, 'Posted', icon: AppIcons.checkCircle);
      // Replace the composer with the new post (works even when the composer
      // was opened from a link, with nothing behind it).
      if (context.canPop()) {
        context.pop();
        context.push('/post/$id');
      } else {
        context.go('/post/$id');
      }
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final me = ref.watch(myProfileProvider).value;
    final canAnnounce = _community?.can(CommunityPermissions.postAnnouncements) ?? false;
    final types = [
      PostType.text,
      PostType.image,
      PostType.question,
      PostType.poll,
      PostType.achievement,
      if (canAnnounce) PostType.announcement,
      PostType.video,
      if (widget.eventId != null) PostType.event,
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Close', icon: const Icon(AppIcons.close), onPressed: () => context.pop()),
        title: const Text('New post'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AppButton(
              label: 'Post',
              size: ButtonSize.small,
              loading: _posting,
              onPressed: _valid && !_posting ? _post : null,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 120),
        children: [
          Row(
            children: [
              if (me != null)
                _postsAnonymously
                    ? const AnonymousAvatar(alias: 'me', size: 40)
                    : UserAvatar(name: me.fullName, url: me.avatarUrl, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: c.surfaceMuted,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: _chooseDestination,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_community != null) ...[
                              CommunityAvatar(
                                name: _community!.name,
                                color: _community!.color,
                                url: _community!.avatarUrl,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                _community?.name ?? 'Your profile',
                                overflow: TextOverflow.ellipsis,
                                style: context.text.labelMedium,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(AppIcons.down, size: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_canBeAnonymous) ...[
            const SizedBox(height: Space.md),
            _AnonymousToggle(
              value: _postsAnonymously,
              locked: me?.isPrivate ?? false,
              onChanged: (value) => setState(() => _anonymous = value),
            ),
          ] else if (_community == null && (me?.isPrivate ?? false)) ...[
            const SizedBox(height: Space.md),
            Text(
              'Your profile is private, so posts here are only visible to people you follow. '
              'Post in a community to share anonymously.',
              style: context.text.bodySmall,
            ),
          ],
          const SizedBox(height: Space.lg),
          ChipRow(
            padding: EdgeInsets.zero,
            children: [
              for (final type in types)
                PillChip(
                  label: type.label,
                  icon: type.icon,
                  dense: true,
                  selected: _type == type,
                  onTap: () => setState(() => _type = type),
                ),
            ],
          ),
          const SizedBox(height: Space.lg),
          if (_needsTitle || _type == PostType.text)
            _BareField(
              controller: _title,
              hint: switch (_type) {
                PostType.question => 'What do you want to ask?',
                PostType.poll => 'Ask a question',
                PostType.announcement => 'Announcement title',
                PostType.achievement => 'What did you achieve?',
                _ => 'Title (optional)',
              },
              style: context.text.headlineSmall!,
              maxLines: 3,
            ),
          _BareField(
            controller: _body,
            hint: switch (_type) {
              PostType.question => 'Add details so people can help (optional)',
              PostType.achievement => 'Tell the story: the team, the build, what you learned',
              PostType.image || PostType.video => 'Write a caption…',
              PostType.event => 'Say something about the event…',
              _ => 'What\'s happening on campus?',
            },
            style: context.text.bodyLarge!,
            maxLines: null,
            minLines: 3,
          ),
          if (_type == PostType.poll) ...[
            const SizedBox(height: Space.md),
            for (var i = 0; i < _options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _options[i],
                  onChanged: (_) => setState(() {}),
                  maxLength: 80,
                  decoration: InputDecoration(
                    hintText: 'Option ${i + 1}',
                    counterText: '',
                    suffixIcon: _options.length > 2
                        ? IconButton(
                            tooltip: 'Remove option',
                            icon: const Icon(AppIcons.close, size: 18),
                            onPressed: () => setState(() => _options.removeAt(i).dispose()),
                          )
                        : null,
                  ),
                ),
              ),
            if (_options.length < 6)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _options.add(TextEditingController())),
                  icon: const Icon(AppIcons.plus, size: 18),
                  label: const Text('Add option'),
                ),
              ),
            const SizedBox(height: Space.sm),
            Text('Poll length', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: 8,
              children: [
                for (final (label, duration) in [
                  ('1 day', const Duration(days: 1)),
                  ('3 days', const Duration(days: 3)),
                  ('1 week', const Duration(days: 7)),
                ])
                  PillChip(
                    label: label,
                    dense: true,
                    selected: _pollDuration == duration,
                    onTap: () => setState(() => _pollDuration = duration),
                  ),
              ],
            ),
          ],
          if (_images.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Stack(
                  children: [
                    GestureDetector(
                      onTap: () => _adjust(i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.md),
                        child: Image.memory(_images[i].bytes, width: 110, height: 110, fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: GestureDetector(
                        onTap: () => _adjust(i),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(AppIcons.crop, size: 13, color: Colors.white),
                              SizedBox(width: 4),
                              Text('Adjust', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => setState(() => _images.removeAt(i)),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(AppIcons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            _MusicRow(
              music: _music,
              onAdd: _addMusic,
              onRemove: () => setState(() => _music = null),
            ),
          ],
          if (_type == PostType.video) ...[
            const SizedBox(height: Space.md),
            _video == null
                ? AppButton(
                    label: 'Choose a video',
                    icon: AppIcons.video,
                    variant: ButtonVariant.secondary,
                    onPressed: _pickVideo,
                  )
                : ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(AppIcons.video),
                    title: Text(_video!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${(_video!.size / (1024 * 1024)).toStringAsFixed(1)} MB'),
                    trailing: IconButton(
                      tooltip: 'Remove video',
                      icon: const Icon(AppIcons.close),
                      onPressed: () => setState(() => _video = null),
                    ),
                  ),
          ],
          const SizedBox(height: Space.xl),
          Text('Topics', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
          const SizedBox(height: 4),
          Text('Pick up to 3 so the right people see this.', style: context.text.bodySmall),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in Interests.all.entries.take(16))
                PillChip(
                  label: entry.value,
                  dense: true,
                  selected: _tags.contains(entry.key),
                  onTap: () => setState(() {
                    if (!_tags.remove(entry.key) && _tags.length < 3) _tags.add(entry.key);
                  }),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: _type == PostType.video || _type == PostType.event || _type == PostType.poll
          ? null
          : SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.line)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Add photos',
                      icon: const Icon(AppIcons.image),
                      onPressed: _images.length >= 4 ? null : _pickImages,
                    ),
                    IconButton(
                      tooltip: 'Take a photo',
                      icon: const Icon(AppIcons.camera),
                      onPressed: _images.length >= 4
                          ? null
                          : () async {
                              final photo = await MediaPicker.image(source: ImageSource.camera);
                              if (photo == null || !context.mounted) return;
                              final adjusted = await adjustPhoto(context, photo, maxSide: 2048);
                              if (mounted) setState(() => _images.add(adjusted ?? photo));
                            },
                    ),
                    IconButton(
                      tooltip: 'Add music',
                      icon: Icon(_music == null ? AppIcons.music : AppIcons.musicFill),
                      onPressed: _images.isEmpty ? null : _addMusic,
                    ),
                    const Spacer(),
                    Text('${_images.length}/4 photos', style: context.text.bodySmall),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
    );
  }
}

class _AnonymousToggle extends StatelessWidget {
  const _AnonymousToggle({required this.value, required this.locked, required this.onChanged});

  final bool value;

  /// Private profiles always post anonymously.
  final bool locked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: value ? c.accentSoft : c.surfaceMuted,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: locked ? null : () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              Icon(
                value ? AppIcons.anonymous : AppIcons.anonymousOutline,
                size: 22,
                color: value ? c.accentInk : c.inkMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Post anonymously', style: context.text.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      locked
                          ? 'Always on because your profile is private.'
                          : 'Shows a random name like anonymous_quiet_otter_421 instead of yours.',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              Switch(value: value, onChanged: locked ? null : onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _BareField extends StatelessWidget {
  const _BareField({required this.controller, required this.hint, required this.style, this.maxLines, this.minLines});

  final TextEditingController controller;
  final String hint;
  final TextStyle style;
  final int? maxLines;
  final int? minLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: style,
      maxLines: maxLines,
      minLines: minLines,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: style.copyWith(color: context.colors.inkSubtle),
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
      ),
    );
  }
}

/// The photo post's music: "Add music", or the chosen song with edit/remove.
class _MusicRow extends StatelessWidget {
  const _MusicRow({required this.music, required this.onAdd, required this.onRemove});

  final MediaItem? music;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final music = this.music;
    if (music == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(AppIcons.music, size: 18),
          label: const Text('Add music'),
        ),
      );
    }
    final start = (music.startMs ?? 0) ~/ 1000;
    return Material(
      color: c.surfaceMuted,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onAdd,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Icon(AppIcons.musicFill, color: c.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(music.title ?? 'Original audio', style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      'From ${start ~/ 60}:${(start % 60).toString().padLeft(2, '0')} · ${(music.durationMs ?? 30000) ~/ 1000} s · tap to change',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(tooltip: 'Remove music', icon: const Icon(AppIcons.close, size: 18), onPressed: onRemove),
            ],
          ),
        ),
      ),
    );
  }
}