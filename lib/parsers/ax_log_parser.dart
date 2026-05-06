import 'dart:io';

import 'package:csv/csv.dart';

import '../models/log_event.dart';

/// Parses AX_LOG CSV exports.
///
/// Header (line 1):
///   `ID,DATE_TIME_LOG,MESSAGE,UNIT_NAME,ROUTINE_NAME,KEY_TAG,STATE`
/// Date format: `dd/MM/yyyy HH:mm:ss` (Italian).
/// STATE: 0=OK, 1=WARNING, 2=ERROR, 3=DEBUG.
class AxLogParser {
  static const _converter = CsvToListConverter(
    fieldDelimiter: ',',
    eol: '\n',
    shouldParseNumbers: false,
  );

  Future<ParsedAxLog> parseFile(File file) async {
    final raw = await file.readAsString();
    return parseString(raw, sourceName: _baseName(file.path));
  }

  ParsedAxLog parseString(String raw, {required String sourceName}) {
    final normalized = raw.replaceAll('\r\n', '\n');
    final rows = _converter.convert(normalized);
    final events = <AxLogEvent>[];
    final warnings = <String>[];
    final skippedSamples = <String>[];
    var skipped = 0;

    if (rows.isEmpty) {
      return ParsedAxLog(
        events: events,
        warnings: warnings,
        skippedRows: 0,
        skippedSamples: skippedSamples,
      );
    }

    final header = rows.first.map((e) => e.toString().trim().toUpperCase()).toList();
    final colId = header.indexOf('ID');
    final colDate = header.indexOf('DATE_TIME_LOG');
    final colMsg = header.indexOf('MESSAGE');
    final colUnit = header.indexOf('UNIT_NAME');
    final colRoutine = header.indexOf('ROUTINE_NAME');
    final colKey = header.indexOf('KEY_TAG');
    final colState = header.indexOf('STATE');

    if (colDate < 0 || colMsg < 0 || colState < 0) {
      warnings.add(
          '$sourceName: missing required columns (DATE_TIME_LOG/MESSAGE/STATE).');
      return ParsedAxLog(
        events: events,
        warnings: warnings,
        skippedRows: 0,
        skippedSamples: skippedSamples,
      );
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

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length <= colState) {
        if (row.every((c) => c.toString().trim().isEmpty)) continue;
        recordSkip('row has fewer than ${colState + 1} columns', row);
        continue;
      }

      final dateStr = row[colDate].toString().trim();
      final ts = _tryParseDate(dateStr);
      if (ts == null) {
        recordSkip('unparseable date "$dateStr"', row);
        continue;
      }

      final stateStr = row[colState].toString().trim();
      final state = int.tryParse(stateStr);
      if (state == null) {
        recordSkip('non-numeric STATE "$stateStr"', row);
        continue;
      }

      events.add(AxLogEvent(
        timestamp: ts,
        sourceName: sourceName,
        content: colMsg < row.length ? row[colMsg].toString() : '',
        state: state,
        unitName: colUnit >= 0 && colUnit < row.length
            ? row[colUnit].toString().trim()
            : '',
        routineName: colRoutine >= 0 && colRoutine < row.length
            ? row[colRoutine].toString().trim()
            : '',
        keyTag: colKey >= 0 && colKey < row.length
            ? row[colKey].toString().trim()
            : null,
        recordId: colId >= 0 && colId < row.length
            ? row[colId].toString().trim()
            : null,
      ));
    }

    if (skipped > 0) {
      warnings.add('$sourceName: skipped $skipped malformed rows.');
    }

    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return ParsedAxLog(
      events: events,
      warnings: warnings,
      skippedRows: skipped,
      skippedSamples: skippedSamples,
    );
  }

  static DateTime? _tryParseDate(String value) {
    // Format: 06/05/2026 06:30:03
    if (value.length < 19) return null;
    try {
      final d = int.parse(value.substring(0, 2));
      final mo = int.parse(value.substring(3, 5));
      final y = int.parse(value.substring(6, 10));
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

class ParsedAxLog {
  ParsedAxLog({
    required this.events,
    required this.warnings,
    required this.skippedRows,
    required this.skippedSamples,
  });

  final List<AxLogEvent> events;
  final List<String> warnings;
  final int skippedRows;
  final List<String> skippedSamples;
}
