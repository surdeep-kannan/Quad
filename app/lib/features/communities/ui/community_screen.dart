import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/paged_list.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/states.dart';
import '../../events/providers.dart';
import '../../events/ui/event_tiles.dart';
import '../../moderation/ui/report_sheet.dart';
import '../../posts/data/post.dart';
import '../../posts/providers.dart';
import '../../posts/ui/post_card.dart';
import '../data/community.dart';
import '../data/community_repository.dart';
import '../providers.dart';
import 'community_tiles.dart';

enum _Section { posts, rooms, events, about }

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  _Section _section = _Section.posts;
  String _sort = 'hot';

  Future<void> _menu(Community community) async {
    final notifier = ref.read(communityProvider(widget.slug).notifier);
    await showActionSheet(
      context,
      actions: [
        SheetAction(
          icon: AppIcons.share,
          label: 'Share community',
          onTap: () {
            final link = kIsWeb ? '${Uri.base.origin}/#/c/${community.slug}' : 'quad://c/${community.slug}';
            SharePlus.instance.share(ShareParams(text: 'Join ${community.name} on Quad\n$link'));
          },
        ),
        if (community.isStaff)
          SheetAction(
            icon: AppIcons.settings,
            label: 'Manage community',
            onTap: () => context.push('/c/${community.slug}/manage'),
          ),
        SheetAction(icon: AppIcons.users, label: 'Members', onTap: () => context.push('/c/${community.slug}/members')),
        if ((community.isMember || community.isPending) && !community.isOwner)
          SheetAction(
            icon: AppIcons.signOut,
            label: community.isPending ? 'Withdraw request' : 'Leave community',
            destructive: true,
            onTap: () async {
              final ok =
                  community.isPending ||
                  await confirm(
                    context,
                    title: 'Leave ${community.name}?',
                    message: 'You\'ll stop seeing its posts and rooms in your feed.',
                    confirmLabel: 'Leave',
                    destructive: true,
                  );
              if (!ok) return;
              try {
                await notifier.leave();
              } catch (error) {
                if (mounted) showToast(context, friendlyError(error), error: true);
              }
            },
          ),
        if (!community.isMember)
          SheetAction(
            icon: AppIcons.flag,
            label: 'Report community',
            destructive: true,
            onTap: () => showReportSheet(context, targetType: 'community', targetId: community.id, what: 'community'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final community = ref.watch(communityProvider(widget.slug));
    return community.when(
      loading: () => Scaffold(appBar: AppBar(), body: const ListSkeleton(count: 5)),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(error: error, onRetry: () => ref.invalidate(communityProvider(widget.slug))),
      ),
      data: (data) {
        if (data == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: AppIcons.communities,
              title: 'Community not found',
              message: 'It may have been deleted.',
            ),
          );
        }
        return _buildPage(context, data);
      },
    );
  }

  Widget _buildPage(BuildContext context, Community community) {
    final c = context.colors;
    final accent = Palette.at(community.color);
    final notifier = ref.read(communityProvider(widget.slug).notifier);

    final slivers = <Widget>[
      SliverAppBar(
        pinned: true,
        expandedHeight: 132,
        backgroundColor: c.background,
        leading: Padding(
          padding: const EdgeInsets.all(6),
          child: CircleAvatar(
            backgroundColor: Colors.black.withValues(alpha: 0.28),
            child: IconButton(
              tooltip: 'Back',
              icon: const Icon(AppIcons.back, color: Colors.white, size: 20),
              onPressed: () => context.pop(),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(6),
            child: CircleAvatar(
              backgroundColor: Colors.black.withValues(alpha: 0.28),
              child: IconButton(
                tooltip: 'More',
                icon: const Icon(AppIcons.more, color: Colors.white, size: 20),
                onPressed: () => _menu(community),
              ),
            ),
          ),
        ],
        flexibleSpace: FlexibleSpaceBar(
          collapseMode: CollapseMode.pin,
          background: community.bannerUrl != null
              ? AppImage(community.bannerUrl!)
              : DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [accent, Color.lerp(accent, Colors.black, 0.25)!],
                    ),
                  ),
                  child: CustomPaint(painter: _DotsPainter(Colors.white.withValues(alpha: 0.12))),
                ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Transform.translate(
                    offset: Offset.zero,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: c.background, width: 4),
                      ),
                      child: CommunityAvatar(
                        name: community.name,
                        color: community.color,
                        url: community.avatarUrl,
                        size: 76,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: EdgeInsets.zero,
                    child: community.isStaff
                        ? AppButton(
                            label: 'Manage',
                            icon: AppIcons.settings,
                            variant: ButtonVariant.secondary,
                            size: ButtonSize.medium,
                            onPressed: () => context.push('/c/${community.slug}/manage'),
                          )
                        : JoinButton(
                            community: community,
                            size: ButtonSize.medium,
                            onChanged: (_) => notifier.reload(),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              Transform.translate(
                offset: Offset.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(community.name, style: context.text.headlineLarge)),
                        if (community.isPrivate) ...[
                          const SizedBox(width: 6),
                          Icon(AppIcons.lock, size: 18, color: c.inkMuted, semanticLabel: 'Private'),
                        ],
                      ],
                    ),
                    if (community.tagline != null) ...[
                      const SizedBox(height: 4),
                      Text(community.tagline!, style: context.text.bodyMedium!.copyWith(color: c.inkMuted)),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Tag(
                          label: CommunityCategories.label(community.category),
                          icon: CommunityCategories.icon(community.category),
                        ),
                        GestureDetector(
                          onTap: () => context.push('/c/${community.slug}/members'),
                          child: Tag(label: plural(community.membersCount, 'member'), icon: AppIcons.users),
                        ),
                        if (community.college != null)
                          GestureDetector(
                            onTap: () => context.push('/college/${community.college!.id}'),
                            child: Tag(label: community.college!.label, icon: AppIcons.graduation),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      SliverPersistentHeader(
        pinned: true,
        delegate: _SectionBar(
          selected: _section,
          onSelected: (section) => setState(() => _section = section),
          background: c.background,
          line: c.line,
        ),
      ),
    ];

    if (!community.canSeeContent && _section != _Section.about) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: AppIcons.lock,
            title: community.isPending ? 'Request pending' : 'This community is private',
            message: community.isPending
                ? 'You\'ll get a notification when a moderator approves you.'
                : 'Request to join to see posts, rooms and events.',
          ),
        ),
      );
    } else {
      slivers.addAll(switch (_section) {
        _Section.posts => _posts(community),
        _Section.rooms => [_RoomsSliver(community: community)],
        _Section.events => [_EventsSliver(community: community)],
        _Section.about => [SliverToBoxAdapter(child: _About(community: community))],
      });
    }

    return Scaffold(
      body: AppRefresh(
        onRefresh: () async {
          await notifier.reload();
          ref.invalidate(communityFeedProvider);
          ref.invalidate(communityRoomsProvider(community.id));
          ref.invalidate(communityEventsProvider(community.id));
        },
        child: CustomScrollView(slivers: slivers),
      ),
      floatingActionButton: community.isMember && _section == _Section.posts
          ? FloatingActionButton(
              tooltip: 'New post',
              onPressed: () => context.push('/compose?community=${community.id}'),
              backgroundColor: c.ink,
              foregroundColor: c.inkInverse,
              shape: const CircleBorder(),
              child: const Icon(AppIcons.plusBold),
            )
          : null,
    );
  }

  List<Widget> _posts(Community community) {
    final key = (communityId: community.id, sort: _sort);
    final feed = ref.watch(communityFeedProvider(key));
    final notifier = ref.read(communityFeedProvider(key).notifier);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: ChipRow(
            children: [
              for (final (value, label) in [('hot', 'Hot'), ('new', 'New'), ('top', 'Top')])
                PillChip(
                  label: label,
                  dense: true,
                  selected: _sort == value,
                  onTap: () => setState(() => _sort = value),
                ),
            ],
          ),
        ),
      ),
      PagedSliverList<Post>(
        value: feed,
        onLoadMore: notifier.loadMore,
        onRetry: () => ref.invalidate(communityFeedProvider(key)),
        skeleton: const Skeleton(child: Column(children: [PostSkeleton(), PostSkeleton()])),
        empty: EmptyState(
          icon: AppIcons.chatText,
          title: 'No posts yet',
          message: community.isMember ? 'Kick things off with the first post.' : 'Join to start the conversation.',
          compact: true,
        ),
        itemBuilder: (_, post, _) => PostCard(post: post, showCommunity: false, isMod: community.isMod),
      ),
    ];
  }
}

