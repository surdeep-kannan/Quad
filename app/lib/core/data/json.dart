/// Small, forgiving readers for JSON rows coming back from PostgREST.
typedef Json = Map<String, dynamic>;

DateTime? dateOrNull(Object? value) => value is String ? DateTime.tryParse(value) : null;

DateTime dateOf(Object? value) => dateOrNull(value) ?? DateTime.fromMillisecondsSinceEpoch(0);

int intOf(Object? value, [int fallback = 0]) => switch (value) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v) ?? fallback,
      _ => fallback,
    };

double doubleOf(Object? value, [double fallback = 0]) => switch (value) {
      final num v => v.toDouble(),
      final String v => double.tryParse(v) ?? fallback,
      _ => fallback,
    };

bool boolOf(Object? value) => value == true;

String? stringOrNull(Object? value) => value is String && value.isNotEmpty ? value : null;

List<String> stringsOf(Object? value) => value is List ? value.whereType<String>().toList() : const [];

Json? jsonOrNull(Object? value) => value is Map ? Map<String, dynamic>.from(value) : null;

List<Json> jsonListOf(Object? value) =>
    value is List ? value.whereType<Map<dynamic, dynamic>>().map(Map<String, dynamic>.from).toList() : const [];
