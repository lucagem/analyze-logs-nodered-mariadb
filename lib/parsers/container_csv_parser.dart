import 'dart:io';

import '../models/log_event.dart';
import '../models/log_source.dart';

/// Parses several flavors of MariaDB / Node-RED container logs.
///
/// Three formats are handled — the parser sniffs the first ~50 lines and
/// commits to the one whose record header matches:
///
///   1. **Docker-container CSV** (the canonical export):
///      `2026/05/04 10:43:27,stdout,…`
///   2. **MariaDB plain log** (raw `mariadbd` output, no CSV wrapper):
///      `2026-05-04 10:58:20 16 [Warning] Aborted connection 16 to db: 'GI4'…`
///   3. **Node-RED plain log** (raw `node-red` output, no year in the line):
///      `4 May 14:19:19 - [info] Server now running at http://127.0.0.1:1880/`
///
/// We do NOT use a generic CSV parser. The container exports frequently
/// contain unbalanced double-quotes inside the `content` field (TLS
/// certificates, JSON snippets, MSSQL connection strings with embedded
/// commas) which confuse standard CSV quoting and merge whole blocks into
/// one field. Anchoring on the format-specific record-header regex avoids
/// that.
///
/// Lines that do not start with a record header are either:
///   - **continuations** of the current event (multi-line certs, banners,
///     stack traces) — appended to the open record's content;
///   - **orphans** that appear before any record header (e.g. Node-RED
///     pre-startup `[appParams] Overridden from ENV: …` banners). Each
///     orphan becomes its own [LogEvent] with a *synthetic* timestamp
///     interpolated between the previous and next real timestamps; the
///     event is flagged via [LogEvent.synthetic] so the UI can mark it.
class ContainerCsvParser {
  ContainerCsvParser({required this.kind});

  final LogSourceKind kind;

  /// Docker-CSV record header: `2026/05/04 10:43:27,stdout,…`
  static final _csvStart =
      RegExp(r'^(\d{4})/(\d{2})/(\d{2})\s(\d{2}):(\d{2}):(\d{2}),(stdout|stderr),(.*)$');

