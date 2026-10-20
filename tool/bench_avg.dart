import 'dart:io';

/// Runs a compiled benchmark binary several times and prints the average.
///
/// Usage:
///   `dart run tool/bench_avg.dart [--runs=N] <path-to-benchmark-binary>`
Future<void> main(List<String> arguments) async {
  var runs = 3;
  String? binary;

  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == '--runs') {
      if (i + 1 >= arguments.length) {
        _usage('--runs requires a value');
        return;
      }
      runs = int.tryParse(arguments[++i]) ?? 0;
    } else if (argument.startsWith('--runs=')) {
      runs = int.tryParse(argument.substring('--runs='.length)) ?? 0;
    } else if (argument.startsWith('-')) {
      _usage('unknown option: $argument');
      return;
    } else {
      binary = argument;
    }
  }

  if (binary == null || runs < 1) {
    _usage('a benchmark binary and a positive --runs value are required');
    return;
  }

  final resultPattern = RegExp(
    r'^(.+?)\s+([0-9]+(?:\.[0-9]+)?) ns/op\s+[0-9,]+ K ops/s$',
  );
  final samples = <String, List<double>>{};
  final order = <String>[];
  var expectedRows = 0;

  for (var run = 1; run <= runs; run++) {
    stderr.writeln('benchmark run $run/$runs...');
    final ProcessResult result;
    try {
      result = await Process.run(binary, const <String>[]);
    } on ProcessException catch (error) {
      stderr.writeln('failed to run $binary: ${error.message}');
      exitCode = 1;
      return;
    }

    if (result.exitCode != 0) {
      stderr.writeln('benchmark failed with exit code ${result.exitCode}');
      final output = result.stdout.toString().trim();
      final error = result.stderr.toString().trim();
      if (output.isNotEmpty) {
        stderr.writeln(output);
      }
      if (error.isNotEmpty) {
        stderr.writeln(error);
      }
      exitCode = result.exitCode;
      return;
    }

    final output = result.stdout.toString();
    var rows = 0;
    for (final line in output.split('\n')) {
      final match = resultPattern.firstMatch(line.trimRight());
      if (match == null) {
        continue;
      }
      final name = match.group(1)!.trim();
      final nanoseconds = double.parse(match.group(2)!);
      samples
          .putIfAbsent(name, () {
            order.add(name);
            return <double>[];
          })
          .add(nanoseconds);
      rows++;
    }

    if (rows == 0) {
      stderr.writeln('could not parse any ns/op rows from the benchmark');
      stderr.writeln(output);
      exitCode = 1;
      return;
    }
    if (run == 1) {
      expectedRows = rows;
    } else if (rows != expectedRows) {
      stderr.writeln(
        'benchmark row count changed between runs: '
        '$expectedRows -> $rows',
      );
      exitCode = 1;
      return;
    }
  }

  for (final name in order) {
    if (samples[name]!.length != runs) {
      stderr.writeln('missing samples for "$name"');
      exitCode = 1;
      return;
    }
  }

  stdout.writeln('pepper benchmarks — average of $runs runs');
  stdout.writeln();
  for (final name in order) {
    final values = samples[name]!;
    final average = values.reduce((a, b) => a + b) / values.length;
    final kOpsPerSecond = 1e6 / average;
    stdout.writeln(
      '${name.padRight(44)}'
      '${average.toStringAsFixed(1).padLeft(9)} ns/op'
      '${_group(kOpsPerSecond.round()).padLeft(12)} K ops/s',
    );
  }
}

void _usage(String message) {
  stderr.writeln(message);
  stderr.writeln(
    'Usage: dart run tool/bench_avg.dart [--runs=N] <benchmark-binary>',
  );
  exitCode = 64;
}

String _group(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
