import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/paged.dart';
import 'data/community.dart';
import 'data/community_repository.dart';

final myCommunitiesProvider = FutureProvider<List<Community>>((ref) {
  return ref.watch(communityRepositoryProvider).mine();
});

final suggestedCommunitiesProvider = FutureProvider.autoDispose<List<Community>>((ref) {
  return ref.watch(communityRepositoryProvider).suggested(limit: 12);
});

final discoverCommunitiesProvider =
    AsyncNotifierProvider.autoDispose.family<DiscoverCommunities, Paged<Community>, String?>(DiscoverCommunities.new);

class DiscoverCommunities extends PagedNotifier<Community> {
  DiscoverCommunities(this.category);

  final String? category;

  @override
  Future<List<Community>> fetch(int offset, int limit) =>
      ref.read(communityRepositoryProvider).discover(category: category, offset: offset, limit: limit);

  @override
  Object idOf(Community item) => item.id;
}

/// A community page, with join/leave applied locally.
final communityProvider =
    AsyncNotifierProvider.autoDispose.family<CommunityNotifier, Community?, String>(CommunityNotifier.new);

class CommunityNotifier extends AsyncNotifier<Community?> {
  CommunityNotifier(this.slug);

  final String slug;

  CommunityRepository get _repo => ref.read(communityRepositoryProvider);

  @override
  Future<Community?> build() => _repo.bySlug(slug);

  Future<void> reload() async {
    final community = await _repo.bySlug(slug);
    if (ref.mounted) state = AsyncData(community);
  }

  /// Returns the new status: 'active' or 'pending'.
  Future<String> join() async {
    final community = state.value!;
    final status = await _repo.join(community.id);
    if (ref.mounted) {
      state = AsyncData(community.withMembership(
        status: status,
        role: 'member',
        membersCount: community.membersCount + (status == 'active' ? 1 : 0),
      ));
    }
    ref.invalidate(myCommunitiesProvider);
    return status;
  }

  Future<void> leave() async {
    final community = state.value!;
    await _repo.leave(community.id);
    if (ref.mounted) {
      state = AsyncData(community.withMembership(
        status: null,
        membersCount: community.membersCount - (community.isMember ? 1 : 0),
      ));
    }
    ref.invalidate(myCommunitiesProvider);
  }
}

final communityMembersProvider =
    FutureProvider.autoDispose.family<List<CommunityMember>, ({String communityId, String status})>((ref, key) {
  return ref.watch(communityRepositoryProvider).members(key.communityId, status: key.status, limit: 200);
});

final communityRoomsProvider = FutureProvider.autoDispose.family<List<Room>, String>((ref, communityId) {
  return ref.watch(communityRepositoryProvider).rooms(communityId);
});

final roomProvider = FutureProvider.autoDispose.family<Room?, String>((ref, roomId) {
  return ref.watch(communityRepositoryProvider).room(roomId);
});
