import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/realtime.dart';
import '../../../core/data/supabase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/states.dart';
import '../data/chat_models.dart';
import '../providers.dart';

enum _Filter { all, unread, direct, groups, rooms }

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  _Filter _filter = _Filter.all;

  bool _matches(Conversation c) => switch (_filter) {
        _Filter.all => true,
        _Filter.unread => c.unreadCount > 0,
        _Filter.direct => c.isDirect,
        _Filter.groups => c.isGroup,
        _Filter.rooms => c.isRoom,
      };

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(chatListProvider);
    return Scaffold(
      body: Column(
        children: [
          TabHeader(
            title: 'Chats',
            actions: [
              IconTap(icon: AppIcons.newChat, tooltip: 'New chat', onTap: () => context.push('/chat/new')),
            ],
            bottom: Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 0, Space.sm),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                    child: SearchField(hint: 'Search messages', readOnly: true, onTap: () => context.push('/chat/search')),
                  ),
                  const SizedBox(height: Space.md),
                  ChipRow(
                    children: [
                      for (final filter in _Filter.values)
                        PillChip(
                          label: switch (filter) {
                            _Filter.all => 'All',
                            _Filter.unread => 'Unread',
                            _Filter.direct => 'Direct',
                            _Filter.groups => 'Groups',
                            _Filter.rooms => 'Rooms',
                          },
                          dense: true,
                          selected: _filter == filter,
                          onTap: () => setState(() => _filter = filter),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: list.when(
              loading: () => const ListSkeleton(count: 7, itemBuilder: _rowSkeleton),
              error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(chatListProvider)),
              data: (all) {
                final shown = all.where(_matches).toList();
                if (shown.isEmpty) {
                  return EmptyState(
                    icon: AppIcons.chat,
                    title: _filter == _Filter.all ? 'No chats yet' : 'Nothing here',
                    message: _filter == _Filter.all ? 'Message a classmate or start a group for your project.' : null,
                    actionLabel: _filter == _Filter.all ? 'Start a chat' : null,
                    onAction: () => context.push('/chat/new'),
                  );
                }
                return RefreshIndicator(
                  color: context.colors.ink,
                  onRefresh: ref.read(chatListProvider.notifier).refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: shown.length,
                    itemBuilder: (_, i) => ConversationRow(conversation: shown[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Widget _rowSkeleton(int _) => const RowSkeleton(avatarSize: 52);

class ConversationRow extends ConsumerWidget {
  const ConversationRow({super.key, required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final me = ref.watch(currentUserIdProvider);
    final online = conversation.isDirect && ref.watch(onlineUsersProvider).contains(conversation.otherUser?.id);
    final unread = conversation.unreadCount > 0;
    final fromMe = conversation.lastMessageSenderId == me;
    final preview = conversation.lastMessagePreview ?? (conversation.isGroup ? 'Group created' : 'Say hi 👋');

    return InkWell(
      onTap: () => context.push(conversation.isRoom && conversation.room != null ? '/room/${conversation.room!.id}' : '/chat/${conversation.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: 9),
        child: Row(
          children: [
            ConversationAvatar(conversation: conversation, online: online, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall!.copyWith(fontSize: 15.5, fontWeight: unread ? FontWeight.w800 : FontWeight.w600),
                        ),
                      ),
                      if (conversation.muted) ...[Icon(AppIcons.mute, size: 14, color: c.inkSubtle), const SizedBox(width: 4)],
                      Text(
                        chatTime(conversation.sortTime),
                        style: context.text.labelSmall!.copyWith(
                          color: unread ? c.accentInk : c.inkSubtle,
                          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (conversation.isRoom && conversation.room != null)
                        Text('${conversation.room!.community.name} · ', style: context.text.bodySmall!.copyWith(color: c.inkSubtle)),
                      Expanded(
                        child: Text(
                          '${fromMe ? 'You: ' : ''}$preview',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall!.copyWith(
                            color: unread ? c.ink : c.inkMuted,
                            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unread) ...[const SizedBox(width: 8), CountBadge(count: conversation.unreadCount, muted: conversation.muted)],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Person photo for direct chats, community icon for rooms, initials for groups.
class ConversationAvatar extends StatelessWidget {
  const ConversationAvatar({super.key, required this.conversation, this.online = false, this.size = 48});

  final Conversation conversation;
  final bool online;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (conversation.isRoom && conversation.room != null) {
      final community = conversation.room!.community;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          CommunityAvatar(name: community.name, color: community.color, url: community.avatarUrl, size: size),
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: context.colors.ink,
                shape: BoxShape.circle,
                border: Border.all(color: context.colors.background, width: 2),
              ),
              child: Icon(AppIcons.hash, size: size * 0.2, color: context.colors.inkInverse),
            ),
          ),
        ],
      );
    }
    return UserAvatar(
      name: conversation.displayName,
      url: conversation.otherUser?.avatarUrl ?? conversation.avatarUrl,
      size: size,
      online: online,
    );
  }
}

/// Shows people's typing as three bouncing dots.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.color});

  final Color? color;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.colors.inkMuted;
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Transform.translate(
              offset: Offset(0, -3 * _bounce((_controller.value - i * 0.18) % 1)),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }

  double _bounce(double t) => t < 0.5 ? Curves.easeOut.transform(t * 2) : Curves.easeIn.transform((1 - t) * 2);
}
