import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/supabase_providers.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../posts/ui/post_card.dart';
import '../data/community.dart';
import '../data/community_repository.dart';
import '../providers.dart';

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

/// Members grouped as staff first. Moderators get management actions.
class MemberList extends ConsumerWidget {
  const MemberList({super.key, required this.community, this.status = 'active'});

  final Community community;
  final String status;

  Future<void> _manage(BuildContext context, WidgetRef ref, CommunityMember member) async {
    final repo = ref.read(communityRepositoryProvider);
    final key = (communityId: community.id, status: status);
    Future<void> run(Future<void> Function() action, String done) async {
      try {
        await action();
        ref.invalidate(communityMembersProvider(key));
        if (context.mounted) showToast(context, done);
      } catch (error) {
        if (context.mounted) showToast(context, friendlyError(error), error: true);
      }
    }

    await showActionSheet(
      context,
      title: member.user.fullName,
      actions: [
        SheetAction(icon: AppIcons.user, label: 'View profile', onTap: () => context.push('/u/${member.user.username}')),
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
        ] else if (member.role != 'owner') ...[
          if (community.isAdmin && member.role == 'member')
            SheetAction(
              icon: AppIcons.shield,
              label: 'Make moderator',
              onTap: () => run(() => repo.setRole(community.id, member.user.id, 'moderator'), 'Now a moderator'),
            ),
          if (community.isOwner && member.role != 'admin')
            SheetAction(
              icon: AppIcons.shield,
              label: 'Make admin',
              onTap: () => run(() => repo.setRole(community.id, member.user.id, 'admin'), 'Now an admin'),
            ),
          if (community.isAdmin && member.role != 'member')
            SheetAction(
              icon: AppIcons.user,
              label: 'Remove staff role',
              onTap: () => run(() => repo.setRole(community.id, member.user.id, 'member'), 'Role removed'),
            ),
          SheetAction(
            icon: AppIcons.signOut,
            label: 'Remove from community',
            destructive: true,
            onTap: () => run(() => repo.removeMember(community.id, member.user.id), 'Removed'),
          ),
          SheetAction(
            icon: AppIcons.block,
            label: 'Ban',
            destructive: true,
            onTap: () async {
              final ok = await confirm(
                context,
                title: 'Ban ${member.user.firstName}?',
                message: 'They\'ll be removed and can\'t rejoin until unbanned.',
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
            icon: AppIcons.users,
            title: status == 'pending' ? 'No pending requests' : 'No members yet',
            compact: true,
          );
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final member = list[i];
            final canManage = community.isMod && member.user.id != me;
            return PersonRow(
              user: member.user,
              subtitle: member.department ?? '@${member.user.username}',
              onTap: canManage ? () => _manage(context, ref, member) : null,
              trailing: status == 'pending'
                  ? Text('Tap to review', style: context.text.labelSmall!.copyWith(color: context.colors.accentInk))
                  : RoleBadge(role: member.role),
            );
          },
        );
      },
    );
  }
}