  /// MariaDB plain log. Two variants:
  ///   `2026-05-04 10:58:20 16 [Warning] Aborted connection 16 …`
  ///   `2026-05-04 13:29:17+02:00 [Note] [Entrypoint]: …`
  /// We require a `[Level]` tag (optionally preceded by a thread-id) to
  /// avoid false matches against ISO dates that appear inside payload
  /// text (SQL literals, error bodies, etc.).
  static final _mariadbStart = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})\s(\d{2}):(\d{2}):(\d{2})(?:[+-]\d{2}:?\d{2}|Z)?\s+(?:\d+\s+)?\[[A-Za-z]+\].*$');

  /// Node-RED plain log: `4 May 14:19:19 - [info] …`
  static final _noderedStart = RegExp(
      r'^(\d{1,2})\s(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s(\d{2}):(\d{2}):(\d{2})\s+-\s+(.*)$');

  /// Year hint for Node-RED lines (which carry no year). Extracted from
  /// the source filename pattern `_YYYY-MM-DD_`.
  static final _filenameYear = RegExp(r'_(\d{4})-(\d{2})-(\d{2})_');

  static const _months = <String, int>{
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };

  Future<ParsedContainerLog> parseFile(File file) async {
    final raw = await file.readAsString();
    return parseString(raw, sourceName: _baseName(file.path));
  }

  ParsedContainerLog parseString(String raw, {required String sourceName}) {
    final lines = raw.replaceAll('\r\n', '\n').split('\n');
    final format = _sniffFormat(lines);
    final yearHint = _extractYearHint(sourceName) ?? DateTime.now().year;

    final events = <LogEvent>[];
    final warnings = <String>[];
    final skippedSamples = <String>[];
    var skipped = 0;
    var sawHeader = false;
    var syntheticCount = 0;

    DateTime? curTs;
    String? curStream;
    final curContent = StringBuffer();
    final orphans = <String>[];
    DateTime? lastRealTs;

    void flushCurrent() {
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

    /// Materializes any pending orphan lines as separate events with
    /// timestamps interpolated between [prev] and [next]. If only one
    /// anchor is present the orphans are placed just before [next] (or
    /// just after [prev]) at 1 ms intervals.
    void flushOrphans({DateTime? prev, DateTime? next}) {
      if (orphans.isEmpty) return;
      final n = orphans.length;
      List<DateTime> stamps;
      if (prev != null && next != null && next.isAfter(prev)) {
        final spanUs = next.difference(prev).inMicroseconds;
        // Spread n stamps strictly between prev and next.
        final stepUs = spanUs ~/ (n + 1);
        stamps = [
          for (var i = 0; i < n; i++)
            prev.add(Duration(microseconds: stepUs * (i + 1))),
        ];
      } else if (next != null) {
        // Pre-first-record orphans — place them just before `next`.
        stamps = [
          for (var i = 0; i < n; i++)
            next.subtract(Duration(milliseconds: n - i)),
        ];
      } else if (prev != null) {
        // Post-last-record orphans — place them just after `prev`.
        stamps = [
          for (var i = 0; i < n; i++)
            prev.add(Duration(milliseconds: i + 1)),
        ];
      } else {
        // No anchors at all (file has zero real timestamps). Use epoch +
        // sequential ms so events still sort. This is rare but possible
        // for pure-banner files.
        final base = DateTime.fromMillisecondsSinceEpoch(0);
        stamps = [
          for (var i = 0; i < n; i++) base.add(Duration(milliseconds: i)),
        ];
      }
      for (var i = 0; i < n; i++) {
        events.add(LogEvent(
          timestamp: stamps[i],
          sourceKind: kind,
          sourceName: sourceName,
          content: orphans[i],
          synthetic: true,
        ));
      }
      syntheticCount += n;
      orphans.clear();
    }

    _Header? matchHeader(String line) {
      switch (format) {
        case _Format.containerCsv:
          final m = _csvStart.firstMatch(line);
          if (m == null) return null;
          return _Header(
            timestamp: DateTime(
              int.parse(m.group(1)!),
              int.parse(m.group(2)!),
              int.parse(m.group(3)!),
              int.parse(m.group(4)!),
              int.parse(m.group(5)!),
              int.parse(m.group(6)!),
            ),
            stream: m.group(7),
            content: m.group(8) ?? '',
          );
        case _Format.mariadbPlain:
          final m = _mariadbStart.firstMatch(line);
          if (m == null) return null;
          return _Header(
            timestamp: DateTime(
              int.parse(m.group(1)!),
              int.parse(m.group(2)!),
              int.parse(m.group(3)!),
              int.parse(m.group(4)!),
              int.parse(m.group(5)!),
              int.parse(m.group(6)!),
            ),
            // Keep the full original line as content — the connection-id
            // and `[Level]` are useful for rule matching.
            content: line,
          );
        case _Format.noderedPlain:
          final m = _noderedStart.firstMatch(line);
          if (m == null) return null;
          final mo = _months[m.group(2)!];
          if (mo == null) return null;
          return _Header(
            timestamp: DateTime(
              yearHint,
              mo,
              int.parse(m.group(1)!),
              int.parse(m.group(3)!),
              int.parse(m.group(4)!),
              int.parse(m.group(5)!),
            ),
            content: line,
          );
      }
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) {
        // Preserve blank lines as continuations of the current event so
        // multi-line banners (e.g. Node-RED welcome banner) keep their
        // shape, but ignore blanks before any record.
        if (curTs != null) {
          curContent.write('\n');
        }
        continue;
      }

      // Skip the optional first-line container name and the CSV header
      // (only relevant in the containerCsv format; harmless in others).
      if (i < 4 && format == _Format.containerCsv) {
        final lower = trimmed.toLowerCase();
        if (lower == 'date,stream,content') {
          sawHeader = true;
          continue;
        }
        if (i == 0 && !_csvStart.hasMatch(trimmed)) {
          // Free-form container name on the first line — skip silently.
          continue;
        }
      }

      final header = matchHeader(trimmed);
      if (header != null) {
        // Close the previous record, then start the new one.
        flushCurrent();
        if (orphans.isNotEmpty) {
          flushOrphans(prev: lastRealTs, next: header.timestamp);
        }
        curTs = header.timestamp;
        curStream = header.stream;
        curContent.write(header.content);
        lastRealTs = header.timestamp;
        continue;
      }

      // Not a record header.
      if (curTs != null) {
        // Continuation of the current event.
        if (curContent.isNotEmpty) curContent.write('\n');
        curContent.write(trimmed);
        continue;
      }

      // Orphan: no current record yet — buffer until we see a real
      // timestamp (or EOF) and synthesize a timestamp then.
      orphans.add(trimmed);
    }

    flushCurrent();
    if (orphans.isNotEmpty) {
      flushOrphans(prev: lastRealTs, next: null);
    }

    if (format == _Format.containerCsv && !sawHeader) {
      warnings.add('CSV header not found in $sourceName; assumed records were '
          'parsed by line prefix.');
    }
    if (format != _Format.containerCsv) {
      warnings.add('$sourceName: parsed as ${format.label} '
          '(no Docker-CSV header found).');
    }
    if (syntheticCount > 0) {
      warnings.add('$sourceName: $syntheticCount line(s) with no leading '
          'timestamp were assigned synthetic timestamps interpolated between '
          'adjacent records (marked with ~ in the timeline).');
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
      syntheticEvents: syntheticCount,
    );
  }

  /// Decides which header format the file uses by scanning the first
  /// non-empty lines. Defaults to [containerCsv] when no real timestamps
  /// are found at all (preserves the legacy behavior).
  _Format _sniffFormat(List<String> lines) {
    var csv = 0;
    var mariadb = 0;
    var nodered = 0;
    var scanned = 0;
    for (final raw in lines) {
      if (scanned >= 80) break;
      final line = raw.trim();
      if (line.isEmpty) continue;
      scanned++;
      if (_csvStart.hasMatch(line)) {
        csv++;
        // Single CSV-format hit is decisive — no other format embeds the
        // `,(stdout|stderr),` infix in column 0.
        return _Format.containerCsv;
      }
      if (_mariadbStart.hasMatch(line)) mariadb++;
      if (_noderedStart.hasMatch(line)) nodered++;
    }
    if (csv > 0) return _Format.containerCsv;
    if (mariadb > nodered && mariadb > 0) return _Format.mariadbPlain;
    if (nodered > 0) return _Format.noderedPlain;
    // No timestamps found anywhere — fall back to CSV (legacy path will
    // mark every line as malformed, which surfaces the issue clearly).
    return _Format.containerCsv;
  }

  int? _extractYearHint(String sourceName) {
    final m = _filenameYear.firstMatch(sourceName);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  static String _baseName(String path) {
    final unix = path.replaceAll('\\', '/');
    final idx = unix.lastIndexOf('/');
    return idx == -1 ? unix : unix.substring(idx + 1);
  }
}

enum _Format {
  containerCsv('Docker container CSV'),
  mariadbPlain('MariaDB plain log'),
  noderedPlain('Node-RED plain log');

  const _Format(this.label);
  final String label;
}

class _Header {
  _Header({required this.timestamp, required this.content, this.stream});
  final DateTime timestamp;
  final String content;
  final String? stream;
}

class ParsedContainerLog {
  ParsedContainerLog({
    required this.events,
    required this.warnings,
    required this.skippedRows,
    required this.skippedSamples,
    this.syntheticEvents = 0,
  });

  final List<LogEvent> events;
  final List<String> warnings;
  final int skippedRows;
  final List<String> skippedSamples;

  /// Number of events whose timestamp was interpolated by the parser
  /// because the source line had no leading timestamp.
  final int syntheticEvents;
}
