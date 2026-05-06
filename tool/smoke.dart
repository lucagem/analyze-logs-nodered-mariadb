import 'dart:convert';
import 'dart:io';

import 'package:log_analyzer/analyzers/analyzer.dart';
import 'package:log_analyzer/models/analysis_result.dart';
import 'package:log_analyzer/models/log_source.dart';
import 'package:log_analyzer/models/rules_config.dart';
import 'package:log_analyzer/reporters/markdown_reporter.dart';

/// Standalone smoke test that exercises the analyzer against ./examples
/// without going through Flutter. Run with: `dart run tool/smoke.dart`.
Future<void> main() async {
  final raw = await File('assets/rules.json').readAsString();
  final rules = RulesConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  final sources = <LogSource>[
    LogSource(
      kind: LogSourceKind.mariadbContainer,
      path: 'examples/ex2/gi4_mariadb.csv',
      displayName: 'gi4_mariadb.csv',
    ),
    LogSource(
      kind: LogSourceKind.noderedContainer,
      path: 'examples/ex2/gi4_nodered_1880.csv',
      displayName: 'gi4_nodered_1880.csv',
    ),
    LogSource(
      kind: LogSourceKind.noderedContainer,
      path: 'examples/ex2/gi4_nodered_1881.csv',
      displayName: 'gi4_nodered_1881.csv',
    ),
    LogSource(
      kind: LogSourceKind.noderedContainer,
      path: 'examples/ex2/gi4_nodered_1882.csv',
      displayName: 'gi4_nodered_1882.csv',
    ),
    LogSource(
      kind: LogSourceKind.mariadbSlowQuery,
      path: 'examples/ex1/mysql_slow.log',
      displayName: 'mysql_slow.log',
    ),
    LogSource(
      kind: LogSourceKind.axLog,
      path: 'examples/ex2/ax_log_202605061200.csv',
      displayName: 'ax_log_202605061200.csv',
    ),
  ];

  final analyzer = Analyzer(rules);
  final stopwatch = Stopwatch()..start();
  final result = await analyzer.run(AnalysisInput(sources: sources));
  stopwatch.stop();

  stdout.writeln('Parsed in ${stopwatch.elapsedMilliseconds} ms');
  stdout.writeln('Effective range: ${result.effectiveFrom} → ${result.effectiveTo}');
  stdout.writeln('Suspicious events: ${result.suspicious.length}');
  stdout.writeln('Slow queries: ${result.slowQueries.length}');
  stdout.writeln('Restarts: ${result.restarts.length}');
  stdout.writeln('Warnings:');
  for (final w in result.warnings) {
    stdout.writeln('  - $w');
  }

  final md = MarkdownReporter(rules).render(result);
  await Directory('build/smoke').create(recursive: true);
  await File('build/smoke/report.md').writeAsString(md);
  stdout.writeln('Wrote build/smoke/report.md (${md.length} chars)');
}
