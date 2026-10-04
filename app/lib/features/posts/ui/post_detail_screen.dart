import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/rich_body.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/states.dart';
import '../../communities/providers.dart';
import '../../moderation/data/moderation_repository.dart';
import '../../moderation/ui/report_sheet.dart';
import '../../profile/providers.dart';
import '../data/post.dart';
import '../providers.dart';
import 'post_card.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  Comment? _replyTo;
  bool _sending = false;
  bool _anonymous = false;
  bool _newestFirst = false;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _reply(Comment comment) {
    setState(() => _replyTo = comment);
    _focus.requestFocus();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final private = ref.read(myProfileProvider).value?.isPrivate ?? false;
      await ref
          .read(commentsProvider(widget.postId).notifier)
          .add(text, parentId: _replyTo?.id, anonymous: _anonymous || private);
      _input.clear();
      setState(() => _replyTo = null);
      HapticFeedback.lightImpact();
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = ref.watch(postProvider(widget.postId));
    final comments = ref.watch(commentsProvider(widget.postId));
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        title: Text(post.value?.community?.name ?? 'Post'),
        shape: Border(bottom: BorderSide(color: c.line)),
      ),
      body: post.when(
        loading: () => const Skeleton(child: PostSkeleton(withMedia: true)),
        error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(postProvider(widget.postId))),
        data: (data) {
          if (data == null) {
            return const EmptyState(
              icon: AppIcons.eyeSlash,
              title: 'Post not available',
              message: 'It may have been deleted or is only visible to members.',
            );
          }
          final live = ref.livePost(data);
          final community = data.community == null ? null : ref.watch(communityProvider(data.community!.slug)).value;
          final isMod = community?.isMod ?? false;
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  color: c.ink,
                  onRefresh: () async {
                    ref.invalidate(postProvider(widget.postId));
                    ref.invalidate(commentsProvider(widget.postId));
                  },
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: PostCard(post: data, inDetail: true, isMod: isMod),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, 8, 4),
                          child: Row(
                            children: [
                              Text('Comments', style: context.text.headlineSmall),
                              const SizedBox(width: 8),
                              Text(
                                compactCount(live.commentsCount),
                                style: context.text.titleMedium!.copyWith(color: c.inkSubtle),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () => setState(() => _newestFirst = !_newestFirst),
                                icon: const Icon(AppIcons.filter, size: 16),
                                label: Text(_newestFirst ? 'Newest' : 'Top'),
                                style: TextButton.styleFrom(
                                  foregroundColor: c.inkMuted,
                                  textStyle: context.text.labelMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      comments.when(
                        loading: () => const SliverToBoxAdapter(child: ListSkeleton(count: 3)),
                        error: (error, _) => SliverToBoxAdapter(
                          child: ErrorState(
                            error: error,
                            compact: true,
                            onRetry: () => ref.invalidate(commentsProvider(widget.postId)),
                          ),
                        ),
                        data: (list) {
                          if (list.isEmpty) {
                            return const SliverToBoxAdapter(
                              child: EmptyState(
                                icon: AppIcons.comment,
                                title: 'No comments yet',
                                message: 'Start the conversation.',
                                compact: true,
                              ),
                            );
                          }
                          final ordered = _thread(list, newestFirst: _newestFirst);
                          return SliverList.builder(
                            itemCount: ordered.length,
                            itemBuilder: (_, i) => _CommentTile(
                              comment: ordered[i],
                              postId: widget.postId,
                              isMod: isMod,
                              onReply: live.isLocked ? null : () => _reply(ordered[i]),
                            ),
                          );
                        },
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
                ),
              ),
              if (live.isLocked && !isMod)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + context.safePadding.bottom),
                  color: c.surfaceMuted,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(AppIcons.lock, size: 16, color: c.inkMuted),
                      const SizedBox(width: 6),
                      Text('Comments are turned off', style: context.text.bodySmall),
                    ],
                  ),
                )
              else
                _CommentComposer(
                  controller: _input,
                  focusNode: _focus,
                  replyTo: _replyTo,
                  sending: _sending,
                  anonymous: _anonymous,
                  onAnonymousChanged: (value) => setState(() => _anonymous = value),
                  onCancelReply: () => setState(() => _replyTo = null),
                  onSend: _send,
                ),
            ],
          );
        },
      ),
    );
  }

  /// Flattens the comment tree depth-first. Top-level comments are ordered
  /// by likes (or newest), replies oldest first so conversations read in order.
  List<Comment> _thread(List<Comment> comments, {required bool newestFirst}) {
    final ids = {for (final c in comments) c.id};
    final children = <String?, List<Comment>>{};
    for (final comment in comments) {
      final parent = comment.parentId != null && ids.contains(comment.parentId) ? comment.parentId : null;
      children.putIfAbsent(parent, () => []).add(comment);
    }
    final roots = children[null] ?? [];
    roots.sort(
      (a, b) => newestFirst
          ? b.createdAt.compareTo(a.createdAt)
          : (b.likesCount + b.repliesCount).compareTo(a.likesCount + a.repliesCount) != 0
          ? (b.likesCount + b.repliesCount).compareTo(a.likesCount + a.repliesCount)
          : a.createdAt.compareTo(b.createdAt),
    );
    final out = <Comment>[];
    void visit(Comment comment) {
      out.add(comment);
      final replies = children[comment.id] ?? [];
      replies.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      replies.forEach(visit);
    }

    roots.forEach(visit);
    return out;
  }
}

