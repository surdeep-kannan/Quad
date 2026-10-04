import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../data/refs.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/context_x.dart';
import 'app_icons.dart';
import 'app_image.dart';

/// A student's photo, or their initials on a colour derived from their name.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.url,
    this.size = 40,
    this.online = false,
    this.ring,
  });

  final String name;
  final String? url;
  final double size;
  final bool online;

  /// Draws a ring in this colour around the avatar (e.g. for stories/live).
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = Palette.forText(name);
    Widget avatar = ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: url != null && url!.isNotEmpty
            ? AppImage(url!, width: size, height: size, placeholderColor: color.withValues(alpha: 0.25))
            : ColoredBox(
                color: color,
                child: Center(
                  child: Text(
                    name.initials,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontWeight: FontWeight.w700,
                      fontSize: size * 0.38,
                      height: 1,
                      letterSpacing: -0.3,
                      color: Palette.foregroundOn(color),
                    ),
                  ),
                ),
              ),
      ),
    );

    if (ring != null) {
      avatar = Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring!, width: 2)),
        child: avatar,
      );
    }

    return Semantics(
      label: name,
      image: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          if (online)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.3 + 2,
                height: size * 0.3 + 2,
                decoration: BoxDecoration(
                  color: c.online,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.background, width: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Stand-in for anonymous authors: a detective glyph on a colour derived from
/// the alias, so different aliases look different but reveal nothing.
class AnonymousAvatar extends StatelessWidget {
  const AnonymousAvatar({super.key, required this.alias, this.size = 40});

  final String alias;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Palette.forText(alias);
    return Semantics(
      label: 'Anonymous',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(AppIcons.anonymous, size: size * 0.52, color: color),
      ),
    );
  }
}

/// Makes [child] (usually an avatar or a name) open [user]'s profile when
/// tapped. Anonymous people and unknown usernames aren't tappable.
class ProfileTap extends StatelessWidget {
  const ProfileTap({super.key, required this.user, required this.child});

  final UserRef? user;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final user = this.user;
    if (user == null || user.isAnonymous || user.username.isEmpty) return child;
    return Semantics(
      button: true,
      label: 'Open ${user.fullName}\'s profile',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push('/u/${user.username}'),
        child: child,
      ),
    );
  }
}

/// A person's avatar, or the anonymous one when they posted anonymously.
class AuthorAvatar extends StatelessWidget {
  const AuthorAvatar({super.key, required this.user, this.size = 40, this.online = false});

  final UserRef user;
  final double size;
  final bool online;

  @override
  Widget build(BuildContext context) => user.isAnonymous
      ? AnonymousAvatar(alias: user.fullName, size: size)
      : UserAvatar(name: user.fullName, url: user.avatarUrl, size: size, online: online);
}

/// Communities use rounded squares (like app icons) so they're never confused
/// with people.
class CommunityAvatar extends StatelessWidget {
  const CommunityAvatar({
    super.key,
    required this.name,
    required this.color,
    this.url,
    this.size = 44,
  });

  final String name;
  final int color;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = Palette.at(color);
    final radius = BorderRadius.circular(size * 0.3);
    return Semantics(
      label: name,
      image: true,
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox.square(
          dimension: size,
          child: url != null && url!.isNotEmpty
              ? AppImage(url!, width: size, height: size)
              : ColoredBox(
                  color: bg,
                  child: Center(
                    child: Text(
                      name.initials,
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        fontWeight: FontWeight.w800,
                        fontSize: size * 0.36,
                        height: 1,
                        letterSpacing: -0.4,
                        color: Palette.foregroundOn(bg),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Overlapping avatars for "who's going" and "members" previews.
class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, required this.people, this.size = 24, this.max = 4});

  /// (name, avatar url) pairs.
  final List<(String, String?)> people;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = people.take(max).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final overlap = size * 0.34;
    return SizedBox(
      height: size,
      width: size + (shown.length - 1) * (size - overlap),
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: context.colors.surface, width: 2),
                ),
                child: UserAvatar(name: shown[i].$1, url: shown[i].$2, size: size - 4),
              ),
            ),
        ],
      ),
    );
  }
}