class _SectionBar extends SliverPersistentHeaderDelegate {
  _SectionBar({required this.selected, required this.onSelected, required this.background, required this.line});

  final _Section selected;
  final ValueChanged<_Section> onSelected;
  final Color background;
  final Color line;

  @override
  double get minExtent => 46;

  @override
  double get maxExtent => 46;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final c = context.colors;
    const labels = {
      _Section.posts: 'Posts',
      _Section.rooms: 'Rooms',
      _Section.events: 'Events',
      _Section.about: 'About',
    };
    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (final section in _Section.values)
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onSelected(section);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: section == selected ? c.ink : Colors.transparent, width: 2.5),
                  ),
                ),
                child: Text(
                  labels[section]!,
                  style: context.text.titleSmall!.copyWith(
                    fontSize: 15,
                    color: section == selected ? c.ink : c.inkSubtle,
                    fontWeight: section == selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_SectionBar oldDelegate) =>
      oldDelegate.selected != selected || oldDelegate.background != background;
}

class _RoomsSliver extends ConsumerWidget {
  const _RoomsSliver({required this.community});

  final Community community;

  bool get _canManage => community.can(CommunityPermissions.manageRooms);

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final created = await showAppSheet<bool>(context, builder: (_) => _RoomSheet(communityId: community.id));
    if (created ?? false) ref.invalidate(communityRoomsProvider(community.id));
  }

  Future<void> _manage(BuildContext context, WidgetRef ref, Room room) async {
    final repo = ref.read(communityRepositoryProvider);
    Future<void> run(Future<void> Function() action, String done) async {
      try {
        await action();
        ref.invalidate(communityRoomsProvider(community.id));
        ref.invalidate(roomProvider(room.id));
        if (context.mounted) showToast(context, done);
      } catch (error) {
        if (context.mounted) showToast(context, friendlyError(error), error: true);
      }
    }

    await showActionSheet(
      context,
      title: '# ${room.name}',
      actions: [
        SheetAction(
          icon: AppIcons.edit,
          label: 'Edit room',
          subtitle: 'Name, topic and type',
          onTap: () async {
            final saved = await showAppSheet<bool>(
              context,
              builder: (_) => _RoomSheet(communityId: community.id, room: room),
            );
            if (saved ?? false) {
              ref.invalidate(communityRoomsProvider(community.id));
              ref.invalidate(roomProvider(room.id));
            }
          },
        ),
        SheetAction(
          icon: AppIcons.lock,
          label: room.isLocked ? 'Unlock room' : 'Lock room',
          subtitle: room.isLocked ? 'Everyone can chat again' : 'Only people who moderate room chat can post',
          onTap: () => run(
            () => repo.updateRoom(room.id, {'is_locked': !room.isLocked}),
            room.isLocked ? 'Room unlocked' : 'Room locked',
          ),
        ),
        SheetAction(
          icon: AppIcons.trash,
          label: 'Delete room',
          destructive: true,
          onTap: () async {
            final ok = await confirm(
              context,
              title: 'Delete #${room.name}?',
              message: 'Its messages will be deleted for everyone. This can\'t be undone.',
              confirmLabel: 'Delete',
              destructive: true,
            );
            if (ok) await run(() => repo.deleteRoom(room.id), 'Room deleted');
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(communityRoomsProvider(community.id));
    final c = context.colors;
    return rooms.when(
      loading: () => const SliverToBoxAdapter(child: ListSkeleton(count: 4)),
      error: (error, _) => SliverToBoxAdapter(
        child: ErrorState(
          error: error,
          compact: true,
          onRetry: () => ref.invalidate(communityRoomsProvider(community.id)),
        ),
      ),
      data: (list) => SliverList.list(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 14, Space.gutter, 6),
            child: Text(
              _canManage
                  ? 'Rooms have live chat plus voice and video. Long-press a room to edit, lock or delete it.'
                  : 'Rooms have live chat plus voice and video. Drop in anytime.',
              style: context.text.bodySmall,
            ),
          ),
          for (final room in list)
            ListTile(
              onTap: () => context.push('/room/${room.id}'),
              onLongPress: _canManage ? () => _manage(context, ref, room) : null,
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(12)),
                child: Icon(RoomKinds.icon(room.kind), size: 20, color: c.ink),
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      room.name,
                      style: context.text.titleSmall!.copyWith(
                        fontSize: 15,
                        fontWeight: room.hasUnread ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (room.isLocked) ...[const SizedBox(width: 4), Icon(AppIcons.lock, size: 13, color: c.inkSubtle)],
                ],
              ),
              subtitle: Text(
                room.lastMessagePreview ?? room.topic ?? RoomKinds.all[room.kind] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: room.hasUnread
                  ? Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                    )
                  : Text(room.lastMessageAt == null ? '' : timeAgo(room.lastMessageAt!), style: context.text.bodySmall),
            ),
          if (_canManage)
            Padding(
              padding: const EdgeInsets.all(Space.gutter),
              child: AppButton(
                label: 'Create a room',
                icon: AppIcons.plus,
                variant: ButtonVariant.secondary,
                size: ButtonSize.medium,
                onPressed: () => _create(context, ref),
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

/// Creates a room, or edits [room] when given.
class _RoomSheet extends ConsumerStatefulWidget {
  const _RoomSheet({required this.communityId, this.room});

  final String communityId;
  final Room? room;

  @override
  ConsumerState<_RoomSheet> createState() => _RoomSheetState();
}

class _RoomSheetState extends ConsumerState<_RoomSheet> {
  late final _name = TextEditingController(text: widget.room?.name);
  late final _topic = TextEditingController(text: widget.room?.topic);
  late String _kind = widget.room?.kind ?? 'study';
  bool _busy = false;

  bool get _editing => widget.room != null;

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    final repo = ref.read(communityRepositoryProvider);
    final name = _name.text.trim();
    final topic = _topic.text.trim().isEmpty ? null : _topic.text.trim();
    try {
      if (_editing) {
        await repo.updateRoom(widget.room!.id, {'name': name, 'topic': topic, 'kind': _kind});
      } else {
        await repo.createRoom(widget.communityId, name: name, topic: topic, kind: _kind);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_editing ? 'Edit room' : 'New room', style: context.text.headlineSmall),
          const SizedBox(height: Space.lg),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in RoomKinds.all.entries.where((e) => e.key != 'general' || _kind == 'general'))
                PillChip(
                  label: entry.value,
                  icon: RoomKinds.icon(entry.key),
                  dense: true,
                  selected: _kind == entry.key,
                  onTap: () => setState(() {
                    _kind = entry.key;
                    if (_name.text.isEmpty) _name.text = entry.value.toLowerCase().replaceAll(' ', '-');
                  }),
                ),
            ],
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'room-name', prefixIcon: Icon(AppIcons.hash, size: 18)),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _topic,
            decoration: const InputDecoration(hintText: 'What is this room for? (optional)'),
          ),
          const SizedBox(height: Space.xl),
          AppButton(
            label: _editing ? 'Save room' : 'Create room',
            expand: true,
            loading: _busy,
            onPressed: _name.text.trim().length < 2 ? null : _create,
          ),
        ],
      ),
    );
  }
}