class _CommentTile extends ConsumerWidget {
  const _CommentTile({required this.comment, required this.postId, required this.isMod, required this.onReply});

  final Comment comment;
  final String postId;
  final bool isMod;
  final VoidCallback? onReply;

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final mine = comment.isMine;
    final notifier = ref.read(commentsProvider(postId).notifier);
    await showActionSheet(
      context,
      actions: [
        SheetAction(
          icon: AppIcons.copy,
          label: 'Copy text',
          onTap: () => Clipboard.setData(ClipboardData(text: comment.body ?? '')),
        ),
        if (mine)
          SheetAction(
            icon: AppIcons.edit,
            label: 'Edit',
            onTap: () async {
              final body = await _editDialog(context, comment.body ?? '');
              if (body == null || body.trim().isEmpty) return;
              try {
                await notifier.edit(comment, body.trim());
              } catch (error) {
                if (context.mounted) showToast(context, friendlyError(error), error: true);
              }
            },
          ),
        if (mine || isMod)
          SheetAction(
            icon: AppIcons.trash,
            label: 'Delete',
            destructive: true,
            onTap: () async {
              try {
                await notifier.remove(comment);
              } catch (error) {
                if (context.mounted) showToast(context, friendlyError(error), error: true);
              }
            },
          ),
        if (!mine && isMod)
          SheetAction(
            icon: AppIcons.shield,
            label: 'Remove as moderator',
            destructive: true,
            onTap: () async {
              try {
                await ref
                    .read(moderationRepositoryProvider)
                    .moderate(targetType: 'comment', targetId: comment.id, action: 'remove');
                ref.invalidate(commentsProvider(postId));
              } catch (error) {
                if (context.mounted) showToast(context, friendlyError(error), error: true);
              }
            },
          ),
        if (!mine)
          SheetAction(
            icon: AppIcons.flag,
            label: 'Report',
            destructive: true,
            onTap: () => showReportSheet(context, targetType: 'comment', targetId: comment.id, what: 'comment'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final depth = comment.depth.clamp(0, 5);
    final author = comment.author;
    return Padding(
      padding: EdgeInsets.only(left: Space.gutter + depth * 18.0, right: 8),
      child: Container(
        decoration: depth > 0
            ? BoxDecoration(
                border: Border(left: BorderSide(color: c.line, width: 2)),
              )
            : null,
        padding: EdgeInsets.only(left: depth > 0 ? 12 : 0, top: 10, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: author == null || author.isAnonymous ? null : () => context.push('/u/${author.username}'),
              child: author == null
                  ? CircleAvatar(radius: 14, backgroundColor: c.surfaceMuted)
                  : AuthorAvatar(user: author, size: 28),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: author == null
                            ? Text(
                                comment.isRemoved ? 'Removed' : 'Deleted',
                                style: context.text.labelMedium!.copyWith(color: c.inkSubtle),
                              )
                            : NameLine(
                                name: comment.isMine && author.isAnonymous
                                    ? '${author.fullName} (you)'
                                    : author.fullName,
                                verified: author.isVerified,
                                style: context.text.labelLarge!.copyWith(
                                  fontSize: 14,
                                  color: author.isAnonymous ? c.inkMuted : null,
                                ),
                              ),
                      ),
                      Text(
                        '  ${timeAgo(comment.createdAt)}${comment.editedAt != null ? ' · edited' : ''}',
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (comment.isGone)
                    Text(
                      comment.isRemoved ? 'Removed by moderators' : 'This comment was deleted',
                      style: context.text.bodyMedium!.copyWith(color: c.inkSubtle, fontStyle: FontStyle.italic),
                    )
                  else
                    RichBody(comment.body ?? '', maxLines: 10),
                  if (!comment.isGone)
                    Row(
                      children: [
                        Pressable(
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            try {
                              await ref.read(commentsProvider(postId).notifier).toggleLike(comment);
                            } catch (error) {
                              if (context.mounted) showToast(context, friendlyError(error), error: true);
                            }
                          },
                          semanticLabel: comment.likedByMe ? 'Unlike comment' : 'Like comment',
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                            child: Row(
                              children: [
                                Icon(
                                  comment.likedByMe ? AppIcons.heartFill : AppIcons.heart,
                                  size: 16,
                                  color: comment.likedByMe ? c.accent : c.inkSubtle,
                                ),
                                if (comment.likesCount > 0) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '${comment.likesCount}',
                                    style: context.text.labelSmall!.copyWith(color: c.inkMuted),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        if (onReply != null)
                          Pressable(
                            onTap: onReply,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                              child: Text('Reply', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
                            ),
                          ),
                        const Spacer(),
                        Pressable(
                          onTap: () => _menu(context, ref),
                          semanticLabel: 'Comment options',
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(AppIcons.more, size: 18, color: c.inkSubtle),
                          ),
                        ),
                      ],
                    )
                  else
                    const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _editDialog(BuildContext context, String initial) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Edit comment'),
      content: TextField(controller: controller, maxLines: 5, minLines: 2, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text), child: const Text('Save')),
      ],
    ),
  ).whenComplete(controller.dispose);
}

class _CommentComposer extends ConsumerWidget {
  const _CommentComposer({
    required this.controller,
    required this.focusNode,
    required this.replyTo,
    required this.sending,
    required this.anonymous,
    required this.onAnonymousChanged,
    required this.onCancelReply,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Comment? replyTo;
  final bool sending;
  final bool anonymous;
  final ValueChanged<bool> onAnonymousChanged;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final me = ref.watch(myProfileProvider).value;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      padding: EdgeInsets.fromLTRB(12, 8, 8, 8 + context.safePadding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyTo != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Row(
                children: [
                  Icon(AppIcons.reply, size: 14, color: c.inkMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Replying to ${replyTo!.author?.fullName ?? 'comment'}',
                      style: context.text.labelMedium!.copyWith(color: c.inkMuted),
                    ),
                  ),
                  GestureDetector(
                    onTap: onCancelReply,
                    child: Icon(AppIcons.close, size: 16, color: c.inkMuted),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (me != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Tooltip(
                    message: me.isPrivate
                        ? 'Your profile is private, so comments are always anonymous'
                        : (anonymous ? 'Commenting anonymously (tap to switch)' : 'Tap to comment anonymously'),
                    child: InkResponse(
                      onTap: me.isPrivate
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              onAnonymousChanged(!anonymous);
                            },
                      radius: 22,
                      child: me.isPrivate || anonymous
                          ? const AnonymousAvatar(alias: 'me', size: 34)
                          : UserAvatar(name: me.fullName, url: me.avatarUrl, size: 34),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  style: context.text.bodyMedium,
                  decoration: InputDecoration(
                    hintText: (me?.isPrivate ?? false) || anonymous
                        ? (replyTo == null ? 'Comment anonymously…' : 'Reply anonymously…')
                        : (replyTo == null ? 'Add a comment…' : 'Write a reply…'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(color: c.lineStrong),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => IconButton(
                  tooltip: 'Send',
                  onPressed: sending || controller.text.trim().isEmpty ? null : onSend,
                  icon: sending
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(AppIcons.send, color: controller.text.trim().isEmpty ? c.inkSubtle : c.accent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
