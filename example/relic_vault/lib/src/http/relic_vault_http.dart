import 'dart:convert';
import 'dart:io';

import 'package:relic/relic.dart';

import '../config.dart';
import '../metrics/app_metrics.dart';
import '../model/relic_update.dart';
import '../model/search_query.dart';
import '../service/relic_service.dart';
import 'ui.dart';

/// Builds the Relic application for the demo.
RelicApp buildRelicVaultApp({
  required RelicService service,
  required AppMetrics metrics,
  required CacheSettings settings,
  bool logRequests = false,
}) {
  final app = RelicApp();
  app.use('/', _observe(metrics));
  if (logRequests) {
    app.use('/', _logRequests());
  }

  final api = RelicVaultApi(
    service: service,
    metrics: metrics,
    settings: settings,
  );
  api.register(app);
  app.fallback = api.fallback;
  return app;
}

/// Route handlers for the Relic Vault API and demo page.
final class RelicVaultApi {
  /// Creates the route handlers.
  RelicVaultApi({
    required this.service,
    required this.metrics,
    required this.settings,
  });

  /// The cache-aware application service.
  final RelicService service;

  /// Process-wide counters.
  final AppMetrics metrics;

  /// Cache configuration included in stats.
  final CacheSettings settings;

  /// Registers every route.
  void register(RelicApp app) {
    app.get('/health', health);
    app.get('/api/cache/stats', stats);
    app.post('/api/cache/purge', purgeCache);
    app.get('/api/relics/:id', getRelic);
    app.get('/api/relics', listOrSearch);
    app.put('/api/relics/:id', updateRelic);
    app.get('/', ui);
  }

  /// A minimal health check for the benchmark harness.
  Response health(Request request) {
    return Response.ok(body: Body.fromString('ok'), headers: _noStoreHeaders());
  }

  /// Returns cache, database and process counters.
  Response stats(Request request) {
    return _json(
      jsonEncode(
        metrics.toJson(
          settings: settings,
          detail: service.detailMetrics,
          search: service.searchMetrics,
        ),
      ),
    );
  }

  /// Clears both caches.
  Response purgeCache(Request request) {
    service.purgeCaches();
    return _json('{"ok":true}');
  }

  /// Returns the demo page.
  Response ui(Request request) {
    return Response.ok(
      body: Body.fromString(relicVaultUi, mimeType: MimeType.html),
      headers: _noStoreHeaders(),
    );
  }

  /// Matches unmatched routes.
  Response fallback(Request request) {
    if (request.url.path.startsWith('api/')) {
      return _error('not found', 404);
    }
    return Response.notFound(
      body: Body.fromString('Not found'),
      headers: _noStoreHeaders(),
    );
  }

  /// Returns one relic.
  Future<Response> getRelic(Request request) async {
    final id = _pathId(request);
    if (id == null) {
      return _error('invalid relic id', 400);
    }
    final body = await service.getRelic(id);
    if (body == null) {
      return _error('relic not found', 404);
    }
    return _json(body);
  }

  /// Handles batch reads and search.
  Future<Response> listOrSearch(Request request) async {
    final parameters = request.url.queryParameters;
    final rawIds = parameters['ids'];
    if (rawIds != null) {
      final ids = _parseIds(rawIds);
      if (ids == null) {
        return _error(
          'ids must be a comma-separated list of positive integers',
          400,
        );
      }
      final result = await service.getRelics(ids);
      return _json(result.toJsonString());
    }

    final rawLimit = parameters['limit'];
    final limit = rawLimit == null ? 20 : int.tryParse(rawLimit) ?? 20;
    final query = SearchQuery(
      text: parameters['q'] ?? '',
      culture: parameters['culture'],
      era: parameters['era'],
      limit: limit,
    );
    return _json(await service.search(query));
  }

  /// Applies a partial update and invalidates cache entries.
  Future<Response> updateRelic(Request request) async {
    final id = _pathId(request);
    if (id == null) {
      return _error('invalid relic id', 400);
    }

    final rawBody = await request.readAsString();
    if (rawBody.trim().isEmpty) {
      return _error('a JSON body is required', 400);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(rawBody);
    } on FormatException {
      return _error('invalid JSON body', 400);
    }
    if (decoded is! Map<String, dynamic>) {
      return _error('the JSON body must be an object', 400);
    }

    final RelicUpdate update;
    try {
      update = _parseUpdate(decoded);
    } on FormatException catch (error) {
      return _error(error.message, 400);
    }

    final body = await service.updateRelic(id, update);
    if (body == null) {
      return _error('relic not found', 404);
    }
    return _json(body);
  }

  int? _pathId(Request request) {
    final raw = request.rawPathParameters[#id];
    if (raw == null) {
      return null;
    }
    final id = int.tryParse(raw);
    return id != null && id > 0 ? id : null;
  }

  List<int>? _parseIds(String raw) {
    final parts = raw
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty || parts.length > 100) {
      return null;
    }
    final ids = <int>[];
    for (final part in parts) {
      final id = int.tryParse(part);
      if (id == null || id < 1) {
        return null;
      }
      ids.add(id);
    }
    return ids;
  }

  RelicUpdate _parseUpdate(Map<String, dynamic> data) {
    String? stringValue(String key) {
      final value = data[key];
      if (value == null) {
        return null;
      }
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('$key must be a non-empty string');
      }
      return value.trim();
    }

    int? intValue(String key, {required int min, required int max}) {
      final value = data[key];
      if (value == null) {
        return null;
      }
      if (value is! int || value < min || value > max) {
        throw FormatException('$key must be an integer between $min and $max');
      }
      return value;
    }

    return RelicUpdate(
      name: stringValue('name'),
      culture: stringValue('culture'),
      era: stringValue('era'),
      material: stringValue('material'),
      rarity: intValue('rarity', min: 1, max: 5),
      description: stringValue('description'),
      discoveredYear: intValue('discoveredYear', min: 1, max: 3000),
      discoverySite: stringValue('discoverySite'),
    );
  }
}

Middleware _observe(AppMetrics metrics) {
  return (inner) {
    return (request) async {
      final path = request.url.path;
      final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
      if (normalizedPath != 'health' && normalizedPath != 'api/cache/stats') {
        metrics.recordRequest();
      }
      try {
        final result = await inner(request);
        if (result is Response) {
          return result.copyWith(
            headers: result.headers.transform((headers) {
              headers['cache-control'] = ['no-store'];
            }),
          );
        }
        return result;
      } catch (error, stackTrace) {
        metrics.recordError();
        stderr.writeln('Unhandled request error: $error\n$stackTrace');
        return _error('internal server error', 500);
      }
    };
  };
}

Middleware _logRequests() {
  return (inner) {
    return (request) async {
      final watch = Stopwatch()..start();
      final result = await inner(request);
      final status = result is Response ? result.statusCode : '?';
      print(
        '${request.method.name.toUpperCase()} ${request.url.path} '
        '$status ${watch.elapsedMilliseconds}ms',
      );
      return result;
    };
  };
}

Response _json(String body, {int status = 200}) {
  return Response(
    status,
    body: Body.fromString(body, mimeType: MimeType.json),
    headers: _noStoreHeaders(),
  );
}

Response _error(String message, int status) {
  return _json(jsonEncode({'error': message}), status: status);
}

Headers _noStoreHeaders() {
  return Headers.build((headers) {
    headers['cache-control'] = ['no-store'];
  });
}
