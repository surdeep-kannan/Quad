import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/supabase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/rich_body.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../moderation/ui/report_sheet.dart';
import '../data/event.dart';
import '../data/event_repository.dart';
import '../providers.dart';
import 'event_poster.dart';

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(eventProvider(eventId));
    return event.when(
      loading: () => Scaffold(appBar: AppBar(), body: const CenteredLoader()),
      error: (error, _) => Scaffold(appBar: AppBar(), body: ErrorState(error: error, onRetry: () => ref.invalidate(eventProvider(eventId)))),
      data: (data) => data == null
          ? Scaffold(
              appBar: AppBar(),
              body: const EmptyState(icon: AppIcons.events, title: 'Event not found', message: 'It may have been removed.'),
            )
          : _EventPage(event: data),
    );
  }
}

class _EventPage extends ConsumerStatefulWidget {
  const _EventPage({required this.event});

  final CampusEvent event;

  @override
  ConsumerState<_EventPage> createState() => _EventPageState();
}

class _EventPageState extends ConsumerState<_EventPage> {
  bool _busy = false;

  CampusEvent get event => widget.event;

  bool get _isOrganizer => event.organizer.id == ref.read(supabaseProvider).uid;

  Future<void> _register() async {
    setState(() => _busy = true);
    try {
      final status = await ref.read(eventProvider(event.id).notifier).register();
      HapticFeedback.mediumImpact();
      if (mounted) {
        showToast(
          context,
          status == 'going' ? 'You\'re in! We\'ll remind you before it starts.' : 'It\'s full. You\'re on the waitlist.',
          icon: AppIcons.ticket,
        );
      }
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await confirm(
      context,
      title: 'Cancel registration?',
      message: event.isFull ? 'Your spot will go to the next person on the waitlist.' : 'You can register again later if there\'s space.',
      confirmLabel: 'Cancel registration',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref.read(eventProvider(event.id).notifier).cancelRegistration();
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openLink() async {
    try {
      final link = await ref.read(eventRepositoryProvider).meetingLink(event.id);
      if (link == null) {
        if (mounted) showToast(context, 'The organizer hasn\'t added a link yet.');
        return;
      }
      await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    }
  }

  void _share() {
    final link = kIsWeb ? '${Uri.base.origin}/#/event/${event.id}' : 'quad://event/${event.id}';
    SharePlus.instance.share(ShareParams(text: '${event.title}\n${eventWhen(event.startsAt, end: event.endsAt)}\n$link'));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final updates = ref.watch(eventUpdatesProvider(event.id)).value ?? const [];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
            actions: [
              IconButton(tooltip: 'Share', icon: const Icon(AppIcons.share), onPressed: _share),
              IconButton(
                tooltip: 'More',
                icon: const Icon(AppIcons.more),
                onPressed: () => showActionSheet(
                  context,
                  actions: [
                    if (_isOrganizer) ...[
                      SheetAction(icon: AppIcons.edit, label: 'Edit event', onTap: () => context.push('/event/${event.id}/edit')),
                      SheetAction(icon: AppIcons.users, label: 'Manage attendees', onTap: () => context.push('/event/${event.id}/manage')),
                      SheetAction(
                        icon: AppIcons.megaphone,
                        label: 'Share in a community post',
                        onTap: () => context.push('/compose?type=event&event=${event.id}${event.community == null ? '' : '&community=${event.community!.id}'}'),
                      ),
                    ] else
                      SheetAction(
                        icon: AppIcons.flag,
                        label: 'Report event',
                        destructive: true,
                        onTap: () => showReportSheet(context, targetType: 'event', targetId: event.id, what: 'event'),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Hero(tag: 'poster-${event.id}', child: EventPoster.of(event, radius: Radii.xl)),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Tag(label: EventCategories.single(event.category), icon: EventCategories.icon(event.category)),
                      if (event.isCancelled) Tag(label: 'Cancelled', color: c.danger, background: c.dangerSoft),
                      if (event.isLive) Tag(label: 'Happening now', color: c.onAccent, background: c.accent),
                    ],
                  ),
                  const SizedBox(height: Space.md),
                  Text(event.title, style: context.text.displaySmall),
                  const SizedBox(height: Space.xl),
                  _InfoRow(
                    icon: AppIcons.clock,
                    title: eventWhen(event.startsAt, end: event.endsAt),
                    subtitle: eventCountdown(event.startsAt, event.endsAt),
                  ),
                  _InfoRow(
                    icon: event.isOnline ? AppIcons.monitor : AppIcons.mapPin,
                    title: event.where,
                    subtitle: event.hasLink
                        ? (event.isGoing ? 'Tap to join the online session' : 'Link shared with registered attendees')
                        : event.address,
                    onTap: event.hasLink && (event.isGoing || _isOrganizer) ? _openLink : null,
                  ),
                  _InfoRow(
                    icon: AppIcons.ticket,
                    title: event.capacity == null
                        ? plural(event.registrationsCount, 'person going', 'people going')
                        : '${event.registrationsCount} / ${event.capacity} spots taken',
                    subtitle: event.isFull
                        ? (event.waitlistCount > 0 ? '${event.waitlistCount} on the waitlist' : 'Full. New registrations join the waitlist')
                        : event.spotsLeft != null
                            ? '${event.spotsLeft} spots left'
                            : 'Free entry',
                  ),
                  if (event.attendeesPreview.isNotEmpty) ...[
                    const SizedBox(height: Space.sm),
                    Row(
                      children: [
                        AvatarStack(people: [for (final p in event.attendeesPreview) (p.fullName, p.avatarUrl)], size: 30, max: 5),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _goingLine(event),
                            style: context.text.bodySmall,
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: Space.xl),
                  const Divider(),
                  const SizedBox(height: Space.lg),
                  Text('Hosted by', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
                  const SizedBox(height: Space.sm),
                  InkWell(
                    onTap: () => context.push('/u/${event.organizer.username}'),
                    child: Row(
                      children: [
                        UserAvatar(name: event.organizer.fullName, url: event.organizer.avatarUrl, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              NameLine(name: event.organizer.fullName, verified: event.organizer.isVerified),
                              if (event.community != null)
                                Text('for ${event.community!.name}', style: context.text.bodySmall)
                              else if (event.college != null)
                                Text(event.college!.label, style: context.text.bodySmall),
                            ],
                          ),
                        ),
                        if (event.community != null)
                          TextButton(onPressed: () => context.push('/c/${event.community!.slug}'), child: const Text('Community')),
                      ],
                    ),
                  ),
                  if (event.description != null) ...[
                    const SizedBox(height: Space.xl),
                    Text('About', style: context.text.headlineSmall),
                    const SizedBox(height: Space.sm),
                    RichBody(event.description!, style: context.text.bodyLarge),
                  ],
                  if (updates.isNotEmpty) ...[
                    const SizedBox(height: Space.xl),
                    Text('Updates', style: context.text.headlineSmall),
                    const SizedBox(height: Space.sm),
                    for (final update in updates)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: Space.sm),
                        padding: const EdgeInsets.all(Space.md),
                        decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.md)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(update.body, style: context.text.bodyMedium),
                            const SizedBox(height: 4),
                            Text('${update.author.fullName} · ${timeAgo(update.createdAt)}', style: context.text.bodySmall),
                          ],
                        ),
                      ),
                  ],
                  if (event.tags.isNotEmpty) ...[
                    const SizedBox(height: Space.lg),
                    Wrap(spacing: 8, runSpacing: 8, children: [for (final tag in event.tags) Tag(label: '#$tag')]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomAction(
        event: event,
        isOrganizer: _isOrganizer,
        busy: _busy,
        onRegister: _register,
        onCancel: _cancel,
        onJoin: _openLink,
      ),
    );
  }

  String _goingLine(CampusEvent event) {
    final names = event.attendeesPreview.map((p) => p.firstName).take(2).toList();
    final others = event.registrationsCount - names.length;
    if (names.isEmpty) return '';
    if (others <= 0) return '${names.join(' and ')} going';
    return '${names.join(', ')} and ${compactCount(others)} ${others == 1 ? 'other' : 'others'} going';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, this.subtitle, this.onTap});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall!.copyWith(fontSize: 15)),
                  if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, style: context.text.bodySmall),
                ],
              ),
            ),
            if (onTap != null) Icon(AppIcons.forward, size: 18, color: c.inkSubtle),
          ],
        ),
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.event,
    required this.isOrganizer,
    required this.busy,
    required this.onRegister,
    required this.onCancel,
    required this.onJoin,
  });

  final CampusEvent event;
  final bool isOrganizer;
  final bool busy;
  final VoidCallback onRegister;
  final VoidCallback onCancel;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Widget child;
    if (isOrganizer) {
      child = AppButton(
        label: 'Manage attendees',
        icon: AppIcons.users,
        expand: true,
        onPressed: () => context.push('/event/${event.id}/manage'),
      );
    } else if (event.isCancelled) {
      child = const AppButton(label: 'This event was cancelled', expand: true, onPressed: null);
    } else if (event.isPast) {
      child = const AppButton(label: 'This event has ended', expand: true, variant: ButtonVariant.secondary, onPressed: null);
    } else if (event.isGoing) {
      child = Row(
        children: [
          Expanded(
            child: event.hasLink
                ? AppButton(label: 'Join online', icon: AppIcons.videoCall, expand: true, onPressed: onJoin)
                : AppButton(label: 'You\'re going', icon: AppIcons.checkCircle, variant: ButtonVariant.secondary, expand: true, onPressed: null),
          ),
          const SizedBox(width: 8),
          AppButton(label: 'Cancel', variant: ButtonVariant.ghost, loading: busy, onPressed: onCancel),
        ],
      );
    } else if (event.isWaitlisted) {
      child = Row(
        children: [
          const Expanded(child: AppButton(label: 'On the waitlist', variant: ButtonVariant.secondary, expand: true, onPressed: null)),
          const SizedBox(width: 8),
          AppButton(label: 'Leave', variant: ButtonVariant.ghost, loading: busy, onPressed: onCancel),
        ],
      );
    } else if (event.registrationClosed) {
      child = const AppButton(label: 'Registrations closed', expand: true, onPressed: null);
    } else {
      child = AppButton(
        label: event.isFull ? 'Join waitlist' : 'Register',
        icon: AppIcons.ticket,
        variant: event.isFull ? ButtonVariant.secondary : ButtonVariant.accent,
        expand: true,
        loading: busy,
        onPressed: onRegister,
      );
    }
    return Container(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
      padding: EdgeInsets.fromLTRB(Space.gutter, 12, Space.gutter, 12 + context.safePadding.bottom),
      child: child,
    );
  }
}
