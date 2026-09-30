import 'package:material_ui/material_ui.dart';

import '../../../core/data/json.dart';
import '../../../core/data/refs.dart';
import '../../../core/widgets/app_icons.dart';

class CampusEvent {
  const CampusEvent({
    required this.id,
    required this.organizer,
    required this.title,
    required this.category,
    required this.startsAt,
    required this.mode,
    this.description,
    this.community,
    this.college,
    this.posterUrl,
    this.posterTheme,
    this.endsAt,
    this.venue,
    this.address,
    this.capacity,
    this.registrationDeadline,
    this.registrationsCount = 0,
    this.waitlistCount = 0,
    this.visibility = 'public',
    this.tags = const [],
    this.isCancelled = false,
    this.myStatus,
    this.attendeesPreview = const [],
    this.createdAt,
  });

  /// Reads a row from the `event_details` view.
  factory CampusEvent.fromJson(Json json) => CampusEvent(
        id: json['id'] as String,
        organizer: UserRef.fromJson(jsonOrNull(json['organizer']) ?? {'id': json['organizer_id']}),
        title: json['title'] as String? ?? '',
        category: json['category'] as String? ?? 'other',
        startsAt: dateOf(json['starts_at']),
        endsAt: dateOrNull(json['ends_at']),
        mode: json['mode'] as String? ?? 'in_person',
        description: stringOrNull(json['description']),
        community: jsonOrNull(json['community']) == null ? null : CommunityRef.fromJson(jsonOrNull(json['community'])!),
        college: jsonOrNull(json['college']) == null ? null : CollegeRef.fromJson(jsonOrNull(json['college'])!),
        posterUrl: stringOrNull(json['poster_url']),
        posterTheme: jsonOrNull(json['poster_theme']),
        venue: stringOrNull(json['venue']),
        address: stringOrNull(json['address']),
        capacity: json['capacity'] == null ? null : intOf(json['capacity']),
        registrationDeadline: dateOrNull(json['registration_deadline']),
        registrationsCount: intOf(json['registrations_count']),
        waitlistCount: intOf(json['waitlist_count']),
        visibility: json['visibility'] as String? ?? 'public',
        tags: stringsOf(json['tags']),
        isCancelled: boolOf(json['is_cancelled']),
        myStatus: stringOrNull(json['my_status']),
        attendeesPreview: jsonListOf(json['attendees_preview']).map(UserRef.fromJson).toList(),
        createdAt: dateOrNull(json['created_at']),
      );

  final String id;
  final UserRef organizer;
  final String title;
  final String category;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String mode;
  final String? description;
  final CommunityRef? community;
  final CollegeRef? college;
  final String? posterUrl;
  final Json? posterTheme;
  final String? venue;
  final String? address;
  final int? capacity;
  final DateTime? registrationDeadline;
  final int registrationsCount;
  final int waitlistCount;
  final String visibility;
  final List<String> tags;
  final bool isCancelled;
  final String? myStatus;
  final List<UserRef> attendeesPreview;
  final DateTime? createdAt;

  bool get isGoing => myStatus == 'going' || myStatus == 'attended';
  bool get isWaitlisted => myStatus == 'waitlist';
  bool get isFull => capacity != null && registrationsCount >= capacity!;
  int? get spotsLeft => capacity == null ? null : (capacity! - registrationsCount).clamp(0, capacity!);
  bool get isOnline => mode == 'online';
  bool get hasLink => mode != 'in_person';

  DateTime get effectiveEnd => endsAt ?? startsAt.add(const Duration(hours: 2));
  bool get isPast => DateTime.now().isAfter(effectiveEnd);
  bool get isLive => !isPast && DateTime.now().isAfter(startsAt);
  bool get registrationClosed =>
      isCancelled || isPast || (registrationDeadline != null && DateTime.now().isAfter(registrationDeadline!));

  String get where => switch (mode) {
        'online' => 'Online',
        'hybrid' => venue == null ? 'Hybrid' : '$venue · Online too',
        _ => venue ?? 'Venue to be announced',
      };

  CampusEvent withStatus(String? status, {int? registrationsCount, int? waitlistCount}) => CampusEvent(
        id: id,
        organizer: organizer,
        title: title,
        category: category,
        startsAt: startsAt,
        endsAt: endsAt,
        mode: mode,
        description: description,
        community: community,
        college: college,
        posterUrl: posterUrl,
        posterTheme: posterTheme,
        venue: venue,
        address: address,
        capacity: capacity,
        registrationDeadline: registrationDeadline,
        registrationsCount: registrationsCount ?? this.registrationsCount,
        waitlistCount: waitlistCount ?? this.waitlistCount,
        visibility: visibility,
        tags: tags,
        isCancelled: isCancelled,
        myStatus: status,
        attendeesPreview: attendeesPreview,
        createdAt: createdAt,
      );
}

class Registration {
  const Registration({required this.user, required this.status, required this.createdAt, this.department});

  factory Registration.fromJson(Json json) {
    final user = jsonOrNull(json['user']) ?? const {};
    return Registration(
      user: UserRef.fromJson(user),
      department: stringOrNull(user['department']),
      status: json['status'] as String? ?? 'going',
      createdAt: dateOf(json['created_at']),
    );
  }

  final UserRef user;
  final String? department;
  final String status;
  final DateTime createdAt;
}

class EventUpdate {
  const EventUpdate({required this.id, required this.author, required this.body, required this.createdAt});

  factory EventUpdate.fromJson(Json json) => EventUpdate(
        id: json['id'] as String,
        author: UserRef.fromJson(jsonOrNull(json['author']) ?? {'id': json['author_id']}),
        body: json['body'] as String? ?? '',
        createdAt: dateOf(json['created_at']),
      );

  final String id;
  final UserRef author;
  final String body;
  final DateTime createdAt;
}

abstract final class EventCategories {
  static const all = <String, String>{
    'hackathon': 'Hackathons',
    'workshop': 'Workshops',
    'conference': 'Conferences',
    'club': 'Club events',
    'cultural': 'Cultural',
    'sports': 'Sports',
    'competition': 'Competitions',
    'webinar': 'Webinars',
    'placement': 'Placements',
    'meetup': 'Meetups',
    'other': 'Other',
  };

  static String label(String key) => all[key] ?? 'Other';

  /// Singular label for badges ("Hackathon").
  static String single(String key) => switch (key) {
        'hackathon' => 'Hackathon',
        'workshop' => 'Workshop',
        'conference' => 'Conference',
        'club' => 'Club event',
        'cultural' => 'Cultural',
        'sports' => 'Sports',
        'competition' => 'Competition',
        'webinar' => 'Webinar',
        'placement' => 'Placement',
        'meetup' => 'Meetup',
        _ => 'Event',
      };

  static IconData icon(String key) => switch (key) {
        'hackathon' => AppIcons.lightning,
        'workshop' => AppIcons.code,
        'conference' => AppIcons.megaphone,
        'club' => AppIcons.users,
        'cultural' => AppIcons.sparkle,
        'sports' => AppIcons.trophy,
        'competition' => AppIcons.flagBanner,
        'webinar' => AppIcons.monitor,
        'placement' => AppIcons.briefcase,
        'meetup' => AppIcons.chatText,
        _ => AppIcons.ticket,
      };
}
