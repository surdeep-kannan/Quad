import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/avatars.dart';
import '../data/notification_repository.dart';

/// One notification: who did what, where, and when. Tapping opens it.
class NotificationTile extends ConsumerWidget {
  const NotificationTile({super.key, required this.notification, this.compact = false, this.onOpened});

  final AppNotification notification;
  final bool compact;
  final VoidCallback? onOpened;

  String get _route {
    final n = notification;
    return switch (n.type) {
      'follow' => '/u/${n.actor?.username}',
      'community_join_request' => '/c/${n.community?.slug}/manage',
      'community_join_approved' || 'community_role' => '/c/${n.community?.slug}',
      'event_registration' || 'event_update' || 'event_reminder' || 'event_waitlist_promoted' => '/event/${n.eventId}',
      'missed_call' => '/chat/${n.conversationId}',
      'room_invite' => '/room/${n.roomId}',
      _ => n.postId != null ? '/post/${n.postId}' : '/notifications',
    };
  }

  (IconData, String) _describe() {
    final n = notification;
    final who = n.actor?.fullName ?? 'Someone';
    final snippet = n.data['snippet'] as String?;
    final what = (n.post?['title'] as String?) ?? (n.post?['body'] as String?) ?? 'your post';
    return switch (n.type) {
      'follow' => (AppIcons.userPlus, '$who started following you'),
      'post_reaction' => (AppIcons.heartFill, '$who reacted to "$what"'),
      'post_comment' => (AppIcons.comment, '$who commented: ${snippet ?? ''}'),
      'comment_reply' => (AppIcons.reply, '$who replied: ${snippet ?? ''}'),
      'mention' => (AppIcons.at, '$who mentioned you: ${snippet ?? ''}'),
      'thread_activity' => (AppIcons.chatText, '$who commented on a discussion you follow'),
      'announcement' => (AppIcons.megaphone, '${n.community?.name ?? 'A community'}: ${snippet ?? 'new announcement'}'),
      'community_join_request' => (AppIcons.userPlus, '$who asked to join ${n.community?.name ?? 'your community'}'),
      'community_join_approved' => (AppIcons.checkCircle, 'You\'re in! ${n.community?.name ?? 'The community'} approved your request'),
      'community_role' => (AppIcons.shield, 'You\'re now ${n.data['role'] ?? 'staff'} of ${n.community?.name ?? 'a community'}'),
      'event_registration' => (AppIcons.ticket, '$who registered for ${n.event?['title'] ?? 'your event'}'),
      'event_update' => (AppIcons.megaphone, '${n.event?['title'] ?? 'Event'}: ${snippet ?? 'new update'}'),
      'event_reminder' => (AppIcons.clock, '${n.event?['title'] ?? 'Your event'} starts ${n.data['when'] == 'hour' ? 'within the hour' : 'tomorrow'}'),
      'event_waitlist_promoted' => (AppIcons.ticket, 'A spot opened up. You\'re going to ${n.event?['title'] ?? 'the event'}!'),
      'missed_call' => (AppIcons.phone, 'Missed ${n.data['kind'] == 'video' ? 'video' : 'voice'} call from $who'),
      'room_invite' => (AppIcons.hash, '$who invited you to #${n.data['room'] ?? 'a room'}'),
      'report_update' => (AppIcons.shield, 'Moderators reviewed your report'),
      'content_removed' => (AppIcons.warning, 'Your ${n.data['target'] ?? 'post'} was removed: ${n.data['reason'] ?? ''}'),
      _ => (AppIcons.bell, 'New activity'),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final (icon, text) = _describe();
    final actor = notification.actor;
    return InkWell(
      onTap: () {
        onOpened?.call();
        context.push(_route);
      },
      child: Container(
        color: notification.isUnread && !compact ? c.accentSoft.withValues(alpha: 0.4) : null,
        padding: EdgeInsets.symmetric(horizontal: Space.gutter, vertical: compact ? 10 : 12),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                if (actor != null)
                  UserAvatar(name: actor.fullName, url: actor.avatarUrl, size: 44)
                else if (notification.community != null)
                  CommunityAvatar(name: notification.community!.name, color: notification.community!.color, url: notification.community!.avatarUrl, size: 44)
                else
                  CircleAvatar(radius: 22, backgroundColor: c.surfaceMuted, child: Icon(icon, color: c.ink, size: 20)),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle, border: Border.all(color: c.surface, width: 2)),
                    child: Icon(icon, size: 11, color: c.inkInverse),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, maxLines: compact ? 2 : 3, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
                  const SizedBox(height: 2),
                  Text(timeAgo(notification.createdAt), style: context.text.bodySmall),
                ],
              ),
            ),
            if (notification.isUnread && !compact)
              Container(width: 8, height: 8, margin: const EdgeInsets.only(left: 8), decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle)),
          ],
        ),
      ),
    );
  }
}
