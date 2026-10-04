import '../../../core/data/json.dart';
import '../../../core/data/refs.dart';

class Profile {
  const Profile({
    required this.id,
    required this.username,
    required this.fullName,
    this.avatarUrl,
    this.bio,
    this.collegeId,
    this.college,
    this.department,
    this.yearOfStudy,
    this.skills = const [],
    this.interests = const [],
    this.isVerified = false,
    this.followersCount = 0,
    this.followingCount = 0,
    this.postsCount = 0,
    this.onboarded = false,
    this.lastSeenAt,
    this.createdAt,
    this.isFollowing = false,
    this.followsMe = false,
    this.isBlocked = false,
    this.isPrivate = false,
    this.canSee = true,
  });

  /// Reads a row from the `profile_summaries` view.
  factory Profile.fromJson(Json json) => Profile(
        id: json['id'] as String,
        username: json['username'] as String? ?? '',
        fullName: json['full_name'] as String? ?? 'Student',
        avatarUrl: stringOrNull(json['avatar_url']),
        bio: stringOrNull(json['bio']),
        collegeId: stringOrNull(json['college_id']),
        college: jsonOrNull(json['college']) == null ? null : CollegeRef.fromJson(jsonOrNull(json['college'])!),
        department: stringOrNull(json['department']),
        yearOfStudy: json['year_of_study'] == null ? null : intOf(json['year_of_study']),
        skills: stringsOf(json['skills']),
        interests: stringsOf(json['interests']),
        isVerified: boolOf(json['is_verified']),
        followersCount: intOf(json['followers_count']),
        followingCount: intOf(json['following_count']),
        postsCount: intOf(json['posts_count']),
        onboarded: boolOf(json['onboarded']),
        lastSeenAt: dateOrNull(json['last_seen_at']),
        createdAt: dateOrNull(json['created_at']),
        isFollowing: boolOf(json['is_following']),
        followsMe: boolOf(json['follows_me']),
        isBlocked: boolOf(json['is_blocked']),
        isPrivate: boolOf(json['is_private']),
        canSee: json['can_see'] != false,
      );

  final String id;
  final String username;
  final String fullName;
  final String? avatarUrl;
  final String? bio;
  final String? collegeId;
  final CollegeRef? college;
  final String? department;
  final int? yearOfStudy;
  final List<String> skills;
  final List<String> interests;
  final bool isVerified;
  final int followersCount;
  final int followingCount;
  final int postsCount;
  final bool onboarded;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;
  final bool isFollowing;
  final bool followsMe;
  final bool isBlocked;

  /// Private profiles post anonymously in communities and show their details
  /// only to people they follow.
  final bool isPrivate;

  /// False when this is someone else's private profile you can't see.
  final bool canSee;

  UserRef get ref => UserRef(
        id: id,
        username: username,
        fullName: fullName,
        avatarUrl: avatarUrl,
        isVerified: isVerified,
        lastSeenAt: lastSeenAt,
      );

  /// "IIT Madras · Computer Science · 3rd year" with the parts that exist.
  String get academicLine {
    final parts = <String>[
      ?college?.label,
      ?department,
      if (yearOfStudy != null) _year(yearOfStudy!),
    ];
    return parts.join(' · ');
  }

  static String _year(int year) {
    const suffixes = {1: 'st', 2: 'nd', 3: 'rd'};
    return '$year${suffixes[year] ?? 'th'} year';
  }

  Profile copyWith({
    bool? isFollowing,
    int? followersCount,
    bool? isBlocked,
    String? avatarUrl,
    String? fullName,
    String? bio,
  }) {
    return Profile(
      id: id,
      username: username,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      collegeId: collegeId,
      college: college,
      department: department,
      yearOfStudy: yearOfStudy,
      skills: skills,
      interests: interests,
      isVerified: isVerified,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount,
      postsCount: postsCount,
      onboarded: onboarded,
      lastSeenAt: lastSeenAt,
      createdAt: createdAt,
      isFollowing: isFollowing ?? this.isFollowing,
      followsMe: followsMe,
      isBlocked: isBlocked ?? this.isBlocked,
      isPrivate: isPrivate,
      canSee: canSee,
    );
  }
}

class Achievement {
  const Achievement({
    required this.id,
    required this.userId,
    required this.title,
    required this.category,
    this.description,
    this.issuer,
    this.achievedOn,
    this.url,
  });

  factory Achievement.fromJson(Json json) => Achievement(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        title: json['title'] as String? ?? '',
        category: json['category'] as String? ?? 'other',
        description: stringOrNull(json['description']),
        issuer: stringOrNull(json['issuer']),
        achievedOn: dateOrNull(json['achieved_on']),
        url: stringOrNull(json['url']),
      );

  final String id;
  final String userId;
  final String title;
  final String category;
  final String? description;
  final String? issuer;
  final DateTime? achievedOn;
  final String? url;

  static const categories = <String, String>{
    'hackathon': 'Hackathon',
    'competition': 'Competition',
    'academic': 'Academic',
    'sports': 'Sports',
    'cultural': 'Cultural',
    'certification': 'Certification',
    'internship': 'Internship',
    'research': 'Research',
    'leadership': 'Leadership',
    'other': 'Other',
  };
}

/// Interests students pick in onboarding. Posts, communities and events use
/// the same keys as tags, which is what powers feed recommendations.
abstract final class Interests {
  static const all = <String, String>{
    'ai-ml': 'AI & ML',
    'web-dev': 'Web dev',
    'app-dev': 'App dev',
    'competitive-programming': 'Competitive programming',
    'open-source': 'Open source',
    'cybersecurity': 'Cybersecurity',
    'data-science': 'Data science',
    'cloud': 'Cloud & DevOps',
    'robotics': 'Robotics',
    'design': 'Design',
    'startups': 'Startups',
    'placements': 'Placements',
    'research': 'Research',
    'finance': 'Finance',
    'photography': 'Photography',
    'music': 'Music',
    'dance': 'Dance',
    'film': 'Film',
    'writing': 'Writing',
    'debate': 'Debate & MUN',
    'gaming': 'Gaming',
    'sports': 'Sports',
    'fitness': 'Fitness',
    'travel': 'Travel',
    'volunteering': 'Volunteering',
  };

  static String label(String key) => all[key] ?? key.replaceAll('-', ' ');
}
