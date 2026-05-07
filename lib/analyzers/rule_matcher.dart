import '../models/log_event.dart';
import '../models/log_source.dart';
import '../models/rules_config.dart';
import '../models/suspicious_event.dart';

/// Applies a list of [RulePattern]s against a [LogEvent] and returns the matches.
class RuleMatcher {
  RuleMatcher(this.patterns);

  final List<RulePattern> patterns;

  /// Returns at most one event per line — the first matching rule wins.
  /// Rules in `rules.json` are ordered specific → generic, so a generic
  /// "[Warning]" pattern never shadows the more informative "Aborted
  /// connection" / "Deadlock" categories.
  Iterable<SuspiciousEvent> match(LogEvent event) sync* {
    final body = event.content;
    for (final pattern in patterns) {
      if (pattern.regex.hasMatch(body)) {
        yield SuspiciousEvent(
          timestamp: event.timestamp,
          sourceKind: event.sourceKind,
          sourceName: event.sourceName,
          severity: pattern.severity,
          category: pattern.category,
          ruleId: pattern.id,
          excerpt: _flatten(body),
          sourceEvent: event,
          metadata: const {},
        );
        return;
      }
    }
  }

  static String _flatten(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact;
  }
}

/// Detects restart events for sources with a known startup-marker regex
/// (e.g. MariaDB "ready for connections", Node-RED "Started flows").
class RestartDetector {
  RestartDetector(this.markerRegex);

  final RegExp markerRegex;

  Iterable<DateTime> detect(Iterable<LogEvent> events, LogSourceKind kind) sync* {
    for (final e in events) {
      if (e.sourceKind != kind) continue;
      if (markerRegex.hasMatch(e.content)) {
        yield e.timestamp;
      }
    }
  }
}
