import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/realtime.dart';
import '../../../core/data/supabase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../posts/ui/post_card.dart';
import '../../profile/data/profile_repository.dart';
import '../data/chat_repository.dart';
import '../providers.dart';

class ConversationInfoScreen extends ConsumerWidget {
  const ConversationInfoScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationProvider(conversationId));
    final list = ref.watch(chatListProvider).value ?? const [];
    final muted = list.where((c) => c.id == conversationId).firstOrNull?.muted ?? false;
    final me = ref.watch(currentUserIdProvider);
    final online = ref.watch(onlineUsersProvider);
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        title: const Text('Details'),
      ),
      body: state.when(
        loading: () => const CenteredLoader(),
        error: (error, _) => ErrorState(error: error),
        data: (chat) {
          final info = chat.info;
          final isGroup = info.type == 'group';
          final myRole = info.members.where((m) => m.user.id == me).firstOrNull?.role;
          final other = info.members.where((m) => m.user.id != me).firstOrNull?.user;
          final title = isGroup ? (info.title ?? 'Group') : (other?.fullName ?? 'Chat');

          Future<void> run(Future<void> Function() action, [String? done]) async {
            try {
              await action();
              if (done != null && context.mounted) showToast(context, done);
            } catch (error) {
              if (context.mounted) showToast(context, friendlyError(error), error: true);
            }
          }

          return ListView(
            children: [
              const SizedBox(height: Space.lg),
              Center(child: UserAvatar(name: title, url: isGroup ? info.avatarUrl : other?.avatarUrl, size: 88)),
              const SizedBox(height: Space.md),
              Center(child: Text(title, style: context.text.headlineMedium)),
              if (isGroup) Center(child: Text(plural(info.members.length, 'member'), style: context.text.bodySmall)),
              const SizedBox(height: Space.lg),
              SwitchListTile(
                secondary: const Icon(AppIcons.mute),
                title: const Text('Mute notifications'),
                value: muted,
                onChanged: (value) => run(() async {
                  await ref.read(chatRepositoryProvider).setMuted(conversationId, value);
                  ref.read(chatListProvider.notifier).setMuted(conversationId, value);
                }),
              ),
              if (!isGroup && other != null) ...[
                ListTile(leading: const Icon(AppIcons.user), title: const Text('View profile'), onTap: () => context.push('/u/${other.username}')),
                ListTile(
                  leading: Icon(AppIcons.block, color: c.danger),
                  title: Text('Block ${other.firstName}', style: TextStyle(color: c.danger)),
                  onTap: () async {
                    final ok = await confirm(
                      context,
                      title: 'Block ${other.firstName}?',
                      message: 'They won\'t be able to message you or see your posts. They won\'t be told.',
                      confirmLabel: 'Block',
                      destructive: true,
                    );
                    if (ok) await run(() => ref.read(profileRepositoryProvider).block(other.id), 'Blocked');
                  },
                ),
              ],
              if (isGroup) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 4),
                  child: Text('Members', style: context.text.headlineSmall),
                ),
                for (final member in info.members)
                  PersonRow(
                    user: member.user,
                    online: online.contains(member.user.id),
                    subtitle: member.user.id == me ? 'You' : '@${member.user.username}',
                    trailing: member.isAdmin ? RoleBadge(role: member.role == 'owner' ? 'owner' : 'admin') : null,
                    onTap: (myRole == 'owner' || myRole == 'admin') && member.user.id != me && member.role != 'owner'
                        ? () => showActionSheet(
                              context,
                              title: member.user.fullName,
                              actions: [
                                SheetAction(icon: AppIcons.user, label: 'View profile', onTap: () => context.push('/u/${member.user.username}')),
                                SheetAction(
                                  icon: AppIcons.signOut,
                                  label: 'Remove from group',
                                  destructive: true,
                                  onTap: () => run(() async {
                                    await ref.read(chatRepositoryProvider).removeMember(conversationId, member.user.id);
                                    ref.invalidate(conversationProvider(conversationId));
                                  }, 'Removed'),
                                ),
                              ],
                            )
                        : null,
                  ),
                const Divider(),
                ListTile(
                  leading: Icon(AppIcons.signOut, color: c.danger),
                  title: Text('Leave group', style: TextStyle(color: c.danger)),
                  onTap: () async {
                    final ok = await confirm(
                      context,
                      title: 'Leave $title?',
                      message: 'You\'ll stop getting messages from this group.',
                      confirmLabel: 'Leave',
                      destructive: true,
                    );
                    if (!ok) return;
                    await run(() async {
                      await ref.read(chatRepositoryProvider).removeMember(conversationId, me!);
                      await ref.read(chatListProvider.notifier).refresh();
                      if (context.mounted) context.go('/chat');
                    });
                  },
                ),
              ],
              const SizedBox(height: Space.xxl),
            ],
          );
        },
      ),
    );
  }
}
