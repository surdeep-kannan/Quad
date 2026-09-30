import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/json.dart';
import '../../core/data/supabase_providers.dart';
import 'data/profile.dart';
import 'data/profile_repository.dart';

/// The signed-in student's own profile. Null when signed out.
final myProfileProvider = AsyncNotifierProvider<MyProfileNotifier, Profile?>(MyProfileNotifier.new);

class MyProfileNotifier extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return null;
    return ref.read(profileRepositoryProvider).byId(uid);
  }

  Future<void> reload() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final profile = await ref.read(profileRepositoryProvider).byId(uid);
    if (ref.mounted) state = AsyncData(profile);
  }

  /// Saves profile fields, then reloads.
  Future<void> save(Json fields) async {
    await ref.read(profileRepositoryProvider).update(fields);
    await reload();
  }
}

final profileByUsernameProvider = FutureProvider.autoDispose.family<Profile?, String>((ref, username) {
  return ref.watch(profileRepositoryProvider).byUsername(username);
});

final achievementsProvider = FutureProvider.autoDispose.family<List<Achievement>, String>((ref, userId) {
  return ref.watch(profileRepositoryProvider).achievements(userId);
});

final suggestedPeopleProvider = FutureProvider.autoDispose<List<Profile>>((ref) {
  return ref.watch(profileRepositoryProvider).suggested(limit: 12);
});

final followersProvider = FutureProvider.autoDispose.family<List<Profile>, String>((ref, userId) {
  return ref.watch(profileRepositoryProvider).followers(userId, limit: 100);
});

final followingProvider = FutureProvider.autoDispose.family<List<Profile>, String>((ref, userId) {
  return ref.watch(profileRepositoryProvider).following(userId, limit: 100);
});

final blockedUsersProvider = FutureProvider.autoDispose<List<Profile>>((ref) {
  return ref.watch(profileRepositoryProvider).blocked();
});

/// Follow state that survives list rebuilds: userId -> following.
final followOverridesProvider = NotifierProvider<FollowOverrides, Map<String, bool>>(FollowOverrides.new);

class FollowOverrides extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => const {};

  bool isFollowing(Profile profile) => state[profile.id] ?? profile.isFollowing;

  /// Optimistically flips the follow, reverting if the request fails.
  Future<void> toggle(Profile profile) async {
    final following = isFollowing(profile);
    state = {...state, profile.id: !following};
    try {
      final repo = ref.read(profileRepositoryProvider);
      if (following) {
        await repo.unfollow(profile.id);
      } else {
        await repo.follow(profile.id);
      }
    } catch (_) {
      state = {...state, profile.id: following};
      rethrow;
    }
  }
}

/// Keeps last_seen_at fresh while the app is open.
final presenceHeartbeatProvider = Provider<void>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return;
  final repo = ref.read(profileRepositoryProvider);
  unawaited(repo.touchLastSeen().catchError((_) {}));
  final timer = Timer.periodic(const Duration(minutes: 1), (_) {
    unawaited(repo.touchLastSeen().catchError((_) {}));
  });
  ref.onDispose(timer.cancel);
});
