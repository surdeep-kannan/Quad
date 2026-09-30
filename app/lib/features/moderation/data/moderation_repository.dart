import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/json.dart';
import '../../../core/data/refs.dart';
import '../../../core/data/supabase_providers.dart';

enum ReportReason {
  spam('spam', 'Spam or scam', 'Ads, fake giveaways, repetitive posting'),
  harassment('harassment', 'Harassment or bullying', 'Targeting, threatening or shaming someone'),
  hate('hate', 'Hate speech', 'Attacks on identity, caste, religion or gender'),
  nudity('nudity', 'Nudity or sexual content', ''),
  violence('violence', 'Violence or threats', ''),
  misinformation('misinformation', 'False information', 'Fake notices, results or exam leaks'),
  selfHarm('self_harm', 'Self-harm or suicide', 'Someone may be at risk'),
  impersonation('impersonation', 'Impersonation', 'Pretending to be someone else'),
  other('other', 'Something else', '');

  const ReportReason(this.key, this.label, this.hint);

  final String key;
  final String label;
  final String hint;
}

class Report {
  const Report({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.status,
    required this.createdAt,
    required this.reporter,
    required this.snapshot,
    required this.reportsOnTarget,
    this.details,
    this.communityId,
    this.targetUser,
  });

  factory Report.fromJson(Json json) => Report(
        id: json['id'] as String,
        targetType: json['target_type'] as String,
        targetId: json['target_id'] as String,
        reason: json['reason'] as String? ?? 'other',
        status: json['status'] as String? ?? 'open',
        createdAt: dateOf(json['created_at']),
        reporter: UserRef.fromJson(jsonOrNull(json['reporter']) ?? {'id': ''}),
        snapshot: jsonOrNull(json['snapshot']) ?? const {},
        reportsOnTarget: intOf(json['reports_on_target'], 1),
        details: stringOrNull(json['details']),
        communityId: stringOrNull(json['community_id']),
        targetUser: jsonOrNull(json['target_user']) == null ? null : UserRef.fromJson(jsonOrNull(json['target_user'])!),
      );

  final String id;
  final String targetType;
  final String targetId;
  final String reason;
  final String status;
  final DateTime createdAt;
  final UserRef reporter;
  final Json snapshot;
  final int reportsOnTarget;
  final String? details;
  final String? communityId;
  final UserRef? targetUser;

  String get reasonLabel =>
      ReportReason.values.where((r) => r.key == reason).firstOrNull?.label ?? 'Something else';

  /// The reported text, as it was when reported.
  String get excerpt {
    final title = snapshot['title'] as String?;
    final body = snapshot['body'] as String?;
    final name = snapshot['full_name'] as String? ?? snapshot['name'] as String?;
    return [title, body, name].whereType<String>().where((s) => s.isNotEmpty).join(' — ');
  }
}

final moderationRepositoryProvider =
    Provider<ModerationRepository>((ref) => ModerationRepository(ref.watch(supabaseProvider)));

class ModerationRepository {
  ModerationRepository(this._client);

  final SupabaseClient _client;

  Future<void> report({
    required String targetType,
    required String targetId,
    required ReportReason reason,
    String? details,
  }) async {
    await _client.rpc<void>('submit_report', params: {
      'p_target_type': targetType,
      'p_target_id': targetId,
      'p_reason': reason.key,
      'p_details': details,
    });
  }

  Future<List<Report>> queue({String? communityId, String status = 'open'}) async {
    var query = _client.from('report_details').select().eq('status', status);
    query = communityId == null ? query.isFilter('community_id', null) : query.eq('community_id', communityId);
    final rows = await query.order('created_at', ascending: false).limit(100);
    // One entry per reported item; the newest report represents the rest.
    final seen = <String>{};
    return [
      for (final row in rows)
        if (seen.add('${row['target_type']}:${row['target_id']}')) Report.fromJson(row),
    ];
  }

  Future<void> resolve(String reportId, {required bool actioned, String? note}) async {
    await _client.rpc<void>('resolve_report', params: {
      'p_report': reportId,
      'p_status': actioned ? 'actioned' : 'dismissed',
      'p_note': note,
    });
  }

  /// [action]: remove, restore, pin, unpin, lock or unlock.
  Future<void> moderate({required String targetType, required String targetId, required String action, String? reason}) async {
    await _client.rpc<void>('moderate_content', params: {
      'p_target_type': targetType,
      'p_target_id': targetId,
      'p_action': action,
      'p_reason': reason,
    });
  }
}
