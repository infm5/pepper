import 'dart:convert';
import 'dart:io';

import 'package:relic/relic.dart';
import 'package:relic_vault/relic_vault.dart';
import 'package:test/test.dart';

import 'fake_relic_repository.dart';

const _settings = CacheSettings(
  capacity: 100,
  searchCapacity: 100,
  missingCapacity: 100,
  detailTtl: Duration(minutes: 1),
  searchTtl: Duration(minutes: 1),
  jitter: Duration.zero,
  janitor: false,
);

Relic _relic(int id) {
  return Relic(
    id: id,
    name: 'Gilded Mask $id',
    culture: 'Roman',
    era: 'Classical',
    material: 'gold',
    rarity: 3,
    description: 'A gold relic from the Roman Classical era.',
    discoveredYear: 1900 + id,
    discoverySite: 'Pompeii',
  );
}

void main() {
  late HttpClient client;
  late RelicService service;
  late ServerHandle server;

  setUp(() async {
    final repository = FakeRelicRepository(
      relics: {1: _relic(1), 2: _relic(2)},
    );
    service = RelicService(repository: repository, settings: _settings);
    final metrics = AppMetrics();
    final app = buildRelicVaultApp(
      service: service,
      metrics: metrics,
      settings: _settings,
    );
    final relicServer = await app.serve(
      address: InternetAddress.loopbackIPv4,
      port: 0,
    );
    server = ServerHandle(
      relicServer,
      Uri.parse('http://127.0.0.1:${relicServer.port}'),
    );
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    service.dispose();
    await server.close();
  });

  Future<(int, String)> request(
    String method,
    String path, {
    Object? body,
  }) async {
    final req = await client.openUrl(method, server.baseUri.resolve(path));
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final response = await req.close();
    final text = await response.transform(utf8.decoder).join();
    return (response.statusCode, text);
  }

  test('serves detail, batch, search, stats and updates', () async {
    final (detailStatus, detailBody) = await request('GET', '/api/relics/1');
    expect(detailStatus, 200);
    expect(jsonDecode(detailBody)['name'], 'Gilded Mask 1');

    final (missingStatus, _) = await request('GET', '/api/relics/99');
    expect(missingStatus, 404);

    final (batchStatus, batchBody) = await request(
      'GET',
      '/api/relics?ids=1,2,99',
    );
    expect(batchStatus, 200);
    final batch = jsonDecode(batchBody) as Map<String, dynamic>;
    expect(batch['items'], hasLength(2));
    expect(batch['missing'], [99]);

    final (searchStatus, searchBody) = await request(
      'GET',
      '/api/relics?q=gold&limit=5',
    );
    expect(searchStatus, 200);
    expect(jsonDecode(searchBody), hasLength(2));

    final (updateStatus, updateBody) = await request(
      'PUT',
      '/api/relics/1',
      body: {'name': 'Updated Mask', 'rarity': 5},
    );
    expect(updateStatus, 200);
    expect(jsonDecode(updateBody)['name'], 'Updated Mask');

    final (updatedStatus, updatedBody) = await request('GET', '/api/relics/1');
    expect(updatedStatus, 200);
    expect(jsonDecode(updatedBody)['rarity'], 5);

    final (statsStatus, statsBody) = await request('GET', '/api/cache/stats');
    expect(statsStatus, 200);
    final stats = jsonDecode(statsBody) as Map<String, dynamic>;
    expect(stats['cache']['enabled'], isTrue);
    expect(stats['requests'], greaterThan(0));
  });

  test('clears caches through the demo endpoint', () async {
    await request('GET', '/api/relics/1');
    final before =
        jsonDecode((await request('GET', '/api/cache/stats')).$2)
            as Map<String, dynamic>;
    expect(before['cache']['detail']['length'], 1);

    final (purgeStatus, purgeBody) = await request('POST', '/api/cache/purge');
    expect(purgeStatus, 200);
    expect(jsonDecode(purgeBody), {'ok': true});

    final after =
        jsonDecode((await request('GET', '/api/cache/stats')).$2)
            as Map<String, dynamic>;
    expect(after['cache']['detail']['length'], 0);
  });

  test('rejects malformed updates', () async {
    final (status, body) = await request(
      'PUT',
      '/api/relics/1',
      body: {'rarity': 99},
    );
    expect(status, 400);
    expect(jsonDecode(body)['error'], contains('rarity'));
  });
}

final class ServerHandle {
  ServerHandle(this.server, this.baseUri);

  final RelicServer server;
  final Uri baseUri;

  Future<void> close() => server.close(force: true);
}
