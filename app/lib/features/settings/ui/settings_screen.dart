import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../legal/legal_screen.dart';
import '../../posts/ui/post_card.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/providers.dart';
import '../theme_mode.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final me = ref.watch(myProfileProvider).value;
    final c = context.colors;

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, Space.sm),
      child: Text(title.toUpperCase(), style: context.text.labelSmall!.copyWith(color: c.inkSubtle, letterSpacing: 1)),
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          section('Account'),
          ListTile(
            leading: const Icon(AppIcons.user),
            title: const Text('Edit profile'),
            onTap: () => context.push('/profile/edit'),
          ),
          if (me != null)
            ListTile(
              leading: const Icon(AppIcons.at),
              title: const Text('Username'),
              subtitle: Text('@${me.username}'),
            ),
          section('Your library'),
          ListTile(
            leading: const Icon(AppIcons.bookmark),
            title: const Text('Saved posts'),
            onTap: () => context.push('/saved'),
          ),
          ListTile(
            leading: const Icon(AppIcons.heart),
            title: const Text('Liked videos'),
            subtitle: const Text('Reels and videos you liked'),
            onTap: () => context.push('/library/liked'),
          ),
          ListTile(
            leading: const Icon(AppIcons.playlist),
            title: const Text('Playlists'),
            subtitle: const Text('Your own collections of reels and videos'),
            onTap: () => context.push('/library/playlists'),
          ),
          section('Appearance'),
          for (final (value, label, icon) in [
            (ThemeMode.system, 'Match my phone', AppIcons.device),
            (ThemeMode.light, 'Light', AppIcons.sun),
            (ThemeMode.dark, 'Dark', AppIcons.moon),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              trailing: mode == value ? Icon(AppIcons.checkCircle, color: c.accent) : null,
              onTap: () => ref.read(themeModeProvider.notifier).set(value),
            ),
          section('Privacy & safety'),
          if (me != null)
            SwitchListTile(
              secondary: Icon(me.isPrivate ? AppIcons.lock : AppIcons.globe),
              title: const Text('Private profile'),
              subtitle: Text(
                me.isPrivate
                    ? 'Only people you follow can see your profile, posts and details. In communities your posts, '
                          'comments and room messages show a random anonymous name.'
                    : 'Anyone can see your profile. Turn this on to hide it and stay anonymous in communities.',
              ),
              isThreeLine: true,
              value: me.isPrivate,
              onChanged: (value) async {
                try {
                  await ref.read(myProfileProvider.notifier).save({'is_private': value});
                  if (context.mounted) {
                    showToast(context, value ? 'Your profile is now private' : 'Your profile is now public');
                  }
                } catch (error) {
                  if (context.mounted) showToast(context, friendlyError(error), error: true);
                }
              },
            ),
          ListTile(
            leading: const Icon(AppIcons.block),
            title: const Text('Blocked people'),
            onTap: () => context.push('/settings/blocked'),
          ),
          section('Discover'),
          ListTile(
            leading: const Icon(AppIcons.ranking),
            title: const Text('College rankings'),
            onTap: () => context.push('/colleges'),
          ),
          section('About'),
          ListTile(
            leading: const Icon(AppIcons.shield),
            title: const Text('Community guidelines'),
            subtitle: const Text('Be kind, respect anonymity, no spam or hate.'),
            onTap: () => context.push(LegalDoc.guidelines.route),
          ),
          ListTile(
            leading: const Icon(AppIcons.document),
            title: const Text('Terms of service'),
            onTap: () => context.push(LegalDoc.terms.route),
          ),
          ListTile(
            leading: const Icon(AppIcons.lock),
            title: const Text('Privacy policy'),
            onTap: () => context.push(LegalDoc.privacy.route),
          ),
          const SizedBox(height: Space.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: AppButton(
              label: 'Sign out',
              icon: AppIcons.signOut,
              variant: ButtonVariant.danger,
              expand: true,
              onPressed: () async {
                final ok = await confirm(
                  context,
                  title: 'Sign out?',
                  message: 'You can sign back in anytime.',
                  confirmLabel: 'Sign out',
                );
                if (ok) await ref.read(authRepositoryProvider).signOut();
              },
            ),
          ),
          const SizedBox(height: Space.xxxl),
        ],
      ),
    );
  }
}

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedUsersProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        title: const Text('Blocked people'),
      ),
      body: blocked.when(
        loading: () => const ListSkeleton(),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(blockedUsersProvider)),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: AppIcons.block,
                title: 'No one blocked',
                message: 'People you block can\'t message you or see your posts.',
              )
            : ListView(
                children: [
                  for (final p in list)
                    PersonRow.profile(
                      p,
                      trailing: AppButton(
                        label: 'Unblock',
                        size: ButtonSize.small,
                        variant: ButtonVariant.secondary,
                        onPressed: () async {
                          try {
                            await ref.read(profileRepositoryProvider).unblock(p.id);
                            ref.invalidate(blockedUsersProvider);
                          } catch (error) {
                            if (context.mounted) showToast(context, friendlyError(error), error: true);
                          }
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
