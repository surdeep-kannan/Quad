import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/json.dart';
import '../../../core/data/refs.dart';
import '../../../core/data/supabase_providers.dart';
import '../../colleges/data/college.dart';
import '../../communities/data/community.dart';
import '../../events/data/event.dart';
import '../../posts/data/post.dart';
import '../../profile/data/profile.dart';

class RoomHit {
  const RoomHit({
    required this.id,
    required this.name,
    required this.kind,
    required this.conversationId,
    required this.isMember,
    required this.community,
    this.topic,
  });

  factory RoomHit.fromJson(Json json) => RoomHit(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        kind: json['kind'] as String? ?? 'general',
        conversationId: json['conversation_id'] as String,
        isMember: boolOf(json['is_member']),
        community: CommunityRef.fromJson(jsonOrNull(json['community']) ?? {'id': ''}),
        topic: stringOrNull(json['topic']),
      );

  final String id;
  final String name;
  final String kind;
  final String conversationId;
  final bool isMember;
  final CommunityRef community;
  final String? topic;
}

class SearchResults {
  const SearchResults({
    this.people = const [],
    this.communities = const [],
    this.events = const [],
    this.posts = const [],
    this.reels = const [],
    this.colleges = const [],
    this.rooms = const [],
  });

  final List<Profile> people;
  final List<Community> communities;
  final List<CampusEvent> events;
  final List<Post> posts;
  final List<Post> reels;
  final List<College> colleges;
  final List<RoomHit> rooms;

  bool get isEmpty =>
      people.isEmpty &&
      communities.isEmpty &&
      events.isEmpty &&
      posts.isEmpty &&
      reels.isEmpty &&
      colleges.isEmpty &&
      rooms.isEmpty;
}

final searchRepositoryProvider = Provider<SearchRepository>((ref) => SearchRepository(ref.watch(supabaseProvider)));

class SearchRepository {
  SearchRepository(this._client);

  final SupabaseClient _client;

  Future<List<Json>> _rpc(String name, String query, int limit, [Json extra = const {}]) async {
    final rows = await _client.rpc<List<dynamic>>(name, params: {'p_query': query, 'p_limit': limit, ...extra});
    return jsonListOf(rows);
  }

  /// Searches everything at once, a few results per kind.
  Future<SearchResults> everything(String query, {int limit = 5}) async {
    final results = await Future.wait([
      _rpc('search_profiles', query, limit),
      _rpc('search_communities', query, limit),
      _rpc('search_events', query, limit),
      _rpc('search_posts', query, limit, {'p_type': null}),
      _rpc('search_posts', query, limit, {'p_type': 'reel'}),
      _rpc('search_colleges', query, limit),
      _rpc('search_rooms', query, limit),
    ]);
    return SearchResults(
      people: results[0].map(Profile.fromJson).toList(),
      communities: results[1].map(Community.fromJson).toList(),
      events: results[2].map(CampusEvent.fromJson).toList(),
      posts: results[3].map(Post.fromJson).where((p) => p.type != PostType.reel).toList(),
      reels: results[4].map(Post.fromJson).toList(),
      colleges: results[5].map(College.fromJson).toList(),
      rooms: results[6].map(RoomHit.fromJson).toList(),
    );
  }

  Future<List<Profile>> people(String query) async =>
      (await _rpc('search_profiles', query, 40)).map(Profile.fromJson).toList();

  Future<List<Community>> communities(String query) async =>
      (await _rpc('search_communities', query, 40)).map(Community.fromJson).toList();

  Future<List<CampusEvent>> events(String query) async =>
      (await _rpc('search_events', query, 40)).map(CampusEvent.fromJson).toList();

  Future<List<Post>> posts(String query, {String? type}) async =>
      (await _rpc('search_posts', query, 40, {'p_type': type})).map(Post.fromJson).toList();

  Future<List<College>> colleges(String query) async =>
      (await _rpc('search_colleges', query, 40)).map(College.fromJson).toList();

  Future<List<RoomHit>> rooms(String query) async =>
      (await _rpc('search_rooms', query, 40)).map(RoomHit.fromJson).toList();
}
