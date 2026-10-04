import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'json.dart';
import 'supabase_providers.dart';

sealed class InboxEvent {
  const InboxEvent();
}

/// A conversation the student is in changed (new message, rename, new chat).
class ConversationsChanged extends InboxEvent {
  const ConversationsChanged(this.conversationId);

  final String? conversationId;
}

class NotificationArrived extends InboxEvent {
  const NotificationArrived(this.id);

  final String id;
}

class CallChanged extends InboxEvent {
  const CallChanged(this.row, {required this.isNew});

  final Json row;
  final bool isNew;
}

/// One private realtime channel per signed-in student that carries
/// everything addressed to them: chat list changes, notifications and calls.
final inboxRealtimeProvider = Provider<InboxRealtime?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  final inbox = InboxRealtime(ref.read(supabaseProvider), uid)..connect();
  ref.onDispose(inbox.dispose);
  return inbox;
});

class InboxRealtime {
  InboxRealtime(this._client, this.userId);

  final SupabaseClient _client;
  final String userId;
  final _events = StreamController<InboxEvent>.broadcast();
  RealtimeChannel? _channel;

  Stream<InboxEvent> get events => _events.stream;

  void connect() {
    final byUser = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: userId);
    _channel = _client
        .channel('user:$userId', opts: const RealtimeChannelConfig(private: true))
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'conversations',
          callback: (payload) => _emit(ConversationsChanged(payload.newRecord['id'] as String?)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'conversation_members',
          filter: byUser,
          callback: (payload) => _emit(ConversationsChanged(payload.newRecord['conversation_id'] as String?)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: byUser,
          callback: (payload) => _emit(NotificationArrived(payload.newRecord['id'] as String)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'calls',
          callback: (payload) => _emit(CallChanged(payload.newRecord, isNew: true)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'calls',
          callback: (payload) => _emit(CallChanged(payload.newRecord, isNew: false)),
        )
        .subscribe();
  }

  void _emit(InboxEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void dispose() {
    final channel = _channel;
    if (channel != null) unawaited(_client.removeChannel(channel));
    unawaited(_events.close());
  }
}

/// Who's online right now, from app-wide presence.
final onlineUsersProvider = NotifierProvider<OnlineUsers, Set<String>>(OnlineUsers.new);

class OnlineUsers extends Notifier<Set<String>> {
  RealtimeChannel? _channel;
  bool _subscribed = false;

  /// Off until [setVisible] is called, so private profiles never flash online.
  bool _visible = false;

  @override
  Set<String> build() {
    final uid = ref.watch(currentUserIdProvider);
    _channel = null;
    _subscribed = false;
    if (uid == null) return const {};
    final client = ref.read(supabaseProvider);
    final channel = client.channel('online', opts: RealtimeChannelConfig(private: true, key: uid));
    _channel = channel;
    channel
        .onPresenceSync((_) {
          final ids = {for (final entry in channel.presenceState()) entry.key};
          if (ref.mounted) state = ids;
        })
        .subscribe((status, error) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            _subscribed = true;
            await _sync();
          }
        });
    ref.onDispose(() => unawaited(client.removeChannel(channel)));
    return const {};
  }

  /// Whether others see you online. Private profiles stay hidden but still
  /// see who else is online.
  Future<void> setVisible(bool visible) async {
    if (_visible == visible) return;
    _visible = visible;
    await _sync();
  }

  Future<void> _sync() async {
    final channel = _channel;
    if (channel == null || !_subscribed) return;
    if (_visible) {
      await channel.track({'online_at': DateTime.now().toUtc().toIso8601String()});
    } else {
      await channel.untrack();
    }
  }
}
