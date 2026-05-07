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

/// One row per loaded file shown in the report header. Captures both the
/// raw span of timestamps in the file and how many events survived the
/// effective-range intersection — so the user can immediately see when a
/// source ends before the requested window.
class SourceStats {
  SourceStats({
    required this.kind,
    required this.displayName,
    required this.totalEvents,
    required this.minTimestamp,
    required this.maxTimestamp,
    required this.eventsInRange,
    required this.skippedRows,
    required this.skippedSamples,
  });

  final LogSourceKind kind;
  final String displayName;
  final int totalEvents;
  final DateTime? minTimestamp;
  final DateTime? maxTimestamp;
  final int eventsInRange;

  /// Total number of rows the parser had to discard.
  final int skippedRows;

  /// Up to a few example malformed rows (raw text) so the user can inspect
  /// what was thrown away. Each entry is prefixed with the reason.
  final List<String> skippedSamples;
}

class AnalysisInput {
  AnalysisInput({
    required this.sources,
    this.from,
    this.to,
    this.axIncludedStates,
  });

  final List<LogSource> sources;
  final DateTime? from;
  final DateTime? to;

  /// Override the AX_LOG state selection for this analysis run. When `null`,
  /// the analyzer falls back to `RulesConfig.axLog.defaultIncludedStates`.
  final Set<int>? axIncludedStates;
}

class AnalysisResult {
  AnalysisResult({
    required this.generatedAt,
    required this.requestedFrom,
    required this.requestedTo,
    required this.effectiveFrom,
    required this.effectiveTo,
    required this.suspicious,
    required this.slowQueries,
    required this.restarts,
    required this.totalLinesParsed,
    required this.sources,
    required this.sourceStats,
    required this.warnings,
    required this.eventsBySource,
  });

  final DateTime generatedAt;
  final DateTime? requestedFrom;
  final DateTime? requestedTo;
  final DateTime? effectiveFrom;
  final DateTime? effectiveTo;
  final List<SuspiciousEvent> suspicious;
  final List<SlowQueryEvent> slowQueries;
  final List<RestartEvent> restarts;
  final int totalLinesParsed;
  final List<LogSource> sources;
  final List<SourceStats> sourceStats;
  final List<String> warnings;

  /// Every parsed event, grouped by source-file display name and sorted by
  /// timestamp. Includes events outside the effective window — used by the
  /// Context viewer to slice [-N, +M] lines around a clicked suspicious
  /// event.
  final Map<String, List<LogEvent>> eventsBySource;
}
