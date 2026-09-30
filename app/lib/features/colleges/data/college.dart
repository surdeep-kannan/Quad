import '../../../core/data/json.dart';
import '../../../core/data/refs.dart';

class College {
  const College({
    required this.id,
    required this.name,
    required this.slug,
    this.shortName,
    this.city,
    this.state,
    this.type,
    this.established,
    this.website,
    this.logoUrl,
    this.description,
    this.isVerified = false,
    this.stats,
  });

  /// Reads a row from `colleges` or the `college_rankings` view (which adds
  /// the stats columns).
  factory College.fromJson(Json json) => College(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        shortName: stringOrNull(json['short_name']),
        city: stringOrNull(json['city']),
        state: stringOrNull(json['state']),
        type: stringOrNull(json['type']),
        established: json['established'] == null ? null : intOf(json['established']),
        website: stringOrNull(json['website']),
        logoUrl: stringOrNull(json['logo_url']),
        description: stringOrNull(json['description']),
        isVerified: boolOf(json['is_verified']),
        stats: json.containsKey('score') ? CollegeStats.fromJson(json) : null,
      );

  final String id;
  final String name;
  final String slug;
  final String? shortName;
  final String? city;
  final String? state;
  final String? type;
  final int? established;
  final String? website;
  final String? logoUrl;
  final String? description;
  final bool isVerified;
  final CollegeStats? stats;

  String get label => shortName ?? name;

  String get location => [city, state].whereType<String>().join(', ');

  String? get typeLabel => switch (type) {
        'public' => 'Public',
        'private' => 'Private',
        'deemed' => 'Deemed university',
        'autonomous' => 'Autonomous',
        _ => null,
      };

  CollegeRef get ref => CollegeRef(id: id, name: name, shortName: shortName, city: city);
}

class CollegeStats {
  const CollegeStats({
    required this.students,
    required this.activeStudents,
    required this.communities,
    required this.clubs,
    required this.events,
    required this.hackathons,
    required this.achievements,
    required this.activity,
    required this.engagementRate,
    required this.pillarScores,
    required this.score,
    this.rank,
    this.computedAt,
  });

  factory CollegeStats.fromJson(Json json) {
    final pillars = jsonOrNull(json['pillar_scores']) ?? const {};
    return CollegeStats(
      students: intOf(json['students']),
      activeStudents: intOf(json['active_students']),
      communities: intOf(json['communities']),
      clubs: intOf(json['clubs']),
      events: intOf(json['events']),
      hackathons: intOf(json['hackathons']),
      achievements: intOf(json['achievements']),
      activity: intOf(json['activity']),
      engagementRate: doubleOf(json['engagement_rate']),
      pillarScores: {for (final e in pillars.entries) e.key: doubleOf(e.value)},
      score: doubleOf(json['score']),
      rank: json['rank'] == null ? null : intOf(json['rank']),
      computedAt: dateOrNull(json['computed_at']),
    );
  }

  final int students;
  final int activeStudents;
  final int communities;
  final int clubs;
  final int events;
  final int hackathons;
  final int achievements;
  final int activity;
  final double engagementRate;
  final Map<String, double> pillarScores;
  final double score;
  final int? rank;
  final DateTime? computedAt;

  /// Fewer than ten students means the score says little yet.
  bool get limitedData => students < 10;

  /// The raw value behind each pillar, for the breakdown.
  int? rawFor(String pillar) => switch (pillar) {
        'activity' => activity,
        'events' => events,
        'clubs' => clubs,
        'hackathons' => hackathons,
        'achievements' => achievements,
        _ => null,
      };
}

class RankingPillar {
  const RankingPillar({
    required this.key,
    required this.label,
    required this.weight,
    required this.description,
    this.windowDays,
  });

  factory RankingPillar.fromJson(Json json) => RankingPillar(
        key: json['key'] as String,
        label: json['label'] as String? ?? '',
        weight: doubleOf(json['weight']),
        description: json['description'] as String? ?? '',
        windowDays: json['window_days'] == null ? null : intOf(json['window_days']),
      );

  final String key;
  final String label;
  final double weight;
  final String description;
  final int? windowDays;
}
