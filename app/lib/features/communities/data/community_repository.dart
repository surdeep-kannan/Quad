import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/json.dart';
import '../../../core/data/supabase_providers.dart';
import 'community.dart';

final communityRepositoryProvider =
    Provider<CommunityRepository>((ref) => CommunityRepository(ref.watch(supabaseProvider)));

class CommunityRepository {
  CommunityRepository(this._client);

  final SupabaseClient _client;

  static const _memberFields =
      'role, status, joined_at, user:profiles(id, username, full_name, avatar_url, is_verified, department)';

  Future<List<Community>> discover({String? category, int offset = 0, int limit = 20}) async {
    var query = _client.from('community_details').select();
    if (category != null) query = query.eq('category', category);
    final rows = await query.order('members_count', ascending: false).order('created_at', ascending: false).range(
          offset,
          offset + limit - 1,
        );
    return rows.map(Community.fromJson).toList();
  }

  Future<List<Community>> mine() async {
    final rows = await _client
        .from('community_details')
        .select()
        .eq('my_status', 'active')
        .order('posts_count', ascending: false)
        .limit(100);
    return rows.map(Community.fromJson).toList();
  }

  Future<List<Community>> byCollege(String collegeId) async {
    final rows = await _client
        .from('community_details')
        .select()
        .eq('college_id', collegeId)
        .order('members_count', ascending: false)
        .limit(30);
    return rows.map(Community.fromJson).toList();
  }

  Future<List<Community>> suggested({int limit = 10}) async {
    final rows = await _client.rpc<List<dynamic>>('suggested_communities', params: {'p_limit': limit});
    return jsonListOf(rows).map(Community.fromJson).toList();
  }

  Future<Community?> bySlug(String slug) async {
    final row = await _client.from('community_details').select().eq('slug', slug).maybeSingle();
    return row == null ? null : Community.fromJson(row);
  }

  Future<Community?> byId(String id) async {
    final row = await _client.from('community_details').select().eq('id', id).maybeSingle();
    return row == null ? null : Community.fromJson(row);
  }

  Future<bool> isSlugTaken(String slug) async {
    final row = await _client.from('communities').select('id').eq('slug', slug).maybeSingle();
    return row != null;
  }

  Future<String> create({
    required String slug,
    required String name,
    required String category,
    required String visibility,
    required int color,
    String? tagline,
    String? description,
    String? collegeId,
    String? avatarUrl,
    List<String> tags = const [],
    List<CommunityRule> rules = const [],
  }) async {
    final row = await _client
        .from('communities')
        .insert({
          'slug': slug,
          'name': name,
          'category': category,
          'visibility': visibility,
          'color': color,
          'tagline': ?tagline,
          'description': ?description,
          'college_id': ?collegeId,
          'avatar_url': ?avatarUrl,
          'tags': tags,
          'rules': [for (final rule in rules) rule.toJson()],
          'created_by': _client.uid,
        })
        .select('slug')
        .single();
    return row['slug'] as String;
  }

  Future<void> update(String id, Json fields) async {
    await _client.from('communities').update(fields).eq('id', id);
  }

  Future<String> join(String id) async => await _client.rpc<String>('join_community', params: {'p_community': id});

  Future<void> leave(String id) async {
    await _client.rpc<void>('leave_community', params: {'p_community': id});
  }

  Future<List<CommunityMember>> members(String communityId, {String status = 'active', int offset = 0, int limit = 50}) async {
    final rows = await _client
        .from('community_members')
        .select(_memberFields)
        .eq('community_id', communityId)
        .eq('status', status)
        .order('joined_at', ascending: true)
        .range(offset, offset + limit - 1);
    final members = rows.map(CommunityMember.fromJson).toList();
    const rank = {'owner': 0, 'admin': 1, 'moderator': 2, 'member': 3};
    members.sort((a, b) => (rank[a.role] ?? 3).compareTo(rank[b.role] ?? 3));
    return members;
  }

  Future<void> setRole(String communityId, String userId, String role) async {
    await _client.rpc<void>('set_member_role', params: {'p_community': communityId, 'p_user': userId, 'p_role': role});
  }

  /// Approve a request / unban ('active') or ban ('banned').
  Future<void> setStatus(String communityId, String userId, String status) async {
    await _client.rpc<void>(
      'set_member_status',
      params: {'p_community': communityId, 'p_user': userId, 'p_status': status},
    );
  }

  Future<void> removeMember(String communityId, String userId) async {
    await _client.rpc<void>('remove_member', params: {'p_community': communityId, 'p_user': userId});
  }

  Future<List<Room>> rooms(String communityId) async {
    final rows = await _client
        .from('room_details')
        .select()
        .eq('community_id', communityId)
        .order('position', ascending: true);
    return rows.map(Room.fromJson).toList();
  }

  Future<Room?> room(String roomId) async {
    final row = await _client.from('room_details').select().eq('id', roomId).maybeSingle();
    return row == null ? null : Room.fromJson(row);
  }

  Future<String> createRoom(String communityId, {required String name, String? topic, String kind = 'general'}) async {
    return _client.rpc<String>(
      'create_room',
      params: {'p_community': communityId, 'p_name': name, 'p_topic': topic, 'p_kind': kind},
    );
  }

  Future<void> updateRoom(String roomId, Json fields) async {
    await _client.from('rooms').update(fields).eq('id', roomId);
  }

  Future<void> deleteRoom(String roomId) async {
    await _client.rpc<void>('delete_room', params: {'p_room': roomId});
  }

  Future<List<Community>> search(String query, {int limit = 20}) async {
    final rows = await _client.rpc<List<dynamic>>('search_communities', params: {'p_query': query, 'p_limit': limit});
    return jsonListOf(rows).map(Community.fromJson).toList();
  }
}
