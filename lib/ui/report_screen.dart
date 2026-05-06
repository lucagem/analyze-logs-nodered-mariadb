import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../models/analysis_result.dart';
import '../models/log_event.dart';
import '../models/log_source.dart';
import '../models/severity.dart';
import '../models/suspicious_event.dart';
import '../services/file_opener.dart';
import '../services/settings_service.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({
    super.key,
    required this.result,
    required this.markdown,
    required this.settings,
    this.aiInsights,
  });

  final AnalysisResult result;
  final String markdown;
  final SettingsService settings;
  final String? aiInsights;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  static final _tsFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
  String? _savedPath;
  bool _saving = false;

  /// Dark red used to highlight CRITICAL / ERROR rows.
  static const _critBg = Color(0xFF7A0E15); // very dark red
  static const _errBg = Color(0xFF9A1B22); // dark red
  static const _warnBg = Color(0xFFB07A00); // amber/dark yellow
  static const _highlightFg = Colors.white;

  /// AX_LOG state-specific palette (cell background).
  static const _axOkBg = Color(0xFF1E6B37); // dark green
  static const _axDebugBg = Color(0xFF455A64); // blue-grey

  /// Returns the (background, foreground) pair for a suspicious event.
  /// AX rows are colored by their STATE value so OK/WARNING/ERROR/DEBUG are
  /// each visually distinct; non-AX rows fall back to severity-based colors.
  (Color, Color?) _rowColors(SuspiciousEvent ev) {
    if (ev.sourceKind == LogSourceKind.axLog) {
      final state = ev.metadata['state'];
      switch (state) {
        case 0:
          return (_axOkBg, _highlightFg);
        case 1:
          return (_warnBg, _highlightFg);
        case 2:
          return (_errBg, _highlightFg);
        case 3:
          return (_axDebugBg, _highlightFg);
      }
    }
    switch (ev.severity) {
      case Severity.critical:
        return (_critBg, _highlightFg);
      case Severity.error:
        return (_errBg, _highlightFg);
      case Severity.warn:
        return (_warnBg.withValues(alpha: 0.18), null);
      case Severity.info:
        return (Colors.transparent, null);
    }
  }

  Future<void> _saveToDisk() async {
    setState(() => _saving = true);
    try {
      final outDir = await widget.settings.resolveOutputDir();
      await outDir.create(recursive: true);
      final ts = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
      final file = File('${outDir.path}/report-$ts.md');
      await file.writeAsString(widget.markdown);
      if (!mounted) return;
      setState(() => _savedPath = file.path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to ${file.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openFolder() async {
    final saved = _savedPath;
    if (saved == null) return;
    final dir = File(saved).parent.path;
    try {
      await FileOpener().openDirectory(dir);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open folder: $e')),
      );
    }
  }

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.markdown));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Markdown copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis report'),
        actions: [
          IconButton(
            tooltip: 'Copy markdown',
            icon: const Icon(Icons.copy),
            onPressed: _copyToClipboard,
          ),
          IconButton(
            tooltip: 'Save to disk',
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt),
            onPressed: _saving ? null : _saveToDisk,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_savedPath != null)
            Container(
              width: double.infinity,
              color: Colors.green.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Saved: $_savedPath',
                        style: const TextStyle(fontSize: 12)),
                  ),
                  TextButton.icon(
                    onPressed: _openFolder,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Open folder'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _header(r),
                const SizedBox(height: 24),
                _summary(r),
                const SizedBox(height: 24),
                _lifecycle(r),
                const SizedBox(height: 24),
                _timeline(r),
                const SizedBox(height: 24),
                _slowQueries(r),
                if (widget.aiInsights != null) ...[
                  const SizedBox(height: 24),
                  Text('AI Insights', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  MarkdownBlock(data: widget.aiInsights!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(AnalysisResult r) {
    final effFrom = r.effectiveFrom != null ? _tsFmt.format(r.effectiveFrom!) : '−∞';
    final effTo = r.effectiveTo != null ? _tsFmt.format(r.effectiveTo!) : '+∞';
    final reqFrom = r.requestedFrom != null ? _tsFmt.format(r.requestedFrom!) : '−∞';
    final reqTo = r.requestedTo != null ? _tsFmt.format(r.requestedTo!) : '+∞';
    final clipped = _rangeWasClipped(r);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Log Analysis Report',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Generated: ${_tsFmt.format(r.generatedAt)}'),
            if (r.requestedFrom != null || r.requestedTo != null)
              Text('Requested range: $reqFrom → $reqTo'),
            Text('Effective range: $effFrom → $effTo'),
            Text('Lines parsed: ${r.totalLinesParsed}'),
            ..._folderLines(r),
            if (clipped) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'The effective range is narrower than requested because at least one '
                  'source has no events outside it — see the table below.',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _sourcesTable(r),
            if (r.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r.warnings.length} parser warning(s):',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    for (final w in r.warnings) Text('• $w'),
                  ],
                ),
              ),
            ],
            if (r.sourceStats.any((s) => s.skippedSamples.isNotEmpty)) ...[
              const SizedBox(height: 12),
              _parserIssues(r),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _folderLines(AnalysisResult r) {
    final folders = <String>{};
    for (final s in r.sources) {
      var idx = s.path.lastIndexOf(r'\');
      final fwd = s.path.lastIndexOf('/');
      if (fwd > idx) idx = fwd;
      if (idx > 0) folders.add(s.path.substring(0, idx));
    }
    if (folders.isEmpty) return const [];
    final sorted = folders.toList()..sort();
    if (sorted.length == 1) {
      return [
        SelectableText('Source folder: ${sorted.first}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ];
    }
    return [
      const Text('Source folders:'),
      for (final f in sorted)
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: SelectableText('• $f',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
    ];
  }

  bool _rangeWasClipped(AnalysisResult r) {
    if (r.requestedFrom != null &&
        r.effectiveFrom != null &&
        r.effectiveFrom!.isAfter(r.requestedFrom!)) {
      return true;
    }
    if (r.requestedTo != null &&
        r.effectiveTo != null &&
        r.effectiveTo!.isBefore(r.requestedTo!)) {
      return true;
    }
    return false;
  }

  Widget _sourcesTable(AnalysisResult r) {
    if (r.sourceStats.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: DataTable(
        headingRowHeight: 32,
        dataRowMinHeight: 28,
        dataRowMaxHeight: 36,
        columnSpacing: 14,
        columns: const [
          DataColumn(label: Text('File')),
          DataColumn(label: Text('Type')),
          DataColumn(label: Text('Total'), numeric: true),
          DataColumn(label: Text('Min ts')),
          DataColumn(label: Text('Max ts')),
          DataColumn(label: Text('In range'), numeric: true),
          DataColumn(label: Text('Skipped'), numeric: true),
        ],
        rows: [
          for (final s in r.sourceStats)
            DataRow(cells: [
              DataCell(Tooltip(message: s.displayName, child: Text(s.displayName))),
              DataCell(Text(s.kind.label)),
              DataCell(Text('${s.totalEvents}')),
              DataCell(Text(s.minTimestamp != null ? _tsFmt.format(s.minTimestamp!) : '—')),
              DataCell(Text(s.maxTimestamp != null ? _tsFmt.format(s.maxTimestamp!) : '—')),
              DataCell(Text('${s.eventsInRange}',
                  style: TextStyle(
                      color: s.eventsInRange == 0 ? Colors.red.shade700 : null,
                      fontWeight: s.eventsInRange == 0 ? FontWeight.w600 : null))),
              DataCell(Text('${s.skippedRows}',
                  style: TextStyle(
                      color: s.skippedRows > 0 ? Colors.orange.shade700 : null))),
            ]),
        ],
      ),
    );
  }

  Widget _parserIssues(AnalysisResult r) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.06),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Parser issues',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Rows the parser had to discard. Typical causes: unparseable dates '
            '(continuation rows of multi-line content) or rows truncated '
            'mid-export.',
            style: TextStyle(fontSize: 12, color: Colors.black87),
          ),
          const SizedBox(height: 8),
          for (final s in r.sourceStats)
            if (s.skippedSamples.isNotEmpty) ...[
              Text('${s.displayName} — ${s.skippedRows} skipped',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              for (final sample in s.skippedSamples)
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
                  child: SelectableText('• $sample',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                ),
              const SizedBox(height: 6),
            ],
        ],
      ),
    );
  }

  Widget _summary(AnalysisResult r) {
    final bySev = <Severity, int>{};
    for (final s in r.suspicious) {
      bySev[s.severity] = (bySev[s.severity] ?? 0) + 1;
    }
    final byCategory = <String, int>{};
    for (final s in r.suspicious) {
      byCategory[s.category] = (byCategory[s.category] ?? 0) + 1;
    }
    final cats = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Summary', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _sevBadge(Severity.critical, bySev[Severity.critical] ?? 0),
                _sevBadge(Severity.error, bySev[Severity.error] ?? 0),
                _sevBadge(Severity.warn, bySev[Severity.warn] ?? 0),
                _sevBadge(Severity.info, bySev[Severity.info] ?? 0),
                _totalBadge(r.suspicious.length),
              ],
            ),
            if (cats.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('By category', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (final entry in cats)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      Expanded(child: Text(entry.key)),
                      Text('${entry.value}',
                          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _lifecycle(AnalysisResult r) {
    if (r.restarts.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lifecycle events (${r.restarts.length})',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            DataTable(
              headingRowHeight: 32,
              dataRowMinHeight: 28,
              dataRowMaxHeight: 36,
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('Time')),
                DataColumn(label: Text('Source')),
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Event')),
              ],
              rows: [
                for (final ev in r.restarts)
                  DataRow(cells: [
                    DataCell(Text(_tsFmt.format(ev.timestamp))),
                    DataCell(Text(ev.sourceKind.label)),
                    DataCell(Text(ev.sourceName)),
                    DataCell(Text(ev.kind)),
                  ]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeline(AnalysisResult r) {
    if (r.suspicious.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('No suspicious events detected.',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
    }
    final shown = r.suspicious.take(200).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Timeline (${shown.length} of ${r.suspicious.length})',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _legendChip('CRITICAL', _critBg, _highlightFg),
                _legendChip('ERROR', _errBg, _highlightFg),
                _legendChip('WARN', _warnBg, _highlightFg),
                _legendChip('AX OK', _axOkBg, _highlightFg),
                _legendChip('AX DEBUG', _axDebugBg, _highlightFg),
              ],
            ),
            const SizedBox(height: 8),
            for (final ev in shown) _timelineRow(ev),
          ],
        ),
      ),
    );
  }

  Widget _timelineRow(SuspiciousEvent ev) {
    final (bg, fg) = _rowColors(ev);
    final excerpt = ev.excerpt.length > 400
        ? '${ev.excerpt.substring(0, 400)}…'
        : ev.excerpt;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: fg, fontSize: 12.5, height: 1.3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(_tsFmt.format(ev.timestamp),
                  style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
            ),
            SizedBox(
              width: 75,
              child: Text(ev.severity.label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            SizedBox(
              width: 170,
              child: Text(ev.sourceName, overflow: TextOverflow.ellipsis),
            ),
            SizedBox(
              width: 170,
              child: Text(ev.category, overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              child: SelectableText(excerpt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slowQueries(AnalysisResult r) {
    if (r.slowQueries.isEmpty) return const SizedBox.shrink();
    final top = [...r.slowQueries]
      ..sort((a, b) => b.queryTime.compareTo(a.queryTime));
    final shown = top.take(20).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Top ${shown.length} slow queries (by duration)',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final q in shown) _slowQueryRow(q),
          ],
        ),
      ),
    );
  }

  Widget _slowQueryRow(SlowQueryEvent q) {
    final sql = q.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    final sample = sql.length > 240 ? '${sql.substring(0, 240)}…' : sql;
    final bg = q.queryTime >= 5
        ? _errBg
        : (q.queryTime >= 1
            ? _warnBg.withValues(alpha: 0.2)
            : Colors.transparent);
    final fg = q.queryTime >= 5 ? _highlightFg : null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: fg, fontSize: 12.5, height: 1.3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(_tsFmt.format(q.timestamp)),
            ),
            SizedBox(
              width: 80,
              child: Text('qt ${q.queryTime.toStringAsFixed(2)}s',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            SizedBox(
              width: 110,
              child: Text('rows ${q.rowsSent}/${q.rowsExamined}'),
            ),
            Expanded(child: SelectableText(sample)),
          ],
        ),
      ),
    );
  }

  Widget _sevBadge(Severity sev, int count) {
    final (bg, fg) = switch (sev) {
      Severity.critical => (_critBg, _highlightFg),
      Severity.error => (_errBg, _highlightFg),
      Severity.warn => (_warnBg, _highlightFg),
      Severity.info => (Colors.grey.shade300, Colors.black87),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text('${sev.label}: $count',
          style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
    );
  }

  Widget _legendChip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _totalBadge(int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text('TOTAL: $total',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    );
  }
}
