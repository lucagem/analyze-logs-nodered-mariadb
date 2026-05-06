import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/analysis_result.dart';
import '../models/severity.dart';
import '../models/suspicious_event.dart';

class AnthropicClient {
  AnthropicClient({
    required this.apiKey,
    required this.model,
    this.baseUrl = 'https://api.anthropic.com/v1/messages',
    this.maxTokens = 1500,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String apiKey;
  final String model;
  final String baseUrl;
  final int maxTokens;
  final http.Client _http;

  /// Asks Claude for a short executive summary + likely root causes
  /// based on a *digest* of the analysis (never the raw log lines).
  Future<String> generateInsights(AnalysisResult result) async {
    final digest = _buildDigest(result);

    final body = jsonEncode({
      'model': model,
      'max_tokens': maxTokens,
      'system':
          'You are a senior site-reliability engineer. Given a digest of suspicious '
              'events from MariaDB and Node-RED container logs, write a concise '
              'Markdown analysis with three sections: '
              '"### Executive summary" (3-5 bullets), '
              '"### Likely root causes" (ranked, each with one-line evidence), and '
              '"### Recommended next steps" (actionable bullets). '
              'Be specific; cite categories or timestamps from the digest. '
              'Do not invent events that are not in the digest.',
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': digest,
            },
          ],
        },
      ],
    });

    final response = await _http.post(
      Uri.parse(baseUrl),
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw AnthropicException(
        'Anthropic API error ${response.statusCode}: ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final content = decoded['content'] as List<dynamic>?;
    if (content == null || content.isEmpty) {
      throw AnthropicException('Anthropic API returned no content.');
    }
    final buf = StringBuffer();
    for (final block in content) {
      if (block is Map<String, dynamic> && block['type'] == 'text') {
        buf.write(block['text']);
      }
    }
    return buf.toString().trim();
  }

  String _buildDigest(AnalysisResult result) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final buf = StringBuffer();
    buf.writeln('## Analysis digest');
    buf.writeln('Effective range: '
        '${result.effectiveFrom != null ? fmt.format(result.effectiveFrom!) : '−∞'} '
        '→ ${result.effectiveTo != null ? fmt.format(result.effectiveTo!) : '+∞'}');
    buf.writeln();

    final bySev = <Severity, int>{};
    for (final s in result.suspicious) {
      bySev[s.severity] = (bySev[s.severity] ?? 0) + 1;
    }
    buf.writeln('Severity totals: '
        'CRITICAL=${bySev[Severity.critical] ?? 0}, '
        'ERROR=${bySev[Severity.error] ?? 0}, '
        'WARN=${bySev[Severity.warn] ?? 0}.');
    buf.writeln();

    final byCategory = <String, List<SuspiciousEvent>>{};
    for (final s in result.suspicious) {
      byCategory.putIfAbsent(s.category, () => []).add(s);
    }
    final cats = byCategory.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    buf.writeln('### Top categories');
    for (final entry in cats.take(15)) {
      final firstTs = entry.value.first.timestamp;
      final lastTs = entry.value.last.timestamp;
      buf.writeln('- **${entry.key}** — ${entry.value.length} events '
          '(${fmt.format(firstTs)} → ${fmt.format(lastTs)})');
      // Sample two excerpts.
      for (final s in entry.value.take(2)) {
        final excerpt = s.excerpt.length > 200
            ? '${s.excerpt.substring(0, 200)}…'
            : s.excerpt;
        buf.writeln('  - [${fmt.format(s.timestamp)}] ${s.sourceName}: $excerpt');
      }
    }
    buf.writeln();

    if (result.restarts.isNotEmpty) {
      buf.writeln('### Lifecycle events');
      for (final r in result.restarts.take(20)) {
        buf.writeln('- ${fmt.format(r.timestamp)} · ${r.sourceKind.label} · ${r.sourceName} · ${r.kind}');
      }
      buf.writeln();
    }

    if (result.slowQueries.isNotEmpty) {
      final top = [...result.slowQueries]
        ..sort((a, b) => b.queryTime.compareTo(a.queryTime));
      buf.writeln('### Top 10 slow queries');
      for (final q in top.take(10)) {
        final sql = q.content.replaceAll(RegExp(r'\s+'), ' ').trim();
        final clipped = sql.length > 300 ? '${sql.substring(0, 300)}…' : sql;
        buf.writeln(
            '- [${fmt.format(q.timestamp)}] qt=${q.queryTime.toStringAsFixed(3)}s '
            'rows ${q.rowsSent}/${q.rowsExamined} · $clipped');
      }
    }

    return buf.toString();
  }

  void close() => _http.close();
}

class AnthropicException implements Exception {
  AnthropicException(this.message);
  final String message;
  @override
  String toString() => message;
}
