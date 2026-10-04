import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/data/media.dart';
import '../../core/data/realtime.dart';
import '../../core/data/refs.dart';
import '../../core/data/supabase_providers.dart';
import '../../core/utils/debouncer.dart';
import 'data/chat_models.dart';
import 'data/chat_repository.dart';

/// The chat list, kept fresh by the inbox channel.
final chatListProvider = AsyncNotifierProvider<ChatList, List<Conversation>>(ChatList.new);

class ChatList extends AsyncNotifier<List<Conversation>> {
  final _debounce = Debouncer(const Duration(milliseconds: 350));

  /// Conversations currently on screen; their unread count stays at zero.
  final Set<String> _open = {};

  @override
  Future<List<Conversation>> build() async {
    final inbox = ref.watch(inboxRealtimeProvider);
    final subscription = inbox?.events.listen((event) {
      if (event is ConversationsChanged) _debounce(refresh);
    });
    ref.onDispose(() {
      unawaited(subscription?.cancel());
      _debounce.dispose();
    });
    return _load();
  }

  Future<List<Conversation>> _load() async {
    final list = await ref.read(chatRepositoryProvider).conversations();
    return [for (final c in list) _open.contains(c.id) ? c.copyWith(unreadCount: 0) : c];
  }

  Future<void> refresh() async {
    try {
      final list = await _load();
      if (ref.mounted) state = AsyncData(list);
    } catch (_) {
      // Keep showing the last good list.
    }
  }

  void opened(String conversationId) {
    _open.add(conversationId);
    _patch(conversationId, (c) => c.copyWith(unreadCount: 0));
  }

  void closed(String conversationId) => _open.remove(conversationId);

  void setMuted(String conversationId, bool muted) => _patch(conversationId, (c) => c.copyWith(muted: muted));

  void _patch(String id, Conversation Function(Conversation) change) {
    final list = state.value;
    if (list == null) return;
    state = AsyncData([for (final c in list) c.id == id ? change(c) : c]);
  }
}

/// Unread conversations for the tab badge (muted ones don't count).
final unreadChatsProvider = Provider<int>((ref) {
  final list = ref.watch(chatListProvider).value ?? const [];
  return list.where((c) => c.unreadCount > 0 && !c.muted).length;
});

class ChatState {
  const ChatState({
    required this.info,
    required this.messages,
    required this.people,
    this.hasOlder = true,
    this.loadingOlder = false,
    this.typing = const {},
    this.myAnonymous = const {},
  });

  final ConversationInfo info;

  /// Oldest first.
  final List<Message> messages;
  final Map<String, UserRef> people;
  final bool hasOlder;
  final bool loadingOlder;

  /// Ids of people typing right now.
  final Set<String> typing;

  /// Ids of anonymous messages the signed-in student sent (they have no sender).
  final Set<String> myAnonymous;

  bool isMine(Message message, String me) => message.senderId == me || myAnonymous.contains(message.id);

  ChatState copyWith({
    ConversationInfo? info,
    List<Message>? messages,
    Map<String, UserRef>? people,
    bool? hasOlder,
    bool? loadingOlder,
    Set<String>? typing,
    Set<String>? myAnonymous,
  }) {
    return ChatState(
      info: info ?? this.info,
      messages: messages ?? this.messages,
      people: people ?? this.people,
      hasOlder: hasOlder ?? this.hasOlder,
      loadingOlder: loadingOlder ?? this.loadingOlder,
      typing: typing ?? this.typing,
      myAnonymous: myAnonymous ?? this.myAnonymous,
    );
  }

  Message? byId(String? id) => id == null ? null : messages.where((m) => m.id == id).firstOrNull;
}

/// An open conversation: history, live messages, typing and sending.
final conversationProvider = AsyncNotifierProvider.autoDispose.family<ConversationController, ChatState, String>(
  ConversationController.new,
);

class ConversationController extends AsyncNotifier<ChatState> {
  ConversationController(this.conversationId);

  final String conversationId;

  static const _pageSize = 40;
  static const _uuid = Uuid();

  RealtimeChannel? _channel;
  final _typingThrottle = Throttler(const Duration(seconds: 2));
  final _typingTimers = <String, Timer>{};
  final _markRead = Debouncer(const Duration(milliseconds: 600));

  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  SupabaseClient get _client => ref.read(supabaseProvider);
  String get _me => _client.uid;

