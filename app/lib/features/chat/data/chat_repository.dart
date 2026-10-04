import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/json.dart';
import '../../../core/data/supabase_providers.dart';
import 'chat_models.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) => ChatRepository(ref.watch(supabaseProvider)));

/// Header information for an open conversation.
class ConversationInfo {
  const ConversationInfo({required this.id, required this.type, required this.members, this.title, this.avatarUrl, this.room});

  final String id;
  final String type;
  final String? title;
  final String? avatarUrl;
  final List<ConversationMember> members;
  final RoomRef? room;
}

class ChatRepository {
  ChatRepository(this._client);

  final SupabaseClient _client;

  static const _memberFields =
      'role, last_read_at, joined_at, user_id, user:profiles(id, username, full_name, avatar_url, is_verified, last_seen_at)';

  Future<List<Conversation>> conversations({String? type}) async {
    final rows = await _client.rpc<List<dynamic>>('my_conversations', params: {'p_type': type});
    return jsonListOf(rows).map(Conversation.fromJson).toList();
  }

  Future<ConversationInfo> info(String conversationId) async {
    final conversation =
        await _client.from('conversations').select('id, type, title, avatar_url').eq('id', conversationId).single();
    final members = await this.members(conversationId);
    RoomRef? room;
    if (conversation['type'] == 'room') {
      final row = await _client
          .from('rooms')
          .select('id, name, kind, community:communities(id, slug, name, avatar_url, color)')
          .eq('conversation_id', conversationId)
          .maybeSingle();
      if (row != null) room = RoomRef.fromJson(row);
    }
    return ConversationInfo(
      id: conversationId,
      type: conversation['type'] as String,
      title: stringOrNull(conversation['title']),
      avatarUrl: stringOrNull(conversation['avatar_url']),
      members: members,
      room: room,
    );
  }

  Future<List<ConversationMember>> members(String conversationId) async {
    final rows = await _client
        .from('conversation_members')
        .select(_memberFields)
        .eq('conversation_id', conversationId)
        .order('joined_at', ascending: true)
        .limit(1000);
    return rows.map(ConversationMember.fromJson).toList();
  }

  /// Newest last. Pass [before] to page back through history.
  Future<List<Message>> messages(String conversationId, {DateTime? before, int limit = 40}) async {
    var query = _client.from('messages').select().eq('conversation_id', conversationId);
    if (before != null) query = query.lt('created_at', before.toUtc().toIso8601String());
    final rows = await query.order('created_at', ascending: false).limit(limit);
    return rows.map(Message.fromJson).toList().reversed.toList();
  }

  /// Which of these anonymous messages the signed-in student sent.
  Future<Set<String>> myAnonymousMessages(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return {};
    final rows = await _client.from('message_authors').select('message_id').inFilter('message_id', list);
    return {for (final row in rows) row['message_id'] as String};
  }

  Future<Message?> message(String id) async {
    final row = await _client.from('messages').select().eq('id', id).maybeSingle();
    return row == null ? null : Message.fromJson(row);
  }

  Future<void> send(Message message) async {
    await _client.from('messages').insert(message.toInsert());
  }

  Future<void> edit(String id, String body) async {
    await _client
        .from('messages')
        .update({'body': body, 'edited_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
  }

  Future<void> unsend(String id) async {
    await _client.from('messages').update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
  }

  Future<void> toggleReaction(String messageId, String emoji) async {
    await _client.rpc<bool>('toggle_message_reaction', params: {'p_message': messageId, 'p_emoji': emoji});
  }

  Future<void> markRead(String conversationId) async {
    await _client
        .from('conversation_members')
        .update({'last_read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('conversation_id', conversationId)
        .eq('user_id', _client.uid);
  }

  Future<void> setMuted(String conversationId, bool muted) async {
    await _client
        .from('conversation_members')
        .update({'muted': muted})
        .eq('conversation_id', conversationId)
        .eq('user_id', _client.uid);
  }

  Future<String> directWith(String userId) =>
      _client.rpc<String>('get_or_create_direct_conversation', params: {'p_user': userId});

  Future<String> createGroup(String title, List<String> memberIds) =>
      _client.rpc<String>('create_group_conversation', params: {'p_title': title, 'p_members': memberIds});

  Future<void> addMembers(String conversationId, List<String> userIds) async {
    await _client.rpc<void>('add_conversation_members', params: {'p_conversation': conversationId, 'p_users': userIds});
  }

  Future<void> removeMember(String conversationId, String userId) async {
    await _client.rpc<void>('remove_conversation_member', params: {'p_conversation': conversationId, 'p_user': userId});
  }

  Future<void> renameGroup(String conversationId, String title) async {
    await _client.from('conversations').update({'title': title}).eq('id', conversationId);
  }

  Future<List<MessageSearchHit>> search(String query, {String? conversationId}) async {
    final rows = await _client.rpc<List<dynamic>>(
      'search_messages',
      params: {'p_query': query, 'p_conversation': conversationId, 'p_limit': 50},
    );
    return jsonListOf(rows).map(MessageSearchHit.fromJson).toList();
  }

  // Calls --------------------------------------------------------------------

  Future<String> startCall(String conversationId, {required bool video}) => _client.rpc<String>(
        'start_call',
        params: {'p_conversation': conversationId, 'p_kind': video ? 'video' : 'voice'},
      );

  Future<void> updateCall(String callId, String status) async {
    await _client.rpc<void>('update_call', params: {'p_call': callId, 'p_status': status});
  }

  Future<Call?> call(String callId) async {
    final row = await _client.from('calls').select().eq('id', callId).maybeSingle();
    return row == null ? null : Call.fromJson(row);
  }
}
