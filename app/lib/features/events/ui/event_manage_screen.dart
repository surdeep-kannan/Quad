import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../posts/ui/post_card.dart';
import '../data/event.dart';
import '../data/event_repository.dart';
import '../providers.dart';

/// Organizer view: attendee list, check-ins, waitlist and updates.
class EventManageScreen extends ConsumerWidget {
  const EventManageScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(eventProvider(eventId)).value;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
          title: Text(event?.title ?? 'Attendees', maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(tooltip: 'Edit event', icon: const Icon(AppIcons.edit), onPressed: () => context.push('/event/$eventId/edit')),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Going${event == null ? '' : ' · ${event.registrationsCount}'}'),
              Tab(text: 'Waitlist${event == null ? '' : ' · ${event.waitlistCount}'}'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (event != null) _UpdateComposer(event: event),
            Expanded(
              child: TabBarView(
                children: [
                  _Attendees(eventId: eventId, group: 'going'),
                  _Attendees(eventId: eventId, group: 'waitlist'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Attendees extends ConsumerWidget {
  const _Attendees({required this.eventId, required this.group});

  final String eventId;
  final String group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (eventId: eventId, group: group);
    final list = ref.watch(eventRegistrationsProvider(key));
    final c = context.colors;

    Future<void> setStatus(Registration registration, String status, String done) async {
      try {
        await ref.read(eventRepositoryProvider).setRegistrationStatus(eventId, registration.user.id, status);
        ref.invalidate(eventRegistrationsProvider(key));
        ref.invalidate(eventRegistrationsProvider((eventId: eventId, group: group == 'going' ? 'waitlist' : 'going')));
        await ref.read(eventProvider(eventId).notifier).reload();
        if (context.mounted) showToast(context, done);
      } catch (error) {
        if (context.mounted) showToast(context, friendlyError(error), error: true);
      }
    }

    return list.when(
      loading: () => const ListSkeleton(),
      error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(eventRegistrationsProvider(key))),
      data: (registrations) {
        if (registrations.isEmpty) {
          return EmptyState(
            icon: AppIcons.ticket,
            title: group == 'waitlist' ? 'Nobody waiting' : 'No registrations yet',
            message: group == 'waitlist' ? null : 'Share the event in your communities to get the word out.',
            compact: true,
          );
        }
        return ListView.builder(
          itemCount: registrations.length,
          itemBuilder: (_, i) {
            final r = registrations[i];
            return PersonRow(
              user: r.user,
              subtitle: '${r.department ?? '@${r.user.username}'} · ${timeAgo(r.createdAt)}',
              onTap: () => showActionSheet(
                context,
                title: r.user.fullName,
                actions: [
                  SheetAction(icon: AppIcons.user, label: 'View profile', onTap: () => context.push('/u/${r.user.username}')),
                  if (group == 'going' && r.status != 'attended')
                    SheetAction(icon: AppIcons.checkCircle, label: 'Check in', onTap: () => setStatus(r, 'attended', 'Checked in')),
                  if (group == 'waitlist')
                    SheetAction(icon: AppIcons.ticket, label: 'Give them a spot', onTap: () => setStatus(r, 'going', 'Moved to going')),
                  SheetAction(
                    icon: AppIcons.close,
                    label: 'Remove registration',
                    destructive: true,
                    onTap: () => setStatus(r, 'cancelled', 'Removed'),
                  ),
                ],
              ),
              trailing: r.status == 'attended'
                  ? Tag(label: 'Checked in', icon: AppIcons.check, color: c.success, background: c.successSoft)
                  : null,
            );
          },
        );
      },
    );
  }
}

class _UpdateComposer extends ConsumerStatefulWidget {
  const _UpdateComposer({required this.event});

  final CampusEvent event;

  @override
  ConsumerState<_UpdateComposer> createState() => _UpdateComposerState();
}

class _UpdateComposerState extends ConsumerState<_UpdateComposer> {
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (_text.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(eventRepositoryProvider).postUpdate(widget.event.id, _text.text.trim());
      _text.clear();
      ref.invalidate(eventUpdatesProvider(widget.event.id));
      if (mounted) showToast(context, 'Update sent to everyone registered');
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.all(Space.gutter),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Send an update', style: context.text.titleSmall),
          const SizedBox(height: 2),
          Text('Everyone registered gets a notification.', style: context.text.bodySmall),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _text,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(hintText: 'e.g. Venue changed to Hall B', fillColor: c.surface),
          ),
          const SizedBox(height: Space.sm),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(label: 'Send update', size: ButtonSize.small, loading: _busy, onPressed: _post),
          ),
        ],
      ),
    );
  }
}
