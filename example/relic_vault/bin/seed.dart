import 'dart:io';

import 'package:args/args.dart';
import 'package:relic_vault/relic_vault.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('db', defaultsTo: 'data/relics.db', help: 'SQLite database.')
    ..addOption('count', defaultsTo: '50000', help: 'Number of relics to seed.')
    ..addFlag(
      'reset',
      defaultsTo: false,
      negatable: false,
      help: 'Drop the existing table before seeding.',
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

  final count = int.tryParse(options['count'] as String);
  if (count == null || count < 1) {
    stderr.writeln('--count must be a positive integer.');
    exitCode = 64;
    return;
  }

  final path = options['db'] as String;
  final repository = SqliteRelicRepository.open(path: path);
  try {
    await repository.seed(count, reset: options['reset'] as bool);
    final total = await repository.rowCount();
    print('Seeded $total relics into $path.');
  } finally {
    repository.close();
  }
}
