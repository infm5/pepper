/// A partial update applied to a relic.
///
/// Fields left as `null` are not changed. An update with every field `null` is
/// a no-op that returns the current relic.
final class RelicUpdate {
  /// Creates an update.
  const RelicUpdate({
    this.name,
    this.culture,
    this.era,
    this.material,
    this.rarity,
    this.description,
    this.discoveredYear,
    this.discoverySite,
  });

  /// The new display name.
  final String? name;

  /// The new culture.
  final String? culture;

  /// The new era.
  final String? era;

  /// The new material.
  final String? material;

  /// The new rarity score.
  final int? rarity;

  /// The new description.
  final String? description;

  /// The new discovery year.
  final int? discoveredYear;

  /// The new discovery site.
  final String? discoverySite;

  /// Whether this update changes no fields.
  bool get isEmpty =>
      name == null &&
      culture == null &&
      era == null &&
      material == null &&
      rarity == null &&
      description == null &&
      discoveredYear == null &&
      discoverySite == null;
}
