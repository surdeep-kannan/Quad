import 'package:material_ui/material_ui.dart';

import '../../../core/data/json.dart';
import '../../../core/data/refs.dart';
import '../../../core/widgets/app_icons.dart';

enum PostType {
  text('text', 'Post', AppIcons.textPost),
  image('image', 'Photo', AppIcons.image),
  video('video', 'Video', AppIcons.video),
  question('question', 'Question', AppIcons.question),
  poll('poll', 'Poll', AppIcons.poll),
  announcement('announcement', 'Announcement', AppIcons.megaphone),
  event('event', 'Event', AppIcons.ticket),
  achievement('achievement', 'Achievement', AppIcons.trophy),
  reel('reel', 'Reel', AppIcons.reels);

  const PostType(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;

  static PostType from(String? key) => values.firstWhere((t) => t.key == key, orElse: () => PostType.text);
}

enum Reaction {
  like('like', '❤️', 'Like'),
  fire('fire', '🔥', 'Fire'),
  haha('haha', '😂', 'Haha'),
  idea('idea', '💡', 'Insightful'),
  clap('clap', '👏', 'Applause');

  const Reaction(this.key, this.emoji, this.label);

  final String key;
  final String emoji;
  final String label;

  static Reaction? from(String? key) => key == null ? null : values.where((r) => r.key == key).firstOrNull;
}

class PollOption {
  const PollOption({required this.id, required this.label, required this.votes});

  factory PollOption.fromJson(Json json) =>
      PollOption(id: json['id'] as String, label: json['label'] as String? ?? '', votes: intOf(json['votes']));

  final String id;
  final String label;
  final int votes;

  PollOption withVotes(int votes) => PollOption(id: id, label: label, votes: votes);
}

/// The slice of an event embedded in event posts.
class EventSummary {
  const EventSummary({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.category,
    required this.mode,
    this.endsAt,
    this.venue,
    this.posterUrl,
    this.posterTheme,
    this.registrationsCount = 0,
    this.capacity,
    this.isCancelled = false,
  });

  factory EventSummary.fromJson(Json json) => EventSummary(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        startsAt: dateOf(json['starts_at']),
        endsAt: dateOrNull(json['ends_at']),
        category: json['category'] as String? ?? 'other',
        mode: json['mode'] as String? ?? 'in_person',
        venue: stringOrNull(json['venue']),
        posterUrl: stringOrNull(json['poster_url']),
        posterTheme: jsonOrNull(json['poster_theme']),
        registrationsCount: intOf(json['registrations_count']),
        capacity: json['capacity'] == null ? null : intOf(json['capacity']),
        isCancelled: boolOf(json['is_cancelled']),
      );

  final String id;
  final String title;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String category;
  final String mode;
  final String? venue;
  final String? posterUrl;
  final Json? posterTheme;
  final int registrationsCount;
  final int? capacity;
  final bool isCancelled;
}

class PostAuthor extends UserRef {
  const PostAuthor({
    required super.id,
    required super.username,
    required super.fullName,
    super.avatarUrl,
    super.isVerified,
    super.isAnonymous,
    this.collegeId,
    this.department,
  });

  factory PostAuthor.fromJson(Json json) {
    final base = UserRef.fromJson(json);
    return PostAuthor(
      id: base.id,
      username: base.username,
      fullName: base.fullName,
      avatarUrl: base.avatarUrl,
      isVerified: base.isVerified,
      isAnonymous: base.isAnonymous,
      collegeId: stringOrNull(json['college_id']),
      department: stringOrNull(json['department']),
    );
  }

  final String? collegeId;
  final String? department;
}

class Post {
  const Post({
    required this.id,
    required this.author,
    required this.type,
    required this.createdAt,
    this.community,
    this.title,
    this.body,
    this.media = const [],
    this.tags = const [],
    this.event,
    this.pollOptions = const [],
    this.pollEndsAt,
    this.myVote,
    this.isPinned = false,
    this.isLocked = false,
    this.isRemoved = false,
    this.removedReason,
    this.reactionCounts = const {},
    this.likesCount = 0,
    this.commentsCount = 0,
    this.sharesCount = 0,
    this.savesCount = 0,
    this.viewsCount = 0,
    this.editedAt,
    this.myReaction,
    this.isSaved = false,
    this.isFollowing = false,
    this.isAnonymous = false,
    this.isMine = false,
  });

  /// Reads a row from the `post_details` view.
  factory Post.fromJson(Json json) {
    final counts = jsonOrNull(json['reaction_counts']) ?? const {};
    return Post(
      id: json['id'] as String,
      author: PostAuthor.fromJson(jsonOrNull(json['author']) ?? {'id': json['author_id']}),
      community: jsonOrNull(json['community']) == null ? null : CommunityRef.fromJson(jsonOrNull(json['community'])!),
      type: PostType.from(json['type'] as String?),
      title: stringOrNull(json['title']),
      body: stringOrNull(json['body']),
      media: jsonListOf(json['media']).map(MediaItem.fromJson).toList(),
      tags: stringsOf(json['tags']),
      event: jsonOrNull(json['event']) == null ? null : EventSummary.fromJson(jsonOrNull(json['event'])!),
      pollOptions: jsonListOf(json['poll_options']).map(PollOption.fromJson).toList(),
      pollEndsAt: dateOrNull(json['poll_ends_at']),
      myVote: stringOrNull(json['my_vote']),
      isPinned: boolOf(json['is_pinned']),
      isLocked: boolOf(json['is_locked']),
      isRemoved: boolOf(json['is_removed']),
      removedReason: stringOrNull(json['removed_reason']),
      reactionCounts: {for (final e in counts.entries) e.key: intOf(e.value)},
      likesCount: intOf(json['likes_count']),
      commentsCount: intOf(json['comments_count']),
      sharesCount: intOf(json['shares_count']),
      savesCount: intOf(json['saves_count']),
      viewsCount: intOf(json['views_count']),
      createdAt: dateOf(json['created_at']),
      editedAt: dateOrNull(json['edited_at']),
      myReaction: Reaction.from(json['my_reaction'] as String?),
      isSaved: boolOf(json['is_saved']),
      isFollowing: boolOf(json['is_following']),
      isAnonymous: boolOf(json['is_anonymous']),
      isMine: boolOf(json['is_mine']),
    );
  }

