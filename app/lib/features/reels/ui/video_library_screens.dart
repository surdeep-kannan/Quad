import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../posts/data/post.dart';
import '../data/video_library.dart';
import 'reels_screen.dart';

/// What the full-screen player shows (passed as the route's `extra`).
class WatchArgs {
  const WatchArgs({required this.title, required this.posts, this.initialIndex = 0});

  final String title;
  final List<Post> posts;
  final int initialIndex;
}

/// Opens [posts] in the full-screen vertical player, starting at [index].
void watchVideos(BuildContext context, {required String title, required List<Post> posts, int index = 0}) {
  context.push(
    '/watch',
    extra: WatchArgs(title: title, posts: posts, initialIndex: index),
  );
}

/// Swipe through a fixed list of videos, reels-style.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.args});

  final WatchArgs? args;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late int _index = widget.args?.initialIndex ?? 0;
  late final _pages = PageController(initialPage: _index);
  bool _muted = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final posts = args?.posts ?? const <Post>[];
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          if (posts.isEmpty)
            const Center(
              child: Text('Nothing to play', style: TextStyle(color: Colors.white70)),
            )
          else
            PageView.builder(
              controller: _pages,
              scrollDirection: Axis.vertical,
              itemCount: posts.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => ReelPage(
                key: ValueKey(posts[i].id),
                post: posts[i],
                active: i == _index && TickerMode.valuesOf(context).enabled,
                muted: _muted,
                onToggleMute: () => setState(() => _muted = !_muted),
              ),
            ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 4,
            left: 4,
            right: 16,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(AppIcons.back, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                Expanded(
                  child: Text(
                    args?.title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                if (posts.length > 1)
                  Text('${_index + 1} / ${posts.length}', style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A 3-column grid of video thumbnails. Tapping opens the player.
class VideoGrid extends StatelessWidget {
  const VideoGrid({super.key, required this.posts, required this.title, this.onLongPress});

  final List<Post> posts;
  final String title;
  final void Function(Post post)? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 9 / 16,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: posts.length,
      itemBuilder: (_, i) => VideoThumb(
        post: posts[i],
        onTap: () => watchVideos(context, title: title, posts: posts, index: i),
        onLongPress: onLongPress == null ? null : () => onLongPress!(posts[i]),
      ),
    );
  }
}

class VideoThumb extends StatelessWidget {
  const VideoThumb({super.key, required this.post, required this.onTap, this.onLongPress});

  final Post post;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final thumb = post.video?.thumbnailUrl;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumb != null)
            AppImage(thumb)
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [c.ink, Palette.forText(post.id)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  post.body ?? post.title ?? '',
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.3),
                ),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0x99000000)],
              ),
            ),
          ),
          Positioned(
            left: 6,
            bottom: 6,
            right: 6,
            child: Row(
              children: [
                const Icon(AppIcons.play, size: 12, color: Colors.white),
                const SizedBox(width: 3),
                Text(
                  compactCount(post.viewsCount),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (post.likesCount > 0) ...[
                  const Icon(AppIcons.heartFill, size: 11, color: Colors.white),
                  const SizedBox(width: 2),
                  Text(
                    compactCount(post.likesCount),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LikedVideosScreen extends ConsumerWidget {
  const LikedVideosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(likedVideosProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        title: const Text('Liked videos'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(likedVideosProvider.future),
        child: liked.when(
          loading: () => const CenteredLoader(),
          error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(likedVideosProvider)),
          data: (posts) => posts.isEmpty
              ? ListView(
                  children: const [
                    EmptyState(
                      icon: AppIcons.heart,
                      title: 'No liked videos yet',
                      message: 'Reels and videos you like show up here.',
                    ),
                  ],
                )
              : VideoGrid(posts: posts, title: 'Liked videos', onLongPress: (post) => showPlaylistSheet(context, post)),
        ),
      ),
    );
  }
}

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider(null));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        title: const Text('Playlists'),
        actions: [
          IconButton(
            tooltip: 'New playlist',
            icon: const Icon(AppIcons.plus),
            onPressed: () async {
              final name = await _askName(context, title: 'New playlist');
              if (name == null) return;
              try {
                await ref.read(videoLibraryProvider).createPlaylist(name);
                ref.invalidate(playlistsProvider);
              } catch (error) {
                if (context.mounted) showToast(context, friendlyError(error), error: true);
              }
            },
          ),
        ],
      ),
      body: playlists.when(
        loading: () => const CenteredLoader(),
        error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(playlistsProvider(null))),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: AppIcons.playlist,
                title: 'No playlists yet',
                message: 'Hold the Save button on a reel, or use its ⋯ menu, to add it to a playlist.',
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                itemCount: list.length,
                itemBuilder: (_, i) => _PlaylistRow(playlist: list[i]),
              ),
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cover = playlist.cover?.thumbnailUrl;
    return ListTile(
      onTap: () => context.push('/library/playlists/${playlist.id}'),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.sm),
        child: SizedBox(
          width: 48,
          height: 64,
          child: cover != null
              ? AppImage(cover)
              : DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [c.ink, Palette.forText(playlist.name)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(AppIcons.playlist, color: Colors.white),
                ),
        ),
      ),
      title: Text(playlist.name, style: context.text.titleSmall),
      subtitle: Text(plural(playlist.itemsCount, 'video')),
      trailing: Icon(AppIcons.forward, size: 18, color: c.inkSubtle),
    );
  }
}

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key, required this.playlistId});

  final String playlistId;

  Future<void> _menu(BuildContext context, WidgetRef ref, Playlist playlist) async {
    final library = ref.read(videoLibraryProvider);
    await showActionSheet(
      context,
      title: playlist.name,
      actions: [
        SheetAction(
          icon: AppIcons.edit,
          label: 'Rename',
          onTap: () async {
            final name = await _askName(context, title: 'Rename playlist', initial: playlist.name);
            if (name == null) return;
            try {
              await library.renamePlaylist(playlist.id, name);
              ref.invalidate(playlistsProvider);
            } catch (error) {
              if (context.mounted) showToast(context, friendlyError(error), error: true);
            }
          },
        ),
        SheetAction(
          icon: AppIcons.trash,
          label: 'Delete playlist',
          destructive: true,
          onTap: () async {
            final ok = await confirm(
              context,
              title: 'Delete ${playlist.name}?',
              message: 'The videos stay where they are; only this list is deleted.',
              confirmLabel: 'Delete',
              destructive: true,
            );
            if (!ok) return;
            try {
              await library.deletePlaylist(playlist.id);
              ref.invalidate(playlistsProvider);
              if (context.mounted) context.pop();
            } catch (error) {
              if (context.mounted) showToast(context, friendlyError(error), error: true);
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(playlistsProvider(null)).value?.where((p) => p.id == playlistId).firstOrNull;
    final videos = ref.watch(playlistVideosProvider(playlistId));
    final title = playlist?.name ?? 'Playlist';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        title: Text(title),
        actions: [
          if (playlist != null)
            IconButton(
              tooltip: 'Playlist options',
              icon: const Icon(AppIcons.more),
              onPressed: () => _menu(context, ref, playlist),
            ),
        ],
      ),
      body: videos.when(
        loading: () => const CenteredLoader(),
        error: (error, _) =>
            ErrorState(error: error, onRetry: () => ref.invalidate(playlistVideosProvider(playlistId))),
        data: (posts) => posts.isEmpty
            ? const EmptyState(
                icon: AppIcons.playlist,
                title: 'This playlist is empty',
                message: 'Hold the Save button on a reel to add it here.',
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.md),
                    child: AppButton(
                      label: 'Play all',
                      icon: AppIcons.play,
                      onPressed: () => watchVideos(context, title: title, posts: posts),
                    ),
                  ),
                  Expanded(
                    child: VideoGrid(
                      posts: posts,
                      title: title,
                      onLongPress: (post) async {
                        final ok = await confirm(
                          context,
                          title: 'Remove from $title?',
                          message: 'The video itself isn\'t deleted.',
                          confirmLabel: 'Remove',
                          destructive: true,
                        );
                        if (!ok) return;
                        try {
                          await ref.read(videoLibraryProvider).removeFromPlaylist(playlistId, post.id);
                          ref.invalidate(playlistVideosProvider(playlistId));
                          ref.invalidate(playlistsProvider);
                        } catch (error) {
                          if (context.mounted) showToast(context, friendlyError(error), error: true);
                        }
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Tick the playlists this video should be in, or start a new one.
Future<void> showPlaylistSheet(BuildContext context, Post post) {
  HapticFeedback.selectionClick();
  return showAppSheet<void>(context, builder: (_) => _PlaylistSheet(post: post));
}

class _PlaylistSheet extends ConsumerWidget {
  const _PlaylistSheet({required this.post});

  final Post post;

  Future<void> _toggle(BuildContext context, WidgetRef ref, Playlist playlist) async {
    final library = ref.read(videoLibraryProvider);
    try {
      if (playlist.containsPost) {
        await library.removeFromPlaylist(playlist.id, post.id);
      } else {
        await library.addToPlaylist(playlist.id, post.id);
      }
      ref.invalidate(playlistsProvider);
      ref.invalidate(playlistVideosProvider(playlist.id));
      if (context.mounted) {
        showToast(context, playlist.containsPost ? 'Removed from ${playlist.name}' : 'Added to ${playlist.name}');
      }
    } catch (error) {
      if (context.mounted) showToast(context, friendlyError(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider(post.id));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
          child: Text('Save to playlist', style: context.text.titleMedium),
        ),
        Flexible(
          child: playlists.when(
            loading: () => const CenteredLoader(),
            error: (error, _) => ErrorState(error: error, compact: true),
            data: (list) => ListView(
              shrinkWrap: true,
              children: [
                for (final playlist in list)
                  CheckboxListTile(
                    value: playlist.containsPost,
                    onChanged: (_) => _toggle(context, ref, playlist),
                    controlAffinity: ListTileControlAffinity.trailing,
                    contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
                    title: Text(playlist.name),
                    subtitle: Text(plural(playlist.itemsCount, 'video')),
                  ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
                  leading: const Icon(AppIcons.listPlus),
                  title: const Text('New playlist'),
                  onTap: () async {
                    final name = await _askName(context, title: 'New playlist');
                    if (name == null) return;
                    try {
                      final library = ref.read(videoLibraryProvider);
                      final id = await library.createPlaylist(name);
                      await library.addToPlaylist(id, post.id);
                      ref.invalidate(playlistsProvider);
                      if (context.mounted) showToast(context, 'Added to $name');
                    } catch (error) {
                      if (context.mounted) showToast(context, friendlyError(error), error: true);
                    }
                  },
                ),
                SizedBox(height: Space.lg + context.safePadding.bottom),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Future<String?> _askName(BuildContext context, {required String title, String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'e.g. Study music, Hackathon tips'),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim().isEmpty ? null : value.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final value = controller.text.trim();
            Navigator.of(dialogContext).pop(value.isEmpty ? null : value);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
