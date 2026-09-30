import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/supabase_providers.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../posts/ui/post_card.dart';
import '../data/profile.dart';
import '../providers.dart';

class FollowListScreen extends ConsumerWidget {
  const FollowListScreen({super.key, required this.username, required this.followers});

  final String username;
  final bool followers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileByUsernameProvider(username)).value;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        title: Text(followers ? 'Followers' : 'Following'),
      ),
      body: profile == null ? const CenteredLoader() : _List(userId: profile.id, followers: followers),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.userId, required this.followers});

  final String userId;
  final bool followers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = followers ? followersProvider(userId) : followingProvider(userId);
    final list = ref.watch(provider);
    final me = ref.watch(currentUserIdProvider);
    return list.when(
      loading: () => const ListSkeleton(),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(provider)),
      data: (people) => people.isEmpty
          ? EmptyState(icon: AppIcons.users, title: followers ? 'No followers yet' : 'Not following anyone yet', compact: true)
          : ListView.builder(
              itemCount: people.length,
              itemBuilder: (_, i) => PersonRow.profile(
                people[i],
                trailing: people[i].id == me ? null : FollowButton(profile: people[i]),
              ),
            ),
    );
  }
}

class FollowButton extends ConsumerWidget {
  const FollowButton({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = ref.watch(followOverridesProvider)[profile.id] ?? profile.isFollowing;
    return AppButton(
      label: following ? 'Following' : 'Follow',
      size: ButtonSize.small,
      variant: following ? ButtonVariant.secondary : ButtonVariant.primary,
      onPressed: () async {
        try {
          await ref.read(followOverridesProvider.notifier).toggle(profile);
        } catch (error) {
          if (context.mounted) showToast(context, friendlyError(error), error: true);
        }
      },
    );
  }
}
