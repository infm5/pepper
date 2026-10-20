import '../model/relic.dart';
import '../model/relic_update.dart';
import '../model/search_query.dart';

/// The persistence boundary behind the Relic Vault service.
abstract interface class RelicRepository {
  /// Finds one relic.
  Future<Relic?> findById(int id);

  /// Finds every relic whose id is in [ids].
  Future<List<Relic>> findByIds(Set<int> ids);

  /// Searches the catalog.
  Future<List<Relic>> search(SearchQuery query);

  /// Applies [update] to a relic and returns the new value.
  Future<Relic?> update(int id, RelicUpdate update);

  /// Returns the number of stored relics.
  Future<int> rowCount();

  /// Releases database resources.
  void close();
}
