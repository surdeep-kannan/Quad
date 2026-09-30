import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/refs.dart';
import '../../../core/data/supabase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/rich_body.dart';
import '../../../core/widgets/sheets.dart';
import '../../chat/data/chat_models.dart';
import '../../chat/data/chat_repository.dart';
import '../../chat/providers.dart';
import '../../events/ui/event_poster.dart';
import '../../moderation/data/moderation_repository.dart';
import '../../moderation/ui/report_sheet.dart';
import '../../profile/data/profile.dart';
import '../data/post.dart';
import '../providers.dart';

/// A post in a feed. Tapping opens the discussion.
class PostCard extends ConsumerWidget {
  const PostCard({super.key, required this.post, this.showCommunity = true, this.isMod = false, this.inDetail = false});

  final Post post;
  final bool showCommunity;

  /// Whether the viewer moderates the community this post is in.
  final bool isMod;
  final bool inDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isPostDeletedProvider(post.id))) return const SizedBox.shrink();
    final live = ref.livePost(post);
    final c = context.colors;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PostHeader(post: live, showCommunity: showCommunity, isMod: isMod),
        if (live.isRemoved) _RemovedNote(reason: live.removedReason),
        if (_typeLabel(live.type) != null) ...[
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: _TypeBadge(type: live.type)),
        ],
        if (live.title != null) ...[
          const SizedBox(height: 8),
          Text(
            live.title!,
            style: context.text.titleMedium!.copyWith(fontSize: inDetail ? 19 : 17, height: 1.3, fontWeight: FontWeight.w700),
          ),
        ],
        if (live.body != null) ...[
          SizedBox(height: live.title != null ? 6 : 8),
          RichBody(live.body!, maxLines: inDetail ? null : 6, style: context.text.bodyMedium),
        ],
        if (live.images.isNotEmpty) ...[
          const SizedBox(height: 12),
          MediaGrid(media: live.images),
        ],
        if (live.type == PostType.poll && live.pollOptions.isNotEmpty) ...[
          const SizedBox(height: 12),
          PollView(post: live),
        ],
        if (live.event != null) ...[
          const SizedBox(height: 12),
          _EventAttachment(event: live.event!),
        ],
        if (live.tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: [
              for (final tag in live.tags.take(4))
                GestureDetector(
                  onTap: () => context.push('/search?q=${Uri.encodeComponent(tag)}'),
                  child: Text('#$tag', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        PostActionBar(post: live, onComment: inDetail ? null : () => context.push('/post/${live.id}')),
      ],
    );

    return Material(
      color: live.type == PostType.announcement ? c.accentSoft.withValues(alpha: context.isDark ? 0.35 : 0.5) : c.surface,
      child: InkWell(
        onTap: inDetail ? null : () => context.push('/post/${live.id}'),
        child: Container(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 14, Space.gutter, 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
          child: content,
        ),
      ),
    );
  }
}

String? _typeLabel(PostType type) => switch (type) {
      PostType.question || PostType.announcement || PostType.achievement || PostType.poll || PostType.event => type.label,
      _ => null,
    };

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final PostType type;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (fg, bg) = switch (type) {
      PostType.announcement => (c.accentInk, c.accentSoft),
      PostType.achievement => (c.warning, c.warningSoft),
      PostType.question => (c.success, c.successSoft),
      _ => (c.inkMuted, c.surfaceMuted),
    };
    return Tag(label: type.label, icon: type.icon, color: fg, background: bg);
  }
}

class _RemovedNote extends StatelessWidget {
  const _RemovedNote({this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(Radii.sm)),
      child: Row(
        children: [
          Icon(AppIcons.eyeSlash, size: 16, color: c.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Hidden from others. ${reason ?? 'Removed by moderators'}',
              style: context.text.bodySmall!.copyWith(color: c.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostHeader extends ConsumerWidget {
  const _PostHeader({required this.post, required this.showCommunity, required this.isMod});

  final Post post;
  final bool showCommunity;
  final bool isMod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final community = post.community;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => context.push('/u/${post.author.username}'),
          child: UserAvatar(name: post.author.fullName, url: post.author.avatarUrl, size: 40),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: GestureDetector(
                      onTap: () => context.push('/u/${post.author.username}'),
                      child: NameLine(name: post.author.fullName, verified: post.author.isVerified),
                    ),
                  ),
                  Text('  ·  ${timeAgo(post.createdAt)}', style: context.text.bodySmall),
                  if (post.isPinned) ...[
                    const SizedBox(width: 6),
                    Icon(AppIcons.pin, size: 14, color: c.accent, semanticLabel: 'Pinned'),
                  ],
                ],
              ),
              const SizedBox(height: 1),
              if (showCommunity && community != null)
                GestureDetector(
                  onTap: () => context.push('/c/${community.slug}'),
                  child: Row(
                    children: [
                      CommunityAvatar(name: community.name, color: community.color, url: community.avatarUrl, size: 16),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          community.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelMedium!.copyWith(color: c.inkMuted),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text('@${post.author.username}', style: context.text.bodySmall),
            ],
          ),
        ),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: 'More',
            icon: Icon(AppIcons.more, color: c.inkMuted, size: 22),
            onPressed: () => showPostMenu(context, ref, post, isMod: isMod),
          ),
        ),
      ],
    );
  }
}

