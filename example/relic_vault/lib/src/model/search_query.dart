import 'dart:convert';

/// A normalized relic search request.
final class SearchQuery {
  /// Creates a search query.
  SearchQuery({String text = '', String? culture, String? era, int limit = 20})
    : text = _normalize(text),
      culture = _normalizeNullable(culture),
      era = _normalizeNullable(era),
      limit = limit.clamp(1, 100);

  /// The free-text query, lower-cased and trimmed.
  final String text;

  /// An optional culture filter, lower-cased and trimmed.
  final String? culture;

  /// An optional era filter, lower-cased and trimmed.
  final String? era;

  /// The maximum number of results, constrained to 1..100.
  final int limit;

  /// A stable key for the search cache.
  String get cacheKey => jsonEncode([text, culture, era, limit]);

  /// Rebuilds a query from [cacheKey].
  factory SearchQuery.fromCacheKey(String cacheKey) {
    final values = jsonDecode(cacheKey) as List<Object?>;
    return SearchQuery(
      text: values[0] as String,
      culture: values[1] as String?,
      era: values[2] as String?,
      limit: values[3] as int,
    );
  }

  static String _normalize(String value) => value.trim().toLowerCase();

  static String? _normalizeNullable(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ? null : normalized;
  }
}
