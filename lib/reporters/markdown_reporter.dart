import 'package:intl/intl.dart';

import '../models/analysis_result.dart';
import '../models/rules_config.dart';
import '../models/severity.dart';
import '../models/suspicious_event.dart';

class MarkdownReporter {
  MarkdownReporter(this.rules);

  final RulesConfig rules;

  String render(AnalysisResult result) {
    final buf = StringBuffer();
    final tsFmt = DateFormat('yyyy-MM-dd HH:mm:ss');

    buf.writeln('# Log Analysis Report');
    buf.writeln();
    buf.writeln('- **Generated:** ${tsFmt.format(result.generatedAt)}');
    buf.writeln(
        '- **Effective range:** ${_fmtRange(result.effectiveFrom, result.effectiveTo, tsFmt)}');
    buf.writeln('- **Lines parsed:** ${result.totalLinesParsed}');
    buf.writeln('- **Sources:**');
    for (final s in result.sources) {
      buf.writeln('  - `${s.kind.label}` — ${s.displayName}');
    }
    if (result.warnings.isNotEmpty) {
      buf.writeln();
      buf.writeln('> ⚠ ${result.warnings.length} parser warning(s):');
      for (final w in result.warnings) {
        buf.writeln('> - $w');
      }
    }
    buf.writeln();

    _writeSummary(buf, result);
    _writeRestarts(buf, result, tsFmt);
    _writeTimeline(buf, result, tsFmt);
    _writeBySource(buf, result, tsFmt);
    _writeTopSlowQueries(buf, result, tsFmt);

    return buf.toString();
  }

  void _writeSummary(StringBuffer buf, AnalysisResult result) {
    buf.writeln('## Summary');
    buf.writeln();
    final bySev = <Severity, int>{};
    for (final s in result.suspicious) {
      bySev[s.severity] = (bySev[s.severity] ?? 0) + 1;
    }
    buf.writeln('| Severity | Count |');
    buf.writeln('|---|---:|');
    for (final sev in [Severity.critical, Severity.error, Severity.warn, Severity.info]) {
      buf.writeln('| ${sev.label} | ${bySev[sev] ?? 0} |');
    }
    buf.writeln('| **Total** | **${result.suspicious.length}** |');
    buf.writeln();

    final byCategory = <String, int>{};
    for (final s in result.suspicious) {
      byCategory[s.category] = (byCategory[s.category] ?? 0) + 1;
    }
    final categoriesSorted = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (categoriesSorted.isNotEmpty) {
      buf.writeln('### By category');
      buf.writeln();
      buf.writeln('| Category | Count |');
      buf.writeln('|---|---:|');
      for (final entry in categoriesSorted) {
        buf.writeln('| ${entry.key} | ${entry.value} |');
      }
      buf.writeln();
    }
  }

  void _writeRestarts(StringBuffer buf, AnalysisResult result, DateFormat fmt) {
    if (result.restarts.isEmpty) return;
    buf.writeln('## Lifecycle events');
    buf.writeln();
    buf.writeln('| Time | Source | Name | Event |');
    buf.writeln('|---|---|---|---|');
    for (final r in result.restarts) {
      buf.writeln(
          '| ${fmt.format(r.timestamp)} | ${r.sourceKind.label} | ${_escape(r.sourceName)} | ${_escape(r.kind)} |');
    }
    buf.writeln();
  }

  void _writeTimeline(StringBuffer buf, AnalysisResult result, DateFormat fmt) {
    if (result.suspicious.isEmpty) {
      buf.writeln('## Timeline');
      buf.writeln();
      buf.writeln('_No suspicious events detected._');
      buf.writeln();
      return;
    }
    final limit = rules.report.timelineLimit;
    final shown = result.suspicious.take(limit).toList();
    buf.writeln('## Timeline (first ${shown.length} of ${result.suspicious.length})');
    buf.writeln();
    buf.writeln('| Time | Severity | Source | Category | Excerpt |');
    buf.writeln('|---|---|---|---|---|');
    for (final s in shown) {
      buf.writeln(
          '| ${fmt.format(s.timestamp)} | ${s.severity.label} | ${_escape(s.sourceName)} | ${_escape(s.category)} | ${_escape(_clipExcerpt(s.excerpt))} |');
    }
    buf.writeln();
  }

  void _writeBySource(StringBuffer buf, AnalysisResult result, DateFormat fmt) {
    final groups = <String, List<SuspiciousEvent>>{};
    for (final s in result.suspicious) {
      groups.putIfAbsent('${s.sourceKind.label} · ${s.sourceName}', () => []).add(s);
    }
    if (groups.isEmpty) return;
    buf.writeln('## By source');
    buf.writeln();
    final keys = groups.keys.toList()..sort();
    for (final k in keys) {
      final events = groups[k]!;
      buf.writeln('### $k (${events.length})');
      buf.writeln();
      buf.writeln('| Time | Severity | Category | Excerpt |');
      buf.writeln('|---|---|---|---|');
      for (final s in events.take(50)) {
        buf.writeln(
            '| ${fmt.format(s.timestamp)} | ${s.severity.label} | ${_escape(s.category)} | ${_escape(_clipExcerpt(s.excerpt))} |');
      }
      if (events.length > 50) {
        buf.writeln();
        buf.writeln('_…${events.length - 50} more events suppressed._');
      }
      buf.writeln();
    }
  }

  void _writeTopSlowQueries(StringBuffer buf, AnalysisResult result, DateFormat fmt) {
    if (result.slowQueries.isEmpty) return;
    final top = [...result.slowQueries]
      ..sort((a, b) => b.queryTime.compareTo(a.queryTime));
    final shown = top.take(rules.slowQuery.topN).toList();
    buf.writeln('## Top ${shown.length} slow queries (by duration)');
    buf.writeln();
    buf.writeln('| Time | qt (s) | lock (s) | sent | examined | schema | SQL |');
    buf.writeln('|---|---:|---:|---:|---:|---|---|');
    for (final q in shown) {
      final sql = _clipExcerpt(q.content);
      buf.writeln(
          '| ${fmt.format(q.timestamp)} | ${q.queryTime.toStringAsFixed(3)} | ${q.lockTime.toStringAsFixed(3)} | ${q.rowsSent} | ${q.rowsExamined} | ${_escape(q.schema ?? '')} | ${_escape(sql)} |');
    }
    buf.writeln();
  }

  String _clipExcerpt(String s) {
    final compact = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final max = rules.report.excerptMaxChars;
    if (compact.length <= max) return compact;
    return '${compact.substring(0, max)}…';
  }

  String _escape(String s) {
    return s.replaceAll('|', r'\|').replaceAll('\n', ' ');
  }

  String _fmtRange(DateTime? from, DateTime? to, DateFormat fmt) {
    if (from == null && to == null) return '_open_';
    return '${from != null ? fmt.format(from) : '−∞'} → ${to != null ? fmt.format(to) : '+∞'}';
  }
}