/// Image layouts for 1-4+ photos, like a chat app's photo grid.
class MediaGrid extends StatelessWidget {
  const MediaGrid({super.key, required this.media});

  final List<MediaItem> media;

  void _open(BuildContext context, int index) {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => _PhotoViewer(media: media, initial: index),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget tile(int i, {double? aspect}) {
      final image = GestureDetector(
        onTap: () => _open(context, i),
        child: AppImage(media[i].url, semanticLabel: 'Photo ${i + 1} of ${media.length}'),
      );
      return aspect == null ? image : AspectRatio(aspectRatio: aspect, child: image);
    }

    const gap = 3.0;
    final Widget grid = switch (media.length) {
      1 => tile(0, aspect: (media[0].aspectRatio ?? 4 / 3).clamp(0.8, 1.91)),
      2 => Row(children: [Expanded(child: tile(0, aspect: 0.9)), const SizedBox(width: gap), Expanded(child: tile(1, aspect: 0.9))]),
      3 => AspectRatio(
          aspectRatio: 1.25,
          child: Row(
            children: [
              Expanded(flex: 3, child: SizedBox.expand(child: tile(0))),
              const SizedBox(width: gap),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    Expanded(child: SizedBox.expand(child: tile(1))),
                    const SizedBox(height: gap),
                    Expanded(child: SizedBox.expand(child: tile(2))),
                  ],
                ),
              ),
            ],
          ),
        ),
      _ => AspectRatio(
          aspectRatio: 1,
          child: Column(
            children: [
              for (final row in [0, 2]) ...[
                if (row == 2) const SizedBox(height: gap),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: SizedBox.expand(child: tile(row))),
                      const SizedBox(width: gap),
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            tile(row + 1),
                            if (row == 2 && media.length > 4)
                              IgnorePointer(
                                child: ColoredBox(
                                  color: Colors.black45,
                                  child: Center(
                                    child: Text(
                                      '+${media.length - 4}',
                                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
    };
    return ClipRRect(borderRadius: BorderRadius.circular(Radii.md), child: grid);
  }
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.media, required this.initial});

  final List<MediaItem> media;
  final int initial;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final _controller = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.media.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => InteractiveViewer(
              maxScale: 4,
              child: Center(child: AppImage(widget.media[i].url, fit: BoxFit.contain, placeholderColor: Colors.black)),
            ),
          ),
          SafeArea(
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(AppIcons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                if (widget.media.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text('${_index + 1} / ${widget.media.length}', style: const TextStyle(color: Colors.white)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Poll options. Before voting they're buttons; after, they show results.
class PollView extends ConsumerWidget {
  const PollView({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final voted = post.myVote != null;
    final showResults = voted || post.pollClosed;
    final total = post.totalVotes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in post.pollOptions)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Pressable(
              scale: 0.985,
              onTap: post.pollClosed
                  ? null
                  : () async {
                      HapticFeedback.selectionClick();
                      try {
                        await ref.read(postActionsProvider).vote(post, option.id);
                      } catch (error) {
                        if (context.mounted) showToast(context, friendlyError(error), error: true);
                      }
                    },
              semanticLabel: showResults
                  ? '${option.label}, ${total == 0 ? 0 : (option.votes * 100 / total).round()} percent'
                  : 'Vote ${option.label}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.md - 2),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    border: Border.all(color: option.id == post.myVote ? c.ink : c.line, width: option.id == post.myVote ? 1.5 : 1),
                    borderRadius: BorderRadius.circular(Radii.md - 2),
                  ),
                  child: Stack(
                    children: [
                      if (showResults)
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: total == 0 ? 0 : option.votes / total),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          builder: (_, value, _) => FractionallySizedBox(
                            widthFactor: value,
                            child: Container(color: option.id == post.myVote ? c.accentSoft : c.surfaceMuted),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                option.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.titleSmall!.copyWith(
                                  fontWeight: option.id == post.myVote ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (option.id == post.myVote) ...[
                              Icon(AppIcons.checkCircle, size: 16, color: c.accent),
                              const SizedBox(width: 6),
                            ],
                            if (showResults)
                              Text(
                                '${total == 0 ? 0 : (option.votes * 100 / total).round()}%',
                                style: context.text.labelMedium,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Text(
          [
            plural(total, 'vote'),
            if (post.pollClosed) 'Final results' else if (post.pollEndsAt != null) 'Ends ${eventCountdown(post.pollEndsAt!, post.pollEndsAt).toLowerCase()}',
          ].join(' · '),
          style: context.text.bodySmall,
        ),
      ],
    );
  }
}

class _EventAttachment extends StatelessWidget {
  const _EventAttachment({required this.event});

  final EventSummary event;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: () => context.push('/event/${event.id}'),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.md + 2),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: EventPoster(
                title: event.title,
                startsAt: event.startsAt,
                category: event.category,
                imageUrl: event.posterUrl,
                theme: event.posterTheme,
                radius: Radii.sm,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eventWhen(event.startsAt).toUpperCase(),
                    style: context.text.labelSmall!.copyWith(color: c.accentInk),
                  ),
                  const SizedBox(height: 4),
                  Text(event.title, style: context.text.titleSmall!.copyWith(fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (event.mode == 'online') 'Online' else ?event.venue,
                      plural(event.registrationsCount, 'person going', 'people going'),
                    ].join(' · '),
                    style: context.text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(AppIcons.forward, color: c.inkSubtle, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Like/react, comment, share and save.
class PostActionBar extends ConsumerWidget {
  const PostActionBar({super.key, required this.post, this.onComment, this.dark = false});

  final Post post;
  final VoidCallback? onComment;
  final bool dark;

  Future<void> _react(BuildContext context, WidgetRef ref, Reaction? reaction) async {
    HapticFeedback.lightImpact();
    try {
      await ref.read(postActionsProvider).react(post, reaction);
    } catch (error) {
      if (context.mounted) showToast(context, friendlyError(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final muted = dark ? Colors.white : c.inkMuted;
    final reacted = post.myReaction != null;

    Widget action({required Widget icon, String? count, required String label, VoidCallback? onTap, VoidCallback? onLongPress}) {
      return Pressable(
        onTap: onTap,
        onLongPress: onLongPress,
        scale: 0.92,
        semanticLabel: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              if (count != null) ...[
                const SizedBox(width: 5),
                Text(count, style: context.text.labelMedium!.copyWith(color: muted, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      );
    }

    final reactionIcon = switch (post.myReaction) {
      null => Icon(AppIcons.heart, size: 22, color: muted),
      Reaction.like => Icon(AppIcons.heartFill, size: 22, color: c.accent),
      final r => Text(r.emoji, style: const TextStyle(fontSize: 18)),
    };

    return Row(
      children: [
        Builder(
          builder: (buttonContext) => action(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
              child: KeyedSubtree(key: ValueKey(post.myReaction), child: reactionIcon),
            ),
            count: post.likesCount > 0 ? compactCount(post.likesCount) : null,
            label: reacted ? 'Remove reaction, ${post.likesCount} reactions' : 'Like, ${post.likesCount} reactions',
            onTap: () => _react(context, ref, reacted ? post.myReaction : Reaction.like),
            onLongPress: () async {
              final picked = await showReactionPicker(buttonContext);
              if (picked != null && context.mounted) await _react(context, ref, picked);
            },
          ),
        ),
        const SizedBox(width: 8),
        action(
          icon: Icon(AppIcons.comment, size: 22, color: muted),
          count: post.commentsCount > 0 ? compactCount(post.commentsCount) : null,
          label: '${post.commentsCount} comments',
          onTap: onComment,
        ),
        const SizedBox(width: 8),
        action(
          icon: Icon(AppIcons.share, size: 21, color: muted),
          label: 'Share',
          onTap: () => showShareSheet(context, ref, post),
        ),
        const Spacer(),
        if (post.topReactions.length > 1 || (post.topReactions.isNotEmpty && post.topReactions.first != Reaction.like))
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(post.topReactions.map((r) => r.emoji).join(), style: const TextStyle(fontSize: 13)),
          ),
        action(
          icon: Icon(post.isSaved ? AppIcons.bookmarkFill : AppIcons.bookmark, size: 22, color: post.isSaved ? (dark ? Colors.white : c.ink) : muted),
          label: post.isSaved ? 'Unsave' : 'Save',
          onTap: () async {
            HapticFeedback.selectionClick();
            try {
              await ref.read(postActionsProvider).toggleSave(post);
              if (context.mounted && !post.isSaved) showToast(context, 'Saved. Find it in your profile.', icon: AppIcons.bookmarkFill);
            } catch (error) {
              if (context.mounted) showToast(context, friendlyError(error), error: true);
            }
          },
        ),
      ],
    );
  }
}

/// A floating row of reactions above [anchor]. Returns the one picked.
Future<Reaction?> showReactionPicker(BuildContext anchor) {
  final box = anchor.findRenderObject() as RenderBox?;
  final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
  return showGeneralDialog<Reaction>(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'Close reactions',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, _, _) {
      final c = context.colors;
      return Stack(
        children: [
          Positioned(
            left: (origin.dx - 8).clamp(8.0, MediaQuery.sizeOf(context).width - 280),
            top: (origin.dy - 62).clamp(40.0, double.infinity),
            child: Material(
              color: c.surface,
              elevation: 8,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(30),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final reaction in Reaction.values)
                      Tooltip(
                        message: reaction.label,
                        child: InkResponse(
                          onTap: () => Navigator.of(context).pop(reaction),
                          radius: 24,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(reaction.emoji, style: const TextStyle(fontSize: 26)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (_, animation, _, child) => ScaleTransition(
      scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
      alignment: Alignment.bottomLeft,
      child: child,
    ),
  );
}

String _postLink(Post post) => kIsWeb ? '${Uri.base.origin}/#/post/${post.id}' : 'quad://post/${post.id}';

/// Send a post to a chat, copy its link or share it outside the app.
Future<void> showShareSheet(BuildContext context, WidgetRef ref, Post post) {
  return showAppSheet<void>(
    context,
    builder: (sheetContext) => _ShareSheet(post: post),
  );
}

class _ShareSheet extends ConsumerWidget {
  const _ShareSheet({required this.post});

  final Post post;

  Future<void> _sendTo(BuildContext context, WidgetRef ref, Conversation conversation) async {
    Navigator.of(context).pop();
    try {
      final message = Message(
        id: const Uuid().v4(),
        conversationId: conversation.id,
        senderId: ref.read(supabaseProvider).uid,
        kind: 'post',
        sharedPostId: post.id,
        body: post.title ?? post.body,
        createdAt: DateTime.now(),
      );
      await ref.read(chatRepositoryProvider).send(message);
      await ref.read(postActionsProvider).shared(post);
      if (context.mounted) showToast(context, 'Sent to ${conversation.displayName}');
    } catch (error) {
      if (context.mounted) showToast(context, friendlyError(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(chatListProvider).value ?? const [];
    final recent = conversations.where((c) => !c.isRoom).take(8).toList();
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
            child: Text('Share post', style: context.text.titleMedium),
          ),
          if (recent.isNotEmpty)
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                itemCount: recent.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final conversation = recent[i];
                  return Pressable(
                    onTap: () => _sendTo(context, ref, conversation),
                    child: SizedBox(
                      width: 68,
                      child: Column(
                        children: [
                          UserAvatar(
                            name: conversation.displayName,
                            url: conversation.otherUser?.avatarUrl ?? conversation.avatarUrl,
                            size: 52,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            conversation.isDirect ? conversation.otherUser!.firstName : conversation.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(AppIcons.link),
            title: const Text('Copy link'),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: _postLink(post)));
              if (context.mounted) {
                Navigator.of(context).pop();
                showToast(context, 'Link copied');
              }
              await ref.read(postActionsProvider).shared(post).catchError((_) {});
            },
          ),
          ListTile(
            leading: const Icon(AppIcons.share),
            title: const Text('Share outside Quad'),
            onTap: () async {
              Navigator.of(context).pop();
              final text = [post.title ?? post.body ?? 'A post on Quad', _postLink(post)].join('\n\n');
              await SharePlus.instance.share(ShareParams(text: text, subject: post.title));
              await ref.read(postActionsProvider).shared(post).catchError((_) {});
            },
          ),
          const SizedBox(height: Space.sm),
        ],
      ),
    );
  }
}

/// The "..." menu on a post.
Future<void> showPostMenu(BuildContext context, WidgetRef ref, Post post, {bool isMod = false}) {
  final mine = post.author.id == ref.read(supabaseProvider).uid;
  final actions = ref.read(postActionsProvider);

  Future<void> run(Future<void> Function() action, [String? done]) async {
    try {
      await action();
      if (done != null && context.mounted) showToast(context, done);
    } catch (error) {
      if (context.mounted) showToast(context, friendlyError(error), error: true);
    }
  }

  Future<void> moderate(String action, {String? reason}) => run(() async {
        await ref.read(moderationRepositoryProvider).moderate(
              targetType: 'post',
              targetId: post.id,
              action: action,
              reason: reason,
            );
        actions.moderated(post.id, action);
      }, switch (action) {
        'pin' => 'Pinned to the top',
        'unpin' => 'Unpinned',
        'lock' => 'Comments turned off',
        'unlock' => 'Comments turned on',
        'remove' => 'Post removed',
        _ => 'Post restored',
      });

  return showActionSheet(
    context,
    actions: [
      SheetAction(
        icon: post.isFollowing ? AppIcons.mute : AppIcons.followPost,
        label: post.isFollowing ? 'Stop following discussion' : 'Follow discussion',
        subtitle: post.isFollowing ? null : 'Get notified about new comments',
        onTap: () => run(() => actions.toggleFollow(post)),
      ),
      SheetAction(
        icon: post.isSaved ? AppIcons.bookmarkFill : AppIcons.bookmark,
        label: post.isSaved ? 'Remove from saved' : 'Save',
        onTap: () => run(() => actions.toggleSave(post)),
      ),
      SheetAction(icon: AppIcons.link, label: 'Copy link', onTap: () => Clipboard.setData(ClipboardData(text: _postLink(post)))),
      if (isMod && post.community != null) ...[
        SheetAction(
          icon: AppIcons.pinOutline,
          label: post.isPinned ? 'Unpin' : 'Pin to top',
          onTap: () => moderate(post.isPinned ? 'unpin' : 'pin'),
        ),
        SheetAction(
          icon: AppIcons.lock,
          label: post.isLocked ? 'Turn comments on' : 'Turn comments off',
          onTap: () => moderate(post.isLocked ? 'unlock' : 'lock'),
        ),
        if (!mine)
          SheetAction(
            icon: AppIcons.shield,
            label: post.isRemoved ? 'Restore post' : 'Remove post',
            destructive: !post.isRemoved,
            onTap: () async {
              if (post.isRemoved) return moderate('restore');
              final ok = await confirm(
                context,
                title: 'Remove this post?',
                message: 'It will be hidden from everyone except the author and moderators.',
                confirmLabel: 'Remove',
                destructive: true,
              );
              if (ok) await moderate('remove');
            },
          ),
      ],
      if (mine)
        SheetAction(
          icon: AppIcons.trash,
          label: 'Delete post',
          destructive: true,
          onTap: () async {
            final ok = await confirm(
              context,
              title: 'Delete post?',
              message: 'This removes the post and its comments for everyone.',
              confirmLabel: 'Delete',
              destructive: true,
            );
            if (ok) await run(() => actions.delete(post), 'Post deleted');
          },
        )
      else
        SheetAction(
          icon: AppIcons.flag,
          label: 'Report post',
          destructive: true,
          onTap: () => showReportSheet(context, targetType: 'post', targetId: post.id, what: 'post'),
        ),
    ],
  );
}

/// A compact row for a person, used in lists.
class PersonRow extends StatelessWidget {
  const PersonRow({super.key, required this.user, this.subtitle, this.trailing, this.onTap, this.online = false});

  final UserRef user;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool online;

  factory PersonRow.profile(Profile profile, {Widget? trailing, VoidCallback? onTap}) => PersonRow(
        user: profile.ref,
        subtitle: profile.academicLine.isEmpty ? '@${profile.username}' : profile.academicLine,
        trailing: trailing,
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap ?? () => context.push('/u/${user.username}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: 10),
        child: Row(
          children: [
            UserAvatar(name: user.fullName, url: user.avatarUrl, size: 44, online: online),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NameLine(name: user.fullName, verified: user.isVerified),
                  if (subtitle != null)
                    Text(subtitle!, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
