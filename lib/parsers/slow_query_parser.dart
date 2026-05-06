import 'dart:io';

import '../models/log_event.dart';

/// Parses MariaDB / MySQL slow query log files.
///
/// Each entry is a block of lines starting with `# Time: YYMMDD HH:MM:SS`
/// (a block may inherit the previous time when omitted), followed by
/// `# User@Host:`, `# Thread_id:`, `# Query_time:` etc., then `SET timestamp=…`
/// and the SQL text. Server banner lines (`mariadbd, Version: …`, `Tcp port: …`,
/// `Time	Id Command	Argument`) are treated as restart markers.
class SlowQueryParser {
  static final _timeRegex = RegExp(r'^#\s*Time:\s*(\d{6})\s+(\d{1,2}):(\d{2}):(\d{2})');
  static final _userHostRegex =
      RegExp(r'^#\s*User@Host:\s*([^\[]+)\[[^\]]*\]\s*@\s*([^\s]*)\s*\[?([^\]]*)\]?');
  static final _threadSchemaRegex =
      RegExp(r'^#\s*Thread_id:\s*(\d+)\s*Schema:\s*(\S+)');
  static final _queryTimeRegex = RegExp(
      r'^#\s*Query_time:\s*([\d.]+)\s*Lock_time:\s*([\d.]+)\s*Rows_sent:\s*(\d+)\s*Rows_examined:\s*(\d+)');
  static final _rowsAffectedRegex =
      RegExp(r'^#\s*Rows_affected:\s*(\d+)(?:\s*Bytes_sent:\s*(\d+))?');
  static final _setTimestampRegex = RegExp(r'^SET timestamp=(\d+)');
  static final _useSchemaRegex = RegExp(r'^use\s+`?([^`;\s]+)`?\s*;', caseSensitive: false);

  Future<ParsedSlowLog> parseFile(File file) async {
    final lines = await file.readAsLines();
    return parseLines(lines, sourceName: _baseName(file.path));
  }

  ParsedSlowLog parseLines(List<String> lines, {required String sourceName}) {
    final events = <SlowQueryEvent>[];
    final restartTimestamps = <DateTime>[];
    final warnings = <String>[];

    DateTime? currentTime;
    String? user;
    String? hostFromUser;
    String? hostBracket;
    int? threadId;
    String? schema;
    double? queryTime;
    double? lockTime;
    int? rowsSent;
    int? rowsExamined;
    int? rowsAffected;
    int? setTimestampEpoch;
    final sqlBuffer = StringBuffer();
    var inSql = false;
    var pendingRestart = false;

    void flushBlock() {
      if (queryTime == null) {
        sqlBuffer.clear();
        inSql = false;
        return;
      }
      final ts = setTimestampEpoch != null
          ? DateTime.fromMillisecondsSinceEpoch(setTimestampEpoch! * 1000, isUtc: false)
          : currentTime;
      if (ts == null) {
        sqlBuffer.clear();
        inSql = false;
        queryTime = null;
        return;
      }
      events.add(SlowQueryEvent(
        timestamp: ts,
        sourceName: sourceName,
        content: sqlBuffer.toString().trim(),
        queryTime: queryTime!,
        lockTime: lockTime ?? 0,
        rowsSent: rowsSent ?? 0,
        rowsExamined: rowsExamined ?? 0,
        rowsAffected: rowsAffected ?? 0,
        user: user ?? '',
        host: hostBracket?.isNotEmpty == true ? hostBracket! : (hostFromUser ?? ''),
        schema: schema,
        threadId: threadId,
      ));
      // Reset block accumulators (timing fields), but keep currentTime/schema as ambient.
      queryTime = null;
      lockTime = null;
      rowsSent = null;
      rowsExamined = null;
      rowsAffected = null;
      setTimestampEpoch = null;
      sqlBuffer.clear();
      inSql = false;
    }

    for (final raw in lines) {
      final line = raw;

      if (line.startsWith('mariadbd,') ||
          line.startsWith('mysqld,') ||
          line.startsWith('Tcp port:') ||
          line.startsWith('Time\t')) {
        flushBlock();
        pendingRestart = true;
        continue;
      }

      if (line.startsWith('# Time:')) {
        flushBlock();
        final m = _timeRegex.firstMatch(line);
        if (m != null) {
          final yymmdd = m.group(1)!;
          final yy = int.parse(yymmdd.substring(0, 2));
          final year = yy < 70 ? 2000 + yy : 1900 + yy;
          final mo = int.parse(yymmdd.substring(2, 4));
          final d = int.parse(yymmdd.substring(4, 6));
          final h = int.parse(m.group(2)!);
          final mi = int.parse(m.group(3)!);
          final s = int.parse(m.group(4)!);
          currentTime = DateTime(year, mo, d, h, mi, s);
          if (pendingRestart) {
            restartTimestamps.add(currentTime);
            pendingRestart = false;
          }
        }
        continue;
      }

      if (line.startsWith('# User@Host:')) {
        final m = _userHostRegex.firstMatch(line);
        if (m != null) {
          user = m.group(1)?.trim();
          hostFromUser = m.group(2)?.trim();
          hostBracket = m.group(3)?.trim();
        }
        continue;
      }

      if (line.startsWith('# Thread_id:')) {
        final m = _threadSchemaRegex.firstMatch(line);
        if (m != null) {
          threadId = int.tryParse(m.group(1)!);
          schema = m.group(2);
        }
        continue;
      }

      if (line.startsWith('# Query_time:')) {
        final m = _queryTimeRegex.firstMatch(line);
        if (m != null) {
          queryTime = double.tryParse(m.group(1)!) ?? 0;
          lockTime = double.tryParse(m.group(2)!) ?? 0;
          rowsSent = int.tryParse(m.group(3)!) ?? 0;
          rowsExamined = int.tryParse(m.group(4)!) ?? 0;
        }
        continue;
      }

      if (line.startsWith('# Rows_affected:')) {
        final m = _rowsAffectedRegex.firstMatch(line);
        if (m != null) {
          rowsAffected = int.tryParse(m.group(1)!) ?? 0;
        }
        continue;
      }

      if (line.startsWith('SET timestamp=')) {
        final m = _setTimestampRegex.firstMatch(line);
        if (m != null) {
          setTimestampEpoch = int.tryParse(m.group(1)!);
        }
        inSql = true;
        continue;
      }

      final useMatch = _useSchemaRegex.firstMatch(line);
      if (useMatch != null) {
        schema = useMatch.group(1);
        inSql = true;
        continue;
      }

      if (line.startsWith('# ')) {
        // Unknown comment line — ignore.
        continue;
      }

      if (inSql || queryTime != null) {
        if (sqlBuffer.isNotEmpty) sqlBuffer.write('\n');
        sqlBuffer.write(line);
      }
    }
    flushBlock();

    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return ParsedSlowLog(
      events: events,
      restarts: restartTimestamps,
      warnings: warnings,
      sourceName: sourceName,
    );
  }

  static String _baseName(String path) {
    final unix = path.replaceAll('\\', '/');
    final idx = unix.lastIndexOf('/');
    return idx == -1 ? unix : unix.substring(idx + 1);
  }
}

class ParsedSlowLog {
  ParsedSlowLog({
    required this.events,
    required this.restarts,
    required this.warnings,
    required this.sourceName,
  });

  final List<SlowQueryEvent> events;
  final List<DateTime> restarts;
  final List<String> warnings;
  final String sourceName;
}
