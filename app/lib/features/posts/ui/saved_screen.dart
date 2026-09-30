import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/paged_list.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/states.dart';
import '../data/post.dart';
import '../providers.dart';
import 'post_card.dart';

class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedPostsProvider);
    final notifier = ref.read(savedPostsProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        title: const Text('Saved'),
      ),
      body: AppRefresh(
        onRefresh: notifier.refresh,
        child: CustomScrollView(
          slivers: [
            PagedSliverList<Post>(
              value: saved,
              onLoadMore: notifier.loadMore,
              onRetry: () => ref.invalidate(savedPostsProvider),
              skeleton: const Skeleton(child: Column(children: [PostSkeleton(), PostSkeleton()])),
              empty: const EmptyState(
                icon: AppIcons.bookmark,
                title: 'Nothing saved yet',
                message: 'Tap the bookmark on any post to keep it here for later.',
              ),
              itemBuilder: (_, post, _) => PostCard(post: post),
            ),
          ],
        ),
      ),
    );
  }
}
