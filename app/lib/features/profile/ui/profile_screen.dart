import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/realtime.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/paged_list.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/states.dart';
import '../../chat/data/chat_repository.dart';
import '../../events/providers.dart';
import '../../events/ui/event_tiles.dart';
import '../../moderation/ui/report_sheet.dart';
import '../../posts/data/post.dart';
import '../../posts/providers.dart';
import '../../posts/ui/post_card.dart';
import '../data/profile.dart';
import '../data/profile_repository.dart';
import '../providers.dart';

enum _Tab { posts, reels, about }

/// A student's profile. Without [username] it shows the signed-in student.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.username});

  final String? username;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  _Tab _tab = _Tab.posts;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(myProfileProvider).value;
    final isSelf = widget.username == null || widget.username == me?.username;
    final profile = isSelf ? AsyncValue.data(me) : ref.watch(profileByUsernameProvider(widget.username!));

    return profile.when(
      loading: () => Scaffold(appBar: AppBar(), body: const ListSkeleton(count: 4)),
      error: (error, _) => Scaffold(appBar: AppBar(), body: ErrorState(error: error)),
      data: (data) {
        if (data == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: AppIcons.user, title: 'Profile not found'));
        }
        return _page(context, data, isSelf);
      },
    );
  }

  Widget _page(BuildContext context, Profile profile, bool isSelf) {
    final c = context.colors;
    final key = (userId: profile.id, reels: _tab == _Tab.reels);
    final posts = ref.watch(userPostsProvider(key));
    final notifier = ref.read(userPostsProvider(key).notifier);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.username == null
            ? null
            : IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        title: Text('@${profile.username}', style: context.text.titleMedium),
        actions: [
          if (isSelf) ...[
            IconButton(tooltip: 'Saved', icon: const Icon(AppIcons.bookmark), onPressed: () => context.push('/saved')),
            IconButton(tooltip: 'Settings', icon: const Icon(AppIcons.settings), onPressed: () => context.push('/settings')),
          ] else
            IconButton(tooltip: 'More', icon: const Icon(AppIcons.more), onPressed: () => _otherMenu(profile)),
        ],
      ),
      body: AppRefresh(
        onRefresh: () async {
          if (isSelf) {
            await ref.read(myProfileProvider.notifier).reload();
          } else {
            ref.invalidate(profileByUsernameProvider(widget.username!));
          }
          await notifier.refresh();
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Header(profile: profile, isSelf: isSelf)),
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                child: Row(
                  children: [
                    for (final tab in _Tab.values)
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _tab = tab),
                          child: Container(
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: _tab == tab ? c.ink : Colors.transparent, width: 2.5)),
                            ),
                            child: Text(
                              switch (tab) { _Tab.posts => 'Posts', _Tab.reels => 'Reels', _Tab.about => 'About' },
                              style: context.text.titleSmall!.copyWith(color: _tab == tab ? c.ink : c.inkSubtle),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_tab == _Tab.about)
              SliverToBoxAdapter(child: _About(profile: profile, isSelf: isSelf))
            else if (_tab == _Tab.reels)
              _ReelGrid(value: posts)
            else
              PagedSliverList<Post>(
                value: posts,
                onLoadMore: notifier.loadMore,
                onRetry: () => ref.invalidate(userPostsProvider(key)),
                skeleton: const Skeleton(child: Column(children: [PostSkeleton(), PostSkeleton()])),
                empty: EmptyState(
                  icon: AppIcons.textPost,
                  title: isSelf ? 'Share your first post' : 'No posts yet',
                  actionLabel: isSelf ? 'Write a post' : null,
                  onAction: () => context.push('/compose'),
                  compact: true,
                ),
                itemBuilder: (_, post, _) => PostCard(post: post),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _otherMenu(Profile profile) {
    final repo = ref.read(profileRepositoryProvider);
    return showActionSheet(
      context,
      actions: [
        SheetAction(
          icon: AppIcons.block,
          label: profile.isBlocked ? 'Unblock' : 'Block',
          destructive: !profile.isBlocked,
          onTap: () async {
            try {
              if (profile.isBlocked) {
                await repo.unblock(profile.id);
              } else {
                final ok = await confirm(
                  context,
                  title: 'Block ${profile.ref.firstName}?',
                  message: 'They won\'t be able to message you, follow you or see your posts.',
                  confirmLabel: 'Block',
                  destructive: true,
                );
                if (!ok) return;
                await repo.block(profile.id);
              }
              ref.invalidate(profileByUsernameProvider(profile.username));
            } catch (error) {
              if (mounted) showToast(context, friendlyError(error), error: true);
            }
          },
        ),
        SheetAction(
          icon: AppIcons.flag,
          label: 'Report',
          destructive: true,
          onTap: () => showReportSheet(context, targetType: 'user', targetId: profile.id, what: 'account'),
        ),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.profile, required this.isSelf});

  final Profile profile;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final following = ref.watch(followOverridesProvider)[profile.id] ?? profile.isFollowing;
    final followerDelta = following == profile.isFollowing ? 0 : (following ? 1 : -1);
    final online = ref.watch(onlineUsersProvider).contains(profile.id);

    Widget stat(String value, String label, VoidCallback? onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Radii.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Text(value, style: context.text.headlineSmall),
                  Text(label, style: context.text.bodySmall),
                ],
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(name: profile.fullName, url: profile.avatarUrl, size: 84, online: online && !isSelf),
              const SizedBox(width: Space.md),
              stat(compactCount(profile.postsCount), 'posts', null),
              stat(compactCount(profile.followersCount + followerDelta), 'followers', () => context.push('/u/${profile.username}/followers')),
              stat(compactCount(profile.followingCount), 'following', () => context.push('/u/${profile.username}/following')),
            ],
          ),
          const SizedBox(height: Space.md),
          NameLine(name: profile.fullName, verified: profile.isVerified, style: context.text.headlineMedium),
          if (profile.academicLine.isNotEmpty) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: profile.collegeId == null ? null : () => context.push('/college/${profile.collegeId}'),
              child: Row(
                children: [
                  Icon(AppIcons.graduation, size: 15, color: c.inkMuted),
                  const SizedBox(width: 6),
                  Expanded(child: Text(profile.academicLine, style: context.text.bodyMedium!.copyWith(color: c.inkMuted))),
                ],
              ),
            ),
          ],
          if (profile.bio != null) ...[
            const SizedBox(height: Space.sm),
            Text(profile.bio!, style: context.text.bodyMedium),
          ],
          if (profile.followsMe && !isSelf) ...[
            const SizedBox(height: Space.sm),
            const Tag(label: 'Follows you'),
          ],
          const SizedBox(height: Space.lg),
          if (isSelf)
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Edit profile',
                    variant: ButtonVariant.secondary,
                    size: ButtonSize.medium,
                    onPressed: () => context.push('/profile/edit'),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: AppButton(
                    label: 'Share profile',
                    variant: ButtonVariant.secondary,
                    size: ButtonSize.medium,
                    onPressed: () => showToast(context, '@${profile.username}'),
                  ),
                ),
              ],
            )
          else if (profile.isBlocked)
            const AppButton(label: 'Blocked', variant: ButtonVariant.secondary, expand: true, size: ButtonSize.medium, onPressed: null)
          else
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: following ? 'Following' : (profile.followsMe ? 'Follow back' : 'Follow'),
                    variant: following ? ButtonVariant.secondary : ButtonVariant.primary,
                    size: ButtonSize.medium,
                    onPressed: () async {
                      try {
                        await ref.read(followOverridesProvider.notifier).toggle(profile);
                      } catch (error) {
                        if (context.mounted) showToast(context, friendlyError(error), error: true);
                      }
                    },
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: AppButton(
                    label: 'Message',
                    variant: ButtonVariant.secondary,
                    size: ButtonSize.medium,
                    onPressed: () async {
                      try {
                        final id = await ref.read(chatRepositoryProvider).directWith(profile.id);
                        if (context.mounted) await context.push('/chat/$id');
                      } catch (error) {
                        if (context.mounted) showToast(context, friendlyError(error), error: true);
                      }
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ReelGrid extends StatelessWidget {
  const _ReelGrid({required this.value});

  final AsyncValue<dynamic> value;

  @override
  Widget build(BuildContext context) {
    final items = (value.value?.items as List<Post>?) ?? const <Post>[];
    if (value.isLoading && items.isEmpty) return const SliverToBoxAdapter(child: CenteredLoader());
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: EmptyState(icon: AppIcons.reels, title: 'No reels yet', compact: true));
    }
    final c = context.colors;
    return SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 9 / 16, mainAxisSpacing: 2, crossAxisSpacing: 2),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final reel = items[i];
        final thumb = reel.video?.thumbnailUrl;
        return GestureDetector(
          onTap: () => context.push('/post/${reel.id}'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumb != null)
                AppImage(thumb)
              else
                DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [c.ink, c.accent], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(reel.body ?? '', maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
              Positioned(
                left: 6,
                bottom: 6,
                child: Row(
                  children: [
                    const Icon(AppIcons.play, size: 12, color: Colors.white),
                    const SizedBox(width: 3),
                    Text(compactCount(reel.viewsCount), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _About extends ConsumerWidget {
  const _About({required this.profile, required this.isSelf});

  final Profile profile;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final achievements = ref.watch(achievementsProvider(profile.id));
    final events = ref.watch(userEventsProvider(profile.id)).value ?? const [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (profile.skills.isNotEmpty) ...[
            Text('Skills', style: context.text.headlineSmall),
            const SizedBox(height: Space.sm),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final s in profile.skills) Tag(label: s)]),
            const SizedBox(height: Space.xl),
          ],
          if (profile.interests.isNotEmpty) ...[
            Text('Interests', style: context.text.headlineSmall),
            const SizedBox(height: Space.sm),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final i in profile.interests) Tag(label: Interests.label(i))]),
            const SizedBox(height: Space.xl),
          ],
          Row(
            children: [
              Expanded(child: Text('Achievements', style: context.text.headlineSmall)),
              if (isSelf)
                TextButton.icon(
                  onPressed: () => _addAchievement(context, ref),
                  icon: const Icon(AppIcons.plus, size: 16),
                  label: const Text('Add'),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          achievements.when(
            loading: () => const CenteredLoader(),
            error: (e, _) => ErrorState(error: e, compact: true),
            data: (list) => list.isEmpty
                ? Text(isSelf ? 'Add hackathon wins, certifications and more.' : 'Nothing added yet.', style: context.text.bodySmall)
                : Column(
                    children: [
                      for (final a in list)
                        Container(
                          margin: const EdgeInsets.only(bottom: Space.sm),
                          padding: const EdgeInsets.all(Space.md),
                          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.md), border: Border.all(color: c.line)),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(color: c.warningSoft, borderRadius: BorderRadius.circular(12)),
                                child: Icon(AppIcons.trophyFill, color: c.warning, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(a.title, style: context.text.titleSmall),
                                    Text(
                                      [
                                        Achievement.categories[a.category] ?? 'Other',
                                        ?a.issuer,
                                        if (a.achievedOn != null) DateFormat('MMM y').format(a.achievedOn!),
                                      ].join(' · '),
                                      style: context.text.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelf)
                                IconButton(
                                  tooltip: 'Delete',
                                  icon: Icon(AppIcons.trash, size: 18, color: c.inkSubtle),
                                  onPressed: () async {
                                    await ref.read(profileRepositoryProvider).deleteAchievement(a.id);
                                    ref.invalidate(achievementsProvider(profile.id));
                                  },
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          if (events.isNotEmpty) ...[
            const SizedBox(height: Space.xl),
            Text('Events', style: context.text.headlineSmall),
            for (final e in events.take(5)) EventRow(event: e),
          ],
          if (profile.createdAt != null) ...[
            const SizedBox(height: Space.xl),
            Text('Joined Quad ${DateFormat('MMMM y').format(profile.createdAt!)}', style: context.text.bodySmall),
          ],
        ],
      ),
    );
  }

  Future<void> _addAchievement(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final issuer = TextEditingController();
    var category = 'hackathon';
    await showAppSheet<void>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add an achievement', style: sheetContext.text.headlineSmall),
              const SizedBox(height: Space.lg),
              AppTextField(label: 'Title', hint: 'e.g. Winner, Smart India Hackathon', controller: title),
              const SizedBox(height: Space.md),
              AppTextField(label: 'Issuer (optional)', controller: issuer),
              const SizedBox(height: Space.md),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in Achievement.categories.entries)
                    PillChip(label: e.value, dense: true, selected: category == e.key, onTap: () => setSheet(() => category = e.key)),
                ],
              ),
              const SizedBox(height: Space.xl),
              AppButton(
                label: 'Add',
                expand: true,
                onPressed: () async {
                  if (title.text.trim().length < 2) return;
                  try {
                    await ref.read(profileRepositoryProvider).addAchievement(
                          title: title.text.trim(),
                          category: category,
                          issuer: issuer.text.trim().isEmpty ? null : issuer.text.trim(),
                          achievedOn: DateTime.now(),
                        );
                    ref.invalidate(achievementsProvider(profile.id));
                    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                  } catch (error) {
                    if (sheetContext.mounted) showToast(sheetContext, friendlyError(error), error: true);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
    title.dispose();
    issuer.dispose();
  }
}
