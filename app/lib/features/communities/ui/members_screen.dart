import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/supabase_providers.dart';
import '../../../core/theme/app_theme.dart';
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

/// Whether your roles let you act on [member] at all.
bool canActOn(Community community, CommunityMember member) => switch (member.status) {
  'pending' => community.can(CommunityPermissions.manageMembers),
  'banned' => community.can(CommunityPermissions.banMembers),
  _ =>
    member.rank < community.myRank &&
        (community.can(CommunityPermissions.manageRoles) ||
            community.can(CommunityPermissions.manageMembers) ||
            community.can(CommunityPermissions.banMembers)),
};

/// Staff actions for one member: view profile, roles (promote/demote), kick,
/// ban, or approve/decline and lift bans. Only what your permissions and rank
/// allow is offered; the database checks again.
Future<void> showMemberActions(
  BuildContext context,
  WidgetRef ref, {
  required Community community,
  required CommunityMember member,
}) async {
  HapticFeedback.mediumImpact();
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

  final manageable = canActOn(community, member) && member.user.id != ref.read(currentUserIdProvider);
  final name = member.user.firstName;
  await showActionSheet(
    context,
    title: member.user.fullName,
    actions: [
      SheetAction(icon: AppIcons.user, label: 'View profile', onTap: () => context.push('/u/${member.user.username}')),
      if (manageable && member.status == 'pending') ...[
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
      ] else if (manageable && member.status == 'banned')
        SheetAction(
          icon: AppIcons.check,
          label: 'Lift ban',
          subtitle: 'They\'ll be a member again',
          onTap: () => run(() => repo.setStatus(community.id, member.user.id, 'active'), 'Ban lifted'),
        )
      else if (manageable) ...[
        if (community.can(CommunityPermissions.manageRoles))
          SheetAction(
            icon: AppIcons.roles,
            label: 'Promote or change roles',
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
            icon: AppIcons.userMinus,
            label: 'Kick',
            subtitle: 'Remove from the community; they can join again',
            destructive: true,
            onTap: () async {
              final ok = await confirm(
                context,
                title: 'Kick $name?',
                message: 'They\'ll be removed and lose their roles. They can join again later.',
                confirmLabel: 'Kick',
                destructive: true,
              );
              if (ok) await run(() => repo.removeMember(community.id, member.user.id), 'Kicked $name');
            },
          ),
        if (community.can(CommunityPermissions.banMembers))
          SheetAction(
            icon: AppIcons.block,
            label: 'Ban',
            subtitle: 'Remove them and block rejoining',
            destructive: true,
            onTap: () async {
              final ok = await confirm(
                context,
                title: 'Ban $name?',
                message: 'They\'ll be removed and can\'t rejoin until the ban is lifted.',
                confirmLabel: 'Ban',
                destructive: true,
              );
              if (ok) await run(() => repo.setStatus(community.id, member.user.id, 'banned'), 'Banned $name');
            },
          ),
      ],
    ],
  );
}

/// Looks up [userId]'s membership, then shows [showMemberActions]. Used where
/// only the person is known (room chat, post authors).
Future<void> showMemberActionsFor(BuildContext context, WidgetRef ref, Community community, String userId) async {
  try {
    final member = await ref.read(communityRepositoryProvider).member(community.id, userId);
    if (!context.mounted) return;
    if (member == null) {
      showToast(context, 'They\'re not in this community anymore');
      return;
    }
    await showMemberActions(context, ref, community: community, member: member);
  } catch (error) {
    if (context.mounted) showToast(context, friendlyError(error), error: true);
  }
}

/// Members, highest rank first. Tap someone to see their profile; staff can
/// long-press to promote, kick or ban people ranked below them.
class MemberList extends ConsumerWidget {
  const MemberList({super.key, required this.community, this.status = 'active'});

  final Community community;

  /// 'active', 'pending' (join requests) or 'banned'.
  final String status;

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
        final staff = status == 'active' && community.isStaff;
        return ListView.builder(
          itemCount: list.length + (staff ? 1 : 0),
          itemBuilder: (_, index) {
            if (staff && index == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.xs),
                child: Text('Long-press someone to promote, kick or ban them.', style: context.text.bodySmall),
              );
            }
            final member = list[index - (staff ? 1 : 0)];
            final canManage = member.user.id != me && canActOn(community, member);
            void actions() => showMemberActions(context, ref, community: community, member: member);
            return PersonRow(
              user: member.user,
              subtitle: member.department ?? '@${member.user.username}',
              // Requests and bans are what these lists are for, so a tap acts.
              onTap: canManage && status != 'active' ? actions : null,
              onLongPress: canManage ? actions : null,
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
