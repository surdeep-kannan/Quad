import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/json.dart';
import '../../../core/data/refs.dart';
import '../../../core/data/supabase_providers.dart';
import '../../posts/data/post.dart';

/// A named, private collection of reels and videos.
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.itemsCount = 0,
    this.cover,
    this.containsPost = false,
    this.updatedAt,
  });

  factory Playlist.fromJson(Json json) => Playlist(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    itemsCount: intOf(json['items_count']),
    cover: jsonOrNull(json['cover']) == null ? null : MediaItem.fromJson(jsonOrNull(json['cover'])!),
    containsPost: boolOf(json['contains_post']),
    updatedAt: dateOrNull(json['updated_at']),
  );

  final String id;
  final String name;
  final int itemsCount;

  /// The most recently added video, for the playlist's artwork.
  final MediaItem? cover;

  /// Whether the video asked about (see [VideoLibrary.playlists]) is in here.
  final bool containsPost;
  final DateTime? updatedAt;
}

final videoLibraryProvider = Provider<VideoLibrary>((ref) => VideoLibrary(ref.watch(supabaseProvider)));

/// Liked videos and playlists.
class VideoLibrary {
  VideoLibrary(this._client);

  final SupabaseClient _client;

  Future<List<Post>> likedVideos({int limit = 60, int offset = 0}) async {
    final rows = await _client.rpc<List<dynamic>>('liked_videos', params: {'p_limit': limit, 'p_offset': offset});
    return jsonListOf(rows).map(Post.fromJson).toList();
  }

  /// Your playlists. Pass [postId] to learn which already contain that video.
  Future<List<Playlist>> playlists({String? postId}) async {
    final rows = await _client.rpc<List<dynamic>>('my_playlists', params: {'p_post': postId});
    return jsonListOf(rows).map(Playlist.fromJson).toList();
  }

  Future<List<Post>> playlistVideos(String playlistId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'playlist_videos',
      params: {'p_playlist': playlistId, 'p_limit': 200},
    );
    return jsonListOf(rows).map(Post.fromJson).toList();
  }

  Future<String> createPlaylist(String name) async {
    final row = await _client.from('playlists').insert({'name': name}).select('id').single();
    return row['id'] as String;
  }

  Future<void> renamePlaylist(String id, String name) async {
    await _client.from('playlists').update({'name': name}).eq('id', id);
  }

  Future<void> deletePlaylist(String id) async {
    await _client.from('playlists').delete().eq('id', id);
  }

  Future<void> addToPlaylist(String playlistId, String postId) async {
    await _client
        .from('playlist_items')
        .upsert(
          {'playlist_id': playlistId, 'post_id': postId},
          onConflict: 'playlist_id,post_id',
          ignoreDuplicates: true,
        );
  }

  Future<void> removeFromPlaylist(String playlistId, String postId) async {
    await _client.from('playlist_items').delete().eq('playlist_id', playlistId).eq('post_id', postId);
  }
}

final likedVideosProvider = FutureProvider.autoDispose<List<Post>>((ref) {
  return ref.watch(videoLibraryProvider).likedVideos();
});

/// Keyed by the video being added (or null for the plain list).
final playlistsProvider = FutureProvider.autoDispose.family<List<Playlist>, String?>((ref, postId) {
  return ref.watch(videoLibraryProvider).playlists(postId: postId);
});

final playlistVideosProvider = FutureProvider.autoDispose.family<List<Post>, String>((ref, playlistId) {
  return ref.watch(videoLibraryProvider).playlistVideos(playlistId);
});