class _EventsSliver extends ConsumerWidget {
  const _EventsSliver({required this.community});

  final Community community;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(communityEventsProvider(community.id));
    return events.when(
      loading: () => const SliverToBoxAdapter(child: ListSkeleton(count: 3)),
      error: (error, _) => SliverToBoxAdapter(
        child: ErrorState(
          error: error,
          compact: true,
          onRetry: () => ref.invalidate(communityEventsProvider(community.id)),
        ),
      ),
      data: (list) => SliverList.list(
        children: [
          if (community.can(CommunityPermissions.manageEvents))
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
              child: AppButton(
                label: 'Create an event',
                icon: AppIcons.calendarPlus,
                variant: ButtonVariant.secondary,
                size: ButtonSize.medium,
                onPressed: () => context.push('/events/new?community=${community.id}'),
              ),
            ),
          if (list.isEmpty)
            const EmptyState(
              icon: AppIcons.events,
              title: 'No upcoming events',
              message: 'Check back soon.',
              compact: true,
            )
          else
            for (final event in list) EventRow(event: event),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _About extends StatelessWidget {
  const _About({required this.community});

  final Community community;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (community.description != null) ...[
            Text(community.description!, style: context.text.bodyLarge),
            const SizedBox(height: Space.xl),
          ],
          if (community.rules.isNotEmpty) ...[
            Text('Rules', style: context.text.headlineSmall),
            const SizedBox(height: Space.md),
            for (var i = 0; i < community.rules.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(8)),
                      child: Text('${i + 1}', style: context.text.labelMedium),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(community.rules[i].title, style: context.text.titleSmall),
                          if (community.rules[i].body != null)
                            Text(community.rules[i].body!, style: context.text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Space.md),
          ],
          if (community.tags.isNotEmpty) ...[
            Wrap(spacing: 8, runSpacing: 8, children: [for (final tag in community.tags) Tag(label: '#$tag')]),
            const SizedBox(height: Space.xl),
          ],
          if (community.createdAt != null)
            Row(
              children: [
                Icon(community.isPrivate ? AppIcons.lock : AppIcons.globe, size: 16, color: c.inkMuted),
                const SizedBox(width: 8),
                Text(
                  '${community.isPrivate ? 'Private' : 'Public'} · Created ${timeAgo(community.createdAt!)}',
                  style: context.text.bodySmall,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = 10; y < size.height; y += 18) {
      for (double x = (y ~/ 18).isEven ? 10 : 19; x < size.width; x += 18) {
        canvas.drawCircle(Offset(x, y), 1.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => oldDelegate.color != color;
}
