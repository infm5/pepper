import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:relic_vault/relic_vault.dart';

import 'trace_generator.dart';

const _profileFull = 'full';
const _profileQuick = 'quick';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'profile',
      defaultsTo: _profileFull,
      allowed: [_profileFull, _profileQuick],
    )
    ..addOption('runs', defaultsTo: '0', help: 'Override the run count.')
    ..addOption(
      'duration',
      defaultsTo: '0',
      help: 'Measurement seconds per run.',
    )
    ..addOption('warmup', defaultsTo: '0', help: 'Warmup seconds.')
    ..addOption('connections', defaultsTo: '64')
    ..addOption('port', defaultsTo: '18080')
    ..addOption('seed-count', defaultsTo: '50000')
    ..addOption('trace-count', defaultsTo: '0')
    ..addOption('db', defaultsTo: 'build/relics.db')
    ..addOption('out', defaultsTo: 'bench/results/latest.md')
    ..addOption('json', defaultsTo: 'bench/results/latest.json')
    ..addOption('raw-dir', defaultsTo: 'bench/results/raw')
    ..addFlag(
      'build',
      defaultsTo: true,
      negatable: true,
      help: 'Build the server before benchmarking.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);

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

  final quick = options['profile'] == _profileQuick;
  final runs = _positiveInt(options, 'runs', fallback: quick ? 1 : 3);
  final duration = _positiveInt(options, 'duration', fallback: quick ? 5 : 20);
  final warmup = _positiveInt(options, 'warmup', fallback: quick ? 1 : 5);
  final traceCount = _positiveInt(
    options,
    'trace-count',
    fallback: quick ? 20000 : 100000,
  );
  final connections = _positiveInt(options, 'connections', fallback: 64);
  final port = _positiveInt(options, 'port', fallback: 18080);
  final seedCount = _positiveInt(options, 'seed-count', fallback: 50000);

  final root = p.dirname(p.dirname(Platform.script.toFilePath()));
  final dbPath = p.normalize(p.join(root, options['db'] as String));
  final tracePath = p.join(root, 'bench', 'trace.txt');
  final rawDir = p.normalize(p.join(root, options['raw-dir'] as String));
  final markdownPath = p.normalize(p.join(root, options['out'] as String));
  final jsonPath = p.normalize(p.join(root, options['json'] as String));
  Directory(rawDir).createSync(recursive: true);

  try {
    await _checkOha();
    print('Seeding benchmark database...');
    await _seed(dbPath, seedCount);

    print('Generating workload trace...');
    await generateTrace(
      path: tracePath,
      baseUrl: 'http://127.0.0.1:$port',
      count: traceCount,
      ids: seedCount,
      seed: 42,
    );

    final binary = p.join(root, 'build/server/bundle/bin/server');
    if (options['build'] as bool) {
      print('Building server...');
      final serverBuildDir = Directory(p.join(root, 'build/server'));
      if (serverBuildDir.existsSync()) {
        serverBuildDir.deleteSync(recursive: true);
      }
      final build = await Process.run(Platform.resolvedExecutable, [
        'build',
        'cli',
        '--target=bin/server.dart',
        '-o',
        'build/server',
      ], workingDirectory: root);
      if (build.exitCode != 0) {
        stderr.writeln(build.stdout);
        stderr.writeln(build.stderr);
        throw StateError('dart build cli failed with ${build.exitCode}');
      }
    }
    if (!File(binary).existsSync()) {
      throw StateError('Server binary not found at $binary');
    }

    final environment = await _collectEnvironment();
    final scenarios = _throughputScenarios(quick: quick);
    final coldScenarios = _coldScenarios();
    final throughput = <ScenarioSummary>[];
    final cold = <ColdSummary>[];

    for (final scenario in scenarios) {
      print('Running ${scenario.name}...');
      final server = await _startServer(
        binary: binary,
        root: root,
        port: port,
        dbPath: dbPath,
        scenario: scenario,
      );
      try {
        await _runOha(
          target: tracePath,
          rawPath: p.join(rawDir, '${scenario.name}-warmup.json'),
          connections: connections,
          requests: null,
          durationSeconds: warmup,
          trace: true,
          root: root,
        );

        final runsDone = <ThroughputRun>[];
        for (var run = 1; run <= runs; run++) {
          final before = await _fetchStats(port);
          final traffic = await _runOha(
            target: tracePath,
            rawPath: p.join(rawDir, '${scenario.name}-$run.json'),
            connections: connections,
            requests: null,
            durationSeconds: duration,
            trace: true,
            root: root,
          );
          final after = await _fetchStats(port);
          final delta = StatsDelta.between(before, after);
          runsDone.add(ThroughputRun(traffic: traffic, stats: delta));
          print(
            '  run $run: ${traffic.rps.toStringAsFixed(0)} req/s, '
            'p99 ${traffic.p99Ms.toStringAsFixed(2)} ms, '
            'hit ${delta.detailHitRate == null ? '—' : '${(delta.detailHitRate! * 100).toStringAsFixed(1)}%'}',
          );
        }
        throughput.add(ScenarioSummary.fromRuns(scenario, runsDone));
      } finally {
        await server.stop();
      }
    }

    for (final scenario in coldScenarios) {
      print('Running ${scenario.name}...');
      final runsDone = <ColdRun>[];
      for (var run = 1; run <= runs; run++) {
        final server = await _startServer(
          binary: binary,
          root: root,
          port: port,
          dbPath: dbPath,
          scenario: scenario.throughput,
        );
        try {
          final before = await _fetchStats(port);
          final traffic = await _runOha(
            target: 'http://127.0.0.1:$port${scenario.path}',
            rawPath: p.join(rawDir, '${scenario.name}-$run.json'),
            connections: 100,
            requests: scenario.requests,
            durationSeconds: 0,
            trace: false,
            root: root,
          );
          final after = await _fetchStats(port);
          runsDone.add(
            ColdRun(traffic: traffic, stats: StatsDelta.between(before, after)),
          );
        } finally {
          await server.stop();
        }
      }
      cold.add(ColdSummary.fromRuns(scenario, runsDone));
    }

    final report = _Report(
      generatedAt: DateTime.now(),
      profile: quick ? _profileQuick : _profileFull,
      environment: environment,
      workload: {
        'traceRequests': traceCount,
        'relics': seedCount,
        'connections': connections,
        'runs': runs,
        'durationSeconds': duration,
        'warmupSeconds': warmup,
      },
      throughput: throughput,
      cold: cold,
    );
    _writeMarkdown(report, markdownPath);
    _writeJson(report, jsonPath);
    print('Wrote $markdownPath');
    print('Wrote $jsonPath');
  } on Object catch (error, stackTrace) {
    stderr.writeln('Benchmark failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

Future<void> _checkOha() async {
  final result = await Process.run('oha', ['--version']);
  if (result.exitCode != 0) {
    throw StateError('oha is required: ${result.stderr}');
  }
  print('Using ${(result.stdout as String).trim()}');
}

Future<void> _seed(String dbPath, int count) async {
  final repository = SqliteRelicRepository.open(path: dbPath);
  try {
    final existing = await repository.rowCount();
    if (existing != count) {
      print('Seeding $count relics into $dbPath...');
      await repository.seed(count, reset: true);
    } else {
      print('Using existing $count-relic database.');
    }
  } finally {
    repository.close();
  }
}

List<Scenario> _throughputScenarios({required bool quick}) {
  final all = <Scenario>[
    const Scenario(
      name: 'local-no-cache',
      cache: false,
      delayUs: 0,
      capacity: 10000,
      searchCapacity: 2000,
      missingCapacity: 5000,
    ),
    const Scenario(
      name: 'local-pepper-lru',
      cache: true,
      delayUs: 0,
      capacity: 10000,
      searchCapacity: 2000,
      missingCapacity: 5000,
    ),
    const Scenario(
      name: 'backend-2ms-no-cache',
      cache: false,
      delayUs: 2000,
      capacity: 10000,
      searchCapacity: 2000,
      missingCapacity: 5000,
    ),
    const Scenario(
      name: 'backend-2ms-pepper-lru-10k',
      cache: true,
      delayUs: 2000,
      capacity: 10000,
      searchCapacity: 2000,
      missingCapacity: 5000,
    ),
    const Scenario(
      name: 'backend-2ms-pepper-lfu-10k',
      cache: true,
      delayUs: 2000,
      algorithm: 'lfu',
      capacity: 10000,
      searchCapacity: 2000,
      missingCapacity: 5000,
    ),
    const Scenario(
      name: 'backend-2ms-pepper-lru-100',
      cache: true,
      delayUs: 2000,
      capacity: 100,
      searchCapacity: 100,
      missingCapacity: 100,
    ),
    const Scenario(
      name: 'backend-2ms-pepper-lru-1k',
      cache: true,
      delayUs: 2000,
      capacity: 1000,
      searchCapacity: 500,
      missingCapacity: 500,
    ),
    const Scenario(
      name: 'backend-2ms-pepper-lru-50k',
      cache: true,
      delayUs: 2000,
      capacity: 50000,
      searchCapacity: 2000,
      missingCapacity: 5000,
    ),
  ];
  if (!quick) {
    return all;
  }
  return all
      .where(
        (scenario) =>
            scenario.name == 'backend-2ms-no-cache' ||
            scenario.name == 'backend-2ms-pepper-lru-10k',
      )
      .toList();
}

List<ColdScenario> _coldScenarios() {
  const base = Scenario(
    name: 'cold',
    cache: true,
    delayUs: 2000,
    capacity: 10000,
    searchCapacity: 2000,
    missingCapacity: 5000,
  );
  return [
    ColdScenario(
      name: 'cold-detail-no-cache',
      path: '/api/relics/1',
      requests: 1000,
      throughput: Scenario(
        name: 'cold-detail-no-cache',
        cache: false,
        delayUs: base.delayUs,
        capacity: base.capacity,
        searchCapacity: base.searchCapacity,
        missingCapacity: base.missingCapacity,
      ),
    ),
    const ColdScenario(
      name: 'cold-detail-pepper',
      path: '/api/relics/1',
      requests: 1000,
      throughput: base,
    ),
    ColdScenario(
      name: 'cold-404-no-cache',
      path: '/api/relics/999999999',
      requests: 1000,
      throughput: Scenario(
        name: 'cold-404-no-cache',
        cache: false,
        delayUs: base.delayUs,
        capacity: base.capacity,
        searchCapacity: base.searchCapacity,
        missingCapacity: base.missingCapacity,
      ),
    ),
    const ColdScenario(
      name: 'cold-404-pepper',
      path: '/api/relics/999999999',
      requests: 1000,
      throughput: base,
    ),
  ];
}

final class Scenario {
  const Scenario({
    required this.name,
    required this.cache,
    required this.delayUs,
    required this.capacity,
    required this.searchCapacity,
    required this.missingCapacity,
    this.algorithm = 'lru',
  });

  final String name;
  final bool cache;
  final int delayUs;
  final String algorithm;
  final int capacity;
  final int searchCapacity;
  final int missingCapacity;
}

final class ColdScenario {
  const ColdScenario({
    required this.name,
    required this.path,
    required this.requests,
    required this.throughput,
  });

  final String name;
  final String path;
  final int requests;
  final Scenario throughput;
}

final class RunningServer {
  RunningServer(this.process, this.output);

  final Process process;
  final List<String> output;

  Future<void> stop() async {
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  }
}

Future<RunningServer> _startServer({
  required String binary,
  required String root,
  required int port,
  required String dbPath,
  required Scenario scenario,
}) async {
  final arguments = <String>[
    '--port=$port',
    '--db=$dbPath',
    '--algorithm=${scenario.algorithm}',
    '--capacity=${scenario.capacity}',
    '--search-capacity=${scenario.searchCapacity}',
    '--missing-capacity=${scenario.missingCapacity}',
    '--ttl-ms=300000',
    '--search-ttl-ms=300000',
    '--jitter-ms=5000',
    '--db-delay-us=${scenario.delayUs}',
    if (!scenario.cache) '--no-cache',
  ];
  final process = await Process.start(
    binary,
    arguments,
    workingDirectory: root,
  );
  final output = <String>[];
  void add(String line) {
    output.add(line);
    if (output.length > 80) {
      output.removeAt(0);
    }
  }

  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(add);
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(add);
  var exited = false;
  unawaited(process.exitCode.then((_) => exited = true));

  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    if (exited) {
      break;
    }
    try {
      if (await _httpStatus(port, '/health') == 200) {
        return RunningServer(process, output);
      }
    } on Object {
      // Server is still starting.
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  process.kill(ProcessSignal.sigkill);
  await process.exitCode;
  throw StateError(
    'Server failed to start for ${scenario.name}:\n${output.join('\n')}',
  );
}

Future<OhaResult> _runOha({
  required String target,
  required String rawPath,
  required int connections,
  required int? requests,
  required int durationSeconds,
  required bool trace,
  required String root,
}) async {
  Directory(p.dirname(rawPath)).createSync(recursive: true);
  final arguments = <String>[
    '--no-tui',
    '--output-format',
    'json',
    '-o',
    rawPath,
    '-c',
    '$connections',
    if (requests != null) ...[
      '-n',
      '$requests',
    ] else ...[
      '-z',
      '${durationSeconds}s',
      '-w',
    ],
    if (trace) '--urls-from-file',
    target,
  ];
  final result = await Process.run('oha', arguments, workingDirectory: root);
  if (result.exitCode != 0) {
    throw StateError(
      'oha failed for $target:\n${result.stdout}\n${result.stderr}',
    );
  }
  final json = jsonDecode(await File(rawPath).readAsString());
  return OhaResult.fromJson(json as Map<String, dynamic>);
}

Future<StatsSnapshot> _fetchStats(int port) async {
  final json = await _getJson(port, '/api/cache/stats');
  return StatsSnapshot.fromJson(json);
}

Future<int> _httpStatus(int port, String path) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _getJson(int port, String path) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}: $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

final class OhaResult {
  OhaResult({
    required this.rps,
    required this.p50Ms,
    required this.p95Ms,
    required this.p99Ms,
    required this.totalRequests,
    required this.expectedRequests,
  });

  factory OhaResult.fromJson(Map<String, dynamic> json) {
    final metrics = json['metrics'] as Map<String, dynamic>;
    final latency = metrics['latency_ms'] as Map<String, dynamic>;
    final statuses =
        (json['statusCodeDistribution'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final errors =
        (json['errorDistribution'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    var total = 0;
    var expected = 0;
    statuses.forEach((key, value) {
      final status = int.tryParse(key) ?? 0;
      final count = (value as num).toInt();
      total += count;
      if ((status >= 200 && status < 400) || status == 404) {
        expected += count;
      }
    });
    errors.forEach((_, value) {
      total += (value as num).toInt();
    });

    return OhaResult(
      rps: (metrics['requests_per_sec'] as num).toDouble(),
      p50Ms: (latency['p50'] as num).toDouble(),
      p95Ms: (latency['p95'] as num).toDouble(),
      p99Ms: (latency['p99'] as num).toDouble(),
      totalRequests: total,
      expectedRequests: expected,
    );
  }

  final double rps;
  final double p50Ms;
  final double p95Ms;
  final double p99Ms;
  final int totalRequests;
  final int expectedRequests;

  double get errorRate =>
      totalRequests == 0 ? 0 : 1 - expectedRequests / totalRequests;
}

final class StatsSnapshot {
  StatsSnapshot({
    required this.requests,
    required this.dbQueries,
    required this.rssBytes,
    required this.detailHits,
    required this.detailMisses,
    required this.detailLength,
    required this.detailMissingLength,
    required this.searchHits,
    required this.searchMisses,
    required this.searchLength,
  });

  factory StatsSnapshot.fromJson(Map<String, dynamic> json) {
    final cache = json['cache'] as Map<String, dynamic>;
    final detail = cache['detail'] as Map<String, dynamic>?;
    final search = cache['search'] as Map<String, dynamic>?;
    return StatsSnapshot(
      requests: (json['requests'] as num).toInt(),
      dbQueries: (json['dbQueries'] as num).toInt(),
      rssBytes: (json['rssBytes'] as num).toInt(),
      detailHits: detail == null ? null : (detail['hits'] as num).toInt(),
      detailMisses: detail == null ? null : (detail['misses'] as num).toInt(),
      detailLength: detail == null ? null : (detail['length'] as num).toInt(),
      detailMissingLength: detail == null
          ? null
          : (detail['missingLength'] as num).toInt(),
      searchHits: search == null ? null : (search['hits'] as num).toInt(),
      searchMisses: search == null ? null : (search['misses'] as num).toInt(),
      searchLength: search == null ? null : (search['length'] as num).toInt(),
    );
  }

  final int requests;
  final int dbQueries;
  final int rssBytes;
  final int? detailHits;
  final int? detailMisses;
  final int? detailLength;
  final int? detailMissingLength;
  final int? searchHits;
  final int? searchMisses;
  final int? searchLength;
}

final class StatsDelta {
  StatsDelta({
    required this.requests,
    required this.dbQueries,
    required this.rssBytes,
    required this.detailHits,
    required this.detailMisses,
    required this.searchHits,
    required this.searchMisses,
  });

  factory StatsDelta.between(StatsSnapshot before, StatsSnapshot after) {
    return StatsDelta(
      requests: after.requests - before.requests,
      dbQueries: after.dbQueries - before.dbQueries,
      rssBytes: after.rssBytes,
      detailHits: after.detailHits == null || before.detailHits == null
          ? null
          : after.detailHits! - before.detailHits!,
      detailMisses: after.detailMisses == null || before.detailMisses == null
          ? null
          : after.detailMisses! - before.detailMisses!,
      searchHits: after.searchHits == null || before.searchHits == null
          ? null
          : after.searchHits! - before.searchHits!,
      searchMisses: after.searchMisses == null || before.searchMisses == null
          ? null
          : after.searchMisses! - before.searchMisses!,
    );
  }

  final int requests;
  final int dbQueries;
  final int rssBytes;
  final int? detailHits;
  final int? detailMisses;
  final int? searchHits;
  final int? searchMisses;

  double? get detailHitRate {
    if (detailHits == null || detailMisses == null) {
      return null;
    }
    final total = detailHits! + detailMisses!;
    return total == 0 ? null : detailHits! / total;
  }

  double? get searchHitRate {
    if (searchHits == null || searchMisses == null) {
      return null;
    }
    final total = searchHits! + searchMisses!;
    return total == 0 ? null : searchHits! / total;
  }
}

final class ThroughputRun {
  const ThroughputRun({required this.traffic, required this.stats});

  final OhaResult traffic;
  final StatsDelta stats;
}

final class ScenarioSummary {
  ScenarioSummary({
    required this.scenario,
    required this.rps,
    required this.p50Ms,
    required this.p95Ms,
    required this.p99Ms,
    required this.errorRate,
    required this.detailHitRate,
    required this.searchHitRate,
    required this.dbQueriesPerRequest,
    required this.rssBytes,
    required this.totalRequests,
  });

  factory ScenarioSummary.fromRuns(
    Scenario scenario,
    List<ThroughputRun> runs,
  ) {
    final detailHits = runs
        .map((run) => run.stats.detailHits)
        .whereType<int>()
        .fold<int>(0, (sum, value) => sum + value);
    final detailMisses = runs
        .map((run) => run.stats.detailMisses)
        .whereType<int>()
        .fold<int>(0, (sum, value) => sum + value);
    final searchHits = runs
        .map((run) => run.stats.searchHits)
        .whereType<int>()
        .fold<int>(0, (sum, value) => sum + value);
    final searchMisses = runs
        .map((run) => run.stats.searchMisses)
        .whereType<int>()
        .fold<int>(0, (sum, value) => sum + value);
    final totalRequests = runs.fold<int>(
      0,
      (sum, run) => sum + run.traffic.totalRequests,
    );
    final expectedRequests = runs.fold<int>(
      0,
      (sum, run) => sum + run.traffic.expectedRequests,
    );
    final dbQueries = runs.fold<int>(
      0,
      (sum, run) => sum + run.stats.dbQueries,
    );
    final actualRequests = runs.fold<int>(
      0,
      (sum, run) => sum + run.stats.requests,
    );

    return ScenarioSummary(
      scenario: scenario,
      rps: _median([for (final run in runs) run.traffic.rps]),
      p50Ms: _median([for (final run in runs) run.traffic.p50Ms]),
      p95Ms: _median([for (final run in runs) run.traffic.p95Ms]),
      p99Ms: _median([for (final run in runs) run.traffic.p99Ms]),
      errorRate: totalRequests == 0 ? 0 : 1 - expectedRequests / totalRequests,
      detailHitRate: detailHits + detailMisses == 0
          ? null
          : detailHits / (detailHits + detailMisses),
      searchHitRate: searchHits + searchMisses == 0
          ? null
          : searchHits / (searchHits + searchMisses),
      dbQueriesPerRequest: actualRequests == 0 ? 0 : dbQueries / actualRequests,
      rssBytes: _medianInt([for (final run in runs) run.stats.rssBytes]),
      totalRequests: actualRequests,
    );
  }

  final Scenario scenario;
  final double rps;
  final double p50Ms;
  final double p95Ms;
  final double p99Ms;
  final double errorRate;
  final double? detailHitRate;
  final double? searchHitRate;
  final double dbQueriesPerRequest;
  final int rssBytes;
  final int totalRequests;

  Map<String, Object?> toJson() => {
    'name': scenario.name,
    'cache': scenario.cache,
    'algorithm': scenario.algorithm,
    'capacity': scenario.capacity,
    'searchCapacity': scenario.searchCapacity,
    'missingCapacity': scenario.missingCapacity,
    'delayUs': scenario.delayUs,
    'rps': rps,
    'p50Ms': p50Ms,
    'p95Ms': p95Ms,
    'p99Ms': p99Ms,
    'errorRate': errorRate,
    'detailHitRate': detailHitRate,
    'searchHitRate': searchHitRate,
    'dbQueriesPerRequest': dbQueriesPerRequest,
    'rssBytes': rssBytes,
    'requests': totalRequests,
  };
}

final class ColdRun {
  const ColdRun({required this.traffic, required this.stats});

  final OhaResult traffic;
  final StatsDelta stats;
}

final class ColdSummary {
  ColdSummary({
    required this.scenario,
    required this.rps,
    required this.p95Ms,
    required this.p99Ms,
    required this.requests,
    required this.dbQueries,
    required this.dbQueriesPerRequest,
    required this.runs,
  });

  factory ColdSummary.fromRuns(ColdScenario scenario, List<ColdRun> runs) {
    final totalRequests = runs.fold<int>(
      0,
      (sum, run) => sum + run.stats.requests,
    );
    final totalDbQueries = runs.fold<int>(
      0,
      (sum, run) => sum + run.stats.dbQueries,
    );
    return ColdSummary(
      scenario: scenario,
      rps: _median([for (final run in runs) run.traffic.rps]),
      p95Ms: _median([for (final run in runs) run.traffic.p95Ms]),
      p99Ms: _median([for (final run in runs) run.traffic.p99Ms]),
      requests: totalRequests,
      dbQueries: totalDbQueries,
      dbQueriesPerRequest: totalRequests == 0
          ? 0
          : totalDbQueries / totalRequests,
      runs: runs.length,
    );
  }

  final ColdScenario scenario;
  final double rps;
  final double p95Ms;
  final double p99Ms;
  final int requests;
  final int dbQueries;
  final double dbQueriesPerRequest;
  final int runs;

  Map<String, Object?> toJson() => {
    'name': scenario.name,
    'path': scenario.path,
    'requests': requests,
    'runs': runs,
    'dbQueries': dbQueries,
    'dbQueriesPerRequest': dbQueriesPerRequest,
    'rps': rps,
    'p95Ms': p95Ms,
    'p99Ms': p99Ms,
  };
}

final class _Report {
  _Report({
    required this.generatedAt,
    required this.profile,
    required this.environment,
    required this.workload,
    required this.throughput,
    required this.cold,
  });

  final DateTime generatedAt;
  final String profile;
  final Map<String, String> environment;
  final Map<String, Object?> workload;
  final List<ScenarioSummary> throughput;
  final List<ColdSummary> cold;
}

void _writeMarkdown(_Report report, String path) {
  final buffer = StringBuffer()
    ..writeln('# Relic Vault benchmark')
    ..writeln()
    ..writeln('Generated: ${report.generatedAt.toIso8601String()}  ')
    ..writeln('Profile: **${report.profile}**  ')
    ..writeln(
      'Workload: **${report.workload['traceRequests']}** URL trace, '
      '**${report.workload['connections']}** connections, '
      '**${report.workload['durationSeconds']}s** per run, '
      '**${report.workload['runs']}** runs per scenario.',
    )
    ..writeln()
    ..writeln('## Environment')
    ..writeln();

  for (final entry in report.environment.entries) {
    buffer.writeln('- **${entry.key}:** ${entry.value}');
  }

  buffer
    ..writeln()
    ..writeln('## Throughput')
    ..writeln()
    ..writeln(
      '| Scenario | RPS | p50 ms | p95 ms | p99 ms | Errors | Detail hit | Search hit | DB q/req | RSS MB |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final result in report.throughput) {
    buffer.writeln(
      '| ${result.scenario.name} '
      '| ${_number(result.rps)} '
      '| ${_ms(result.p50Ms)} '
      '| ${_ms(result.p95Ms)} '
      '| ${_ms(result.p99Ms)} '
      '| ${_pct(result.errorRate)} '
      '| ${_pct(result.detailHitRate)} '
      '| ${_pct(result.searchHitRate)} '
      '| ${result.dbQueriesPerRequest.toStringAsFixed(3)} '
      '| ${_mb(result.rssBytes)} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Cold-start and negative-cache bursts')
    ..writeln()
    ..writeln(
      '| Scenario | Requests | DB queries | DB q/req | RPS | p95 ms | p99 ms |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|');
  for (final result in report.cold) {
    buffer.writeln(
      '| ${result.scenario.name} '
      '| ${result.requests} '
      '| ${result.dbQueries} '
      '| ${result.dbQueriesPerRequest.toStringAsFixed(4)} '
      '| ${_number(result.rps)} '
      '| ${_ms(result.p95Ms)} '
      '| ${_ms(result.p99Ms)} |',
    );
  }

  buffer
    ..writeln()
    ..writeln(
      'Each cold scenario sends 1,000 requests per run; the DB-query column is '
      'the total across runs. Pepper issues one SQLite query per burst.',
    )
    ..writeln()
    ..writeln('## Method')
    ..writeln()
    ..writeln(
      '- `oha` drives a generated URL mix: 60% detail, 25% batch, 10% search, '
      '5% missing ids. Detail ids are Zipf(1.0) distributed over '
      '${report.workload['relics']} relics.',
    )
    ..writeln(
      '- The server is the AOT CLI bundle from `dart build cli`, running in '
      'one isolate. Relic routing and pepper caches are in the same process.',
    )
    ..writeln(
      '- `backend-2ms` scenarios inject an explicit 2 ms delay before every '
      'SQLite operation. The delay is simulated, not a network database.',
    )
    ..writeln(
      '- Throughput numbers are medians across runs for RPS and latency; '
      'cache hit rates and DB queries per request are aggregated across runs.',
    )
    ..writeln(
      '- Benchmark caches use a 5 minute TTL so entries do not expire in the '
      'middle of a scenario. The demo defaults are 60 s for detail and 30 s '
      'for search.',
    )
    ..writeln(
      '- `oha` runs on the same machine as the server. Absolute numbers are '
      'machine-specific; the no-cache and pepper deltas are the point.',
    )
    ..writeln(
      '- A 404 is treated as an expected response in error-rate accounting; '
      'only 5xx and transport errors count as failures.',
    )
    ..writeln(
      '- Search is intentionally a simple `LIKE` scan over SQLite. It is not '
      'FTS5; the goal is to exercise cache behavior, not search quality.',
    )
    ..writeln()
    ..writeln('Raw `oha` JSON is in `bench/results/raw/`.');
  final markdown = buffer
      .toString()
      .split('\n')
      .map((line) => line.trimRight())
      .join('\n');
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(markdown);
}

void _writeJson(_Report report, String path) {
  final json = {
    'generatedAt': report.generatedAt.toIso8601String(),
    'profile': report.profile,
    'environment': report.environment,
    'workload': report.workload,
    'throughput': [for (final result in report.throughput) result.toJson()],
    'cold': [for (final result in report.cold) result.toJson()],
  };
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
}

Future<Map<String, String>> _collectEnvironment() async {
  final values = <String, String>{};
  values['os'] = Platform.operatingSystemVersion;
  values['dart'] = await _command('${Platform.resolvedExecutable} --version');
  values['oha'] = await _command('oha --version');
  values['sqlite'] = await _command('sqlite3 --version');
  if (Platform.isMacOS) {
    values['cpu'] = await _command('sysctl -n machdep.cpu.brand_string');
    final memory = int.tryParse(await _command('sysctl -n hw.memsize'));
    values['memory'] = memory == null
        ? 'unknown'
        : '${(memory / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
  return values;
}

Future<String> _command(String command) async {
  try {
    final result = await Process.run('sh', ['-c', '$command 2>&1']);
    return (result.stdout as String).trim().split('\n').first;
  } on Object {
    return 'unknown';
  }
}

double _median(List<double> values) {
  if (values.isEmpty) {
    return 0;
  }
  final sorted = List<double>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[middle];
  }
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

int _medianInt(List<int> values) {
  if (values.isEmpty) {
    return 0;
  }
  final sorted = List<int>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[middle];
  }
  return ((sorted[middle - 1] + sorted[middle]) / 2).round();
}

String _number(double value) => value.toStringAsFixed(0);

String _ms(double value) => value.toStringAsFixed(2);

String _pct(double? value) =>
    value == null ? '—' : '${(value * 100).toStringAsFixed(1)}%';

String _mb(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);

int _positiveInt(ArgResults options, String name, {required int fallback}) {
  final raw = options[name] as String;
  final value = int.tryParse(raw);
  if (value == null || value < 0) {
    throw FormatException('--$name must be a non-negative integer');
  }
  return value == 0 ? fallback : value;
}
