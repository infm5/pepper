import 'dart:math';

import '../model/relic.dart';

const _adjectives = [
  'Gilded',
  'Obsidian',
  'Jade',
  'Bronze',
  'Silver',
  'Sun',
  'Moon',
  'Royal',
  'Hidden',
  'Ancient',
  'Sacred',
  'Celestial',
  'Iron',
  'Crimson',
  'Ivory',
  'Whispering',
  'Radiant',
  'Forgotten',
];

const _nouns = [
  'Amulet',
  'Blade',
  'Chalice',
  'Crown',
  'Disk',
  'Idol',
  'Mask',
  'Reliquary',
  'Ring',
  'Scepter',
  'Serpent',
  'Shield',
  'Statue',
  'Tablet',
  'Vase',
  'Bracelet',
  'Helmet',
  'Mirror',
];

const _cultures = [
  'Egyptian',
  'Roman',
  'Greek',
  'Norse',
  'Mayan',
  'Persian',
  'Chinese',
  'Celtic',
  'Mesopotamian',
  'Indus',
];

const _eras = [
  'Neolithic',
  'Bronze Age',
  'Iron Age',
  'Classical',
  'Medieval',
  'Renaissance',
];

const _materials = [
  'bronze',
  'gold',
  'jade',
  'obsidian',
  'marble',
  'ivory',
  'clay',
  'iron',
  'silver',
  'glass',
];

const _sites = [
  'Valley of the Kings',
  'Pompeii',
  'Knossos',
  'Uppsala',
  'Tikal',
  'Persepolis',
  'Xi’an',
  'Newgrange',
  'Ur',
  'Mohenjo-daro',
  'Delphi',
  'Petra',
  'Angkor',
  'Avebury',
];

/// Deterministic relic generator used to seed the demo database.
final class RelicSeedGenerator {
  /// Creates a generator with a reproducible random seed.
  RelicSeedGenerator({int seed = 42}) : _random = Random(seed);

  final Random _random;

  /// Generates the relic with [id].
  Relic generate(int id) {
    final adjective = _pick(_adjectives);
    final noun = _pick(_nouns);
    final culture = _pick(_cultures);
    final era = _pick(_eras);
    final material = _pick(_materials);
    final site = _pick(_sites);
    final year = 1800 + _random.nextInt(221);
    final rarity = _rarity();
    final description =
        'A $material ${noun.toLowerCase()} linked to the $culture $era, '
        'recovered at $site in $year. Its surface carries a '
        '${_pick(_descriptorWords)} patina and a ${_pick(_descriptorWords)} '
        'inscription.';

    return Relic(
      id: id,
      name: '$adjective $noun',
      culture: culture,
      era: era,
      material: material,
      rarity: rarity,
      description: description,
      discoveredYear: year,
      discoverySite: site,
    );
  }

  String _pick(List<String> values) => values[_random.nextInt(values.length)];

  int _rarity() {
    final roll = _random.nextDouble();
    if (roll < 0.40) return 1;
    if (roll < 0.65) return 2;
    if (roll < 0.85) return 3;
    if (roll < 0.95) return 4;
    return 5;
  }
}

const _descriptorWords = [
  'faint',
  'deep',
  'mineral',
  'ritual',
  'weathered',
  'luminous',
  'fractured',
  'ornate',
  'sun-baked',
  'salt-stained',
];
