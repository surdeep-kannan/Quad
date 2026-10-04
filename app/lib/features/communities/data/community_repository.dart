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

  static const _memberFields = 'role, status, joined_at, '
      'user:profiles(id, username, full_name, avatar_url, is_verified, department), '
      'community_member_roles(role:community_roles(id, name, color, position, permissions))';

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
    members.sort((a, b) => b.rank.compareTo(a.rank));
    return members;
  }

  /// Roles, highest rank first, with how many people hold each.
  Future<List<CommunityRole>> roles(String communityId) async {
    final rows = await _client
        .from('community_roles')
        .select('id, name, color, position, permissions, community_member_roles(count)')
        .eq('community_id', communityId)
        .order('position', ascending: false);
    return rows.map(CommunityRole.fromJson).toList();
  }

  Future<String> createRole(String communityId, {required String name, required int color, required List<String> permissions}) {
    return _client.rpc<String>('create_community_role', params: {
      'p_community': communityId,
      'p_name': name,
      'p_color': color,
      'p_permissions': permissions,
    });
  }

  Future<void> updateRole(String roleId, {required String name, required int color, required List<String> permissions, required int position}) async {
    await _client.rpc<void>('update_community_role', params: {
      'p_role': roleId,
      'p_name': name,
      'p_color': color,
      'p_permissions': permissions,
      'p_position': position,
    });
  }

  Future<void> deleteRole(String roleId) async {
    await _client.rpc<void>('delete_community_role', params: {'p_role': roleId});
  }

  /// Sets exactly which roles a member has.
  Future<void> setMemberRoles(String communityId, String userId, List<String> roleIds) async {
    await _client.rpc<void>('set_member_roles', params: {'p_community': communityId, 'p_user': userId, 'p_role_ids': roleIds});
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
