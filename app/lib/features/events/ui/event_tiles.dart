import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/pressable.dart';
import '../data/event.dart';
import 'event_poster.dart';

/// Big poster card for featured events.
class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, this.width = 250});

  final CampusEvent event;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: () => context.push('/event/${event.id}'),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                EventPoster.of(event, radius: Radii.lg),
                Positioned(left: 10, top: 10, child: _DateChip(date: event.startsAt)),
                if (event.isGoing)
                  Positioned(
                    right: 10,
                    top: 10,
                    child: Tag(label: 'Going', icon: AppIcons.check, color: Colors.white, background: c.success),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(event.title, style: context.text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(
              '${eventCountdown(event.startsAt, event.endsAt)} · ${event.where}',
              style: context.text.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            _Attendees(event: event),
          ],
        ),
      ),
    );
  }
}

/// Compact row for lists.
class EventRow extends StatelessWidget {
  const EventRow({super.key, required this.event});

  final CampusEvent event;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: () => context.push('/event/${event.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 76, child: EventPoster.of(event, radius: Radii.md)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eventWhen(event.startsAt).toUpperCase(),
                    style: context.text.labelSmall!.copyWith(color: event.isCancelled ? c.danger : c.accentInk),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.title,
                    style: context.text.titleSmall!.copyWith(
                      fontSize: 15.5,
                      decoration: event.isCancelled ? TextDecoration.lineThrough : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(event.isOnline ? AppIcons.monitor : AppIcons.mapPin, size: 13, color: c.inkSubtle),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(event.where, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _Attendees(event: event),
                      const Spacer(),
                      if (event.isCancelled)
                        Tag(label: 'Cancelled', color: c.danger, background: c.dangerSoft)
                      else if (event.isGoing)
                        Tag(label: 'Going', icon: AppIcons.check, color: c.success, background: c.successSoft)
                      else if (event.isWaitlisted)
                        Tag(label: 'Waitlist', color: c.warning, background: c.warningSoft)
                      else if (event.isFull)
                        const Tag(label: 'Full'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Attendees extends StatelessWidget {
  const _Attendees({required this.event});

  final CampusEvent event;

  @override
  Widget build(BuildContext context) {
    if (event.registrationsCount == 0) {
      return Text('Be the first to register', style: context.text.labelSmall!.copyWith(color: context.colors.inkSubtle));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AvatarStack(people: [for (final p in event.attendeesPreview) (p.fullName, p.avatarUrl)], size: 22, max: 3),
        const SizedBox(width: 6),
        Text(
          '${compactCount(event.registrationsCount)} going',
          style: context.text.labelSmall!.copyWith(color: context.colors.inkMuted),
        ),
      ],
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Text(monthShort(date), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFD23A17), letterSpacing: 0.6)),
          Text(
            dayOfMonth(date),
            style: const TextStyle(fontFamily: AppFonts.display, fontSize: 20, fontWeight: FontWeight.w800, height: 1.05, color: Color(0xFF16151B)),
          ),
        ],
      ),
    );
  }
}
