import 'dart:io';

import 'package:log_analyzer/models/log_event.dart';
import 'package:log_analyzer/models/log_source.dart';
import 'package:log_analyzer/parsers/container_csv_parser.dart';

/// Exercises the container parser against the ex5 fixtures (mixed
/// formats: MariaDB ISO plain, Node-RED plain, with `[appParams]`
/// orphans). Run with: `dart run tool/smoke_ex5.dart`.
Future<void> main() async {
  final cases = <(String, LogSourceKind)>[
    ('examples/ex5/gi4_mariadb_500_2026-05-08_0911.csv',
        LogSourceKind.mariadbContainer),
    ('examples/ex5/nodered_1880_500_2026-05-08_0911.csv',
        LogSourceKind.noderedContainer),
    ('examples/ex5/nodered_1881_500_2026-05-08_0911.csv',
        LogSourceKind.noderedContainer),
    ('examples/ex5/nodered_1882_500_2026-05-08_0911.csv',
        LogSourceKind.noderedContainer),
  ];

  for (final (path, kind) in cases) {
    final parser = ContainerCsvParser(kind: kind);
    final result = await parser.parseFile(File(path));
    final synthetic = result.events.where((e) => e.synthetic).length;
    final real = result.events.length - synthetic;
    stdout.writeln('--- $path ---');
    stdout.writeln('  events:    ${result.events.length} '
        '(real=$real, synthetic=$synthetic)');
    stdout.writeln('  skipped:   ${result.skippedRows}');
    if (result.events.isNotEmpty) {
      final first = result.events.first;
      final last = result.events.last;
      stdout.writeln('  range:     ${first.timestamp} → ${last.timestamp}');
    }
    for (final w in result.warnings) {
      stdout.writeln('  warn:      $w');
    }
    // Show the first synthetic + first real event for sanity.
    LogEvent? firstSynth;
    LogEvent? firstReal;
    for (final e in result.events) {
      firstSynth ??= e.synthetic ? e : null;
      firstReal ??= !e.synthetic ? e : null;
      if (firstSynth != null && firstReal != null) break;
    }
    if (firstSynth != null) {
      final preview = firstSynth.content.length > 80
          ? '${firstSynth.content.substring(0, 80)}…'
          : firstSynth.content;
      stdout.writeln('  1st synth: ${firstSynth.timestamp} | $preview');
    }
    if (firstReal != null) {
      final preview = firstReal.content.length > 80
          ? '${firstReal.content.substring(0, 80)}…'
          : firstReal.content;
      stdout.writeln('  1st real:  ${firstReal.timestamp} | $preview');
    }
  }
}
