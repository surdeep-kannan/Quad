import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/json.dart';
import '../../../core/data/supabase_providers.dart';
import 'event.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) => EventRepository(ref.watch(supabaseProvider)));

enum EventWindow {
  upcoming('Upcoming'),
  today('Today'),
  week('This week'),
  weekend('This weekend'),
  online('Online');

  const EventWindow(this.label);

  final String label;
}

class EventRepository {
  EventRepository(this._client);

  final SupabaseClient _client;

  static const _personFields = 'id, username, full_name, avatar_url, is_verified, department';

  String _iso(DateTime time) => time.toUtc().toIso8601String();

  Future<List<CampusEvent>> discover({
    EventWindow window = EventWindow.upcoming,
    String? category,
    String? collegeId,
    int offset = 0,
    int limit = 20,
  }) async {
    final now = DateTime.now();
    var query = _client.from('event_details').select().eq('is_cancelled', false);

    switch (window) {
      case EventWindow.upcoming:
      case EventWindow.online:
        query = query.gte('starts_at', _iso(now.subtract(const Duration(hours: 3))));
      case EventWindow.today:
        final end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
        query = query.gte('starts_at', _iso(now.subtract(const Duration(hours: 3)))).lt('starts_at', _iso(end));
      case EventWindow.week:
        query = query
            .gte('starts_at', _iso(now.subtract(const Duration(hours: 3))))
            .lt('starts_at', _iso(now.add(const Duration(days: 7))));
      case EventWindow.weekend:
        final today = DateTime(now.year, now.month, now.day);
        final DateTime start;
        final DateTime end;
        if (now.weekday == DateTime.sunday) {
          start = today;
          end = today.add(const Duration(days: 1));
        } else {
          start = today.add(Duration(days: DateTime.saturday - now.weekday));
          end = start.add(const Duration(days: 2));
        }
        final from = start.isBefore(now) ? now.subtract(const Duration(hours: 3)) : start;
        query = query.gte('starts_at', _iso(from)).lt('starts_at', _iso(end));
    }
    if (window == EventWindow.online) query = query.neq('mode', 'in_person');
    if (category != null) query = query.eq('category', category);
    if (collegeId != null) query = query.eq('college_id', collegeId);

    final rows = await query.order('starts_at', ascending: true).range(offset, offset + limit - 1);
    return rows.map(CampusEvent.fromJson).toList();
  }

  /// Events the student registered for or is waitlisted on.
  Future<List<CampusEvent>> mine({bool past = false}) async {
    var query = _client.from('event_details').select().inFilter('my_status', ['going', 'waitlist', 'attended']);
    final now = _iso(DateTime.now().subtract(const Duration(hours: 3)));
    query = past ? query.lt('starts_at', now) : query.gte('starts_at', now);
    final rows = await query.order('starts_at', ascending: !past).limit(50);
    return rows.map(CampusEvent.fromJson).toList();
  }

  Future<List<CampusEvent>> hosting() async {
    final rows = await _client
        .from('event_details')
        .select()
        .eq('organizer_id', _client.uid)
        .order('starts_at', ascending: false)
        .limit(50);
    return rows.map(CampusEvent.fromJson).toList();
  }

  Future<List<CampusEvent>> forCommunity(String communityId, {bool upcomingOnly = true}) async {
    var query = _client.from('event_details').select().eq('community_id', communityId).eq('is_cancelled', false);
    if (upcomingOnly) query = query.gte('starts_at', _iso(DateTime.now().subtract(const Duration(hours: 3))));
    final rows = await query.order('starts_at', ascending: true).limit(30);
    return rows.map(CampusEvent.fromJson).toList();
  }

  Future<List<CampusEvent>> forCollege(String collegeId) async {
    final rows = await _client
        .from('event_details')
        .select()
        .eq('college_id', collegeId)
        .eq('is_cancelled', false)
        .gte('starts_at', _iso(DateTime.now().subtract(const Duration(hours: 3))))
        .order('starts_at', ascending: true)
        .limit(20);
    return rows.map(CampusEvent.fromJson).toList();
  }

  Future<List<CampusEvent>> attendedBy(String userId) async {
    final rows = await _client
        .from('event_registrations')
        .select('event_id')
        .eq('user_id', userId)
        .inFilter('status', ['going', 'attended'])
        .order('created_at', ascending: false)
        .limit(30);
    final ids = [for (final row in rows) row['event_id'] as String];
    if (ids.isEmpty) return const [];
    final events = await _client.from('event_details').select().inFilter('id', ids).order('starts_at', ascending: false);
    return events.map(CampusEvent.fromJson).toList();
  }

  Future<CampusEvent?> byId(String id) async {
    final row = await _client.from('event_details').select().eq('id', id).maybeSingle();
    return row == null ? null : CampusEvent.fromJson(row);
  }

  Future<String> create(Json fields) async {
    final row = await _client
        .from('events')
        .insert({...fields, 'organizer_id': _client.uid})
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> update(String id, Json fields) async {
    await _client.from('events').update(fields).eq('id', id);
  }

  Future<void> cancel(String id) => update(id, {'is_cancelled': true});

  Future<void> delete(String id) async {
    await _client.from('events').delete().eq('id', id);
  }

  /// Returns 'going' or 'waitlist'.
  Future<String> register(String id) => _client.rpc<String>('register_for_event', params: {'p_event': id});

  Future<void> cancelRegistration(String id) async {
    await _client.rpc<void>('cancel_event_registration', params: {'p_event': id});
  }

  Future<String?> meetingLink(String id) => _client.rpc<String?>('event_meeting_link', params: {'p_event': id});

  Future<List<Registration>> registrations(String eventId, {List<String> statuses = const ['going', 'attended']}) async {
    final rows = await _client
        .from('event_registrations')
        .select('status, created_at, user:profiles($_personFields)')
        .eq('event_id', eventId)
        .inFilter('status', statuses)
        .order('created_at', ascending: true)
        .limit(500);
    return rows.map(Registration.fromJson).toList();
  }

  Future<void> setRegistrationStatus(String eventId, String userId, String status) async {
    await _client.rpc<void>(
      'set_registration_status',
      params: {'p_event': eventId, 'p_user': userId, 'p_status': status},
    );
  }

  Future<List<EventUpdate>> updates(String eventId) async {
    final rows = await _client
        .from('event_updates')
        .select('id, body, created_at, author_id, author:profiles(id, username, full_name, avatar_url, is_verified)')
        .eq('event_id', eventId)
        .order('created_at', ascending: false)
        .limit(50);
    return rows.map(EventUpdate.fromJson).toList();
  }

  Future<void> postUpdate(String eventId, String body) async {
    await _client.from('event_updates').insert({'event_id': eventId, 'author_id': _client.uid, 'body': body});
  }

  Future<List<CampusEvent>> search(String query, {int limit = 20}) async {
    final rows = await _client.rpc<List<dynamic>>('search_events', params: {'p_query': query, 'p_limit': limit});
    return jsonListOf(rows).map(CampusEvent.fromJson).toList();
  }
}
