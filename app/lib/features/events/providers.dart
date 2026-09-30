import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/paged.dart';
import 'data/event.dart';
import 'data/event_repository.dart';

typedef EventFilter = ({EventWindow window, String? category});

final discoverEventsProvider =
    AsyncNotifierProvider.autoDispose.family<DiscoverEvents, Paged<CampusEvent>, EventFilter>(DiscoverEvents.new);

class DiscoverEvents extends PagedNotifier<CampusEvent> {
  DiscoverEvents(this.filter);

  final EventFilter filter;

  @override
  Future<List<CampusEvent>> fetch(int offset, int limit) => ref
      .read(eventRepositoryProvider)
      .discover(window: filter.window, category: filter.category, offset: offset, limit: limit);

  @override
  Object idOf(CampusEvent item) => item.id;
}

final myEventsProvider = FutureProvider.autoDispose<List<CampusEvent>>((ref) {
  return ref.watch(eventRepositoryProvider).mine();
});

final hostingEventsProvider = FutureProvider.autoDispose<List<CampusEvent>>((ref) {
  return ref.watch(eventRepositoryProvider).hosting();
});

final communityEventsProvider = FutureProvider.autoDispose.family<List<CampusEvent>, String>((ref, communityId) {
  return ref.watch(eventRepositoryProvider).forCommunity(communityId);
});

final userEventsProvider = FutureProvider.autoDispose.family<List<CampusEvent>, String>((ref, userId) {
  return ref.watch(eventRepositoryProvider).attendedBy(userId);
});

final collegeEventsProvider = FutureProvider.autoDispose.family<List<CampusEvent>, String>((ref, collegeId) {
  return ref.watch(eventRepositoryProvider).forCollege(collegeId);
});

/// An event page with registration handled in place.
final eventProvider = AsyncNotifierProvider.autoDispose.family<EventNotifier, CampusEvent?, String>(EventNotifier.new);

class EventNotifier extends AsyncNotifier<CampusEvent?> {
  EventNotifier(this.eventId);

  final String eventId;

  EventRepository get _repo => ref.read(eventRepositoryProvider);

  @override
  Future<CampusEvent?> build() => _repo.byId(eventId);

  Future<void> reload() async {
    final event = await _repo.byId(eventId);
    if (ref.mounted) state = AsyncData(event);
  }

  /// Returns 'going' or 'waitlist'.
  Future<String> register() async {
    final status = await _repo.register(eventId);
    await reload();
    ref.invalidate(myEventsProvider);
    return status;
  }

  Future<void> cancelRegistration() async {
    await _repo.cancelRegistration(eventId);
    await reload();
    ref.invalidate(myEventsProvider);
  }
}

final eventUpdatesProvider = FutureProvider.autoDispose.family<List<EventUpdate>, String>((ref, eventId) {
  return ref.watch(eventRepositoryProvider).updates(eventId);
});

final eventRegistrationsProvider =
    FutureProvider.autoDispose.family<List<Registration>, ({String eventId, String group})>((ref, key) {
  final statuses = switch (key.group) {
    'waitlist' => const ['waitlist'],
    'cancelled' => const ['cancelled'],
    _ => const ['going', 'attended'],
  };
  return ref.watch(eventRepositoryProvider).registrations(key.eventId, statuses: statuses);
});
