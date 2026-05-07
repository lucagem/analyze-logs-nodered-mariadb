import 'log_event.dart';
import 'log_source.dart';
import 'severity.dart';

class SuspiciousEvent {
  SuspiciousEvent({
    required this.timestamp,
    required this.sourceKind,
    required this.sourceName,
    required this.severity,
    required this.category,
    required this.ruleId,
    required this.excerpt,
    this.sourceEvent,
    this.metadata = const {},
  });

  final DateTime timestamp;
  final LogSourceKind sourceKind;
  final String sourceName;
  final Severity severity;
  final String category;
  final String ruleId;
  final String excerpt;

  /// Back-reference to the original parsed log event. Used by the Context
  /// viewer to slice [-N, +M] lines around it.
  final LogEvent? sourceEvent;

  final Map<String, Object?> metadata;
}
