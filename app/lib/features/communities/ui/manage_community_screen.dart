import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../moderation/data/moderation_repository.dart';
import '../data/community.dart';
import '../data/community_repository.dart';
import '../providers.dart';
import 'members_screen.dart';

final _reportQueueProvider = FutureProvider.autoDispose.family<List<Report>, String>((ref, communityId) {
  return ref.watch(moderationRepositoryProvider).queue(communityId: communityId);
});

/// Moderator tools: join requests, the report queue and community details.
class ManageCommunityScreen extends ConsumerWidget {
  const ManageCommunityScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final community = ref.watch(communityProvider(slug)).value;
    if (community == null) return const Scaffold(body: CenteredLoader());
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
          title: Text('Manage ${community.name}'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [Tab(text: 'Reports'), Tab(text: 'Requests'), Tab(text: 'Details')],
          ),
        ),
        body: TabBarView(
          children: [
            _ReportQueue(community: community),
            MemberList(community: community, status: 'pending'),
            _Details(community: community),
          ],
        ),
      ),
    );
  }
}

class _ReportQueue extends ConsumerWidget {
  const _ReportQueue({required this.community});

  final Community community;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(_reportQueueProvider(community.id));
    final c = context.colors;
    return reports.when(
      loading: () => const ListSkeleton(),
      error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(_reportQueueProvider(community.id))),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(icon: AppIcons.shield, title: 'All clear', message: 'No open reports. Nice.');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(Space.gutter),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: Space.md),
          itemBuilder: (_, i) {
            final report = list[i];
            Future<void> resolve({required bool remove}) async {
              try {
                final moderation = ref.read(moderationRepositoryProvider);
                if (remove && report.targetType != 'user') {
                  await moderation.moderate(targetType: report.targetType, targetId: report.targetId, action: 'remove', reason: report.reasonLabel);
                }
                await moderation.resolve(report.id, actioned: remove);
                ref.invalidate(_reportQueueProvider(community.id));
                if (context.mounted) showToast(context, remove ? 'Removed and closed' : 'Dismissed');
              } catch (error) {
                if (context.mounted) showToast(context, friendlyError(error), error: true);
              }
            }

            return Container(
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(Radii.lg),
                border: Border.all(color: c.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Tag(label: report.reasonLabel, color: c.danger, background: c.dangerSoft, icon: AppIcons.flag),
                      const SizedBox(width: 8),
                      Tag(label: report.targetType),
                      const Spacer(),
                      Text(timeAgo(report.createdAt), style: context.text.bodySmall),
                    ],
                  ),
                  const SizedBox(height: Space.md),
                  if (report.targetUser != null)
                    Row(
                      children: [
                        UserAvatar(name: report.targetUser!.fullName, url: report.targetUser!.avatarUrl, size: 24),
                        const SizedBox(width: 8),
                        Text(report.targetUser!.fullName, style: context.text.titleSmall),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Text(
                    report.excerpt.isEmpty ? '(no text)' : report.excerpt,
                    style: context.text.bodyMedium,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (report.details != null) ...[
                    const SizedBox(height: 6),
                    Text('Reporter: "${report.details}"', style: context.text.bodySmall),
                  ],
                  const SizedBox(height: 4),
                  Text(plural(report.reportsOnTarget, 'report'), style: context.text.labelSmall!.copyWith(color: c.inkSubtle)),
                  const SizedBox(height: Space.md),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Dismiss',
                          variant: ButtonVariant.secondary,
                          size: ButtonSize.medium,
                          onPressed: () => resolve(remove: false),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: AppButton(
                          label: 'Remove',
                          variant: ButtonVariant.danger,
                          size: ButtonSize.medium,
                          onPressed: () => resolve(remove: true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Details extends ConsumerStatefulWidget {
  const _Details({required this.community});

  final Community community;

  @override
  ConsumerState<_Details> createState() => _DetailsState();
}

class _DetailsState extends ConsumerState<_Details> {
  late final _name = TextEditingController(text: widget.community.name);
  late final _tagline = TextEditingController(text: widget.community.tagline);
  late final _description = TextEditingController(text: widget.community.description);
  late bool _private = widget.community.isPrivate;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _tagline.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(communityRepositoryProvider).update(widget.community.id, {
        'name': _name.text.trim(),
        'tagline': _tagline.text.trim().isEmpty ? null : _tagline.text.trim(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
        'visibility': _private ? 'private' : 'public',
      });
      await ref.read(communityProvider(widget.community.slug).notifier).reload();
      if (mounted) showToast(context, 'Saved');
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.community.isAdmin) {
      return const EmptyState(icon: AppIcons.lock, title: 'Admins only', message: 'Only owners and admins can edit details.');
    }
    return ListView(
      padding: const EdgeInsets.all(Space.xl),
      children: [
        AppTextField(label: 'Name', controller: _name, maxLength: 60),
        const SizedBox(height: Space.lg),
        AppTextField(label: 'Tagline', controller: _tagline, maxLength: 120),
        const SizedBox(height: Space.lg),
        AppTextField(label: 'Description', controller: _description, maxLines: 5, maxLength: 2000),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _private,
          onChanged: (v) => setState(() => _private = v),
          title: const Text('Private community'),
        ),
        const SizedBox(height: Space.lg),
        AppButton(label: 'Save changes', expand: true, loading: _busy, onPressed: _save),
      ],
    );
  }
}
