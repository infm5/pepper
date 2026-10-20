import 'dart:io';
import 'dart:math';

const _hotQueries = [
  'gold',
  'jade',
  'bronze',
  'roman',
  'sword',
  'mask',
  'vase',
  'serpent',
  'sun',
  'temple',
  'crown',
  'silver',
  'obsidian',
  'ritual',
  'royal',
  'egyptian',
  'norse',
  'mayan',
  'persian',
  'chinese',
];

const _adjectives = [
  'gilded',
  'obsidian',
  'jade',
  'bronze',
  'silver',
  'sun',
  'moon',
  'royal',
  'hidden',
  'ancient',
  'sacred',
  'celestial',
  'iron',
  'crimson',
  'ivory',
];

const _nouns = [
  'amulet',
  'blade',
  'chalice',
  'crown',
  'disk',
  'idol',
  'mask',
  'reliquary',
  'ring',
  'scepter',
  'serpent',
  'shield',
  'statue',
  'tablet',
  'vase',
];

const _cultures = [
  'egyptian',
  'roman',
  'greek',
  'norse',
  'mayan',
  'persian',
  'chinese',
  'celtic',
  'mesopotamian',
  'indus',
];

const _eras = [
  'neolithic',
  'bronze age',
  'iron age',
  'classical',
  'medieval',
  'renaissance',
];

/// Generates a deterministic mixed-workload URL trace.
Future<void> generateTrace({
  required String path,
  required String baseUrl,
  int count = 100000,
  int ids = 50000,
  int seed = 42,
}) async {
  final random = Random(seed);
  final zipf = _ZipfSampler(keys: ids, exponent: 1.0, random: random);
  final base = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  final buffer = StringBuffer();

  for (var i = 0; i < count; i++) {
    final roll = random.nextInt(100);
    if (roll < 60) {
      buffer.writeln('$base/api/relics/${zipf.sample() + 1}');
    } else if (roll < 85) {
      final batch = <int>{};
      while (batch.length < 3) {
        batch.add(zipf.sample() + 1);
      }
      buffer.writeln('$base/api/relics?ids=${batch.join(',')}');
    } else if (roll < 95) {
      final hot = random.nextDouble() < 0.8;
      final query = hot
          ? _hotQueries[random.nextInt(_hotQueries.length)]
          : '${_adjectives[random.nextInt(_adjectives.length)]} '
                '${_nouns[random.nextInt(_nouns.length)]}';
      final parameters = <String, String>{'q': query, 'limit': '20'};
      final filterRoll = random.nextInt(100);
      if (filterRoll < 30) {
        parameters['culture'] = _cultures[random.nextInt(_cultures.length)];
      } else if (filterRoll < 50) {
        parameters['era'] = _eras[random.nextInt(_eras.length)];
      } else if (filterRoll < 60) {
        parameters['culture'] = _cultures[random.nextInt(_cultures.length)];
        parameters['era'] = _eras[random.nextInt(_eras.length)];
      }
      final uri = Uri.parse(
        '$base/api/relics',
      ).replace(queryParameters: parameters);
      buffer.writeln(uri);
    } else {
      buffer.writeln('$base/api/relics/900000000');
    }
  }

  final file = File(path);
  file.parent.createSync(recursive: true);
  await file.writeAsString(buffer.toString());
}

final class _ZipfSampler {
  _ZipfSampler({
    required this.keys,
    required this.exponent,
    required this.random,
  }) : _cumulative = _buildCumulative(keys, exponent);

  final int keys;
  final double exponent;
  final Random random;
  final List<double> _cumulative;

  static List<double> _buildCumulative(int keys, double exponent) {
    final cumulative = List<double>.filled(keys, 0);
    var total = 0.0;
    for (var i = 0; i < keys; i++) {
      total += 1 / pow(i + 1, exponent);
      cumulative[i] = total;
    }
    return cumulative;
  }

  int sample() {
    final target = random.nextDouble() * _cumulative.last;
    var low = 0;
    var high = _cumulative.length - 1;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_cumulative[middle] < target) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}
