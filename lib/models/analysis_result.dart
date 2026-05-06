import 'log_event.dart';
import 'log_source.dart';
import 'suspicious_event.dart';

class RestartEvent {
  RestartEvent({
    required this.timestamp,
    required this.sourceKind,
    required this.sourceName,
    required this.kind,
  });

  final DateTime timestamp;
  final LogSourceKind sourceKind;
  final String sourceName;

  /// Free-form lifecycle label (e.g. "container start", "ready",
  /// "process up", "flows started").
  final String kind;
}

class AnalysisInput {
  AnalysisInput({
    required this.sources,
    this.from,
    this.to,
  });

  final List<LogSource> sources;
  final DateTime? from;
  final DateTime? to;
}

class AnalysisResult {
  AnalysisResult({
    required this.generatedAt,
    required this.effectiveFrom,
    required this.effectiveTo,
    required this.suspicious,
    required this.slowQueries,
    required this.restarts,
    required this.totalLinesParsed,
    required this.sources,
    required this.warnings,
  });

  final DateTime generatedAt;
  final DateTime? effectiveFrom;
  final DateTime? effectiveTo;
  final List<SuspiciousEvent> suspicious;
  final List<SlowQueryEvent> slowQueries;
  final List<RestartEvent> restarts;
  final int totalLinesParsed;
  final List<LogSource> sources;
  final List<String> warnings;
}
