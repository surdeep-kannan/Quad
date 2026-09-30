import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/states.dart';
import '../../communities/data/community_repository.dart';
import '../../communities/ui/community_tiles.dart';
import '../../events/providers.dart';
import '../../events/ui/event_tiles.dart';
import '../providers.dart';

final _collegeCommunitiesProvider = FutureProvider.autoDispose.family((ref, String collegeId) {
  return ref.watch(communityRepositoryProvider).byCollege(collegeId);
});

class CollegeDetailScreen extends ConsumerWidget {
  const CollegeDetailScreen({super.key, required this.collegeId});

  final String collegeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final college = ref.watch(collegeProvider(collegeId));
    final pillars = ref.watch(rankingPillarsProvider).value ?? const [];
    final communities = ref.watch(_collegeCommunitiesProvider(collegeId)).value ?? const [];
    final events = ref.watch(collegeEventsProvider(collegeId)).value ?? const [];
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop())),
      body: college.when(
        loading: () => const CenteredLoader(),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(collegeProvider(collegeId))),
        data: (data) {
          if (data == null) return const EmptyState(icon: AppIcons.graduation, title: 'College not found');
          final stats = data.stats;
          return ListView(
            padding: const EdgeInsets.only(bottom: 60),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                child: Row(
                  children: [
                    CommunityAvatar(name: data.label, color: data.name.length, url: data.logoUrl, size: 64),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data.name, style: context.text.headlineMedium),
                          Text([data.location, ?data.typeLabel, if (data.established != null) 'Est. ${data.established}'].where((s) => s.isNotEmpty).join(' · '), style: context.text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!data.isVerified)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
                  child: Tag(label: 'Added by students · unverified', color: c.warning, background: c.warningSoft),
                ),
              if (stats != null) ...[
                Container(
                  margin: const EdgeInsets.all(Space.gutter),
                  padding: const EdgeInsets.all(Space.lg),
                  decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(Radii.xl)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Quad rank', style: context.text.labelMedium!.copyWith(color: c.inkInverse.withValues(alpha: 0.7))),
                            Text(stats.rank == null ? 'Not ranked' : '#${stats.rank}', style: context.text.displayMedium!.copyWith(color: c.inkInverse)),
                            if (stats.limitedData)
                              Text('Limited data: fewer than 10 students', style: context.text.bodySmall!.copyWith(color: c.inkInverse.withValues(alpha: 0.6))),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(stats.score.toStringAsFixed(1), style: context.text.displaySmall!.copyWith(color: c.accent)),
                          Text('out of 100', style: context.text.bodySmall!.copyWith(color: c.inkInverse.withValues(alpha: 0.6))),
                        ],
                      ),
                    ],
                  ),
                ),
                SectionHeader(title: 'Score breakdown', actionLabel: 'How it works', onAction: () => context.push('/rankings/method'), padding: const EdgeInsets.fromLTRB(Space.gutter, 0, 8, 8)),
                for (final pillar in pillars)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.gutter, 6, Space.gutter, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(pillar.label, style: context.text.titleSmall)),
                            Text(
                              '${stats.rawFor(pillar.key) ?? '${(stats.engagementRate * 100).round()}%'} · ${(pillar.weight * 100).round()}% weight',
                              style: context.text.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (stats.pillarScores[pillar.key] ?? 0).clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: c.surfaceMuted,
                            color: Palette.at(pillars.indexOf(pillar) + 5),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(Space.gutter),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Tag(label: plural(stats.students, 'student'), icon: AppIcons.users),
                      Tag(label: plural(stats.communities, 'community', 'communities'), icon: AppIcons.communities),
                      Tag(label: plural(stats.clubs, 'club'), icon: AppIcons.users),
                      Tag(label: plural(stats.events, 'event'), icon: AppIcons.events),
                    ],
                  ),
                ),
              ],
              if (communities.isNotEmpty) ...[
                const SectionHeader(title: 'Communities'),
                for (final community in communities) CommunityRow(community: community),
              ],
              if (events.isNotEmpty) ...[
                const SectionHeader(title: 'Upcoming events'),
                for (final event in events) EventRow(event: event),
              ],
            ],
          );
        },
      ),
    );
  }
}
