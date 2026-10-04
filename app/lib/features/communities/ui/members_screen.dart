import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/supabase_providers.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../posts/ui/post_card.dart';
import '../data/community.dart';
import '../data/community_repository.dart';
import '../providers.dart';
import 'roles.dart';

class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final community = ref.watch(communityProvider(slug)).value;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        title: Text(community == null ? 'Members' : '${community.name} members'),
      ),
      body: community == null ? const CenteredLoader() : MemberList(community: community),
    );
  }
}

/// Members, highest rank first. Tapping someone ranked below you opens what
/// your permissions allow: roles, removing or banning.
class MemberList extends ConsumerWidget {
  const MemberList({super.key, required this.community, this.status = 'active'});

  final Community community;

  /// 'active', 'pending' (join requests) or 'banned'.
  final String status;

  bool _outranks(CommunityMember member) => member.rank < community.myRank;

  bool _canManage(CommunityMember member) => switch (status) {
    'pending' => community.can(CommunityPermissions.manageMembers),
    'banned' => community.can(CommunityPermissions.banMembers),
    _ =>
      _outranks(member) &&
          (community.can(CommunityPermissions.manageRoles) ||
              community.can(CommunityPermissions.manageMembers) ||
              community.can(CommunityPermissions.banMembers)),
  };

  Future<void> _manage(BuildContext context, WidgetRef ref, CommunityMember member) async {
    final repo = ref.read(communityRepositoryProvider);
    Future<void> run(Future<void> Function() action, String done) async {
      try {
        await action();
        ref.invalidate(communityMembersProvider);
        if (context.mounted) showToast(context, done);
      } catch (error) {
        if (context.mounted) showToast(context, friendlyError(error), error: true);
      }
    }

    final name = member.user.firstName;
    await showActionSheet(
      context,
      title: member.user.fullName,
      actions: [
        SheetAction(
          icon: AppIcons.user,
          label: 'View profile',
          onTap: () => context.push('/u/${member.user.username}'),
        ),
        if (status == 'pending') ...[
          SheetAction(
            icon: AppIcons.check,
            label: 'Approve request',
            onTap: () => run(() => repo.setStatus(community.id, member.user.id, 'active'), 'Approved'),
          ),
          SheetAction(
            icon: AppIcons.close,
            label: 'Decline request',
            destructive: true,
            onTap: () => run(() => repo.removeMember(community.id, member.user.id), 'Declined'),
          ),
        ] else if (status == 'banned')
          SheetAction(
            icon: AppIcons.check,
            label: 'Lift ban',
            subtitle: 'They\'ll be a member again',
            onTap: () => run(() => repo.setStatus(community.id, member.user.id, 'active'), 'Ban lifted'),
          )
        else ...[
          if (community.can(CommunityPermissions.manageRoles))
            SheetAction(
              icon: AppIcons.roles,
              label: 'Edit roles',
              subtitle: member.roles.isEmpty ? 'No roles yet' : member.roles.map((r) => r.name).join(', '),
              onTap: () async {
                final saved = await showAppSheet<bool>(
                  context,
                  builder: (_) => MemberRolesSheet(community: community, member: member),
                );
                if (saved ?? false) {
                  ref.invalidate(communityMembersProvider);
                  if (context.mounted) showToast(context, 'Roles updated');
                }
              },
            ),
          if (community.can(CommunityPermissions.manageMembers))
            SheetAction(
              icon: AppIcons.signOut,
              label: 'Remove from community',
              subtitle: 'They can join again',
              destructive: true,
              onTap: () async {
                final ok = await confirm(
                  context,
                  title: 'Remove $name?',
                  message: 'They\'ll lose their roles. They can join again later.',
                  confirmLabel: 'Remove',
                  destructive: true,
                );
                if (ok) await run(() => repo.removeMember(community.id, member.user.id), 'Removed');
              },
            ),
          if (community.can(CommunityPermissions.banMembers))
            SheetAction(
              icon: AppIcons.block,
              label: 'Ban',
              subtitle: 'Removes them and blocks rejoining',
              destructive: true,
              onTap: () async {
                final ok = await confirm(
                  context,
                  title: 'Ban $name?',
                  message: 'They\'ll be removed and can\'t rejoin until the ban is lifted.',
                  confirmLabel: 'Ban',
                  destructive: true,
                );
                if (ok) await run(() => repo.setStatus(community.id, member.user.id, 'banned'), 'Banned');
              },
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (communityId: community.id, status: status);
    final members = ref.watch(communityMembersProvider(key));
    final me = ref.watch(currentUserIdProvider);
    return members.when(
      loading: () => const ListSkeleton(),
      error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(communityMembersProvider(key))),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: status == 'banned' ? AppIcons.block : AppIcons.users,
            title: switch (status) {
              'pending' => 'No pending requests',
              'banned' => 'Nobody is banned',
              _ => 'No members yet',
            },
            compact: true,
          );
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final member = list[i];
            final canManage = member.user.id != me && _canManage(member);
            return PersonRow(
              user: member.user,
              subtitle: member.department ?? '@${member.user.username}',
              onTap: canManage ? () => _manage(context, ref, member) : null,
              trailing: switch (status) {
                'pending' => Text(
                  'Tap to review',
                  style: context.text.labelSmall!.copyWith(color: context.colors.accentInk),
                ),
                'banned' => Text(canManage ? 'Tap to unban' : 'Banned', style: context.text.labelSmall),
                _ => MemberRoleChips(member: member),
              },
            );
          },
        );
      },
    );
  }
}
