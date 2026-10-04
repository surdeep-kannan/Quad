import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../posts/data/post.dart';
import '../../posts/data/post_repository.dart';
import '../../posts/providers.dart';
import '../../posts/ui/post_card.dart';

/// Full-screen vertical short videos. Swipe up for the next one.
class ReelsScreen extends ConsumerStatefulWidget {
  const ReelsScreen({super.key});

  @override
  ConsumerState<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends ConsumerState<ReelsScreen> {
  int _index = 0;
  bool _muted = false;

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(reelsFeedProvider);
    final notifier = ref.read(reelsFeedProvider.notifier);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          feed.when(
            loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
            error: (e, _) => Theme(data: ThemeData.dark(), child: ErrorState(error: e, onRetry: () => ref.invalidate(reelsFeedProvider))),
            data: (paged) {
              if (paged.items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(AppIcons.reels, color: Colors.white54, size: 48),
                      const SizedBox(height: 12),
                      const Text('No reels yet', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                        onPressed: () => context.push('/reels/new'),
                        child: const Text('Post the first reel'),
                      ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: notifier.refresh,
                child: PageView.builder(
                  scrollDirection: Axis.vertical,
                  itemCount: paged.items.length,
                  onPageChanged: (i) {
                    setState(() => _index = i);
                    if (i >= paged.items.length - 3) notifier.loadMore();
                  },
                  itemBuilder: (_, i) => _ReelPage(
                    post: paged.items[i],
                    active: i == _index && TickerMode.valuesOf(context).enabled,
                    muted: _muted,
                    onToggleMute: () => setState(() => _muted = !_muted),
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: Space.gutter,
            right: 8,
            child: Row(
              children: [
                const Text('Reels', style: TextStyle(color: Colors.white, fontSize: 24, fontFamily: AppFonts.display, fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                  tooltip: 'Upload a reel',
                  icon: const Icon(AppIcons.camera, color: Colors.white),
                  onPressed: () => context.push('/reels/new'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReelPage extends ConsumerStatefulWidget {
  const _ReelPage({required this.post, required this.active, required this.muted, required this.onToggleMute});

  final Post post;
  final bool active;
  final bool muted;
  final VoidCallback onToggleMute;

  @override
  ConsumerState<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends ConsumerState<_ReelPage> {
  VideoPlayerController? _video;
  bool _paused = false;
  bool _viewed = false;
  bool _heart = false;

  @override
  void initState() {
    super.initState();
    final url = widget.post.video?.url;
    if (url != null) {
      _video = VideoPlayerController.networkUrl(Uri.parse(url))
        ..setLooping(true)
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {});
          _sync();
        });
    }
  }

  @override
  void didUpdateWidget(_ReelPage old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    video.setVolume(widget.muted ? 0 : 1);
    if (widget.active && !_paused) {
      video.play();
      if (!_viewed) {
        _viewed = true;
        unawaited(ref.read(postRepositoryProvider).recordView(widget.post.id).catchError((_) {}));
      }
    } else {
      video.pause();
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _like() async {
    HapticFeedback.lightImpact();
    final post = ref.read(postPatchesProvider)[widget.post.id]?.apply(widget.post) ?? widget.post;
    try {
      await ref.read(postActionsProvider).react(post, post.myReaction == null ? Reaction.like : post.myReaction);
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = ref.livePost(widget.post);
    final video = _video;
    return GestureDetector(
      onTap: () {
        setState(() => _paused = !_paused);
        _sync();
      },
      onDoubleTap: () async {
        setState(() => _heart = true);
        if (post.myReaction == null) await _like();
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (mounted) setState(() => _heart = false);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (video != null && video.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(width: video.value.size.width, height: video.value.size.height, child: VideoPlayer(video)),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66000000), Colors.transparent, Colors.transparent, Color(0xAA000000)],
                stops: [0, 0.18, 0.6, 1],
              ),
            ),
          ),
          if (_paused) const Center(child: Icon(AppIcons.play, color: Colors.white70, size: 72)),
          if (_heart) const Center(child: Icon(AppIcons.heartFill, color: Colors.white, size: 110)),
          Positioned(
            left: Space.gutter,
            right: 84,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: post.author.isAnonymous ? null : () => context.push('/u/${post.author.username}'),
                  child: Row(
                    children: [
                      AuthorAvatar(user: post.author, size: 34),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(post.author.fullName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    ],
                  ),
                ),
                if (post.community != null) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => context.push('/c/${post.community!.slug}'),
                    child: Text('in ${post.community!.name}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
                ],
                if (post.body != null) ...[
                  const SizedBox(height: 8),
                  Text(post.body!, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35)),
                ],
                const SizedBox(height: 6),
                Text('${compactCount(post.viewsCount)} views · ${timeAgo(post.createdAt)}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          Positioned(
            right: 8,
            bottom: 24,
            child: Column(
              children: [
                _RailButton(
                  icon: post.myReaction != null ? AppIcons.heartFill : AppIcons.heart,
                  color: post.myReaction != null ? const Color(0xFFFF4F2B) : Colors.white,
                  label: compactCount(post.likesCount),
                  onTap: _like,
                ),
                _RailButton(icon: AppIcons.comment, label: compactCount(post.commentsCount), onTap: () => context.push('/post/${post.id}')),
                _RailButton(icon: AppIcons.share, label: 'Share', onTap: () => showShareSheet(context, ref, post)),
                _RailButton(
                  icon: post.isSaved ? AppIcons.bookmarkFill : AppIcons.bookmark,
                  label: 'Save',
                  onTap: () => ref.read(postActionsProvider).toggleSave(post).catchError((Object e) {
                    if (context.mounted) showToast(context, friendlyError(e), error: true);
                  }),
                ),
                _RailButton(icon: widget.muted ? AppIcons.volumeOff : AppIcons.volumeOn, label: widget.muted ? 'Muted' : 'Sound', onTap: widget.onToggleMute),
                _RailButton(icon: AppIcons.more, label: '', onTap: () => showPostMenu(context, ref, post)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.icon, required this.label, required this.onTap, this.color = Colors.white});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        child: Column(
          children: [
            Icon(icon, color: color, size: 30, shadows: const [Shadow(blurRadius: 8, color: Colors.black45)]),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}
