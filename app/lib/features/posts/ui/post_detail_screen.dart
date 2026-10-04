import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/utils/context_x.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/states.dart';
import '../../communities/providers.dart';
import '../providers.dart';
import 'comments.dart';
import 'post_card.dart';

/// A post with its discussion underneath.
class PostDetailScreen extends ConsumerWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final post = ref.watch(postProvider(postId));
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        title: Text(post.value?.community?.name ?? 'Post'),
        shape: Border(bottom: BorderSide(color: c.line)),
      ),
      body: post.when(
        loading: () => const Skeleton(child: PostSkeleton(withMedia: true)),
        error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(postProvider(postId))),
        data: (data) {
          if (data == null) {
            return const EmptyState(
              icon: AppIcons.eyeSlash,
              title: 'Post not available',
              message: 'It may have been deleted or is only visible to members.',
            );
          }
          final slug = data.community?.slug;
          final isMod = slug == null ? false : (ref.watch(communityProvider(slug)).value?.isMod ?? false);
          return CommentsPane(
            post: data,
            header: [
              SliverToBoxAdapter(
                child: PostCard(post: data, inDetail: true, isMod: isMod),
              ),
            ],
            onRefresh: () async {
              ref.invalidate(postProvider(postId));
              ref.invalidate(commentsProvider(postId));
            },
          );
        },
      ),
    );
  }
}
