import '../models/log_event.dart';
import '../models/rules_config.dart';
import '../models/suspicious_event.dart';
import '../models/severity.dart';

/// Flags slow queries based on duration, lock time, examined-vs-sent ratio,
/// and detects repeating queries within a sliding time window.
class SlowQueryAnalyzer {
  SlowQueryAnalyzer(this.rules);

  final SlowQueryRules rules;

  List<SuspiciousEvent> analyze(List<SlowQueryEvent> events) {
    final out = <SuspiciousEvent>[];

    for (final e in events) {
      if (e.queryTime >= rules.minQueryTimeSeconds) {
        out.add(SuspiciousEvent(
          timestamp: e.timestamp,
          sourceKind: e.sourceKind,
          sourceName: e.sourceName,
          severity: _severityForDuration(e.queryTime),
          category: 'Slow query',
          ruleId: 'sq_duration',
          excerpt: _excerpt(e),
          metadata: {
            'queryTime': e.queryTime,
            'rowsExamined': e.rowsExamined,
            'rowsSent': e.rowsSent,
          },
        ));
      }
      if (e.lockTime >= rules.minLockTimeSeconds) {
        out.add(SuspiciousEvent(
          timestamp: e.timestamp,
          sourceKind: e.sourceKind,
          sourceName: e.sourceName,
          severity: Severity.warn,
          category: 'Slow query · lock',
          ruleId: 'sq_lock',
          excerpt: _excerpt(e),
          metadata: {'lockTime': e.lockTime},
        ));
      }
      final examinedToSent = e.rowsSent == 0
          ? e.rowsExamined
          : (e.rowsExamined ~/ (e.rowsSent == 0 ? 1 : e.rowsSent));
      if (e.rowsExamined >= rules.minRowsExaminedAbsolute &&
          examinedToSent >= rules.minRowsExaminedToSentRatio) {
        out.add(SuspiciousEvent(
          timestamp: e.timestamp,
          sourceKind: e.sourceKind,
          sourceName: e.sourceName,
          severity: Severity.warn,
          category: 'Slow query · selectivity',
          ruleId: 'sq_selectivity',
          excerpt: _excerpt(e),
          metadata: {
            'rowsExamined': e.rowsExamined,
            'rowsSent': e.rowsSent,
            'ratio': examinedToSent,
          },
        ));
      }
    }

    out.addAll(_detectRepeats(events));
    return out;
  }

  Iterable<SuspiciousEvent> _detectRepeats(List<SlowQueryEvent> events) sync* {
    final window = Duration(seconds: rules.repeatWindowSeconds);
    final byFingerprint = <String, List<SlowQueryEvent>>{};
    for (final e in events) {
      byFingerprint.putIfAbsent(_fingerprint(e.content), () => []).add(e);
    }
    for (final entry in byFingerprint.entries) {
      final list = entry.value;
      if (list.length < rules.repeatThreshold) continue;
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      var start = 0;
      for (var end = 0; end < list.length; end++) {
        while (list[end].timestamp.difference(list[start].timestamp) > window) {
          start++;
        }
        final count = end - start + 1;
        if (count >= rules.repeatThreshold) {
          final mid = list[(start + end) ~/ 2];
          yield SuspiciousEvent(
            timestamp: mid.timestamp,
            sourceKind: mid.sourceKind,
            sourceName: mid.sourceName,
            severity: Severity.warn,
            category: 'Slow query · repeated',
            ruleId: 'sq_repeated',
            excerpt: _excerpt(mid),
            metadata: {
              'count': count,
              'windowSeconds': rules.repeatWindowSeconds,
            },
          );
          break; // one repeat-burst per fingerprint
        }
      }
    }
  }

  String _fingerprint(String sql) {
    var s = sql.toLowerCase();
    s = s.replaceAll(RegExp(r"'[^']*'"), "'?'");
    s = s.replaceAll(RegExp(r'\b\d+\b'), '?');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length > 200) s = s.substring(0, 200);
    return s;
  }

  String _excerpt(SlowQueryEvent e) {
    final sql = e.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    final head = sql.length > 240 ? '${sql.substring(0, 240)}…' : sql;
    return 'qt=${e.queryTime.toStringAsFixed(3)}s lock=${e.lockTime.toStringAsFixed(3)}s '
        'rows ${e.rowsSent}/${e.rowsExamined} · $head';
  }

  Severity _severityForDuration(double seconds) {
    if (seconds >= rules.minQueryTimeSeconds * 5) return Severity.error;
    return Severity.warn;
  }
}
