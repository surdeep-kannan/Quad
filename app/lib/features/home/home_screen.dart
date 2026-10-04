import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/context_x.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/avatars.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/paged_list.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/states.dart';
import '../auth/ui/brand.dart';
import '../communities/providers.dart';
import '../communities/ui/community_tiles.dart';
import '../notifications/providers.dart';
import '../posts/data/post.dart';
import '../posts/data/post_repository.dart';
import '../posts/providers.dart';
import '../posts/ui/post_card.dart';
import '../profile/providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: FeedMode.values.length, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final unread = ref.watch(unreadNotificationsProvider).value ?? 0;
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            floating: true,
            snap: true,
            toolbarHeight: 56,
            titleSpacing: Space.gutter,
            title: const Wordmark(size: 27),
            actions: [
              IconTap(icon: AppIcons.search, tooltip: 'Search', onTap: () => context.push('/search')),
              IconTap(
                icon: AppIcons.bell,
                tooltip: unread > 0 ? '$unread new notifications' : 'Notifications',
                onTap: () => context.push('/notifications'),
                badge: unread > 0 ? CountBadge(count: unread) : null,
              ),
              const SizedBox(width: 6),
            ],
            bottom: TabBar(
              controller: _tabs,
              isScrollable: true,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              tabs: [for (final mode in FeedMode.values) Tab(text: mode.label, height: 42)],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [for (final mode in FeedMode.values) _Feed(mode: mode)],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/compose'),
        tooltip: 'New post',
        backgroundColor: c.ink,
        foregroundColor: c.inkInverse,
        elevation: 2,
        shape: const CircleBorder(),
        child: const Icon(AppIcons.plusBold),
      ),
    );
  }
}

class _Feed extends ConsumerWidget {
  const _Feed({required this.mode});

  final FeedMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(homeFeedProvider(mode));
    final notifier = ref.read(homeFeedProvider(mode).notifier);
    return AppRefresh(
      onRefresh: notifier.refresh,
      child: CustomScrollView(
        key: PageStorageKey('feed-${mode.key}'),
        slivers: [
          if (mode == FeedMode.forYou) const SliverToBoxAdapter(child: _ComposerPrompt()),
          PagedSliverList<Post>(
            value: feed,
            onLoadMore: notifier.loadMore,
            onRetry: () => ref.invalidate(homeFeedProvider(mode)),
            skeleton: const Skeleton(child: Column(children: [PostSkeleton(), PostSkeleton(withMedia: true), PostSkeleton()])),
            empty: _EmptyFeed(mode: mode),
            itemBuilder: (context, post, index) {
              if (mode == FeedMode.forYou && index == 3) {
                return Column(children: [const _SuggestedCommunities(), PostCard(post: post)]);
              }
              return PostCard(post: post);
            },
          ),
        ],
      ),
    );
  }
}

class _ComposerPrompt extends ConsumerWidget {
  const _ComposerPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final me = ref.watch(myProfileProvider).value;
    Widget quick(IconData icon, String label, String type) => Pressable(
          onTap: () => context.push('/compose?type=$type'),
          semanticLabel: 'New $label',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Icon(icon, size: 21, color: c.inkMuted),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 12, 10, 12),
      decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.line))),
      child: Row(
        children: [
          if (me != null)
            ProfileTap(
              user: me.ref,
              child: UserAvatar(name: me.fullName, url: me.avatarUrl, size: 36),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => context.push('/compose'),
              child: Text('Share something with your campus…', style: context.text.bodyMedium!.copyWith(color: c.inkSubtle)),
            ),
          ),
          quick(AppIcons.image, 'photo post', 'image'),
          quick(AppIcons.poll, 'poll', 'poll'),
          quick(AppIcons.question, 'question', 'question'),
        ],
      ),
    );
  }
}

class _SuggestedCommunities extends ConsumerWidget {
  const _SuggestedCommunities();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(suggestedCommunitiesProvider).value ?? const [];
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Container(
      color: c.background,
      padding: const EdgeInsets.only(top: Space.lg, bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Row(
              children: [
                Text('Communities for you', style: context.text.headlineSmall),
                const Spacer(),
                GestureDetector(
                  onTap: () => context.go('/communities'),
                  child: Text('See all', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          SizedBox(
            height: 172,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              itemCount: suggestions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => CommunityCard(community: suggestions[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.mode});

  final FeedMode mode;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      FeedMode.following => EmptyState(
          icon: AppIcons.users,
          title: 'Nothing from your people yet',
          message: 'Follow classmates and join communities to fill this feed.',
          actionLabel: 'Find communities',
          onAction: () => context.go('/communities'),
        ),
      FeedMode.campus => EmptyState(
          icon: AppIcons.graduation,
          title: 'Your campus is quiet',
          message: 'Add your college in your profile, or be the first to post.',
          actionLabel: 'Write a post',
          onAction: () => context.push('/compose'),
        ),
      FeedMode.forYou => EmptyState(
          icon: AppIcons.sparkle,
          title: 'Your feed starts here',
          message: 'Join a few communities and we\'ll surface what matters to you.',
          actionLabel: 'Explore communities',
          onAction: () => context.go('/communities'),
        ),
    };
  }
}
