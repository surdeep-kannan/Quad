import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/json.dart';
import '../../../core/data/refs.dart';
import '../../../core/data/supabase_providers.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.createdAt,
    this.actor,
    this.postId,
    this.commentId,
    this.communityId,
    this.eventId,
    this.conversationId,
    this.roomId,
    this.data = const {},
    this.readAt,
    this.post,
    this.community,
    this.event,
  });

  /// Reads a row from the `notification_details` view.
  factory AppNotification.fromJson(Json json) => AppNotification(
        id: json['id'] as String,
        type: json['type'] as String? ?? '',
        createdAt: dateOf(json['created_at']),
        actor: jsonOrNull(json['actor']) == null ? null : UserRef.fromJson(jsonOrNull(json['actor'])!),
        postId: stringOrNull(json['post_id']),
        commentId: stringOrNull(json['comment_id']),
        communityId: stringOrNull(json['community_id']),
        eventId: stringOrNull(json['event_id']),
        conversationId: stringOrNull(json['conversation_id']),
        roomId: stringOrNull(json['room_id']),
        data: jsonOrNull(json['data']) ?? const {},
        readAt: dateOrNull(json['read_at']),
        post: jsonOrNull(json['post']),
        community: jsonOrNull(json['community']) == null ? null : CommunityRef.fromJson(jsonOrNull(json['community'])!),
        event: jsonOrNull(json['event']),
      );

  final String id;
  final String type;
  final DateTime createdAt;
  final UserRef? actor;
  final String? postId;
  final String? commentId;
  final String? communityId;
  final String? eventId;
  final String? conversationId;
  final String? roomId;
  final Json data;
  final DateTime? readAt;
  final Json? post;
  final CommunityRef? community;
  final Json? event;

  bool get isUnread => readAt == null;

  AppNotification markRead() => AppNotification(
        id: id,
        type: type,
        createdAt: createdAt,
        actor: actor,
        postId: postId,
        commentId: commentId,
        communityId: communityId,
        eventId: eventId,
        conversationId: conversationId,
        roomId: roomId,
        data: data,
        readAt: DateTime.now(),
        post: post,
        community: community,
        event: event,
      );
}

final notificationRepositoryProvider =
    Provider<NotificationRepository>((ref) => NotificationRepository(ref.watch(supabaseProvider)));

class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

  Future<List<AppNotification>> list({int offset = 0, int limit = 30}) async {
    final rows = await _client
        .from('notification_details')
        .select()
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return rows.map(AppNotification.fromJson).toList();
  }

  Future<AppNotification?> byId(String id) async {
    final row = await _client.from('notification_details').select().eq('id', id).maybeSingle();
    return row == null ? null : AppNotification.fromJson(row);
  }

  Future<int> unreadCount() async {
    final response = await _client
        .from('notifications')
        .select('id')
        .eq('user_id', _client.uid)
        .isFilter('read_at', null)
        .count(CountOption.exact);
    return response.count;
  }

  Future<void> markAllRead() async {
    await _client.rpc<void>('mark_all_notifications_read');
  }

  Future<void> markRead(String id) async {
    await _client.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
  }
}
