import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/paged.dart';
import 'data/post.dart';
import 'data/post_repository.dart';

/// What the student changed on a post locally, applied on top of whatever
/// copy of the post a screen has. Counts are adjusted relative to that copy,
/// so a fresh server copy that already includes the change isn't counted twice.
class PostPatch {
  const PostPatch({
    this.reactionSet = false,
    this.reaction,
    this.saved,
    this.following,
    this.vote,
    this.commentsCount,
    this.deleted = false,
    this.pinned,
    this.locked,
    this.removed,
    this.title,
    this.body,
    this.shared = false,
  });

  final bool reactionSet;
  final Reaction? reaction;
  final bool? saved;
  final bool? following;
  final String? vote;
  final int? commentsCount;
  final bool deleted;
  final bool? pinned;
  final bool? locked;
  final bool? removed;
  final String? title;
  final String? body;
  final bool shared;

  PostPatch copyWith({
    bool? reactionSet,
    Reaction? reaction,
    bool clearReaction = false,
    bool? saved,
    bool? following,
    String? vote,
    int? commentsCount,
    bool? deleted,
    bool? pinned,
    bool? locked,
    bool? removed,
    String? title,
    String? body,
    bool? shared,
  }) {
    return PostPatch(
      reactionSet: reactionSet ?? this.reactionSet,
      reaction: clearReaction ? null : (reaction ?? this.reaction),
      saved: saved ?? this.saved,
      following: following ?? this.following,
      vote: vote ?? this.vote,
      commentsCount: commentsCount ?? this.commentsCount,
      deleted: deleted ?? this.deleted,
      pinned: pinned ?? this.pinned,
      locked: locked ?? this.locked,
      removed: removed ?? this.removed,
      title: title ?? this.title,
      body: body ?? this.body,
      shared: shared ?? this.shared,
    );
  }

  Post apply(Post base) {
    var post = base;
    if (reactionSet) {
      final counts = Map<String, int>.of(base.reactionCounts);
      if (base.myReaction != null) {
        counts[base.myReaction!.key] = math.max(0, (counts[base.myReaction!.key] ?? 1) - 1);
      }
      if (reaction != null) counts[reaction!.key] = (counts[reaction!.key] ?? 0) + 1;
      final delta = (reaction != null ? 1 : 0) - (base.myReaction != null ? 1 : 0);
      post = post.copyWith(
        myReaction: reaction,
        clearReaction: reaction == null,
        reactionCounts: counts,
        likesCount: math.max(0, base.likesCount + delta),
      );
    }
    if (saved != null) post = post.copyWith(isSaved: saved);
    if (following != null) post = post.copyWith(isFollowing: following);
    if (vote != null && vote != base.myVote) {
      post = post.copyWith(
        myVote: vote,
        pollOptions: [
          for (final option in base.pollOptions)
            option.withVotes(
              option.votes + (option.id == vote ? 1 : 0) - (option.id == base.myVote ? 1 : 0),
            ),
        ],
      );
    }
    if (commentsCount != null) post = post.copyWith(commentsCount: math.max(commentsCount!, base.commentsCount));
    if (pinned != null) post = post.copyWith(isPinned: pinned);
    if (locked != null) post = post.copyWith(isLocked: locked);
    if (removed != null) post = post.copyWith(isRemoved: removed);
    if (title != null || body != null) post = post.copyWith(title: title, body: body);
    if (shared) post = post.copyWith(sharesCount: base.sharesCount + 1);
    return post;
  }
}

final postPatchesProvider = NotifierProvider<PostPatches, Map<String, PostPatch>>(PostPatches.new);

class PostPatches extends Notifier<Map<String, PostPatch>> {
  @override
  Map<String, PostPatch> build() => const {};

  void update(String postId, PostPatch Function(PostPatch patch) change) {
    state = {...state, postId: change(state[postId] ?? const PostPatch())};
  }

  void restore(String postId, PostPatch? previous) {
    final next = {...state};
    if (previous == null) {
      next.remove(postId);
    } else {
      next[postId] = previous;
    }
    state = next;
  }
}

