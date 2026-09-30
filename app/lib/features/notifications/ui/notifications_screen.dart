import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/paged_list.dart';
import '../../../core/widgets/states.dart';
import '../data/notification_repository.dart';
import '../providers.dart';
import 'notification_tile.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationsProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        title: const Text('Notifications'),
        actions: [
          TextButton(onPressed: notifier.markAllRead, child: const Text('Mark all read')),
          const SizedBox(width: 8),
        ],
      ),
      body: AppRefresh(
        onRefresh: notifier.refresh,
        child: CustomScrollView(
          slivers: [
            PagedSliverList<AppNotification>(
              value: list,
              onLoadMore: notifier.loadMore,
              onRetry: () => ref.invalidate(notificationsProvider),
              empty: const EmptyState(
                icon: AppIcons.bell,
                title: 'You\'re all caught up',
                message: 'Likes, comments, event updates and requests show up here.',
              ),
              itemBuilder: (_, n, _) => NotificationTile(notification: n),
            ),
          ],
        ),
      ),
    );
  }
}
