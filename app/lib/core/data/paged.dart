import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A page-by-page list: items loaded so far and whether more exist.
class Paged<T> {
  const Paged({required this.items, required this.hasMore, this.loadingMore = false, this.loadMoreError});

  const Paged.empty() : this(items: const [], hasMore: false);

  final List<T> items;
  final bool hasMore;
  final bool loadingMore;
  final Object? loadMoreError;

  Paged<T> copyWith({List<T>? items, bool? hasMore, bool? loadingMore, Object? loadMoreError}) => Paged(
        items: items ?? this.items,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
        loadMoreError: loadMoreError,
      );
}

/// Base for infinite lists. Subclasses implement [fetch]; the UI calls
/// [loadMore] near the end of the list and [refresh] on pull-to-refresh.
abstract class PagedNotifier<T> extends AsyncNotifier<Paged<T>> {
  int get pageSize => 20;

  Future<List<T>> fetch(int offset, int limit);

  /// Used to drop duplicates when rankings shift between pages.
  Object idOf(T item);

  @override
  Future<Paged<T>> build() async {
    final first = await fetch(0, pageSize);
    return Paged(items: first, hasMore: first.length >= pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await fetch(current.items.length, pageSize);
      if (!ref.mounted) return;
      final seen = current.items.map(idOf).toSet();
      final fresh = next.where((item) => seen.add(idOf(item))).toList();
      state = AsyncData(Paged(items: [...current.items, ...fresh], hasMore: next.length >= pageSize));
    } catch (error) {
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: error));
    }
  }

  Future<void> refresh() async {
    try {
      final first = await fetch(0, pageSize);
      if (!ref.mounted) return;
      state = AsyncData(Paged(items: first, hasMore: first.length >= pageSize));
    } catch (error, stack) {
      if (!ref.mounted) return;
      if (state.value == null) state = AsyncError(error, stack);
      rethrow;
    }
  }

  /// Local edits (e.g. removing a deleted item) without refetching.
  void updateItems(List<T> Function(List<T> items) change) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(items: change(current.items)));
  }
}
