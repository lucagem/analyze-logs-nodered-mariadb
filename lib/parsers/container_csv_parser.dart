import 'dart:io';

import 'package:csv/csv.dart';

import '../models/log_event.dart';
import '../models/log_source.dart';

/// Parses the Docker-container CSV format used for both MariaDB and Node-RED logs.
///
/// Layout:
///   line 1: free-form container name (e.g. `gi4_mariadb`) — skipped
///   line 2: header `date,stream,content`
///   following: rows where `content` may span multiple lines (CSV-quoted).
///
/// Date column is `yyyy/MM/dd HH:mm:ss`.
class ContainerCsvParser {
  ContainerCsvParser({required this.kind});

  final LogSourceKind kind;

  static const _converter = CsvToListConverter(
    fieldDelimiter: ',',
    eol: '\n',
    shouldParseNumbers: false,
  );

  Future<ParsedContainerLog> parseFile(File file) async {
    final raw = await file.readAsString();
    return parseString(raw, sourceName: _baseName(file.path));
  }

  ParsedContainerLog parseString(String raw, {required String sourceName}) {
    final normalized = raw.replaceAll('\r\n', '\n');
    final rows = _converter.convert(normalized);
    final events = <LogEvent>[];
    final warnings = <String>[];
    final skippedSamples = <String>[];
    var skipped = 0;

    var headerIndex = -1;
    for (var i = 0; i < rows.length && i < 5; i++) {
      final row = rows[i].map((e) => e.toString().trim()).toList();
      if (row.length >= 3 &&
          row[0].toLowerCase() == 'date' &&
          row[1].toLowerCase() == 'stream' &&
          row[2].toLowerCase() == 'content') {
        headerIndex = i;
        break;
      }
    }
    if (headerIndex == -1) {
      warnings.add('CSV header not found in $sourceName; assuming row 0 is data.');
      headerIndex = -1;
    }

    void recordSkip(String reason, List<dynamic> row) {
      skipped++;
      if (skippedSamples.length < 3) {
        final flat = row
            .map((c) => c.toString().replaceAll('\n', ' ').replaceAll('\r', ''))
            .join(' | ');
        final clipped = flat.length > 200 ? '${flat.substring(0, 200)}…' : flat;
        skippedSamples.add('$reason — $clipped');
      }
    }

    for (var i = headerIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 3) {
        if (row.every((c) => c.toString().trim().isEmpty)) continue;
        recordSkip('row has fewer than 3 columns', row);
        continue;
      }
      final dateStr = row[0].toString().trim();
      final stream = row[1].toString().trim();
      final content = row[2].toString();

      if (dateStr.isEmpty && stream.isEmpty && content.trim().isEmpty) continue;

      final ts = _tryParseDate(dateStr);
      if (ts == null) {
        recordSkip('unparseable date "$dateStr"', row);
        continue;
      }

      events.add(LogEvent(
        timestamp: ts,
        sourceKind: kind,
        sourceName: sourceName,
        content: content,
        stream: stream.isEmpty ? null : stream,
      ));
    }

    if (skipped > 0) {
      warnings.add('$sourceName: skipped $skipped malformed rows.');
    }

    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return ParsedContainerLog(
      events: events,
      warnings: warnings,
      skippedRows: skipped,
      skippedSamples: skippedSamples,
    );
  }

  static DateTime? _tryParseDate(String value) {
    // Format: 2026/05/05 06:44:49
    if (value.length < 19) return null;
    try {
      final y = int.parse(value.substring(0, 4));
      final mo = int.parse(value.substring(5, 7));
      final d = int.parse(value.substring(8, 10));
      final h = int.parse(value.substring(11, 13));
      final mi = int.parse(value.substring(14, 16));
      final s = int.parse(value.substring(17, 19));
      return DateTime(y, mo, d, h, mi, s);
    } catch (_) {
      return null;
    }
  }

  static String _baseName(String path) {
    final unix = path.replaceAll('\\', '/');
    final idx = unix.lastIndexOf('/');
    return idx == -1 ? unix : unix.substring(idx + 1);
  }
}

class ParsedContainerLog {
  ParsedContainerLog({
    required this.events,
    required this.warnings,
    required this.skippedRows,
    required this.skippedSamples,
  });

  final List<LogEvent> events;
  final List<String> warnings;
  final int skippedRows;
  final List<String> skippedSamples;
}
