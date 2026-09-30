import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/paged.dart';
import '../utils/context_x.dart';
import 'states.dart';

/// Sliver list for a [Paged] provider: skeletons while loading, errors with
/// retry, empty state, and loads the next page near the end.
class PagedSliverList<T> extends StatelessWidget {
  const PagedSliverList({
    super.key,
    required this.value,
    required this.itemBuilder,
    required this.onLoadMore,
    required this.onRetry,
    required this.empty,
    this.skeleton,
    this.separator,
  });

  final AsyncValue<Paged<T>> value;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;
  final Widget empty;
  final Widget? skeleton;
  final Widget? separator;

  @override
  Widget build(BuildContext context) {
    final paged = value.value;
    if (paged == null) {
      if (value.hasError) {
        return SliverFillRemaining(hasScrollBody: false, child: ErrorState(error: value.error!, onRetry: onRetry));
      }
      return SliverToBoxAdapter(child: skeleton ?? const ListSkeleton());
    }
    if (paged.items.isEmpty) return SliverFillRemaining(hasScrollBody: false, child: empty);

    final count = paged.items.length + 1;
    return SliverList.builder(
      itemCount: count,
      itemBuilder: (context, index) {
        if (index == count - 1) {
          if (paged.loadMoreError != null) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(child: TextButton(onPressed: onLoadMore, child: const Text('Couldn\'t load more. Tap to retry'))),
            );
          }
          if (!paged.hasMore) return const SizedBox(height: 96);
          WidgetsBinding.instance.addPostFrameCallback((_) => onLoadMore());
          return const CenteredLoader(padding: 24);
        }
        if (index >= paged.items.length - 4 && paged.hasMore && !paged.loadingMore) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onLoadMore());
        }
        final item = itemBuilder(context, paged.items[index], index);
        if (separator == null || index == 0) return item;
        return Column(mainAxisSize: MainAxisSize.min, children: [separator!, item]);
      },
    );
  }
}

/// Pull-to-refresh with the app's colours.
class AppRefresh extends StatelessWidget {
  const AppRefresh({super.key, required this.onRefresh, required this.child, this.edgeOffset = 0});

  final Future<void> Function() onRefresh;
  final Widget child;
  final double edgeOffset;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: context.colors.ink,
      backgroundColor: context.colors.surface,
      edgeOffset: edgeOffset,
      child: child,
    );
  }
}
