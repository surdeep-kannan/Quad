import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/paged_list.dart';
import '../../../core/widgets/states.dart';
import '../data/college.dart';
import '../providers.dart';

const _states = ['Tamil Nadu', 'Karnataka', 'Maharashtra', 'Delhi', 'Telangana', 'Punjab', 'West Bengal', 'Uttar Pradesh', 'Kerala', 'Rajasthan'];

/// The college leaderboard, with a link to how the scores work.
class CollegeLeaderboardView extends ConsumerStatefulWidget {
  const CollegeLeaderboardView({super.key});

  @override
  ConsumerState<CollegeLeaderboardView> createState() => _CollegeLeaderboardViewState();
}

class _CollegeLeaderboardViewState extends ConsumerState<CollegeLeaderboardView> {
  String? _region;

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(collegeLeaderboardProvider(_region));
    final notifier = ref.read(collegeLeaderboardProvider(_region).notifier);
    final c = context.colors;
    return AppRefresh(
      onRefresh: notifier.refresh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: InkWell(
              onTap: () => context.push('/rankings/method'),
              child: Container(
                margin: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.md),
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.md)),
                child: Row(
                  children: [
                    Icon(AppIcons.info, color: c.accentInk, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ranked by student activity on Quad: events, clubs, hackathons, achievements and engagement. See how it works.',
                        style: context.text.bodySmall!.copyWith(color: c.accentInk),
                      ),
                    ),
                    Icon(AppIcons.forward, size: 16, color: c.accentInk),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: ChipRow(
              children: [
                PillChip(label: 'All India', dense: true, selected: _region == null, onTap: () => setState(() => _region = null)),
                for (final s in _states) PillChip(label: s, dense: true, selected: _region == s, onTap: () => setState(() => _region = s)),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Space.sm)),
          PagedSliverList<College>(
            value: board,
            onLoadMore: notifier.loadMore,
            onRetry: () => ref.invalidate(collegeLeaderboardProvider(_region)),
            empty: const EmptyState(icon: AppIcons.graduation, title: 'No colleges here yet'),
            itemBuilder: (_, college, _) => CollegeRow(college: college),
          ),
        ],
      ),
    );
  }
}

class CollegeRow extends StatelessWidget {
  const CollegeRow({super.key, required this.college});

  final College college;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final stats = college.stats;
    final rank = stats?.rank;
    return InkWell(
      onTap: () => context.push('/college/${college.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                rank == null ? '–' : '$rank',
                textAlign: TextAlign.center,
                style: context.text.headlineSmall!.copyWith(color: rank != null && rank <= 3 ? c.accent : c.inkSubtle),
              ),
            ),
            const SizedBox(width: 8),
            CommunityAvatar(name: college.label, color: college.name.length, url: college.logoUrl, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(college.label, style: context.text.titleSmall!.copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    [college.location, if (stats != null) plural(stats.students, 'student')].where((s) => s.isNotEmpty).join(' · '),
                    style: context.text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (stats != null && rank != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(stats.score.toStringAsFixed(1), style: context.text.titleMedium),
                  Text('score', style: context.text.labelSmall!.copyWith(color: c.inkSubtle)),
                ],
              )
            else
              Text('Not ranked', style: context.text.labelSmall!.copyWith(color: c.inkSubtle)),
          ],
        ),
      ),
    );
  }
}
