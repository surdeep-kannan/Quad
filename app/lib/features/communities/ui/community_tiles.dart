import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/sheets.dart';
import '../data/community.dart';
import '../data/community_repository.dart';
import '../providers.dart';

/// Join / Requested / Joined, handled in place with optimistic feedback.
class JoinButton extends ConsumerStatefulWidget {
  const JoinButton({super.key, required this.community, this.size = ButtonSize.small, this.onChanged});

  final Community community;
  final ButtonSize size;
  final ValueChanged<String?>? onChanged;

  @override
  ConsumerState<JoinButton> createState() => _JoinButtonState();
}

class _JoinButtonState extends ConsumerState<JoinButton> {
  late String? _status = widget.community.myStatus;
  bool _busy = false;

  @override
  void didUpdateWidget(JoinButton old) {
    super.didUpdateWidget(old);
    if (old.community.myStatus != widget.community.myStatus) _status = widget.community.myStatus;
  }

  Future<void> _join() async {
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      final status = await ref.read(communityRepositoryProvider).join(widget.community.id);
      if (!mounted) return;
      setState(() => _status = status);
      widget.onChanged?.call(status);
      ref.invalidate(myCommunitiesProvider);
      if (status == 'pending') showToast(context, 'Request sent. Moderators will review it.');
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_status) {
      'active' => AppButton(label: 'Joined', icon: AppIcons.check, variant: ButtonVariant.secondary, size: widget.size, onPressed: null),
      'pending' => AppButton(label: 'Requested', variant: ButtonVariant.secondary, size: widget.size, onPressed: null),
      'banned' => const SizedBox.shrink(),
      _ => AppButton(
          label: widget.community.isPrivate ? 'Request' : 'Join',
          size: widget.size,
          loading: _busy,
          onPressed: _join,
        ),
    };
  }
}

/// Card for horizontal carousels.
class CommunityCard extends StatelessWidget {
  const CommunityCard({super.key, required this.community});

  final Community community;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = Palette.at(community.color);
    return Pressable(
      onTap: () => context.push('/c/${community.slug}'),
      child: Container(
        width: 156,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 36, color: accent.withValues(alpha: 0.9)),
            Transform.translate(
              offset: const Offset(12, -20),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.surface, width: 3),
                ),
                child: CommunityAvatar(name: community.name, color: community.color, url: community.avatarUrl, size: 40),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Transform.translate(
                    offset: const Offset(0, -14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(community.name, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(plural(community.membersCount, 'member'), style: context.text.bodySmall, maxLines: 1),
                      ],
                    ),
                  ),
                  SizedBox(width: double.infinity, child: JoinButton(community: community)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// List row with avatar, name, tagline and a join button.
class CommunityRow extends StatelessWidget {
  const CommunityRow({super.key, required this.community, this.showJoin = true});

  final Community community;
  final bool showJoin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: () => context.push('/c/${community.slug}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: 10),
        child: Row(
          children: [
            CommunityAvatar(name: community.name, color: community.color, url: community.avatarUrl, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(community.name, style: context.text.titleSmall!.copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (community.isPrivate) ...[
                        const SizedBox(width: 4),
                        Icon(AppIcons.lock, size: 13, color: c.inkSubtle),
                      ],
                    ],
                  ),
                  if (community.tagline != null)
                    Text(community.tagline!, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    [
                      CommunityCategories.label(community.category),
                      plural(community.membersCount, 'member'),
                      if (community.college != null) community.college!.label,
                    ].join(' · '),
                    style: context.text.labelSmall!.copyWith(color: c.inkSubtle, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (showJoin) ...[const SizedBox(width: 8), JoinButton(community: community)],
          ],
        ),
      ),
    );
  }
}
