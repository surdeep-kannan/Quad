import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/paged_list.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/states.dart';
import '../data/event.dart';
import '../data/event_repository.dart';
import '../providers.dart';
import 'event_tiles.dart';

enum _View { discover, going, hosting }

class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  _View _view = _View.discover;
  EventWindow _window = EventWindow.upcoming;
  String? _category;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: Column(
        children: [
          TabHeader(
            title: 'Events',
            actions: [
              IconTap(icon: AppIcons.calendarPlus, tooltip: 'Create an event', onTap: () => context.push('/events/new')),
            ],
            bottom: SizedBox(
              height: 44,
              child: Row(
                children: [
                  const SizedBox(width: Space.gutter),
                  for (final view in _View.values) ...[
                    _ViewTab(
                      label: switch (view) { _View.discover => 'Discover', _View.going => 'Going', _View.hosting => 'Hosting' },
                      selected: _view == view,
                      onTap: () => setState(() => _view = view),
                    ),
                    const SizedBox(width: 18),
                  ],
                ],
              ),
            ),
          ),
          Divider(height: 1, color: c.line),
          Expanded(
            child: switch (_view) {
              _View.discover => _discover(),
              _View.going => const _MineList(hosting: false),
              _View.hosting => const _MineList(hosting: true),
            },
          ),
        ],
      ),
    );
  }

  Widget _discover() {
    final filter = (window: _window, category: _category);
    final events = ref.watch(discoverEventsProvider(filter));
    final notifier = ref.read(discoverEventsProvider(filter).notifier);
    final featured = (events.value?.items ?? const <CampusEvent>[]).where((e) => !e.isPast).take(5).toList();
    return AppRefresh(
      onRefresh: notifier.refresh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: ChipRow(
                children: [
                  for (final window in EventWindow.values)
                    PillChip(
                      label: window.label,
                      dense: true,
                      selected: _window == window,
                      onTap: () => setState(() => _window = window),
                    ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverToBoxAdapter(
            child: ChipRow(
              children: [
                PillChip(label: 'All types', dense: true, selected: _category == null, onTap: () => setState(() => _category = null)),
                for (final entry in EventCategories.all.entries.where((e) => e.key != 'other'))
                  PillChip(
                    label: entry.value,
                    icon: EventCategories.icon(entry.key),
                    dense: true,
                    selected: _category == entry.key,
                    onTap: () => setState(() => _category = entry.key),
                  ),
              ],
            ),
          ),
          if (featured.length >= 2 && _category == null && _window == EventWindow.upcoming) ...[
            const SliverToBoxAdapter(child: SectionHeader(title: 'Coming up')),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 420,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  itemCount: featured.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (_, i) => EventCard(event: featured[i]),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SectionHeader(title: 'All events')),
          ] else
            const SliverToBoxAdapter(child: SizedBox(height: Space.sm)),
          PagedSliverList<CampusEvent>(
            value: events,
            onLoadMore: notifier.loadMore,
            onRetry: () => ref.invalidate(discoverEventsProvider(filter)),
            empty: EmptyState(
              icon: AppIcons.events,
              title: 'No events match',
              message: 'Try another filter, or host one yourself.',
              actionLabel: 'Create an event',
              onAction: () => context.push('/events/new'),
            ),
            itemBuilder: (_, event, _) => EventRow(event: event),
          ),
        ],
      ),
    );
  }
}

class _ViewTab extends StatelessWidget {
  const _ViewTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: selected ? c.ink : Colors.transparent, width: 2.5)),
        ),
        child: Text(
          label,
          style: context.text.titleSmall!.copyWith(
            fontSize: 15,
            color: selected ? c.ink : c.inkSubtle,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MineList extends ConsumerWidget {
  const _MineList({required this.hosting});

  final bool hosting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = hosting ? hostingEventsProvider : myEventsProvider;
    final events = ref.watch(provider);
    return events.when(
      loading: () => const ListSkeleton(),
      error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(provider)),
      data: (list) {
        if (list.isEmpty) {
          return hosting
              ? EmptyState(
                  icon: AppIcons.calendarPlus,
                  title: 'Host your first event',
                  message: 'Workshops, meetups, hackathons. We\'ll even design the poster.',
                  actionLabel: 'Create an event',
                  onAction: () => context.push('/events/new'),
                )
              : const EmptyState(
                  icon: AppIcons.ticket,
                  title: 'No plans yet',
                  message: 'Events you register for show up here with reminders.',
                );
        }
        return RefreshIndicator(
          color: context.colors.ink,
          onRefresh: () async => ref.invalidate(provider),
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => EventRow(event: list[i]),
          ),
        );
      },
    );
  }
}
