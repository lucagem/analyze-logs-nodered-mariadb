import 'dart:io';

import '../models/log_event.dart';
import '../models/log_source.dart';

/// Parses the Docker-container CSV format used for both MariaDB and Node-RED logs.
///
/// Layout:
///   line 1: free-form container name (e.g. `gi4_mariadb`) — skipped
///   line 2: header `date,stream,content`
///   following: rows of `<yyyy/MM/dd HH:mm:ss>,(stdout|stderr),<content>`
///
/// We do NOT use a generic CSV parser here. The container exports
/// frequently contain unbalanced double-quotes inside the `content` field
/// (TLS certificates, JSON snippets, MSSQL connection strings with embedded
/// commas) which confuse standard CSV quoting and cause whole blocks to be
/// merged into a single field — losing genuine events such as `[error]`
/// lines or MSSQL disconnect notices.
///
/// Instead we anchor on the line prefix `YYYY/MM/DD HH:MM:SS,(stdout|stderr),`
/// to detect a new record. Lines that don't match that prefix are treated
/// as continuations of the previous record's `content`.
class ContainerCsvParser {
  ContainerCsvParser({required this.kind});

  final LogSourceKind kind;

  /// Matches a record header at the start of a line:
  /// `2026/05/04 10:43:27,stdout,…`
  static final _recordStart =
      RegExp(r'^(\d{4})/(\d{2})/(\d{2})\s(\d{2}):(\d{2}):(\d{2}),(stdout|stderr),(.*)$');

  Future<ParsedContainerLog> parseFile(File file) async {
    final raw = await file.readAsString();
    return parseString(raw, sourceName: _baseName(file.path));
  }

  ParsedContainerLog parseString(String raw, {required String sourceName}) {
    final lines = raw.replaceAll('\r\n', '\n').split('\n');

    final events = <LogEvent>[];
    final warnings = <String>[];
    final skippedSamples = <String>[];
    var skipped = 0;
    var sawHeader = false;

    DateTime? curTs;
    String? curStream;
    final curContent = StringBuffer();

    void flush() {
      if (curTs == null) return;
      events.add(LogEvent(
        timestamp: curTs!,
        sourceKind: kind,
        sourceName: sourceName,
        content: curContent.toString(),
        stream: curStream,
      ));
      curTs = null;
      curStream = null;
      curContent.clear();
    }

    void recordSkip(String reason, String line) {
      skipped++;
      if (skippedSamples.length < 3) {
        final clean = line.length > 200 ? '${line.substring(0, 200)}…' : line;
        skippedSamples.add('$reason — $clean');
      }
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) continue;

      // Skip the optional first-line container name and the CSV header.
      if (i < 4) {
        final lower = trimmed.toLowerCase();
        if (lower == 'date,stream,content') {
          sawHeader = true;
          continue;
        }
        if (i == 0 && !_recordStart.hasMatch(trimmed)) {
          // Free-form container name on the first line — skip silently.
          continue;
        }
      }

      final m = _recordStart.firstMatch(trimmed);
      if (m != null) {
        // New record — flush the previous one.
        flush();
        final y = int.parse(m.group(1)!);
        final mo = int.parse(m.group(2)!);
        final d = int.parse(m.group(3)!);
        final h = int.parse(m.group(4)!);
        final mi = int.parse(m.group(5)!);
        final s = int.parse(m.group(6)!);
        curTs = DateTime(y, mo, d, h, mi, s);
        curStream = m.group(7);
        curContent.clear();
        curContent.write(m.group(8) ?? '');
        continue;
      }

      // Not a record header — treat as continuation of the current content
      // (typical for multi-line certificates, JSON, etc.).
      if (curTs != null) {
        if (curContent.isNotEmpty) curContent.write('\n');
        curContent.write(trimmed);
        continue;
      }

      // No active record yet and the line doesn't start with a timestamp:
      // this is genuinely malformed (or noise before the first record).
      recordSkip('line has no leading timestamp prefix', trimmed);
    }

    flush();

    if (!sawHeader) {
      warnings.add('CSV header not found in $sourceName; assumed records were '
          'parsed by line prefix.');
    }
    if (skipped > 0) {
      warnings.add('$sourceName: skipped $skipped malformed lines.');
    }

    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return ParsedContainerLog(
      events: events,
      warnings: warnings,
      skippedRows: skipped,
      skippedSamples: skippedSamples,
    );
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
