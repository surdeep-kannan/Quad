import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/paged_list.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/states.dart';
import '../../colleges/ui/colleges_view.dart';
import '../data/community.dart';
import '../providers.dart';
import 'community_tiles.dart';

/// Communities tab: your communities and discovery, plus college rankings.
class CommunitiesScreen extends ConsumerStatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  ConsumerState<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends ConsumerState<CommunitiesScreen> {
  bool _colleges = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TabHeader(
            title: _colleges ? 'Colleges' : 'Communities',
            actions: [
              if (!_colleges)
                IconTap(icon: AppIcons.plus, tooltip: 'Create a community', onTap: () => context.push('/communities/new')),
            ],
            bottom: Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, Space.md),
              child: _Segmented(
                value: _colleges,
                onChanged: (value) => setState(() => _colleges = value),
              ),
            ),
          ),
          Expanded(child: _colleges ? const CollegeLeaderboardView() : const _CommunitiesView()),
        ],
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget segment(String label, IconData icon, bool selected, VoidCallback onTap) => Expanded(
          child: Semantics(
            selected: selected,
            button: true,
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 36,
                decoration: BoxDecoration(
                  color: selected ? c.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: selected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))] : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 16, color: selected ? c.ink : c.inkMuted),
                    const SizedBox(width: 6),
                    Text(label, style: context.text.labelMedium!.copyWith(color: selected ? c.ink : c.inkMuted)),
                  ],
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          segment('Communities', AppIcons.communities, !value, () => onChanged(false)),
          segment('Colleges & rankings', AppIcons.ranking, value, () => onChanged(true)),
        ],
      ),
    );
  }
}

class _CommunitiesView extends ConsumerStatefulWidget {
  const _CommunitiesView();

  @override
  ConsumerState<_CommunitiesView> createState() => _CommunitiesViewState();
}

class _CommunitiesViewState extends ConsumerState<_CommunitiesView> {
  String? _category;

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(myCommunitiesProvider);
    final discover = ref.watch(discoverCommunitiesProvider(_category));
    final notifier = ref.read(discoverCommunitiesProvider(_category).notifier);

    return AppRefresh(
      onRefresh: () async {
        ref.invalidate(myCommunitiesProvider);
        await notifier.refresh();
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: SearchField(hint: 'Search communities', readOnly: true, onTap: () => context.push('/search')),
            ),
          ),
          if ((mine.value ?? const []).isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader(title: 'Your communities')),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  itemCount: mine.value!.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _MineTile(community: mine.value![i]),
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SectionHeader(title: 'Discover')),
          SliverToBoxAdapter(
            child: ChipRow(
              children: [
                PillChip(label: 'All', selected: _category == null, dense: true, onTap: () => setState(() => _category = null)),
                for (final entry in CommunityCategories.all.entries.where((e) => e.key != 'other'))
                  PillChip(
                    label: entry.value,
                    icon: CommunityCategories.icon(entry.key),
                    dense: true,
                    selected: _category == entry.key,
                    onTap: () => setState(() => _category = entry.key),
                  ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Space.sm)),
          PagedSliverList<Community>(
            value: discover,
            onLoadMore: notifier.loadMore,
            onRetry: () => ref.invalidate(discoverCommunitiesProvider(_category)),
            empty: EmptyState(
              icon: AppIcons.communities,
              title: 'No communities here yet',
              message: 'Start the first one and invite your friends.',
              actionLabel: 'Create a community',
              onAction: () => context.push('/communities/new'),
            ),
            itemBuilder: (_, community, _) => CommunityRow(community: community),
          ),
        ],
      ),
    );
  }
}

class _MineTile extends StatelessWidget {
  const _MineTile({required this.community});

  final Community community;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => context.push('/c/${community.slug}'),
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CommunityAvatar(name: community.name, color: community.color, url: community.avatarUrl, size: 60),
                if (community.isStaff) const Positioned(right: -4, bottom: -4, child: _ModDot()),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              community.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: context.text.labelSmall!.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModDot extends StatelessWidget {
  const _ModDot();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.success, shape: BoxShape.circle, border: Border.all(color: c.background, width: 2)),
      child: const Icon(AppIcons.shield, size: 10, color: Colors.white),
    );
  }
}
