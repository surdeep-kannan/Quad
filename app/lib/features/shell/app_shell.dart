import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/realtime.dart';
import '../../core/data/supabase_providers.dart';
import '../../core/utils/context_x.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/avatars.dart';
import '../../core/widgets/badges.dart';
import '../calls/call_service.dart';
import '../chat/providers.dart';
import '../notifications/providers.dart';
import '../notifications/ui/notification_tile.dart';
import '../profile/providers.dart';

/// Private profiles don't show up as online.
final _presenceVisibilityProvider = Provider<void>((ref) {
  final private = ref.watch(myProfileProvider.select((profile) => profile.value?.isPrivate));
  if (private != null) unawaited(ref.read(onlineUsersProvider.notifier).setVisible(!private));
});

/// The six tabs. Reels switches the bar to dark so video stays immersive.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _reels = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(presenceHeartbeatProvider);
    ref.watch(onlineUsersProvider);
    ref.watch(_presenceVisibilityProvider);
    ref.listen(incomingCallProvider, (_, call) {
      if (call != null) context.push('/call/${call.id}');
    });

    final dark = shell.currentIndex == _reels;
    final unreadChats = ref.watch(unreadChatsProvider);
    final me = ref.watch(myProfileProvider).value;

    void go(int index) {
      HapticFeedback.selectionClick();
      shell.goBranch(index, initialLocation: index == shell.currentIndex);
    }

    final items = <_NavItem>[
      const _NavItem('Home', AppIcons.home, AppIcons.homeActive),
      const _NavItem('Communities', AppIcons.communities, AppIcons.communitiesActive),
      const _NavItem('Events', AppIcons.events, AppIcons.eventsActive),
      const _NavItem('Reels', AppIcons.reels, AppIcons.reelsActive),
      _NavItem('Chat', AppIcons.chat, AppIcons.chatActive, badge: unreadChats),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark || context.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Stack(children: [shell, const _BannerLayer()]),
        bottomNavigationBar: _BottomBar(
          dark: dark,
          currentIndex: shell.currentIndex,
          items: items,
          onTap: go,
          profile: me == null ? null : UserAvatar(name: me.fullName, url: me.avatarUrl, size: 26),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.activeIcon, {this.badge = 0});

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final int badge;
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.dark,
    required this.currentIndex,
    required this.items,
    required this.onTap,
    required this.profile,
  });

  final bool dark;
  final int currentIndex;
  final List<_NavItem> items;
  final ValueChanged<int> onTap;
  final Widget? profile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final background = dark ? Colors.black : c.surface;
    final active = dark ? Colors.white : c.ink;
    final inactive = dark ? Colors.white.withValues(alpha: 0.62) : c.inkMuted;

    Widget slot(int index, Widget child, String label) {
      final selected = index == currentIndex;
      return Expanded(
        child: Semantics(
          label: label,
          selected: selected,
          button: true,
          child: InkResponse(
            onTap: () => onTap(index),
            radius: 28,
            highlightColor: Colors.transparent,
            child: SizedBox(
              height: 56,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  child,
                  const SizedBox(height: 5),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: selected ? 5 : 0,
                    height: 5,
                    decoration: BoxDecoration(color: dark ? Colors.white : c.accent, shape: BoxShape.circle),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: dark ? Colors.white10 : c.line)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              slot(
                i,
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      i == currentIndex ? items[i].activeIcon : items[i].icon,
                      size: 26,
                      color: i == currentIndex ? active : inactive,
                    ),
                    if (items[i].badge > 0) Positioned(top: -6, right: -10, child: CountBadge(count: items[i].badge)),
                  ],
                ),
                items[i].badge > 0 ? '${items[i].label}, ${items[i].badge} unread' : items[i].label,
              ),
            slot(
              items.length,
              Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: currentIndex == items.length ? active : Colors.transparent, width: 1.6),
                ),
                child: profile ?? Icon(AppIcons.user, color: inactive),
              ),
              'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

/// Slides a banner in from the top when a notification arrives.
class _BannerLayer extends ConsumerStatefulWidget {
  const _BannerLayer();

  @override
  ConsumerState<_BannerLayer> createState() => _BannerLayerState();
}

class _BannerLayerState extends ConsumerState<_BannerLayer> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notification = ref.watch(notificationBannerProvider);
    ref.listen(notificationBannerProvider, (_, next) {
      _timer?.cancel();
      if (next != null) {
        HapticFeedback.lightImpact();
        _timer = Timer(const Duration(seconds: 4), () => ref.read(notificationBannerProvider.notifier).dismiss());
      }
    });
    final c = context.colors;
    return Positioned(
      left: 10,
      right: 10,
      top: context.safePadding.top + 6,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween(
            begin: const Offset(0, -1.4),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
        child: notification == null
            ? const SizedBox.shrink()
            : Dismissible(
                key: ValueKey(notification.id),
                direction: DismissDirection.up,
                onDismissed: (_) => ref.read(notificationBannerProvider.notifier).dismiss(),
                child: Material(
                  color: c.surface,
                  elevation: 10,
                  shadowColor: Colors.black38,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: NotificationTile(
                    notification: notification,
                    compact: true,
                    onOpened: () => ref.read(notificationBannerProvider.notifier).dismiss(),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Ensures signed-in-only realtime services start with the shell.
final shellServicesProvider = Provider<void>((ref) {
  ref.watch(currentUserIdProvider);
});
