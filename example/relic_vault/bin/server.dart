import 'dart:io';

import 'package:args/args.dart';
import 'package:pepper/pepper.dart';
import 'package:relic/io_adapter.dart';
import 'package:relic_vault/relic_vault.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('host', defaultsTo: '127.0.0.1', help: 'Bind address.')
    ..addOption('port', defaultsTo: '8080', help: 'Bind port.')
    ..addOption('db', defaultsTo: 'data/relics.db', help: 'SQLite database.')
    ..addFlag(
      'cache',
      defaultsTo: true,
      negatable: true,
      help: 'Enable the pepper caches.',
    )
    ..addOption(
      'algorithm',
      defaultsTo: 'lru',
      allowed: ['lru', 'lfu', 'fifo'],
      help: 'Cache eviction algorithm.',
    )
    ..addOption('capacity', defaultsTo: '10000', help: 'Detail cache capacity.')
    ..addOption(
      'search-capacity',
      defaultsTo: '2000',
      help: 'Search cache capacity.',
    )
    ..addOption(
      'missing-capacity',
      defaultsTo: '5000',
      help: 'Negative cache capacity.',
    )
    ..addOption(
      'ttl-ms',
      defaultsTo: '60000',
      help: 'Detail TTL in milliseconds.',
    )
    ..addOption(
      'search-ttl-ms',
      defaultsTo: '30000',
      help: 'Search TTL in milliseconds.',
    )
    ..addOption(
      'jitter-ms',
      defaultsTo: '5000',
      help: 'TTL jitter in milliseconds.',
    )
    ..addOption(
      'db-delay-us',
      defaultsTo: '0',
      help: 'Simulated backend latency in microseconds.',
    )
    ..addFlag(
      'log',
      defaultsTo: false,
      negatable: false,
      help: 'Log every request.',
    )
    ..addFlag(
      'seed',
      defaultsTo: false,
      negatable: false,
      help: 'Seed the database when it is empty.',
    )
    ..addOption(
      'seed-count',
      defaultsTo: '50000',
      help: 'Number of relics to seed with --seed.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  if (options['help'] as bool) {
    print(parser.usage);
    return;
  }

  try {
    final port = _int(options, 'port', min: 0, max: 65535);
    final capacity = _int(options, 'capacity', min: 1);
    final searchCapacity = _int(options, 'search-capacity', min: 1);
    final missingCapacity = _int(options, 'missing-capacity', min: 1);
    final detailTtlMs = _int(options, 'ttl-ms', min: 1);
    final searchTtlMs = _int(options, 'search-ttl-ms', min: 1);
    final jitterMs = _int(options, 'jitter-ms', min: 0);
    final dbDelayUs = _int(options, 'db-delay-us', min: 0);
    final seedCount = _int(options, 'seed-count', min: 1);

    final settings = CacheSettings(
      enabled: options['cache'] as bool,
      algorithm: EvictionAlgorithm.values.byName(
        options['algorithm'] as String,
      ),
      capacity: capacity,
      searchCapacity: searchCapacity,
      missingCapacity: missingCapacity,
      detailTtl: Duration(milliseconds: detailTtlMs),
      searchTtl: Duration(milliseconds: searchTtlMs),
      jitter: Duration(milliseconds: jitterMs),
    );

    final metrics = AppMetrics();
    final repository = SqliteRelicRepository.open(
      path: options['db'] as String,
      delay: Duration(microseconds: dbDelayUs),
      onQuery: metrics.recordDbQuery,
    );

    final existing = await repository.rowCount();
    if (existing == 0) {
      if (!(options['seed'] as bool)) {
        stderr.writeln(
          'The database is empty. Run bin/seed.dart or pass --seed.',
        );
        repository.close();
        exitCode = 1;
        return;
      }
      print('Seeding $seedCount relics...');
      await repository.seed(seedCount);
      print('Seeded ${await repository.rowCount()} relics.');
    }

    final service = RelicService(repository: repository, settings: settings);
    final app = buildRelicVaultApp(
      service: service,
      metrics: metrics,
      settings: settings,
      logRequests: options['log'] as bool,
    );

    final address = InternetAddress(options['host'] as String);
    final server = await app.serve(address: address, port: port);
    print(
      'Relic Vault listening on http://${address.address}:${server.port} '
      '(cache ${settings.enabled ? 'on' : 'off'}, '
      '${settings.algorithm.name}, capacity ${settings.capacity})',
    );

    var shuttingDown = false;
    Future<void> shutdown() async {
      if (shuttingDown) {
        return;
      }
      shuttingDown = true;
      await server.close();
      service.dispose();
      repository.close();
      exit(0);
    }

    ProcessSignal.sigint.watch().listen((_) => shutdown());
    if (!Platform.isWindows) {
      ProcessSignal.sigterm.watch().listen((_) => shutdown());
    }
  } on Object catch (error, stackTrace) {
    stderr.writeln('Failed to start Relic Vault: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

int _int(ArgResults options, String name, {int min = 0, int? max}) {
  final raw = options[name] as String;
  final value = int.tryParse(raw);
  if (value == null || value < min || (max != null && value > max)) {
    throw FormatException(
      '--$name must be an integer between $min and ${max ?? 'infinity'}',
    );
  }
  return value;
}