  @override
  Future<ChatState> build() async {
    ref.onDispose(_teardown);
    final (info, messages) = await (
      _repo.info(conversationId),
      _repo.messages(conversationId, limit: _pageSize),
    ).wait;
    final mine = await _repo.myAnonymousMessages(messages.where((m) => m.isAnonymous).map((m) => m.id));
    _subscribe();
    unawaited(_repo.markRead(conversationId).catchError((_) {}));
    return ChatState(
      info: info,
      messages: messages,
      people: {for (final m in info.members) m.user.id: m.user},
      hasOlder: messages.length >= _pageSize,
      myAnonymous: mine,
    );
  }

  void _subscribe() {
    final filter = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: conversationId);
    _channel = _client
        .channel('chat:$conversationId', opts: const RealtimeChannelConfig(private: true))
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: filter,
          callback: (payload) => _upsert(Message.fromJson(payload.newRecord), arrived: true),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: filter,
          callback: (payload) => _upsert(Message.fromJson(payload.newRecord)),
        )
        .onBroadcast(event: 'typing', callback: _onTyping)
        .subscribe();
  }

  void _teardown() {
    final channel = _channel;
    if (channel != null) unawaited(_client.removeChannel(channel));
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _markRead.dispose();
  }

  void _upsert(Message message, {bool arrived = false}) {
    final current = state.value;
    if (current == null || !ref.mounted) return;
    final index = current.messages.indexWhere((m) => m.id == message.id);
    final messages = [...current.messages];
    if (index == -1) {
      messages.add(message);
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } else {
      messages[index] = message;
    }
    var typing = current.typing;
    if (arrived && message.senderId != null && typing.contains(message.senderId)) {
      typing = {...typing}..remove(message.senderId);
    }
    state = AsyncData(current.copyWith(messages: messages, typing: typing));

    if (arrived && message.senderId != _me) {
      _markRead(() => unawaited(_repo.markRead(conversationId).catchError((_) {})));
    }
    final sender = message.senderId;
    if (sender != null && !current.people.containsKey(sender)) unawaited(_loadPeople());
  }

  Future<void> _loadPeople() async {
    try {
      final members = await _repo.members(conversationId);
      final current = state.value;
      if (current == null || !ref.mounted) return;
      state = AsyncData(current.copyWith(people: {
        ...current.people,
        for (final m in members) m.user.id: m.user,
      }));
    } catch (_) {}
  }

  void _onTyping(Map<String, dynamic> payload) {
    final userId = payload['user_id'] as String?;
    final current = state.value;
    if (userId == null || userId == _me || current == null || !ref.mounted) return;
    _typingTimers[userId]?.cancel();
    _typingTimers[userId] = Timer(const Duration(seconds: 4), () {
      final latest = state.value;
      if (latest == null || !ref.mounted) return;
      state = AsyncData(latest.copyWith(typing: {...latest.typing}..remove(userId)));
    });
    if (!current.typing.contains(userId)) {
      state = AsyncData(current.copyWith(typing: {...current.typing, userId}));
    }
  }

  /// Tells others you're typing. Skipped when anonymous, since it would name you.
  void notifyTyping({bool anonymous = false}) {
    if (anonymous) return;
    _typingThrottle(() {
      unawaited(_channel?.sendBroadcastMessage(event: 'typing', payload: {'user_id': _me}));
    });
  }

  Future<void> loadOlder() async {
    final current = state.value;
    if (current == null || !current.hasOlder || current.loadingOlder || current.messages.isEmpty) return;
    state = AsyncData(current.copyWith(loadingOlder: true));
    try {
      final older = await _repo.messages(conversationId, before: current.messages.first.createdAt, limit: _pageSize);
      final mine = await _repo.myAnonymousMessages(older.where((m) => m.isAnonymous).map((m) => m.id));
      final latest = state.value;
      if (latest == null || !ref.mounted) return;
      state = AsyncData(latest.copyWith(
        messages: [...older, ...latest.messages],
        myAnonymous: {...latest.myAnonymous, ...mine},
        hasOlder: older.length >= _pageSize,
        loadingOlder: false,
      ));
    } catch (_) {
      final latest = state.value;
      if (latest != null && ref.mounted) state = AsyncData(latest.copyWith(loadingOlder: false));
    }
  }

  /// Sends a text message, optionally with files, as a reply, or sharing a
  /// post or event. The message shows immediately and is confirmed by
  /// realtime.
  Future<void> send({
    String? text,
    String? replyToId,
    List<PickedFile> files = const [],
    String? sharedPostId,
    String? sharedEventId,
    String? sticker,
    bool anonymous = false,
  }) async {
    final body = sticker ?? text?.trim();
    final hasBody = body != null && body.isNotEmpty;
    if (!hasBody && files.isEmpty && sharedPostId == null && sharedEventId == null) return;

    final kind = sticker != null
        ? 'sticker'
        : sharedPostId != null
            ? 'post'
            : sharedEventId != null
                ? 'event'
                : files.isEmpty
                    ? 'text'
                    : files.every((f) => f.isImage)
                        ? 'image'
                        : 'file';

    final draft = Message(
      id: _uuid.v4(),
      conversationId: conversationId,
      senderId: _me,
      kind: kind,
      body: hasBody ? body : null,
      replyToId: replyToId,
      sharedPostId: sharedPostId,
      sharedEventId: sharedEventId,
      attachments: [
        for (final f in files)
          Attachment(path: '', name: f.name, mimeType: f.mimeType, size: f.size, width: f.width, height: f.height),
      ],
      createdAt: DateTime.now(),
      sendState: SendState.sending,
      isAnonymous: anonymous,
    );
    if (anonymous) {
      final current = state.value;
      if (current != null) state = AsyncData(current.copyWith(myAnonymous: {...current.myAnonymous, draft.id}));
    }
    _upsert(draft);
    await _deliver(draft, files);
  }

  Future<void> _deliver(Message draft, List<PickedFile> files) async {
    try {
      var message = draft;
      if (files.isNotEmpty) {
        final storage = ref.read(storageRepositoryProvider);
        final uploaded = <Attachment>[];
        for (var i = 0; i < files.length; i++) {
          final path = await storage.uploadChatFile(conversationId, files[i]);
          final a = draft.attachments[i];
          uploaded.add(Attachment(path: path, name: a.name, mimeType: a.mimeType, size: a.size, width: a.width, height: a.height));
        }
        message = Message(
          id: draft.id,
          conversationId: draft.conversationId,
          senderId: draft.senderId,
          kind: draft.kind,
          body: draft.body,
          replyToId: draft.replyToId,
          attachments: uploaded,
          createdAt: draft.createdAt,
          sendState: SendState.sending,
          isAnonymous: draft.isAnonymous,
        );
        _upsert(message);
      }
      await _repo.send(message);
      final current = state.value?.byId(draft.id);
      if (current != null && current.sendState != SendState.sent) _upsert(current.copyWith(sendState: SendState.sent));
    } catch (_) {
      final current = state.value?.byId(draft.id);
      if (current != null) _upsert(current.copyWith(sendState: SendState.failed));
      rethrow;
    }
  }

  Future<void> retry(Message message) async {
    if (message.attachments.any((a) => a.path.isEmpty)) {
      // The files weren't uploaded; the student needs to pick them again.
      remove(message.id);
      return;
    }
    _upsert(message.copyWith(sendState: SendState.sending));
    await _deliver(message, const []);
  }

  void remove(String messageId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(messages: current.messages.where((m) => m.id != messageId).toList()));
  }

  Future<void> toggleReaction(Message message, String emoji) async {
    final mine = message.reactions[emoji]?.contains(_me) ?? false;
    final reactions = {for (final e in message.reactions.entries) e.key: [...e.value]};
    if (mine) {
      reactions[emoji]!.remove(_me);
      if (reactions[emoji]!.isEmpty) reactions.remove(emoji);
    } else {
      (reactions[emoji] ??= []).add(_me);
    }
    _upsert(message.copyWith(reactions: reactions));
    try {
      await _repo.toggleReaction(message.id, emoji);
    } catch (_) {
      _upsert(message);
      rethrow;
    }
  }

  Future<void> edit(Message message, String body) async {
    _upsert(message.copyWith(body: body, editedAt: DateTime.now()));
    await _repo.edit(message.id, body);
  }

  Future<void> unsend(Message message) async {
    _upsert(message.copyWith(deletedAt: DateTime.now()));
    await _repo.unsend(message.id);
  }
}

final messageSearchProvider = FutureProvider.autoDispose.family<List<MessageSearchHit>, String>((ref, query) {
  if (query.trim().length < 2) return const [];
  return ref.watch(chatRepositoryProvider).search(query);
});
