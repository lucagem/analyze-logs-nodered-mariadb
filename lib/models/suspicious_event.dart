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
    this.metadata = const {},
  });

  final DateTime timestamp;
  final LogSourceKind sourceKind;
  final String sourceName;
  final Severity severity;
  final String category;
  final String ruleId;
  final String excerpt;
  final Map<String, Object?> metadata;
}
