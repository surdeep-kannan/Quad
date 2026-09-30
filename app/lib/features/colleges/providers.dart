import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/paged.dart';
import 'data/college.dart';
import 'data/college_repository.dart';

final collegeLeaderboardProvider =
    AsyncNotifierProvider.autoDispose.family<CollegeLeaderboard, Paged<College>, String?>(CollegeLeaderboard.new);

class CollegeLeaderboard extends PagedNotifier<College> {
  CollegeLeaderboard(this.region);

  /// Optional Indian state to filter by, e.g. "Tamil Nadu".
  final String? region;

  @override
  int get pageSize => 30;

  @override
  Future<List<College>> fetch(int offset, int limit) =>
      ref.read(collegeRepositoryProvider).leaderboard(state: region, offset: offset, limit: limit);

  @override
  Object idOf(College item) => item.id;
}

final collegeProvider = FutureProvider.autoDispose.family<College?, String>((ref, id) {
  return ref.watch(collegeRepositoryProvider).byId(id);
});

final rankingPillarsProvider = FutureProvider<List<RankingPillar>>((ref) {
  return ref.watch(collegeRepositoryProvider).pillars();
});

final collegeSearchProvider = FutureProvider.autoDispose.family<List<College>, String>((ref, query) {
  final repo = ref.watch(collegeRepositoryProvider);
  return query.trim().isEmpty ? repo.browse() : repo.search(query.trim());
});