extension LivePost on WidgetRef {
  /// The live version of [post], with the student's local changes applied.
  Post livePost(Post post) {
    final patch = watch(postPatchesProvider.select((patches) => patches[post.id]));
    return patch == null ? post : patch.apply(post);
  }
}

final isPostDeletedProvider = Provider.autoDispose.family<bool, String>((ref, id) {
  return ref.watch(postPatchesProvider.select((patches) => patches[id]?.deleted ?? false));
});

final postActionsProvider = Provider<PostActions>(PostActions.new);

/// Optimistic post interactions. Each method updates the UI first and
/// reverts if the request fails (the error is rethrown for a toast).
class PostActions {
  PostActions(this._ref);

  final Ref _ref;

  PostRepository get _repo => _ref.read(postRepositoryProvider);
  PostPatches get _patches => _ref.read(postPatchesProvider.notifier);

  Future<void> _optimistic(String postId, PostPatch Function(PostPatch) change, Future<void> Function() request) async {
    final previous = _ref.read(postPatchesProvider)[postId];
    _patches.update(postId, change);
    try {
      await request();
    } catch (_) {
      _patches.restore(postId, previous);
      rethrow;
    }
  }

  /// Sets the reaction; passing the current reaction (or null) removes it.
  Future<void> react(Post post, Reaction? reaction) {
    final next = reaction == post.myReaction ? null : reaction;
    return _optimistic(
      post.id,
      (p) => p.copyWith(reactionSet: true, reaction: next, clearReaction: next == null),
      () => next == null ? _repo.unreact(post.id) : _repo.react(post.id, next),
    );
  }

  Future<void> toggleSave(Post post) {
    final next = !post.isSaved;
    return _optimistic(post.id, (p) => p.copyWith(saved: next), () => next ? _repo.save(post.id) : _repo.unsave(post.id));
  }

  Future<void> toggleFollow(Post post) {
    final next = !post.isFollowing;
    return _optimistic(
      post.id,
      (p) => p.copyWith(following: next),
      () => next ? _repo.follow(post.id) : _repo.unfollow(post.id),
    );
  }

  Future<void> vote(Post post, String optionId) {
    return _optimistic(post.id, (p) => p.copyWith(vote: optionId), () => _repo.vote(post.id, optionId));
  }

  Future<void> shared(Post post) {
    return _optimistic(post.id, (p) => p.copyWith(shared: true), () => _repo.recordShare(post.id));
  }

  Future<void> delete(Post post) {
    return _optimistic(post.id, (p) => p.copyWith(deleted: true), () => _repo.delete(post.id));
  }

  void commentsChanged(String postId, int count) {
    _patches.update(postId, (p) => p.copyWith(commentsCount: count));
  }

  void edited(String postId, {String? title, String? body}) {
    _patches.update(postId, (p) => p.copyWith(title: title, body: body));
  }

  void moderated(String postId, String action) {
    _patches.update(
      postId,
      (p) => switch (action) {
        'pin' => p.copyWith(pinned: true),
        'unpin' => p.copyWith(pinned: false),
        'lock' => p.copyWith(locked: true),
        'unlock' => p.copyWith(locked: false),
        'remove' => p.copyWith(removed: true),
        'restore' => p.copyWith(removed: false),
        _ => p,
      },
    );
  }
}

// Feeds ----------------------------------------------------------------------

final homeFeedProvider = AsyncNotifierProvider.family<HomeFeed, Paged<Post>, FeedMode>(HomeFeed.new);

class HomeFeed extends PagedNotifier<Post> {
  HomeFeed(this.mode);

  final FeedMode mode;

  @override
  Future<List<Post>> fetch(int offset, int limit) =>
      ref.read(postRepositoryProvider).homeFeed(mode, offset: offset, limit: limit);

  @override
  Object idOf(Post item) => item.id;
}

typedef CommunityFeedKey = ({String communityId, String sort});

final communityFeedProvider =
    AsyncNotifierProvider.autoDispose.family<CommunityFeed, Paged<Post>, CommunityFeedKey>(CommunityFeed.new);

class CommunityFeed extends PagedNotifier<Post> {
  CommunityFeed(this.key);

  final CommunityFeedKey key;

