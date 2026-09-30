import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/debouncer.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/states.dart';
import '../../colleges/ui/colleges_view.dart';
import '../../communities/data/community.dart';
import '../../communities/ui/community_tiles.dart';
import '../../events/ui/event_tiles.dart';
import '../../posts/ui/post_card.dart';
import '../../profile/ui/follow_list_screen.dart';
import '../data/search_repository.dart';

final _searchProvider = FutureProvider.autoDispose.family<SearchResults, String>((ref, query) {
  if (query.trim().length < 2) return const SearchResults();
  return ref.watch(searchRepositoryProvider).everything(query.trim(), limit: 8);
});

enum _Kind { top, people, communities, events, posts, reels, colleges, rooms }

/// One search box for people, communities, events, posts, reels, colleges and rooms.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  final _debounce = Debouncer(const Duration(milliseconds: 300));
  late String _query = widget.initialQuery ?? '';
  _Kind _kind = _Kind.top;

  @override
  void dispose() {
    _controller.dispose();
    _debounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(_searchProvider(_query));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: Space.gutter),
          child: SearchField(
            hint: 'Search Quad',
            controller: _controller,
            autofocus: widget.initialQuery == null,
            onChanged: (v) => _debounce(() => setState(() => _query = v)),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChipRow(
              children: [
                for (final kind in _Kind.values)
                  PillChip(label: kind.name[0].toUpperCase() + kind.name.substring(1), dense: true, selected: _kind == kind, onTap: () => setState(() => _kind = kind)),
              ],
            ),
          ),
        ),
      ),
      body: _query.trim().length < 2
          ? const EmptyState(icon: AppIcons.search, title: 'Search Quad', message: 'Find students, communities, events, posts, reels, colleges and rooms.')
          : results.when(
              loading: () => const ListSkeleton(),
              error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(_searchProvider(_query))),
              data: (r) => r.isEmpty
                  ? EmptyState(icon: AppIcons.search, title: 'No results for "$_query"', message: 'Try a different word or spelling.')
                  : ListView(padding: const EdgeInsets.only(bottom: 40), children: _sections(context, r)),
            ),
    );
  }

  List<Widget> _sections(BuildContext context, SearchResults r) {
    final show = _kind;
    bool on(_Kind k) => show == _Kind.top || show == k;
    final c = context.colors;
    return [
      if (on(_Kind.people) && r.people.isNotEmpty) ...[
        if (show == _Kind.top) const SectionHeader(title: 'People'),
        for (final p in r.people) PersonRow.profile(p, trailing: FollowButton(profile: p)),
      ],
      if (on(_Kind.communities) && r.communities.isNotEmpty) ...[
        if (show == _Kind.top) const SectionHeader(title: 'Communities'),
        for (final Community community in r.communities) CommunityRow(community: community),
      ],
      if (on(_Kind.events) && r.events.isNotEmpty) ...[
        if (show == _Kind.top) const SectionHeader(title: 'Events'),
        for (final e in r.events) EventRow(event: e),
      ],
      if (on(_Kind.colleges) && r.colleges.isNotEmpty) ...[
        if (show == _Kind.top) const SectionHeader(title: 'Colleges'),
        for (final college in r.colleges) CollegeRow(college: college),
      ],
      if (on(_Kind.rooms) && r.rooms.isNotEmpty) ...[
        if (show == _Kind.top) const SectionHeader(title: 'Rooms'),
        for (final room in r.rooms)
          ListTile(
            leading: CommunityAvatar(name: room.community.name, color: room.community.color, url: room.community.avatarUrl, size: 40),
            title: Text('#${room.name}'),
            subtitle: Text(room.topic ?? room.community.name, maxLines: 1),
            trailing: room.isMember ? null : Text('Join community', style: context.text.labelSmall!.copyWith(color: c.inkSubtle)),
            onTap: () => context.push(room.isMember ? '/room/${room.id}' : '/c/${room.community.slug}'),
          ),
      ],
      if (on(_Kind.reels) && r.reels.isNotEmpty) ...[
        if (show == _Kind.top) const SectionHeader(title: 'Reels'),
        for (final reel in r.reels) PostCard(post: reel),
      ],
      if (on(_Kind.posts) && r.posts.isNotEmpty) ...[
        if (show == _Kind.top) const SectionHeader(title: 'Posts'),
        for (final post in r.posts) PostCard(post: post),
      ],
    ];
  }
}