  final String id;
  final PostAuthor author;
  final CommunityRef? community;
  final PostType type;
  final String? title;
  final String? body;
  final List<MediaItem> media;
  final List<String> tags;
  final EventSummary? event;
  final List<PollOption> pollOptions;
  final DateTime? pollEndsAt;
  final String? myVote;
  final bool isPinned;
  final bool isLocked;
  final bool isRemoved;
  final String? removedReason;
  final Map<String, int> reactionCounts;
  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final int savesCount;
  final int viewsCount;
  final DateTime createdAt;
  final DateTime? editedAt;
  final Reaction? myReaction;
  final bool isSaved;
  final bool isFollowing;

  /// Posted under a random alias. The author still sees it as theirs.
  final bool isAnonymous;

  /// Written by the signed-in student (true even when anonymous).
  final bool isMine;

  bool get pollClosed => pollEndsAt != null && pollEndsAt!.isBefore(DateTime.now());
  int get totalVotes => pollOptions.fold(0, (sum, o) => sum + o.votes);
  MediaItem? get video => media.where((m) => m.isVideo).firstOrNull;
  List<MediaItem> get images => media.where((m) => !m.isVideo).toList();

  /// The two most used reactions, most popular first.
  List<Reaction> get topReactions {
    final entries = reactionCounts.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => Reaction.from(e.key)).whereType<Reaction>().take(2).toList();
  }

  Post copyWith({
    Reaction? myReaction,
    bool clearReaction = false,
    Map<String, int>? reactionCounts,
    int? likesCount,
    int? commentsCount,
    bool? isSaved,
    bool? isFollowing,
    String? myVote,
    List<PollOption>? pollOptions,
    bool? isPinned,
    bool? isLocked,
    bool? isRemoved,
    int? sharesCount,
    String? title,
    String? body,
  }) {
    return Post(
      id: id,
      author: author,
      community: community,
      type: type,
      title: title ?? this.title,
      body: body ?? this.body,
      media: media,
      tags: tags,
      event: event,
      pollOptions: pollOptions ?? this.pollOptions,
      pollEndsAt: pollEndsAt,
      myVote: myVote ?? this.myVote,
      isPinned: isPinned ?? this.isPinned,
      isLocked: isLocked ?? this.isLocked,
      isRemoved: isRemoved ?? this.isRemoved,
      removedReason: removedReason,
      reactionCounts: reactionCounts ?? this.reactionCounts,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      sharesCount: sharesCount ?? this.sharesCount,
      savesCount: savesCount,
      viewsCount: viewsCount,
      createdAt: createdAt,
      editedAt: editedAt,
      myReaction: clearReaction ? null : (myReaction ?? this.myReaction),
      isSaved: isSaved ?? this.isSaved,
      isFollowing: isFollowing ?? this.isFollowing,
      isAnonymous: isAnonymous,
      isMine: isMine,
    );
  }
}

class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.depth,
    required this.createdAt,
    this.parentId,
    this.author,
    this.body,
    this.isDeleted = false,
    this.isRemoved = false,
    this.likesCount = 0,
    this.repliesCount = 0,
    this.editedAt,
    this.likedByMe = false,
    this.isAnonymous = false,
    this.isMine = false,
  });

  /// Reads a row from the `comment_details` view.
  factory Comment.fromJson(Json json) => Comment(
        id: json['id'] as String,
        postId: json['post_id'] as String,
        parentId: stringOrNull(json['parent_id']),
        depth: intOf(json['depth']),
        author: jsonOrNull(json['author']) == null ? null : UserRef.fromJson(jsonOrNull(json['author'])!),
        body: stringOrNull(json['body']),
        isDeleted: boolOf(json['is_deleted']),
        isRemoved: boolOf(json['is_removed']),
        likesCount: intOf(json['likes_count']),
        repliesCount: intOf(json['replies_count']),
        createdAt: dateOf(json['created_at']),
        editedAt: dateOrNull(json['edited_at']),
        likedByMe: boolOf(json['liked_by_me']),
        isAnonymous: boolOf(json['is_anonymous']),
        isMine: boolOf(json['is_mine']),
      );

  final String id;
  final String postId;
  final String? parentId;
  final int depth;
  final UserRef? author;
  final String? body;
  final bool isDeleted;
  final bool isRemoved;
  final int likesCount;
  final int repliesCount;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool likedByMe;
  final bool isAnonymous;
  final bool isMine;

  bool get isGone => isDeleted || isRemoved;

  Comment copyWith({bool? likedByMe, int? likesCount, String? body, bool? isDeleted}) => Comment(
        id: id,
        postId: postId,
        parentId: parentId,
        depth: depth,
        author: author,
        body: body ?? this.body,
        isDeleted: isDeleted ?? this.isDeleted,
        isRemoved: isRemoved,
        likesCount: likesCount ?? this.likesCount,
        repliesCount: repliesCount,
        createdAt: createdAt,
        editedAt: editedAt,
        likedByMe: likedByMe ?? this.likedByMe,
        isAnonymous: isAnonymous,
        isMine: isMine,
      );
}
