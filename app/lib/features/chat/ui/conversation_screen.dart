import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/media.dart';
import '../../../core/data/realtime.dart';
import '../../../core/data/refs.dart';
import '../../../core/data/supabase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../calls/call_service.dart';
import '../../calls/ui/room_voice_bar.dart';
import '../../communities/data/community.dart';
import '../../communities/providers.dart';
import '../../communities/ui/members_screen.dart';
import '../../events/providers.dart';
import '../../events/ui/event_poster.dart';
import '../../moderation/data/moderation_repository.dart';
import '../../moderation/ui/report_sheet.dart';
import '../../posts/providers.dart';
import '../../profile/providers.dart';
import '../data/chat_models.dart';
import '../providers.dart';
import 'chat_list_screen.dart';
import 'stickers.dart';

const _quickReactions = ['👍', '❤️', '😂', '🔥', '😮', '🙏'];

/// A community room: its chat plus a bar to join voice or video.
class RoomScreen extends ConsumerWidget {
  const RoomScreen({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(roomProvider(roomId));
    return room.when(
      loading: () => Scaffold(appBar: AppBar(), body: const CenteredLoader()),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(error: error, onRetry: () => ref.invalidate(roomProvider(roomId))),
      ),
      data: (data) {
        if (data == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: AppIcons.hash, title: 'Room not found'),
          );
        }
        if (!data.isMember) {
          return Scaffold(
            appBar: AppBar(title: Text('#${data.name}')),
            body: const EmptyState(
              icon: AppIcons.lock,
              title: 'Join the community to chat',
              message: 'Rooms are open to community members.',
            ),
          );
        }
        return ConversationScreen(conversationId: data.conversationId, room: data);
      },
    );
  }
}

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key, required this.conversationId, this.room});

  final String conversationId;
  final Room? room;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Message? _replyTo;
  Message? _editing;
  bool _anonymous = false;
  bool _stickersOpen = false;
  late final ChatList _chatList = ref.read(chatListProvider.notifier);

  /// Room messages from private profiles are always anonymous.
  bool get _mustBeAnonymous => widget.room != null && (ref.read(myProfileProvider).value?.isPrivate ?? false);

  bool get _sendAnonymously => widget.room != null && (_anonymous || _mustBeAnonymous);

  @override
  void initState() {
    super.initState();
    _chatList.opened(widget.conversationId);
    // Typing brings the keyboard back in place of the sticker panel.
    _focus.addListener(() {
      if (_focus.hasFocus && _stickersOpen) setState(() => _stickersOpen = false);
    });
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
        ref.read(conversationProvider(widget.conversationId).notifier).loadOlder();
      }
    });
  }

  @override
  void dispose() {
    _chatList.closed(widget.conversationId);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  ConversationController get _controller => ref.read(conversationProvider(widget.conversationId).notifier);

  void _toggleStickers() {
    if (_stickersOpen) {
      setState(() => _stickersOpen = false);
      _focus.requestFocus();
    } else {
      _focus.unfocus();
      setState(() => _stickersOpen = true);
    }
  }

  Future<void> _sendSticker(String id) async {
    final replyTo = _replyTo;
    setState(() => _replyTo = null);
    try {
      await _controller.send(sticker: id, replyToId: replyTo?.id, anonymous: _sendAnonymously);
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    final editing = _editing;
    final replyTo = _replyTo;
    _input.clear();
    setState(() {
      _replyTo = null;
      _editing = null;
    });
    try {
      if (editing != null) {
        await _controller.edit(editing, text);
      } else {
        await _controller.send(text: text, replyToId: replyTo?.id, anonymous: _sendAnonymously);
      }
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    }
  }

  Future<void> _attach() async {
    await showActionSheet(
      context,
      actions: [
        SheetAction(
          icon: AppIcons.image,
          label: 'Photos',
          onTap: () async {
            final images = await MediaPicker.images(limit: 4);
            if (images.isEmpty) return;
            await _sendFiles(images);
          },
        ),
        SheetAction(
          icon: AppIcons.camera,
          label: 'Camera',
          onTap: () async {
            final image = await MediaPicker.image(source: ImageSource.camera);
            if (image != null) await _sendFiles([image]);
          },
        ),
        SheetAction(
          icon: AppIcons.file,
          label: 'File',
          onTap: () async {
            final file = await MediaPicker.anyFile();
            if (file == null) return;
            if (file.size > 25 * 1024 * 1024) {
              if (mounted) showToast(context, 'Files can be up to 25 MB.', error: true);
              return;
            }
            await _sendFiles([file]);
          },
        ),
      ],
    );
  }

  Future<void> _sendFiles(List<PickedFile> files) async {
    try {
      await _controller.send(
        files: files,
        text: _input.text.trim().isEmpty ? null : _input.text.trim(),
        replyToId: _replyTo?.id,
        anonymous: _sendAnonymously,
      );
      _input.clear();
      setState(() => _replyTo = null);
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    }
  }

  /// The room's community, for staff actions. Kept loaded by [build].
  Community? get _community {
    final slug = ref.read(conversationProvider(widget.conversationId)).value?.info.room?.community.slug;
    return slug == null ? null : ref.read(communityProvider(slug)).value;
  }

  Future<void> _messageMenu(Message message, bool mine) async {
    HapticFeedback.mediumImpact();
    final community = widget.room == null ? null : _community;
    final sender = message.senderId;
    final canModerate = !mine && (community?.can(CommunityPermissions.manageMessages) ?? false);
    final memberOptions = !mine && sender != null && !message.isAnonymous && (community?.isStaff ?? false);
    await showAppSheet<void>(
      context,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final emoji in _quickReactions)
                    InkResponse(
                      radius: 26,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _controller.toggleReaction(message, emoji).catchError((Object error) {
                          if (mounted) showToast(context, friendlyError(error), error: true);
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(emoji, style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(AppIcons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                setState(() => _replyTo = message);
                _focus.requestFocus();
              },
            ),
            if (message.body != null && !message.isSticker)
              ListTile(
                leading: const Icon(AppIcons.copy),
                title: const Text('Copy text'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: message.body!));
                  Navigator.of(sheetContext).pop();
                  showToast(context, 'Copied');
                },
              ),
            if (mine && message.kind == 'text')
              ListTile(
                leading: const Icon(AppIcons.edit),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() {
                    _editing = message;
                    _replyTo = null;
                    _input.text = message.body ?? '';
                  });
                  _focus.requestFocus();
                },
              ),
            if (memberOptions)
              ListTile(
                leading: const Icon(AppIcons.roles),
                title: const Text('Member options'),
                subtitle: const Text('Profile, promote, kick or ban'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showMemberActionsFor(context, ref, community!, sender);
                },
              ),
            if (canModerate)
              ListTile(
                leading: Icon(AppIcons.shield, color: sheetContext.colors.danger),
                title: Text('Remove message', style: TextStyle(color: sheetContext.colors.danger)),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    await ref
                        .read(moderationRepositoryProvider)
                        .moderate(targetType: 'message', targetId: message.id, action: 'remove');
                    if (mounted) showToast(context, 'Message removed');
                  } catch (error) {
                    if (mounted) showToast(context, friendlyError(error), error: true);
                  }
                },
              ),
            if (mine)
              ListTile(
                leading: Icon(AppIcons.trash, color: sheetContext.colors.danger),
                title: Text('Unsend', style: TextStyle(color: sheetContext.colors.danger)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _controller.unsend(message).catchError((Object error) {
                    if (mounted) showToast(context, friendlyError(error), error: true);
                  });
                },
              )
            else
              ListTile(
                leading: Icon(AppIcons.flag, color: sheetContext.colors.danger),
                title: Text('Report', style: TextStyle(color: sheetContext.colors.danger)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showReportSheet(context, targetType: 'message', targetId: message.id, what: 'message');
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(conversationProvider(widget.conversationId));
    // Keep the room's community (and your permissions in it) loaded for staff actions.
    final roomCommunity = state.value?.info.room?.community.slug;
    if (roomCommunity != null) ref.watch(communityProvider(roomCommunity));
    final c = context.colors;
    final scaffold = Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        titleSpacing: 0,
        shape: Border(bottom: BorderSide(color: c.line)),
        title: state.value == null ? null : _Header(state: state.value!, room: widget.room),
        actions: [
          if (state.value != null && widget.room == null) ...[
            IconButton(
              tooltip: 'Voice call',
              icon: const Icon(AppIcons.phone),
              onPressed: () => startCall(context, ref, widget.conversationId, video: false),
            ),
            IconButton(
              tooltip: 'Video call',
              icon: const Icon(AppIcons.videoCall),
              onPressed: () => startCall(context, ref, widget.conversationId, video: true),
            ),
          ],
          IconButton(
            tooltip: 'Details',
            icon: const Icon(AppIcons.info),
            onPressed: () => widget.room != null
                ? context.push('/c/${state.value?.info.room?.community.slug ?? ''}')
                : context.push('/chat/${widget.conversationId}/info'),
          ),
        ],
      ),
      body: state.when(
        loading: () => const CenteredLoader(),
        error: (error, _) =>
            ErrorState(error: error, onRetry: () => ref.invalidate(conversationProvider(widget.conversationId))),
        data: (chat) => Column(
          children: [
            if (widget.room != null) RoomVoiceBar(room: widget.room!),
            Expanded(
              child: _MessageList(
                chat: chat,
                scroll: _scroll,
                onLongPress: _messageMenu,
                onSwipeReply: (m) {
                  HapticFeedback.selectionClick();
                  setState(() => _replyTo = m);
                  _focus.requestFocus();
                },
              ),
            ),
            if (chat.typing.isNotEmpty) _TypingLine(chat: chat),
            _Composer(
              controller: _input,
              focusNode: _focus,
              replyTo: _replyTo,
              replyName: _replyTo == null ? null : senderOf(chat, _replyTo!)?.fullName,
              editing: _editing != null,
              anonymous: widget.room == null ? null : _sendAnonymously,
              anonymousLocked: _mustBeAnonymous,
              onAnonymousToggle: () {
                HapticFeedback.selectionClick();
                setState(() => _anonymous = !_anonymous);
                showToast(context, _anonymous ? 'Your messages here are now anonymous' : 'Sending as yourself');
              },
              onCancel: () => setState(() {
                _replyTo = null;
                if (_editing != null) _input.clear();
                _editing = null;
              }),
              onAttach: _attach,
              onSend: _send,
              onTyping: () => _controller.notifyTyping(anonymous: _sendAnonymously),
              stickersOpen: _stickersOpen,
              onStickers: _toggleStickers,
            ),
            if (_stickersOpen && _editing == null)
              Padding(
                padding: EdgeInsets.only(bottom: context.safePadding.bottom),
                child: StickerPanel(onPick: _sendSticker),
              ),
          ],
        ),
      ),
    );
    // Back closes the sticker panel before leaving the chat.
    return PopScope(
      canPop: !_stickersOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _stickersOpen = false);
      },
      child: scaffold,
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.state, this.room});

  final ChatState state;
  final Room? room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = state.info;
    final me = ref.watch(currentUserIdProvider);
    final c = context.colors;
    final String title;
    final Widget avatar;
    String subtitle;

    if (room != null || info.type == 'room') {
      final community = info.room?.community;
      title = '#${room?.name ?? info.title ?? 'room'}';
      avatar = CommunityAvatar(
        name: community?.name ?? title,
        color: community?.color ?? 0,
        url: community?.avatarUrl,
        size: 36,
      );
      subtitle = community?.name ?? 'Room';
    } else if (info.type == 'direct') {
      final other = info.members.where((m) => m.user.id != me).firstOrNull?.user;
      title = other?.fullName ?? 'Chat';
      final online = other != null && ref.watch(onlineUsersProvider).contains(other.id);
      avatar = UserAvatar(name: title, url: other?.avatarUrl, size: 36, online: online);
      subtitle = online ? 'Online' : lastSeen(other?.lastSeenAt);
    } else {
      title = info.title ?? 'Group';
      avatar = UserAvatar(name: title, url: info.avatarUrl, size: 36);
      subtitle = plural(info.members.length, 'member');
    }
    if (state.typing.isNotEmpty) subtitle = 'typing…';

    return Row(
      children: [
        avatar,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                subtitle,
                style: context.text.bodySmall!.copyWith(
                  color: subtitle == 'Online' || subtitle == 'typing…' ? c.success : c.inkMuted,
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Who to show for [message]: its anonymous alias, or the member who sent it.
UserRef? senderOf(ChatState chat, Message message) => message.isAnonymous
    ? UserRef(id: '', username: '', fullName: message.anonName ?? 'anonymous', isAnonymous: true)
    : chat.people[message.senderId];

/// Groups consecutive messages from the same person. Every anonymous message
/// has its own alias, so they never group.
String _groupKey(Message message) => message.isAnonymous ? 'anon:${message.id}' : (message.senderId ?? '');

class _MessageList extends ConsumerWidget {
  const _MessageList({required this.chat, required this.scroll, required this.onLongPress, required this.onSwipeReply});

  final ChatState chat;
  final ScrollController scroll;
  final void Function(Message message, bool mine) onLongPress;
  final ValueChanged<Message> onSwipeReply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final messages = chat.messages.reversed.toList();
    if (messages.isEmpty) {
      return const EmptyState(icon: AppIcons.chat, title: 'No messages yet', message: 'Say hi and break the ice 👋');
    }
    return ListView.builder(
      controller: scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: messages.length + (chat.loadingOlder ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) return const CenteredLoader(padding: 12);
        final message = messages[index];
        final newer = index > 0 ? messages[index - 1] : null;
        final older = index < messages.length - 1 ? messages[index + 1] : null;
        final mine = me != null && chat.isMine(message, me);
        final startsGroup =
            older == null ||
            _groupKey(older) != _groupKey(message) ||
            older.isSystem ||
            message.createdAt.difference(older.createdAt).inMinutes > 5;
        final endsGroup =
            newer == null ||
            _groupKey(newer) != _groupKey(message) ||
            newer.isSystem ||
            newer.createdAt.difference(message.createdAt).inMinutes > 5;
        final newDay = older == null || !_sameDay(older.createdAt, message.createdAt);

        return Column(
          children: [
            if (newDay) _DaySeparator(date: message.createdAt),
            if (message.isSystem)
              _SystemLine(message: message, sender: chat.people[message.senderId])
            else
              _Bubble(
                message: message,
                mine: mine,
                sender: senderOf(chat, message),
                avatarColumn: chat.info.type != 'direct',
                showName: startsGroup && !mine && chat.info.type != 'direct',
                showAvatar: endsGroup && !mine && chat.info.type != 'direct',
                tail: endsGroup,
                replyTo: chat.byId(message.replyToId),
                replyName: switch (chat.byId(message.replyToId)) {
                  final reply? => reply.isAnonymous ? reply.anonName : chat.people[reply.senderId]?.firstName,
                  null => null,
                },
                gapAbove: startsGroup ? 10 : 2,
                onLongPress: () => onLongPress(message, mine),
                onSwipeReply: () => onSwipeReply(message),
                onRetry: () => ref.read(conversationProvider(message.conversationId).notifier).retry(message),
                onReact: (emoji) =>
                    ref.read(conversationProvider(message.conversationId).notifier).toggleReaction(message, emoji),
                me: me,
              ),
          ],
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) {
    final x = a.toLocal();
    final y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(dayLabel(date), style: context.text.labelSmall!.copyWith(color: context.colors.inkSubtle)),
    );
  }
}

class _SystemLine extends StatelessWidget {
  const _SystemLine({required this.message, required this.sender});

  final Message message;
  final UserRef? sender;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isCall = message.kind == 'call';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isCall) ...[
            Icon(message.body == 'Video call' ? AppIcons.videoCall : AppIcons.phone, size: 14, color: c.inkMuted),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              isCall
                  ? '${sender?.firstName ?? 'Someone'} started a ${message.body?.toLowerCase() ?? 'call'} · ${clockTime(message.createdAt)}'
                  : '${sender?.firstName ?? 'Someone'} ${message.body ?? ''}',
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatefulWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.sender,
    required this.avatarColumn,
    required this.showName,
    required this.showAvatar,
    required this.tail,
    required this.replyTo,
    required this.replyName,
    required this.gapAbove,
    required this.onLongPress,
    required this.onSwipeReply,
    required this.onRetry,
    required this.onReact,
    required this.me,
  });

  final Message message;
  final bool mine;
  final UserRef? sender;

  /// Group chats and rooms keep a column for avatars so bubbles line up.
  final bool avatarColumn;
  final bool showName;
  final bool showAvatar;
  final bool tail;
  final Message? replyTo;
  final String? replyName;
  final double gapAbove;
  final VoidCallback onLongPress;
  final VoidCallback onSwipeReply;
  final VoidCallback onRetry;
  final ValueChanged<String> onReact;
  final String? me;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  double _drag = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final message = widget.message;
    final mine = widget.mine;
    final bg = mine ? c.ink : c.surface;
    final fg = mine ? c.inkInverse : c.ink;
    const radius = Radius.circular(20);
    const small = Radius.circular(6);
    final borderRadius = BorderRadius.only(
      topLeft: radius,
      topRight: radius,
      bottomLeft: !mine && widget.tail ? small : radius,
      bottomRight: mine && widget.tail ? small : radius,
    );

    Widget content;
    if (message.isDeleted) {
      content = Text(
        'Message unsent',
        style: context.text.bodyMedium!.copyWith(color: fg.withValues(alpha: 0.6), fontStyle: FontStyle.italic),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.replyTo != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
              decoration: BoxDecoration(
                color: (mine ? Colors.white : c.ink).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border(left: BorderSide(color: c.accent, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.replyName ?? 'Reply',
                    style: context.text.labelSmall!.copyWith(color: mine ? Colors.white70 : c.accentInk),
                  ),
                  Text(
                    widget.replyTo!.preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall!.copyWith(color: fg.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),
          for (final attachment in message.attachments) _AttachmentView(attachment: attachment, mine: mine),
          if (message.sharedPostId != null) _SharedPost(postId: message.sharedPostId!, mine: mine),
          if (message.sharedEventId != null) _SharedEvent(eventId: message.sharedEventId!, mine: mine),
          if (message.body != null && message.kind != 'post')
            Padding(
              padding: EdgeInsets.only(top: message.attachments.isEmpty ? 0 : 6),
              child: Text(message.body!, style: context.text.bodyMedium!.copyWith(color: fg, height: 1.35)),
            ),
        ],
      );
    }

    Widget meta(Color fg) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.editedAt != null && !message.isDeleted)
          Text('edited · ', style: context.text.labelSmall!.copyWith(color: fg.withValues(alpha: 0.5), fontSize: 10)),
        Text(
          clockTime(message.createdAt),
          style: context.text.labelSmall!.copyWith(color: fg.withValues(alpha: 0.55), fontSize: 10.5),
        ),
        if (message.isAnonymous) ...[
          const SizedBox(width: 4),
          Icon(AppIcons.anonymous, size: 11, color: fg.withValues(alpha: 0.55)),
        ],
        if (mine) ...[
          const SizedBox(width: 3),
          Icon(
            switch (message.sendState) {
              SendState.sending => AppIcons.clock,
              SendState.failed => AppIcons.warning,
              SendState.sent => AppIcons.check,
            },
            size: 12,
            color: message.sendState == SendState.failed ? c.danger : fg.withValues(alpha: 0.55),
          ),
        ],
      ],
    );

    // Stickers float on their own, without a bubble.
    final Widget bubble = message.isSticker && !message.isDeleted
        ? Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.replyTo != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.6),
                  decoration: BoxDecoration(
                    color: c.surfaceMuted,
                    borderRadius: BorderRadius.circular(10),
                    border: Border(left: BorderSide(color: c.accent, width: 3)),
                  ),
                  child: Text(
                    '${widget.replyName ?? 'Reply'}: ${widget.replyTo!.preview}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall,
                  ),
                ),
              StickerView(id: message.body ?? '', size: 128),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: meta(c.ink)),
            ],
          )
        : Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
            padding: EdgeInsets.fromLTRB(
              message.attachments.isNotEmpty ? 4 : 12,
              message.attachments.isNotEmpty ? 4 : 8,
              message.attachments.isNotEmpty ? 4 : 12,
              8,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: borderRadius,
              border: mine ? null : Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                content,
                const SizedBox(height: 2),
                Padding(
                  padding: EdgeInsets.only(right: message.attachments.isNotEmpty ? 6 : 0),
                  child: meta(fg),
                ),
              ],
            ),
          );

    final reactions = message.reactions.entries.where((e) => e.value.isNotEmpty).toList();

    return GestureDetector(
      onLongPress: message.isDeleted ? null : widget.onLongPress,
      onHorizontalDragUpdate: message.isDeleted
          ? null
          : (details) => setState(() => _drag = (_drag + details.delta.dx).clamp(0, 72)),
      onHorizontalDragEnd: (_) {
        if (_drag > 56) widget.onSwipeReply();
        setState(() => _drag = 0);
      },
      child: Padding(
        padding: EdgeInsets.only(top: widget.gapAbove),
        child: Stack(
          children: [
            if (_drag > 8)
              Positioned(
                left: 4,
                top: 0,
                bottom: 0,
                child: Opacity(
                  opacity: (_drag / 56).clamp(0, 1),
                  child: Icon(AppIcons.reply, color: c.inkMuted),
                ),
              ),
            AnimatedContainer(
              duration: Duration(milliseconds: _drag == 0 ? 180 : 0),
              transform: Matrix4.translationValues(_drag, 0, 0),
              child: Row(
                mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!mine && widget.avatarColumn)
                    SizedBox(
                      width: 36,
                      child: widget.showAvatar && widget.sender != null
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: GestureDetector(
                                onTap: widget.sender!.isAnonymous
                                    ? null
                                    : () => context.push('/u/${widget.sender!.username}'),
                                child: AuthorAvatar(user: widget.sender!, size: 28),
                              ),
                            )
                          : null,
                    ),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        if (widget.showName && widget.sender != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 12, bottom: 3),
                            child: Text(
                              widget.sender!.fullName,
                              style: context.text.labelSmall!.copyWith(
                                color: c.inkMuted,
                                fontStyle: widget.sender!.isAnonymous ? FontStyle.italic : null,
                              ),
                            ),
                          ),
                        bubble,
                        if (reactions.isNotEmpty)
                          Transform.translate(
                            offset: const Offset(0, -4),
                            child: Wrap(
                              spacing: 4,
                              children: [
                                for (final entry in reactions)
                                  GestureDetector(
                                    onTap: () => widget.onReact(entry.key),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: entry.value.contains(widget.me) ? c.accentSoft : c.surface,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: entry.value.contains(widget.me) ? c.accent : c.line),
                                      ),
                                      child: Text(
                                        '${entry.key}${entry.value.length > 1 ? ' ${entry.value.length}' : ''}',
                                        style: context.text.labelSmall,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (message.sendState == SendState.failed)
                          GestureDetector(
                            onTap: widget.onRetry,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2, right: 4),
                              child: Text(
                                'Not sent. Tap to retry',
                                style: context.text.labelSmall!.copyWith(color: c.danger),
                              ),
                            ),
                          ),
                      ],
                    ),
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

class _AttachmentView extends ConsumerWidget {
  const _AttachmentView({required this.attachment, required this.mine});

  final Attachment attachment;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    if (attachment.path.isEmpty) {
      return Container(
        width: 200,
        height: 140,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(16)),
        child: const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return FutureBuilder<String>(
      future: ref.read(storageRepositoryProvider).chatFileUrl(attachment.path),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (attachment.isImage) {
          final aspect = attachment.width != null && attachment.height != null && attachment.height! > 0
              ? (attachment.width! / attachment.height!).clamp(0.6, 1.8)
              : 1.2;
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 240,
                child: AspectRatio(
                  aspectRatio: aspect.toDouble(),
                  child: url == null
                      ? ColoredBox(color: c.surfaceMuted)
                      : GestureDetector(
                          onTap: () => launchUrl(Uri.parse(url)),
                          child: AppImage(url, semanticLabel: attachment.name),
                        ),
                ),
              ),
            ),
          );
        }
        final fg = mine ? c.inkInverse : c.ink;
        return InkWell(
          onTap: url == null ? null : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Container(
            width: 230,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(color: fg.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(AppIcons.file, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelMedium!.copyWith(color: fg),
                      ),
                      Text(
                        fileSize(attachment.size),
                        style: context.text.labelSmall!.copyWith(color: fg.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                Icon(AppIcons.download, size: 18, color: fg.withValues(alpha: 0.7)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SharedPost extends ConsumerWidget {
  const _SharedPost({required this.postId, required this.mine});

  final String postId;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final post = ref.watch(postProvider(postId)).value;
    final c = context.colors;
    final fg = mine ? c.inkInverse : c.ink;
    return GestureDetector(
      onTap: () => context.push('/post/$postId'),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: fg.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
        child: post == null
            ? Text('Post unavailable', style: context.text.bodySmall!.copyWith(color: fg))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AuthorAvatar(user: post.author, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          post.author.fullName,
                          style: context.text.labelMedium!.copyWith(color: fg),
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (post.images.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: AppImage(post.images.first.url, height: 120, width: double.infinity, radius: 10),
                    ),
                  Text(
                    post.title ?? post.body ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall!.copyWith(color: fg),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SharedEvent extends ConsumerWidget {
  const _SharedEvent({required this.eventId, required this.mine});

  final String eventId;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(eventProvider(eventId)).value;
    if (event == null) return const SizedBox(width: 200, height: 60);
    return GestureDetector(
      onTap: () => context.push('/event/$eventId'),
      child: SizedBox(width: 200, child: EventPoster.of(event, radius: 14)),
    );
  }
}

class _TypingLine extends StatelessWidget {
  const _TypingLine({required this.chat});

  final ChatState chat;

  @override
  Widget build(BuildContext context) {
    final names = chat.typing.map((id) => chat.people[id]?.firstName).whereType<String>().toList();
    final text = switch (names.length) {
      0 => 'Someone is typing',
      1 => '${names.first} is typing',
      2 => '${names[0]} and ${names[1]} are typing',
      _ => 'Several people are typing',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          const TypingDots(),
          const SizedBox(width: 8),
          Text(text, style: context.text.bodySmall),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.replyTo,
    required this.replyName,
    required this.editing,
    required this.onCancel,
    required this.onAttach,
    required this.onSend,
    required this.onTyping,
    required this.anonymous,
    required this.anonymousLocked,
    required this.onAnonymousToggle,
    required this.stickersOpen,
    required this.onStickers,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Message? replyTo;
  final String? replyName;
  final bool editing;
  final VoidCallback onCancel;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final VoidCallback onTyping;

  /// Whether messages go out anonymously; null where that isn't offered
  /// (only community rooms allow it).
  final bool? anonymous;
  final bool anonymousLocked;
  final VoidCallback onAnonymousToggle;
  final bool stickersOpen;
  final VoidCallback onStickers;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      // The sticker panel sits below and takes the bottom inset instead.
      padding: EdgeInsets.fromLTRB(6, 6, 6, 6 + (stickersOpen ? 0 : context.safePadding.bottom)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyTo != null || editing)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 4, 6),
              child: Row(
                children: [
                  Icon(editing ? AppIcons.edit : AppIcons.reply, size: 16, color: c.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          editing ? 'Editing message' : 'Replying to ${replyName ?? 'message'}',
                          style: context.text.labelMedium!.copyWith(color: c.accentInk),
                        ),
                        if (replyTo != null)
                          Text(
                            replyTo!.preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  IconButton(tooltip: 'Cancel', icon: const Icon(AppIcons.close, size: 18), onPressed: onCancel),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Attach',
                icon: Icon(AppIcons.plus, color: c.inkMuted),
                onPressed: editing ? null : onAttach,
              ),
              if (anonymous != null && !editing)
                IconButton(
                  tooltip: anonymousLocked
                      ? 'Your profile is private, so you\'re always anonymous here'
                      : (anonymous! ? 'Sending anonymously' : 'Send anonymously'),
                  onPressed: anonymousLocked ? null : onAnonymousToggle,
                  style: anonymous! ? IconButton.styleFrom(backgroundColor: c.accentSoft) : null,
                  icon: Icon(
                    anonymous! ? AppIcons.anonymous : AppIcons.anonymousOutline,
                    color: anonymous! ? c.accentInk : c.inkMuted,
                  ),
                ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => onTyping(),
                  style: context.text.bodyMedium,
                  decoration: InputDecoration(
                    hintText: anonymous ?? false ? 'Message anonymously' : 'Message',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    suffixIcon: editing
                        ? null
                        : IconButton(
                            tooltip: stickersOpen ? 'Keyboard' : 'Stickers',
                            icon: Icon(stickersOpen ? AppIcons.keyboard : AppIcons.sticker, color: c.inkMuted),
                            onPressed: onStickers,
                          ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(color: c.lineStrong),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final empty = controller.text.trim().isEmpty;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    margin: const EdgeInsets.only(bottom: 2, right: 2),
                    decoration: BoxDecoration(color: empty ? c.surfaceMuted : c.accent, shape: BoxShape.circle),
                    child: IconButton(
                      tooltip: editing ? 'Save' : 'Send',
                      onPressed: empty ? null : onSend,
                      icon: Icon(
                        editing ? AppIcons.check : AppIcons.send,
                        color: empty ? c.inkSubtle : Colors.white,
                        size: 20,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
