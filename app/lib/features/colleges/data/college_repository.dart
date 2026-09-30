import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/json.dart';
import '../../../core/data/supabase_providers.dart';
import 'college.dart';

final collegeRepositoryProvider = Provider<CollegeRepository>((ref) => CollegeRepository(ref.watch(supabaseProvider)));

class CollegeRepository {
  CollegeRepository(this._client);

  final SupabaseClient _client;

  /// Verified colleges first, alphabetical. Used by the onboarding picker.
  Future<List<College>> browse({int limit = 60}) async {
    final rows = await _client
        .from('colleges')
        .select()
        .order('is_verified', ascending: false)
        .order('name', ascending: true)
        .limit(limit);
    return rows.map(College.fromJson).toList();
  }

  Future<List<College>> search(String query, {int limit = 20}) async {
    final rows = await _client.rpc<List<dynamic>>('search_colleges', params: {'p_query': query, 'p_limit': limit});
    return jsonListOf(rows).map(College.fromJson).toList();
  }

  Future<College> add({required String name, String? city, String? state}) async {
    final slugBase = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    final suffix = DateTime.now().millisecondsSinceEpoch.toRadixString(36).substring(4);
    final slug = '${slugBase.length > 60 ? slugBase.substring(0, 60) : slugBase}-$suffix';
    final row = await _client
        .from('colleges')
        .insert({
          'name': name.trim(),
          'slug': slug,
          'city': ?city,
          'state': ?state,
          'created_by': _client.uid,
        })
        .select()
        .single();
    return College.fromJson(row);
  }

  Future<List<College>> leaderboard({String? state, int offset = 0, int limit = 30}) async {
    final rows = await _client.rpc<List<dynamic>>(
      'college_leaderboard',
      params: {'p_state': state, 'p_limit': limit, 'p_offset': offset},
    );
    return jsonListOf(rows).map(College.fromJson).toList();
  }

  Future<College?> byId(String id) async {
    final row = await _client.from('college_rankings').select().eq('id', id).maybeSingle();
    return row == null ? null : College.fromJson(row);
  }

  Future<List<RankingPillar>> pillars() async {
    final rows = await _client.from('ranking_pillars').select().order('position', ascending: true);
    return rows.map(RankingPillar.fromJson).toList();
  }

  Future<int> studentCount(String collegeId) async {
    final response = await _client.from('profiles').select('id').eq('college_id', collegeId).count(CountOption.exact);
    return response.count;
  }
}
