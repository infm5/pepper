import 'package:args/args.dart';

import 'trace_generator.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('base-url', defaultsTo: 'http://127.0.0.1:18080')
    ..addOption('output', defaultsTo: 'bench/trace.txt')
    ..addOption('count', defaultsTo: '100000')
    ..addOption('ids', defaultsTo: '50000')
    ..addOption('seed', defaultsTo: '42')
    ..addFlag('help', abbr: 'h', negatable: false);

  final options = parser.parse(arguments);
  if (options['help'] as bool) {
    print(parser.usage);
    return;
  }

  final count = int.parse(options['count'] as String);
  final ids = int.parse(options['ids'] as String);
  final seed = int.parse(options['seed'] as String);
  final output = options['output'] as String;
  final baseUrl = options['base-url'] as String;

  await generateTrace(
    path: output,
    baseUrl: baseUrl,
    count: count,
    ids: ids,
    seed: seed,
  );
  print('Wrote $count URLs to $output.');
}
