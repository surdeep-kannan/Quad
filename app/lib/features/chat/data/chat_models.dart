import '../../../core/data/json.dart';
import '../../../core/data/refs.dart';

class RoomRef {
  const RoomRef({required this.id, required this.name, required this.kind, required this.community});

  factory RoomRef.fromJson(Json json) => RoomRef(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        kind: json['kind'] as String? ?? 'general',
        community: CommunityRef.fromJson(jsonOrNull(json['community']) ?? {'id': ''}),
      );

  final String id;
  final String name;
  final String kind;
  final CommunityRef community;
}

/// A row in the chat list.
class Conversation {
  const Conversation({
    required this.id,
    required this.type,
    required this.createdAt,
    this.title,
    this.avatarUrl,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.lastMessageSenderId,
    this.unreadCount = 0,
    this.muted = false,
    this.membersCount = 0,
    this.otherUser,
    this.room,
  });

  /// Reads a row from the `my_conversations()` function.
  factory Conversation.fromJson(Json json) => Conversation(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'direct',
        createdAt: dateOf(json['created_at']),
        title: stringOrNull(json['title']),
        avatarUrl: stringOrNull(json['avatar_url']),
        lastMessageAt: dateOrNull(json['last_message_at']),
        lastMessagePreview: stringOrNull(json['last_message_preview']),
        lastMessageSenderId: stringOrNull(json['last_message_sender_id']),
        unreadCount: intOf(json['unread_count']),
        muted: boolOf(json['muted']),
        membersCount: intOf(json['members_count']),
        otherUser: jsonOrNull(json['other_user']) == null ? null : UserRef.fromJson(jsonOrNull(json['other_user'])!),
        room: jsonOrNull(json['room']) == null ? null : RoomRef.fromJson(jsonOrNull(json['room'])!),
      );

  final String id;
  final String type;
  final DateTime createdAt;
  final String? title;
  final String? avatarUrl;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final String? lastMessageSenderId;
  final int unreadCount;
  final bool muted;
  final int membersCount;
  final UserRef? otherUser;
  final RoomRef? room;

  bool get isDirect => type == 'direct';
  bool get isGroup => type == 'group';
  bool get isRoom => type == 'room';

  String get displayName => switch (type) {
        'direct' => otherUser?.fullName ?? 'Student',
        'room' => room == null ? '#${title ?? 'room'}' : '#${room!.name}',
        _ => title ?? 'Group',
      };

  DateTime get sortTime => lastMessageAt ?? createdAt;

  Conversation copyWith({int? unreadCount, bool? muted}) => Conversation(
        id: id,
        type: type,
        createdAt: createdAt,
        title: title,
        avatarUrl: avatarUrl,
        lastMessageAt: lastMessageAt,
        lastMessagePreview: lastMessagePreview,
        lastMessageSenderId: lastMessageSenderId,
        unreadCount: unreadCount ?? this.unreadCount,
        muted: muted ?? this.muted,
        membersCount: membersCount,
        otherUser: otherUser,
        room: room,
      );
}

class ConversationMember {
  const ConversationMember({required this.user, required this.role, required this.lastReadAt, required this.joinedAt});

  factory ConversationMember.fromJson(Json json) => ConversationMember(
        user: UserRef.fromJson(jsonOrNull(json['user']) ?? {'id': json['user_id']}),
        role: json['role'] as String? ?? 'member',
        lastReadAt: dateOf(json['last_read_at']),
        joinedAt: dateOf(json['joined_at']),
      );

  final UserRef user;
  final String role;
  final DateTime lastReadAt;
  final DateTime joinedAt;

  bool get isAdmin => role == 'owner' || role == 'admin';
}

/// A file or image on a message. Chat files live in a private bucket, so
/// [path] is resolved to a signed URL when shown.
class Attachment {
  const Attachment({required this.path, required this.name, required this.mimeType, required this.size, this.width, this.height});

  factory Attachment.fromJson(Json json) => Attachment(
        path: json['path'] as String? ?? '',
        name: json['name'] as String? ?? 'file',
        mimeType: json['mime'] as String? ?? 'application/octet-stream',
        size: intOf(json['size']),
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
      );

  final String path;
  final String name;
  final String mimeType;
  final int size;
  final int? width;
  final int? height;

  bool get isImage => mimeType.startsWith('image/');

  Json toJson() => {
        'path': path,
        'name': name,
        'mime': mimeType,
        'size': size,
        'width': ?width,
        'height': ?height,
      };
}

enum SendState { sending, sent, failed }

