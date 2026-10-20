import 'package:relic_vault/relic_vault.dart';
import 'package:test/test.dart';

void main() {
  late SqliteRelicRepository repository;

  setUp(() {
    repository = SqliteRelicRepository.inMemory();
  });

  tearDown(() {
    repository.close();
  });

  test('seeds, reads, filters and updates relics', () async {
    await repository.seed(2000);
    expect(await repository.rowCount(), 2000);

    final sample = await repository.findById(1);
    expect(sample, isNotNull);
    expect(sample!.id, 1);

    final batch = await repository.findByIds({1, 2, 999999});
    expect(batch.map((relic) => relic.id), containsAll([1, 2]));

    final culture = sample.culture;
    final filtered = await repository.search(
      SearchQuery(culture: culture, limit: 100),
    );
    expect(filtered, isNotEmpty);
    expect(
      filtered.every(
        (relic) => relic.culture.toLowerCase() == culture.toLowerCase(),
      ),
      isTrue,
    );

    final token = sample.name.split(' ').first.toLowerCase();
    final text = await repository.search(SearchQuery(text: token, limit: 50));
    expect(text, isNotEmpty);

    final updated = await repository.update(
      1,
      const RelicUpdate(name: 'Updated Relic', rarity: 5),
    );
    expect(updated, isNotNull);
    expect(updated!.name, 'Updated Relic');
    expect(updated.rarity, 5);

    final reread = await repository.findById(1);
    expect(reread!.name, 'Updated Relic');
  });
}
