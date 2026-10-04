import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/auth/ui/auth_screens.dart';
import '../../features/auth/ui/welcome_screen.dart';
import '../../features/calls/ui/call_screen.dart';
import '../../features/chat/ui/chat_list_screen.dart';
import '../../features/chat/ui/conversation_info_screen.dart';
import '../../features/chat/ui/conversation_screen.dart';
import '../../features/chat/ui/message_search_screen.dart';
import '../../features/chat/ui/new_chat_screen.dart';
import '../../features/colleges/ui/college_detail_screen.dart';
import '../../features/colleges/ui/colleges_screen.dart';
import '../../features/colleges/ui/ranking_method_screen.dart';
import '../../features/communities/ui/communities_screen.dart';
import '../../features/communities/ui/community_screen.dart';
import '../../features/communities/ui/create_community_screen.dart';
import '../../features/communities/ui/manage_community_screen.dart';
import '../../features/communities/ui/members_screen.dart';
import '../../features/events/ui/event_detail_screen.dart';
import '../../features/events/ui/event_editor_screen.dart';
import '../../features/events/ui/event_manage_screen.dart';
import '../../features/events/ui/events_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/legal/legal_screen.dart';
import '../../features/notifications/ui/notifications_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/posts/ui/composer_screen.dart';
import '../../features/posts/ui/post_detail_screen.dart';
import '../../features/posts/ui/saved_screen.dart';
import '../../features/profile/providers.dart';
import '../../features/profile/ui/edit_profile_screen.dart';
import '../../features/profile/ui/follow_list_screen.dart';
import '../../features/profile/ui/profile_screen.dart';
import '../../features/reels/ui/create_reel_screen.dart';
import '../../features/reels/ui/reels_screen.dart';
import '../../features/reels/ui/video_library_screens.dart';
import '../../features/search/ui/search_screen.dart';
import '../../features/settings/ui/settings_screen.dart';
import '../../features/shell/app_shell.dart';
import '../data/supabase_providers.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

const _authRoutes = {'/welcome', '/sign-in', '/sign-up', '/forgot-password'};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, _) => refresh.value++);
  ref.listen(myProfileProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  GoRoute page(String path, Widget Function(GoRouterState state) builder) => GoRoute(
        path: path,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => builder(state),
      );

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final signedIn = ref.read(supabaseProvider).auth.currentSession != null;
      // The legal pages are readable before signing up.
      if (location.startsWith('/legal/')) return null;
      if (!signedIn) return _authRoutes.contains(location) ? null : '/welcome';

      final profile = ref.read(myProfileProvider);
      if (!profile.hasValue) return location == '/splash' ? null : '/splash';
      final me = profile.value;
      if (me == null) return location == '/splash' ? null : '/splash';
      if (!me.onboarded) return location == '/onboarding' ? null : '/onboarding';
      if (_authRoutes.contains(location) || location == '/onboarding' || location == '/splash') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/sign-up', builder: (_, _) => const SignUpScreen()),
      GoRoute(path: '/forgot-password', builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/communities', builder: (_, _) => const CommunitiesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/events', builder: (_, _) => const EventsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/reels', builder: (_, _) => const ReelsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/chat', builder: (_, _) => const ChatListScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/me', builder: (_, _) => const ProfileScreen())]),
        ],
      ),
      page('/notifications', (_) => const NotificationsScreen()),
      page('/search', (s) => SearchScreen(initialQuery: s.uri.queryParameters['q'])),
      page('/compose', (s) => ComposerScreen(
            communityId: s.uri.queryParameters['community'],
            initialType: s.uri.queryParameters['type'],
            eventId: s.uri.queryParameters['event'],
          )),
      page('/post/:id', (s) => PostDetailScreen(postId: s.pathParameters['id']!)),
      page('/saved', (_) => const SavedScreen()),
      page('/u/:username', (s) => ProfileScreen(username: s.pathParameters['username'])),
      page('/u/:username/followers', (s) => FollowListScreen(username: s.pathParameters['username']!, followers: true)),
      page('/u/:username/following', (s) => FollowListScreen(username: s.pathParameters['username']!, followers: false)),
      page('/profile/edit', (_) => const EditProfileScreen()),
      page('/communities/new', (_) => const CreateCommunityScreen()),
      page('/c/:slug', (s) => CommunityScreen(slug: s.pathParameters['slug']!)),
      page('/c/:slug/members', (s) => MembersScreen(slug: s.pathParameters['slug']!)),
      page('/c/:slug/manage', (s) => ManageCommunityScreen(slug: s.pathParameters['slug']!)),
      page('/room/:id', (s) => RoomScreen(roomId: s.pathParameters['id']!)),
      page('/events/new', (s) => EventEditorScreen(communityId: s.uri.queryParameters['community'])),
      page('/event/:id', (s) => EventDetailScreen(eventId: s.pathParameters['id']!)),
      page('/event/:id/edit', (s) => EventEditorScreen(eventId: s.pathParameters['id'])),
      page('/event/:id/manage', (s) => EventManageScreen(eventId: s.pathParameters['id']!)),
      page('/reels/new', (_) => const CreateReelScreen()),
      page('/watch', (s) => VideoPlayerScreen(args: s.extra is WatchArgs ? s.extra! as WatchArgs : null)),
      page('/library/liked', (_) => const LikedVideosScreen()),
      page('/library/playlists', (_) => const PlaylistsScreen()),
      page('/library/playlists/:id', (s) => PlaylistScreen(playlistId: s.pathParameters['id']!)),
      page('/chat/new', (_) => const NewChatScreen()),
      page('/chat/search', (_) => const MessageSearchScreen()),
      page('/chat/:id', (s) => ConversationScreen(conversationId: s.pathParameters['id']!)),
      page('/chat/:id/info', (s) => ConversationInfoScreen(conversationId: s.pathParameters['id']!)),
      page('/call/:id', (s) => CallScreen(callId: s.pathParameters['id']!, outgoing: s.uri.queryParameters['outgoing'] == '1')),
      page('/voice/:roomId', (s) => CallScreen(roomId: s.pathParameters['roomId']!, video: s.uri.queryParameters['video'] == '1')),
      page('/colleges', (_) => const CollegesScreen()),
      page('/college/:id', (s) => CollegeDetailScreen(collegeId: s.pathParameters['id']!)),
      page('/rankings/method', (_) => const RankingMethodScreen()),
      page('/settings', (_) => const SettingsScreen()),
      page('/settings/blocked', (_) => const BlockedUsersScreen()),
      page('/legal/:doc', (s) => LegalScreen(doc: LegalDoc.fromSlug(s.pathParameters['doc']))),
    ],
  );
});