class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.kind,
    required this.createdAt,
    this.senderId,
    this.body,
    this.attachments = const [],
    this.replyToId,
    this.sharedPostId,
    this.sharedEventId,
    this.reactions = const {},
    this.editedAt,
    this.deletedAt,
    this.sendState = SendState.sent,
    this.isAnonymous = false,
    this.anonName,
  });

  factory Message.fromJson(Json json) {
    final reactions = jsonOrNull(json['reactions']) ?? const {};
    return Message(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: stringOrNull(json['sender_id']),
      kind: json['kind'] as String? ?? 'text',
      body: stringOrNull(json['body']),
      attachments: jsonListOf(json['attachments']).map(Attachment.fromJson).toList(),
      replyToId: stringOrNull(json['reply_to_id']),
      sharedPostId: stringOrNull(json['shared_post_id']),
      sharedEventId: stringOrNull(json['shared_event_id']),
      reactions: {for (final e in reactions.entries) e.key: stringsOf(e.value)},
      editedAt: dateOrNull(json['edited_at']),
      deletedAt: dateOrNull(json['deleted_at']),
      createdAt: dateOf(json['created_at']),
      isAnonymous: boolOf(json['is_anonymous']),
      anonName: stringOrNull(json['anon_name']),
    );
  }

  final String id;
  final String conversationId;
  final String? senderId;
  final String kind;
  final String? body;
  final List<Attachment> attachments;
  final String? replyToId;
  final String? sharedPostId;
  final String? sharedEventId;

  /// Emoji -> ids of the people who reacted with it.
  final Map<String, List<String>> reactions;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final SendState sendState;

  /// Sent under [anonName] in a room; the server stores no sender.
  final bool isAnonymous;
  final String? anonName;

  bool get isDeleted => deletedAt != null;
  bool get isSystem => kind == 'system' || kind == 'call';

  /// One-line summary for reply previews and notifications.
  String get preview {
    if (isDeleted) return 'Message deleted';
    return switch (kind) {
      'image' => (body?.isNotEmpty ?? false) ? '📷 $body' : '📷 Photo',
      'file' => '📎 ${attachments.firstOrNull?.name ?? 'File'}',
      'post' => 'Shared a post',
      'event' => 'Shared an event',
      _ => body ?? '',
    };
  }

  Message copyWith({
    String? body,
    Map<String, List<String>>? reactions,
    DateTime? editedAt,
    DateTime? deletedAt,
    SendState? sendState,
  }) =>
      Message(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        kind: kind,
        body: body ?? this.body,
        attachments: attachments,
        replyToId: replyToId,
        sharedPostId: sharedPostId,
        sharedEventId: sharedEventId,
        reactions: reactions ?? this.reactions,
        editedAt: editedAt ?? this.editedAt,
        deletedAt: deletedAt ?? this.deletedAt,
        createdAt: createdAt,
        sendState: sendState ?? this.sendState,
        isAnonymous: isAnonymous,
        anonName: anonName,
      );

  Json toInsert() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'kind': kind,
        'body': body,
        'attachments': [for (final a in attachments) a.toJson()],
        'reply_to_id': replyToId,
        'shared_post_id': sharedPostId,
        'shared_event_id': sharedEventId,
        'is_anonymous': isAnonymous,
      };
}

class MessageSearchHit {
  const MessageSearchHit({
    required this.id,
    required this.conversationId,
    required this.body,
    required this.createdAt,
    required this.sender,
    required this.conversationTitle,
  });

  factory MessageSearchHit.fromJson(Json json) {
    final conversation = jsonOrNull(json['conversation']) ?? const {};
    return MessageSearchHit(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      body: json['body'] as String? ?? '',
      createdAt: dateOf(json['created_at']),
      sender: UserRef.fromJson(jsonOrNull(json['sender']) ?? {'id': ''}),
      conversationTitle: conversation['type'] == 'room'
          ? '#${conversation['title'] ?? 'room'}'
          : (conversation['title'] as String? ?? 'Chat'),
    );
  }

  final String id;
  final String conversationId;
  final String body;
  final DateTime createdAt;
  final UserRef sender;
  final String conversationTitle;
}

class Call {
  const Call({
    required this.id,
    required this.conversationId,
    required this.kind,
    required this.status,
    required this.createdAt,
    this.startedBy,
  });

  factory Call.fromJson(Json json) => Call(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String,
        kind: json['kind'] as String? ?? 'voice',
        status: json['status'] as String? ?? 'ringing',
        createdAt: dateOf(json['created_at']),
        startedBy: stringOrNull(json['started_by']),
      );

  final String id;
  final String conversationId;
  final String kind;
  final String status;
  final DateTime createdAt;
  final String? startedBy;

  bool get isVideo => kind == 'video';
}
