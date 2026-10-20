/// A catalog entry stored by the Relic Vault demo.
final class Relic {
  /// Creates a relic.
  const Relic({
    required this.id,
    required this.name,
    required this.culture,
    required this.era,
    required this.material,
    required this.rarity,
    required this.description,
    required this.discoveredYear,
    required this.discoverySite,
  });

  /// The database identifier.
  final int id;

  /// The display name.
  final String name;

  /// The originating culture.
  final String culture;

  /// The historical era.
  final String era;

  /// The primary material.
  final String material;

  /// A rarity score from 1 (common) to 5 (exceptional).
  final int rarity;

  /// A prose description.
  final String description;

  /// The year the relic was recovered.
  final int discoveredYear;

  /// The location where the relic was recovered.
  final String discoverySite;

  /// The full API representation.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'culture': culture,
    'era': era,
    'material': material,
    'rarity': rarity,
    'description': description,
    'discoveredYear': discoveredYear,
    'discoverySite': discoverySite,
  };

  /// The compact representation used by search and batch endpoints.
  Map<String, Object?> toSummaryJson() => {
    'id': id,
    'name': name,
    'culture': culture,
    'era': era,
    'material': material,
    'rarity': rarity,
    'discoveredYear': discoveredYear,
    'discoverySite': discoverySite,
  };

  /// Creates a copy with the supplied fields replaced.
  Relic copyWith({
    String? name,
    String? culture,
    String? era,
    String? material,
    int? rarity,
    String? description,
    int? discoveredYear,
    String? discoverySite,
  }) {
    return Relic(
      id: id,
      name: name ?? this.name,
      culture: culture ?? this.culture,
      era: era ?? this.era,
      material: material ?? this.material,
      rarity: rarity ?? this.rarity,
      description: description ?? this.description,
      discoveredYear: discoveredYear ?? this.discoveredYear,
      discoverySite: discoverySite ?? this.discoverySite,
    );
  }
}
