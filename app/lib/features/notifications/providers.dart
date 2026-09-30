import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/paged.dart';
import '../../core/data/realtime.dart';
import 'data/notification_repository.dart';

/// Unread notification count for the bell badge, bumped live.
final unreadNotificationsProvider = AsyncNotifierProvider<UnreadNotifications, int>(UnreadNotifications.new);

class UnreadNotifications extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    final inbox = ref.watch(inboxRealtimeProvider);
    final subscription = inbox?.events.listen((event) {
      if (event is NotificationArrived) state = AsyncData((state.value ?? 0) + 1);
    });
    ref.onDispose(() => unawaited(subscription?.cancel()));
    return ref.read(notificationRepositoryProvider).unreadCount();
  }

  void clear() => state = const AsyncData(0);
}

/// The newest notification to show as an in-app banner.
final notificationBannerProvider = NotifierProvider<NotificationBanner, AppNotification?>(NotificationBanner.new);

class NotificationBanner extends Notifier<AppNotification?> {
  @override
  AppNotification? build() {
    final inbox = ref.watch(inboxRealtimeProvider);
    final subscription = inbox?.events.listen((event) async {
      if (event is! NotificationArrived) return;
      final notification = await ref.read(notificationRepositoryProvider).byId(event.id);
      if (ref.mounted && notification != null) state = notification;
    });
    ref.onDispose(() => unawaited(subscription?.cancel()));
    return null;
  }

  void dismiss() => state = null;
}

final notificationsProvider = AsyncNotifierProvider.autoDispose<NotificationsList, Paged<AppNotification>>(
  NotificationsList.new,
);

class NotificationsList extends PagedNotifier<AppNotification> {
  @override
  int get pageSize => 30;

  @override
  Future<Paged<AppNotification>> build() async {
    final inbox = ref.watch(inboxRealtimeProvider);
    final subscription = inbox?.events.listen((event) async {
      if (event is! NotificationArrived) return;
      final notification = await ref.read(notificationRepositoryProvider).byId(event.id);
      if (notification == null || !ref.mounted) return;
      updateItems((items) => [notification, ...items.where((n) => n.id != notification.id)]);
    });
    ref.onDispose(() => unawaited(subscription?.cancel()));
    return super.build();
  }

  @override
  Future<List<AppNotification>> fetch(int offset, int limit) =>
      ref.read(notificationRepositoryProvider).list(offset: offset, limit: limit);

  @override
  Object idOf(AppNotification item) => item.id;

  Future<void> markAllRead() async {
    await ref.read(notificationRepositoryProvider).markAllRead();
    updateItems((items) => [for (final n in items) n.isUnread ? n.markRead() : n]);
    ref.read(unreadNotificationsProvider.notifier).clear();
  }
}
