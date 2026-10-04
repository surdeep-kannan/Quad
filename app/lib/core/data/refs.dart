import 'json.dart';

/// The compact person shape embedded in posts, comments, events and chats.
class UserRef {
  const UserRef({
    required this.id,
    required this.username,
    required this.fullName,
    this.avatarUrl,
    this.isVerified = false,
    this.lastSeenAt,
    this.isAnonymous = false,
  });

  /// Anonymous authors come back with no id and their alias as the name.
  factory UserRef.fromJson(Json json) => UserRef(
        id: json['id'] as String? ?? '',
        username: json['username'] as String? ?? '',
        fullName: json['full_name'] as String? ?? 'Student',
        avatarUrl: stringOrNull(json['avatar_url']),
        isVerified: boolOf(json['is_verified']),
        lastSeenAt: dateOrNull(json['last_seen_at']),
        isAnonymous: boolOf(json['is_anonymous']) && json['id'] == null,
      );

  final String id;
  final String username;
  final String fullName;
  final String? avatarUrl;
  final bool isVerified;
  final DateTime? lastSeenAt;

  /// Shown to others as a random alias; can't be opened or messaged.
  final bool isAnonymous;

  String get firstName => fullName.split(' ').first;
}

class CommunityRef {
  const CommunityRef({
    required this.id,
    required this.slug,
    required this.name,
    this.avatarUrl,
    this.color = 0,
    this.category,
  });

  factory CommunityRef.fromJson(Json json) => CommunityRef(
        id: json['id'] as String,
        slug: json['slug'] as String? ?? '',
        name: json['name'] as String? ?? '',
        avatarUrl: stringOrNull(json['avatar_url']),
        color: intOf(json['color']),
        category: stringOrNull(json['category']),
      );

  final String id;
  final String slug;
  final String name;
  final String? avatarUrl;
  final int color;
  final String? category;
}

class CollegeRef {
  const CollegeRef({required this.id, required this.name, this.shortName, this.city});

  factory CollegeRef.fromJson(Json json) => CollegeRef(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        shortName: stringOrNull(json['short_name']),
        city: stringOrNull(json['city']),
      );

  final String id;
  final String name;
  final String? shortName;
  final String? city;

  String get label => shortName ?? name;
}

/// An image or video attached to a post, reel or poster.
class MediaItem {
  const MediaItem({
    required this.url,
    required this.type,
    this.width,
    this.height,
    this.thumbnailUrl,
    this.durationMs,
  });

  factory MediaItem.fromJson(Json json) => MediaItem(
        url: json['url'] as String? ?? '',
        type: json['type'] as String? ?? 'image',
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        thumbnailUrl: stringOrNull(json['thumbnail_url']),
        durationMs: (json['duration_ms'] as num?)?.toInt(),
      );

  final String url;
  final String type;
  final int? width;
  final int? height;
  final String? thumbnailUrl;
  final int? durationMs;

  bool get isVideo => type == 'video';

  double? get aspectRatio => width != null && height != null && height! > 0 ? width! / height! : null;

  Json toJson() => {
        'url': url,
        'type': type,
        'width': ?width,
        'height': ?height,
        'thumbnail_url': ?thumbnailUrl,
        'duration_ms': ?durationMs,
      };
}
