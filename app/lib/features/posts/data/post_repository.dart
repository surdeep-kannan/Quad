import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/json.dart';
import '../../../core/data/refs.dart';
import '../../../core/data/supabase_providers.dart';
import 'post.dart';

final postRepositoryProvider = Provider<PostRepository>((ref) => PostRepository(ref.watch(supabaseProvider)));

enum FeedMode {
  forYou('for_you', 'For you'),
  following('following', 'Following'),
  campus('campus', 'Campus');

  const FeedMode(this.key, this.label);

  final String key;
  final String label;
}

class PostRepository {
  PostRepository(this._client);

  final SupabaseClient _client;

  List<Post> _posts(Object? rows) => jsonListOf(rows).map(Post.fromJson).toList();

  Future<List<Post>> homeFeed(FeedMode mode, {int offset = 0, int limit = 20}) async {
    final rows = await _client.rpc<List<dynamic>>(
      'home_feed',
      params: {'p_mode': mode.key, 'p_limit': limit, 'p_offset': offset},
    );
    return _posts(rows);
  }

  Future<List<Post>> communityFeed(String communityId, {String sort = 'hot', int offset = 0, int limit = 20}) async {
    final rows = await _client.rpc<List<dynamic>>(
      'community_feed',
      params: {'p_community': communityId, 'p_sort': sort, 'p_limit': limit, 'p_offset': offset},
    );
    return _posts(rows);
  }

  Future<List<Post>> reelsFeed({int offset = 0, int limit = 8}) async {
    final rows = await _client.rpc<List<dynamic>>('reels_feed', params: {'p_limit': limit, 'p_offset': offset});
    return _posts(rows);
  }

  Future<List<Post>> byAuthor(String userId, {bool reels = false, int offset = 0, int limit = 20}) async {
    var query = _client.from('post_details').select().eq('author_id', userId);
    query = reels ? query.eq('type', 'reel') : query.neq('type', 'reel');
    final rows = await query.order('created_at', ascending: false).range(offset, offset + limit - 1);
    return _posts(rows);
  }

  Future<Post?> byId(String id) async {
    final row = await _client.from('post_details').select().eq('id', id).maybeSingle();
    return row == null ? null : Post.fromJson(row);
  }

  Future<List<Post>> saved({int offset = 0, int limit = 20}) async {
    final rows = await _client
        .from('saved_posts')
        .select('post_id')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    final ids = [for (final row in rows) row['post_id'] as String];
    if (ids.isEmpty) return const [];
    final posts = _posts(await _client.from('post_details').select().inFilter('id', ids));
    final byId = {for (final p in posts) p.id: p};
    return [for (final id in ids) ?byId[id]];
  }

  Future<List<Post>> search(String query, {String? type, int limit = 20}) async {
    final rows = await _client.rpc<List<dynamic>>(
      'search_posts',
      params: {'p_query': query, 'p_type': type, 'p_limit': limit},
    );
    return _posts(rows);
  }

  Future<String> create({
    required PostType type,
    String? communityId,
    String? title,
    String? body,
    List<MediaItem> media = const [],
    List<String> tags = const [],
    String? eventId,
    List<String>? pollOptions,
    DateTime? pollEndsAt,
    bool anonymous = false,
  }) async {
    return _client.rpc<String>('create_post', params: {
      'p_type': type.key,
      'p_community_id': communityId,
      'p_title': title,
      'p_body': body,
      'p_media': [for (final m in media) m.toJson()],
      'p_tags': tags,
      'p_event_id': eventId,
      'p_poll_options': pollOptions,
      'p_poll_ends_at': pollEndsAt?.toUtc().toIso8601String(),
      'p_is_anonymous': anonymous,
    });
  }

  Future<void> edit(String id, {String? title, String? body}) async {
    await _client.from('posts').update({
      'title': title,
      'body': body,
      'edited_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('posts').delete().eq('id', id);
  }

  Future<void> react(String postId, Reaction reaction) async {
    await _client.from('post_reactions').upsert(
      {'post_id': postId, 'user_id': _client.uid, 'kind': reaction.key},
      onConflict: 'post_id,user_id',
    );
  }

  Future<void> unreact(String postId) async {
    await _client.from('post_reactions').delete().eq('post_id', postId).eq('user_id', _client.uid);
  }

  Future<void> save(String postId) async {
    await _client.from('saved_posts').insert({'post_id': postId, 'user_id': _client.uid});
  }

  Future<void> unsave(String postId) async {
    await _client.from('saved_posts').delete().eq('post_id', postId).eq('user_id', _client.uid);
  }

  Future<void> follow(String postId) async {
    await _client.from('post_follows').insert({'post_id': postId, 'user_id': _client.uid});
  }

  Future<void> unfollow(String postId) async {
    await _client.from('post_follows').delete().eq('post_id', postId).eq('user_id', _client.uid);
  }

  Future<void> vote(String postId, String optionId) async {
    await _client.rpc<void>('vote_poll', params: {'p_post': postId, 'p_option': optionId});
  }

  Future<void> recordView(String postId) async {
    await _client.rpc<void>('record_post_view', params: {'p_post': postId});
  }

  Future<void> recordShare(String postId) async {
    await _client.rpc<void>('record_post_share', params: {'p_post': postId});
  }

  /// People who reacted, newest first.
  Future<List<(UserRef, Reaction)>> reactions(String postId, {int limit = 100}) async {
    final rows = await _client
        .from('post_reactions')
        .select('kind, user:profiles(id, username, full_name, avatar_url, is_verified)')
        .eq('post_id', postId)
        .order('created_at', ascending: false)
        .limit(limit);
    return [
      for (final row in rows)
        if (jsonOrNull(row['user']) != null)
          (UserRef.fromJson(jsonOrNull(row['user'])!), Reaction.from(row['kind'] as String?) ?? Reaction.like),
    ];
  }

  // Comments -----------------------------------------------------------------

  Future<List<Comment>> comments(String postId) async {
    final rows = await _client
        .from('comment_details')
        .select()
        .eq('post_id', postId)
        .order('created_at', ascending: true)
        .limit(500);
    return rows.map(Comment.fromJson).toList();
  }

  Future<Comment> addComment(String postId, String body, {String? parentId, bool anonymous = false}) async {
    final inserted = await _client
        .from('comments')
        .insert({'post_id': postId, 'author_id': _client.uid, 'body': body, 'parent_id': ?parentId, 'is_anonymous': anonymous})
        .select('id')
        .single();
    final row = await _client.from('comment_details').select().eq('id', inserted['id'] as String).single();
    return Comment.fromJson(row);
  }

  Future<void> editComment(String id, String body) async {
    await _client
        .from('comments')
        .update({'body': body, 'edited_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
  }

  Future<void> deleteComment(String id) async {
    await _client.rpc<void>('delete_comment', params: {'p_comment': id});
  }

  Future<void> likeComment(String id) async {
    await _client.from('comment_likes').insert({'comment_id': id, 'user_id': _client.uid});
  }

  Future<void> unlikeComment(String id) async {
    await _client.from('comment_likes').delete().eq('comment_id', id).eq('user_id', _client.uid);
  }
}