  @override
  Future<List<Post>> fetch(int offset, int limit) => ref
      .read(postRepositoryProvider)
      .communityFeed(key.communityId, sort: key.sort, offset: offset, limit: limit);

  @override
  Object idOf(Post item) => item.id;
}

typedef UserPostsKey = ({String userId, bool reels});

final userPostsProvider = AsyncNotifierProvider.autoDispose.family<UserPosts, Paged<Post>, UserPostsKey>(UserPosts.new);

class UserPosts extends PagedNotifier<Post> {
  UserPosts(this.key);

  final UserPostsKey key;

  @override
  int get pageSize => key.reels ? 18 : 20;

  @override
  Future<List<Post>> fetch(int offset, int limit) =>
      ref.read(postRepositoryProvider).byAuthor(key.userId, reels: key.reels, offset: offset, limit: limit);

  @override
  Object idOf(Post item) => item.id;
}

final savedPostsProvider = AsyncNotifierProvider.autoDispose<SavedPosts, Paged<Post>>(SavedPosts.new);

class SavedPosts extends PagedNotifier<Post> {
  @override
  Future<List<Post>> fetch(int offset, int limit) =>
      ref.read(postRepositoryProvider).saved(offset: offset, limit: limit);

  @override
  Object idOf(Post item) => item.id;
}

final reelsFeedProvider = AsyncNotifierProvider<ReelsFeed, Paged<Post>>(ReelsFeed.new);

class ReelsFeed extends PagedNotifier<Post> {
  @override
  int get pageSize => 8;

  @override
  Future<List<Post>> fetch(int offset, int limit) =>
      ref.read(postRepositoryProvider).reelsFeed(offset: offset, limit: limit);

  @override
  Object idOf(Post item) => item.id;
}

final postProvider = FutureProvider.autoDispose.family<Post?, String>((ref, id) {
  return ref.watch(postRepositoryProvider).byId(id);
});

// Comments ---------------------------------------------------------------------

final commentsProvider = AsyncNotifierProvider.autoDispose.family<CommentsNotifier, List<Comment>, String>(
  CommentsNotifier.new,
);

class CommentsNotifier extends AsyncNotifier<List<Comment>> {
  CommentsNotifier(this.postId);

  final String postId;

  PostRepository get _repo => ref.read(postRepositoryProvider);

  @override
  Future<List<Comment>> build() => _repo.comments(postId);

  Future<void> add(String body, {String? parentId}) async {
    final comment = await _repo.addComment(postId, body, parentId: parentId);
    if (!ref.mounted) return;
    final list = [...state.value ?? <Comment>[], comment];
    state = AsyncData(list);
    ref.read(postActionsProvider).commentsChanged(postId, list.where((c) => !c.isGone).length);
  }

  Future<void> remove(Comment comment) async {
    await _repo.deleteComment(comment.id);
    if (!ref.mounted) return;
    final hasReplies = (state.value ?? const []).any((c) => c.parentId == comment.id);
    state = AsyncData([
      for (final c in state.value ?? <Comment>[])
        if (c.id != comment.id)
          c
        else if (hasReplies)
          c.copyWith(isDeleted: true),
    ]);
  }

  Future<void> edit(Comment comment, String body) async {
    await _repo.editComment(comment.id, body);
    if (!ref.mounted) return;
    state = AsyncData([
      for (final c in state.value ?? <Comment>[]) c.id == comment.id ? c.copyWith(body: body) : c,
    ]);
  }

  Future<void> toggleLike(Comment comment) async {
    final liked = !comment.likedByMe;
    void set(bool value, int delta) {
      state = AsyncData([
        for (final c in state.value ?? <Comment>[])
          c.id == comment.id ? c.copyWith(likedByMe: value, likesCount: math.max(0, c.likesCount + delta)) : c,
      ]);
    }

    set(liked, liked ? 1 : -1);
    try {
      if (liked) {
        await _repo.likeComment(comment.id);
      } else {
        await _repo.unlikeComment(comment.id);
      }
    } catch (_) {
      if (ref.mounted) set(!liked, liked ? -1 : 1);
      rethrow;
    }
  }
}
