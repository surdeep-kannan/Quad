import 'package:material_ui/material_ui.dart';

import '../../../core/data/json.dart';
import '../../../core/data/refs.dart';
import '../../../core/widgets/app_icons.dart';

class Community {
  const Community({
    required this.id,
    required this.slug,
    required this.name,
    required this.category,
    this.tagline,
    this.description,
    this.collegeId,
    this.college,
    this.avatarUrl,
    this.bannerUrl,
    this.color = 0,
    this.visibility = 'public',
    this.rules = const [],
    this.tags = const [],
    this.createdBy,
    this.membersCount = 0,
    this.postsCount = 0,
    this.createdAt,
    this.myRole,
    this.myStatus,
  });

  /// Reads a row from the `community_details` view.
  factory Community.fromJson(Json json) => Community(
        id: json['id'] as String,
        slug: json['slug'] as String? ?? '',
        name: json['name'] as String? ?? '',
        category: json['category'] as String? ?? 'other',
        tagline: stringOrNull(json['tagline']),
        description: stringOrNull(json['description']),
        collegeId: stringOrNull(json['college_id']),
        college: jsonOrNull(json['college']) == null ? null : CollegeRef.fromJson(jsonOrNull(json['college'])!),
        avatarUrl: stringOrNull(json['avatar_url']),
        bannerUrl: stringOrNull(json['banner_url']),
        color: intOf(json['color']),
        visibility: json['visibility'] as String? ?? 'public',
        rules: jsonListOf(json['rules']).map(CommunityRule.fromJson).toList(),
        tags: stringsOf(json['tags']),
        createdBy: stringOrNull(json['created_by']),
        membersCount: intOf(json['members_count']),
        postsCount: intOf(json['posts_count']),
        createdAt: dateOrNull(json['created_at']),
        myRole: stringOrNull(json['my_role']),
        myStatus: stringOrNull(json['my_status']),
      );

  final String id;
  final String slug;
  final String name;
  final String category;
  final String? tagline;
  final String? description;
  final String? collegeId;
  final CollegeRef? college;
  final String? avatarUrl;
  final String? bannerUrl;
  final int color;
  final String visibility;
  final List<CommunityRule> rules;
  final List<String> tags;
  final String? createdBy;
  final int membersCount;
  final int postsCount;
  final DateTime? createdAt;
  final String? myRole;
  final String? myStatus;

  bool get isPrivate => visibility == 'private';
  bool get isMember => myStatus == 'active';
  bool get isPending => myStatus == 'pending';
  bool get isBanned => myStatus == 'banned';
  bool get isMod => isMember && const {'owner', 'admin', 'moderator'}.contains(myRole);
  bool get isAdmin => isMember && const {'owner', 'admin'}.contains(myRole);
  bool get isOwner => isMember && myRole == 'owner';

  /// Private communities hide their content from non-members.
  bool get canSeeContent => !isPrivate || isMember;

  CommunityRef get ref => CommunityRef(id: id, slug: slug, name: name, avatarUrl: avatarUrl, color: color, category: category);

  Community withMembership({String? status, String? role, int? membersCount}) => Community(
        id: id,
        slug: slug,
        name: name,
        category: category,
        tagline: tagline,
        description: description,
        collegeId: collegeId,
        college: college,
        avatarUrl: avatarUrl,
        bannerUrl: bannerUrl,
        color: color,
        visibility: visibility,
        rules: rules,
        tags: tags,
        createdBy: createdBy,
        membersCount: membersCount ?? this.membersCount,
        postsCount: postsCount,
        createdAt: createdAt,
        myRole: status == null ? null : (role ?? myRole ?? 'member'),
        myStatus: status,
      );
}

class CommunityRule {
  const CommunityRule({required this.title, this.body});

  factory CommunityRule.fromJson(Json json) => CommunityRule(
        title: json['title'] as String? ?? '',
        body: stringOrNull(json['body']),
      );

