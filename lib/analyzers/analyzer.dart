import 'dart:io';

import '../models/analysis_result.dart';
import '../models/log_event.dart';
import '../models/log_source.dart';
import '../models/rules_config.dart';
import '../models/suspicious_event.dart';
import '../parsers/ax_log_parser.dart';
import '../parsers/container_csv_parser.dart';
import '../parsers/slow_query_parser.dart';
import 'rule_matcher.dart';
import 'slow_query_analyzer.dart';

class Analyzer {
  Analyzer(this.rules);

  final RulesConfig rules;

  Future<AnalysisResult> run(AnalysisInput input) async {
    final containerEvents = <LogEvent>[];
    final slowQueryEvents = <SlowQueryEvent>[];
    final axLogEvents = <AxLogEvent>[];
    final restartList = <RestartEvent>[];
    final warnings = <String>[];
    var totalLines = 0;

    for (final source in input.sources) {
      final file = File(source.path);
      if (!await file.exists()) {
        warnings.add('File not found: ${source.path}');
        continue;
      }
      switch (source.kind) {
        case LogSourceKind.mariadbContainer:
          final parser = ContainerCsvParser(kind: LogSourceKind.mariadbContainer);
          final parsed = await parser.parseFile(file);
          containerEvents.addAll(parsed.events);
          warnings.addAll(parsed.warnings);
          totalLines += parsed.events.length;
          break;
        case LogSourceKind.noderedContainer:
          final parser = ContainerCsvParser(kind: LogSourceKind.noderedContainer);
          final parsed = await parser.parseFile(file);
          containerEvents.addAll(parsed.events);
          warnings.addAll(parsed.warnings);
          totalLines += parsed.events.length;
          break;
        case LogSourceKind.mariadbSlowQuery:
          final parser = SlowQueryParser();
          final parsed = await parser.parseFile(file);
          slowQueryEvents.addAll(parsed.events);
          warnings.addAll(parsed.warnings);
          totalLines += parsed.events.length;
          for (final ts in parsed.restarts) {
            restartList.add(RestartEvent(
              timestamp: ts,
              sourceKind: LogSourceKind.mariadbSlowQuery,
              sourceName: parsed.sourceName,
              kind: 'mariadbd banner',
            ));
          }
          break;
        case LogSourceKind.axLog:
          final parser = AxLogParser();
          final parsed = await parser.parseFile(file);
          axLogEvents.addAll(parsed.events);
          warnings.addAll(parsed.warnings);
          totalLines += parsed.events.length;
          break;
      }
    }

    // Determine the effective time window: intersection of CSV span and the
    // optional user-provided [from, to]. This window is also applied to the
    // slow-log events, so cross-source correlation stays meaningful.
    final csvLikeEvents = <DateTime>[
      ...containerEvents.map((e) => e.timestamp),
      ...axLogEvents.map((e) => e.timestamp),
    ];
    DateTime? csvFrom;
    DateTime? csvTo;
    if (csvLikeEvents.isNotEmpty) {
      csvFrom = csvLikeEvents.first;
      csvTo = csvLikeEvents.first;
      for (final t in csvLikeEvents) {
        if (t.isBefore(csvFrom!)) csvFrom = t;
        if (t.isAfter(csvTo!)) csvTo = t;
      }
    }

    DateTime? effFrom = csvFrom;
    DateTime? effTo = csvTo;
    if (input.from != null) {
      effFrom = effFrom == null || input.from!.isAfter(effFrom)
          ? input.from
          : effFrom;
    }
    if (input.to != null) {
      effTo = effTo == null || input.to!.isBefore(effTo) ? input.to : effTo;
    }

    final fromBound = effFrom;
    final toBound = effTo;
    bool inRange(DateTime ts) {
      if (fromBound != null && ts.isBefore(fromBound)) return false;
      if (toBound != null && ts.isAfter(toBound)) return false;
      return true;
    }

    final filteredContainer =
        containerEvents.where((e) => inRange(e.timestamp)).toList(growable: false);
    final filteredSlow =
        slowQueryEvents.where((e) => inRange(e.timestamp)).toList(growable: false);
    final filteredAx =
        axLogEvents.where((e) => inRange(e.timestamp)).toList(growable: false);

    if (slowQueryEvents.isNotEmpty && filteredSlow.isEmpty && csvFrom != null) {
      warnings.add(
          'Slow log timestamps do not overlap with container/AX-log window — slow queries excluded.');
    }

    // MariaDB / Node-RED suspicious events
    final mariadbMatcher = RuleMatcher(rules.mariadb.patterns);
    final noderedMatcher = RuleMatcher(rules.nodered.patterns);
    final suspicious = <SuspiciousEvent>[];
    for (final e in filteredContainer) {
      switch (e.sourceKind) {
        case LogSourceKind.mariadbContainer:
          suspicious.addAll(mariadbMatcher.match(e));
          break;
        case LogSourceKind.noderedContainer:
          suspicious.addAll(noderedMatcher.match(e));
          break;
        case LogSourceKind.mariadbSlowQuery:
        case LogSourceKind.axLog:
          break;
      }
    }

    // Slow query suspicious events
    final slowAnalyzer = SlowQueryAnalyzer(rules.slowQuery);
    suspicious.addAll(slowAnalyzer.analyze(filteredSlow));

    // AX_LOG suspicious events. Severity / category come from the STATE
    // column (mapped via AxState), filtered by the user-selected state set.
    final axStates =
        input.axIncludedStates ?? rules.axLog.defaultIncludedStates;
    for (final e in filteredAx) {
      if (!axStates.contains(e.state)) continue;
      final meta = AxState.forValue(e.state);
      final unit = e.unitName.isEmpty ? 'AX' : e.unitName;
      final routine = e.routineName.isEmpty ? '' : ' · ${e.routineName}';
      final msg = e.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      suspicious.add(SuspiciousEvent(
        timestamp: e.timestamp,
        sourceKind: LogSourceKind.axLog,
        sourceName: e.sourceName,
        severity: meta.severity,
        category: meta.category,
        ruleId: 'ax_state_${e.state}',
        excerpt: '$unit$routine: $msg',
        metadata: {
          'state': e.state,
          'recordId': e.recordId,
          'keyTag': e.keyTag,
        },
      ));
    }

    // Lifecycle (startup) detection on container logs — multiple markers
    // per source, each yielding a labeled RestartEvent.
    for (final marker in rules.mariadb.startupMarkers) {
      for (final ts in RestartDetector(marker.regex).detect(
        filteredContainer,
        LogSourceKind.mariadbContainer,
      )) {
        restartList.add(RestartEvent(
          timestamp: ts,
          sourceKind: LogSourceKind.mariadbContainer,
          sourceName: 'mariadb',
          kind: marker.kind,
        ));
      }
    }
    final noderedNames = filteredContainer
        .where((e) => e.sourceKind == LogSourceKind.noderedContainer)
        .map((e) => e.sourceName)
        .toSet();
    for (final marker in rules.nodered.startupMarkers) {
      // Detect per-source so the lifecycle row knows which Node-RED port.
      for (final name in noderedNames) {
        final scoped = filteredContainer.where(
            (e) => e.sourceKind == LogSourceKind.noderedContainer && e.sourceName == name);
        for (final ts in RestartDetector(marker.regex).detect(
          scoped,
          LogSourceKind.noderedContainer,
        )) {
          restartList.add(RestartEvent(
            timestamp: ts,
            sourceKind: LogSourceKind.noderedContainer,
            sourceName: name,
            kind: marker.kind,
          ));
        }
      }
    }

    final filteredRestarts =
        restartList.where((r) => inRange(r.timestamp)).toList(growable: false)
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    suspicious.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return AnalysisResult(
      generatedAt: DateTime.now(),
      effectiveFrom: effFrom,
      effectiveTo: effTo,
      suspicious: suspicious,
      slowQueries: filteredSlow,
      restarts: filteredRestarts,
      totalLinesParsed: totalLines,
      sources: input.sources,
      warnings: warnings,
    );
  }
}