  final String title;
  final String? body;

  Json toJson() => {'title': title, 'body': ?body};
}

class CommunityMember {
  const CommunityMember({
    required this.user,
    required this.role,
    required this.status,
    required this.joinedAt,
    this.department,
  });

  factory CommunityMember.fromJson(Json json) {
    final user = jsonOrNull(json['user']) ?? const {};
    return CommunityMember(
      user: UserRef.fromJson(user),
      department: stringOrNull(user['department']),
      role: json['role'] as String? ?? 'member',
      status: json['status'] as String? ?? 'active',
      joinedAt: dateOf(json['joined_at']),
    );
  }

  final UserRef user;
  final String? department;
  final String role;
  final String status;
  final DateTime joinedAt;

  bool get isStaff => role != 'member';
}

class Room {
  const Room({
    required this.id,
    required this.communityId,
    required this.conversationId,
    required this.name,
    required this.kind,
    this.topic,
    this.position = 0,
    this.isLocked = false,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.lastReadAt,
    this.isMember = false,
  });

  /// Reads a row from the `room_details` view.
  factory Room.fromJson(Json json) => Room(
        id: json['id'] as String,
        communityId: json['community_id'] as String,
        conversationId: json['conversation_id'] as String,
        name: json['name'] as String? ?? '',
        kind: json['kind'] as String? ?? 'general',
        topic: stringOrNull(json['topic']),
        position: intOf(json['position']),
        isLocked: boolOf(json['is_locked']),
        lastMessageAt: dateOrNull(json['last_message_at']),
        lastMessagePreview: stringOrNull(json['last_message_preview']),
        lastReadAt: dateOrNull(json['last_read_at']),
        isMember: boolOf(json['is_member']),
      );

  final String id;
  final String communityId;
  final String conversationId;
  final String name;
  final String kind;
  final String? topic;
  final int position;
  final bool isLocked;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final DateTime? lastReadAt;
  final bool isMember;

  bool get hasUnread =>
      isMember && lastMessageAt != null && (lastReadAt == null || lastMessageAt!.isAfter(lastReadAt!));
}

/// Community categories, with how they're shown.
abstract final class CommunityCategories {
  static const all = <String, String>{
    'college': 'College',
    'department': 'Department',
    'technical': 'Tech',
    'club': 'Clubs',
    'hackathon': 'Hackathons',
    'sports': 'Sports',
    'career': 'Careers',
    'hobby': 'Hobbies',
    'event': 'Events',
    'other': 'Other',
  };

  static String label(String key) => all[key] ?? 'Other';

  static IconData icon(String key) => switch (key) {
        'college' => AppIcons.graduation,
        'department' => AppIcons.buildings,
        'technical' => AppIcons.code,
        'club' => AppIcons.users,
        'hackathon' => AppIcons.lightning,
        'sports' => AppIcons.trophy,
        'career' => AppIcons.briefcase,
        'hobby' => AppIcons.sparkle,
        'event' => AppIcons.ticket,
        _ => AppIcons.hash,
      };
}

/// Room kinds offered when creating a room.
abstract final class RoomKinds {
  static const all = <String, String>{
    'general': 'General',
    'study': 'Study room',
    'coding': 'Coding room',
    'placement': 'Placement talk',
    'hackathon': 'Hackathon room',
    'gaming': 'Gaming room',
    'club': 'Club room',
    'event': 'Event room',
    'announcements': 'Announcements',
  };

  static IconData icon(String kind) => switch (kind) {
        'study' => AppIcons.book,
        'coding' => AppIcons.code,
        'placement' => AppIcons.briefcase,
        'hackathon' => AppIcons.lightning,
        'gaming' => AppIcons.gamepad,
        'club' => AppIcons.users,
        'event' => AppIcons.ticket,
        'announcements' => AppIcons.megaphone,
        _ => AppIcons.hash,
      };
}
