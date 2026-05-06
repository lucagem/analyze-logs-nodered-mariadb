import 'severity.dart';

class RulePattern {
  RulePattern({
    required this.id,
    required this.regex,
    required this.severity,
    required this.category,
    required this.description,
  });

  final String id;
  final RegExp regex;
  final Severity severity;
  final String category;
  final String description;

  factory RulePattern.fromJson(Map<String, dynamic> json) {
    return RulePattern(
      id: json['id'] as String,
      regex: _compile(json['regex'] as String),
      severity: Severity.parse(json['severity'] as String),
      category: json['category'] as String,
      description: (json['description'] as String?) ?? '',
    );
  }

  /// Strips the inline `(?i)` flag (unsupported by Dart RegExp) and forwards
  /// it as `caseSensitive: false` on the constructor.
  static RegExp _compile(String pattern) {
    var caseSensitive = true;
    var p = pattern;
    if (p.startsWith('(?i)')) {
      caseSensitive = false;
      p = p.substring(4);
    }
    return RegExp(p, caseSensitive: caseSensitive);
  }
}

class StartupMarker {
  StartupMarker({required this.regex, required this.kind});

  final RegExp regex;
  final String kind;

  factory StartupMarker.fromJson(Map<String, dynamic> json) {
    return StartupMarker(
      regex: RulePattern._compile(json['regex'] as String),
      kind: json['kind'] as String,
    );
  }
}

class MariadbRules {
  MariadbRules({
    required this.patterns,
    required this.startupMarkers,
    required this.ignoreNoteCategories,
  });

  final List<RulePattern> patterns;
  final List<StartupMarker> startupMarkers;
  final List<String> ignoreNoteCategories;

  factory MariadbRules.fromJson(Map<String, dynamic> json) {
    return MariadbRules(
      patterns: (json['patterns'] as List)
          .map((e) => RulePattern.fromJson(e as Map<String, dynamic>))
          .toList(),
      startupMarkers: _parseMarkers(
        json['startupMarkers'],
        json['restartMarkerRegex'] as String?,
        defaultRegex: 'ready for connections',
        defaultKind: 'ready',
      ),
      ignoreNoteCategories:
          ((json['ignoreNoteCategories'] as List?) ?? const []).cast<String>(),
    );
  }
}

class NoderedRules {
  NoderedRules({
    required this.patterns,
    required this.startupMarkers,
  });

  final List<RulePattern> patterns;
  final List<StartupMarker> startupMarkers;

  factory NoderedRules.fromJson(Map<String, dynamic> json) {
    return NoderedRules(
      patterns: (json['patterns'] as List)
          .map((e) => RulePattern.fromJson(e as Map<String, dynamic>))
          .toList(),
      startupMarkers: _parseMarkers(
        json['startupMarkers'],
        json['restartMarkerRegex'] as String?,
        defaultRegex: 'Started flows',
        defaultKind: 'flows started',
      ),
    );
  }
}

/// Parses the new `startupMarkers` array. Falls back to the legacy
/// `restartMarkerRegex` single-string config (backwards compatibility).
List<StartupMarker> _parseMarkers(
  Object? markers,
  String? legacy, {
  required String defaultRegex,
  required String defaultKind,
}) {
  if (markers is List) {
    return markers
        .map((e) => StartupMarker.fromJson(e as Map<String, dynamic>))
        .toList();
  }
  return [
    StartupMarker(
      regex: RulePattern._compile(legacy ?? defaultRegex),
      kind: defaultKind,
    ),
  ];
}

class SlowQueryRules {
  SlowQueryRules({
    required this.minQueryTimeSeconds,
    required this.minLockTimeSeconds,
    required this.minRowsExaminedToSentRatio,
    required this.minRowsExaminedAbsolute,
    required this.topN,
    required this.repeatWindowSeconds,
    required this.repeatThreshold,
  });

  final double minQueryTimeSeconds;
  final double minLockTimeSeconds;
  final int minRowsExaminedToSentRatio;
  final int minRowsExaminedAbsolute;
  final int topN;
  final int repeatWindowSeconds;
  final int repeatThreshold;

  factory SlowQueryRules.fromJson(Map<String, dynamic> json) {
    return SlowQueryRules(
      minQueryTimeSeconds: (json['minQueryTimeSeconds'] as num).toDouble(),
      minLockTimeSeconds: (json['minLockTimeSeconds'] as num).toDouble(),
      minRowsExaminedToSentRatio: json['minRowsExaminedToSentRatio'] as int,
      minRowsExaminedAbsolute: json['minRowsExaminedAbsolute'] as int,
      topN: json['topN'] as int,
      repeatWindowSeconds: json['repeatWindowSeconds'] as int,
      repeatThreshold: json['repeatThreshold'] as int,
    );
  }
}

/// Static metadata for an AX_LOG STATE value.
class AxState {
  const AxState(this.value, this.label, this.severity);

  final int value;
  final String label;
  final Severity severity;

  /// Built-in catalog covering OK / WARNING / ERROR / DEBUG.
  static const ok = AxState(0, 'OK', Severity.info);
  static const warning = AxState(1, 'WARNING', Severity.warn);
  static const error = AxState(2, 'ERROR', Severity.error);
  static const debug = AxState(3, 'DEBUG', Severity.info);

  static const all = [ok, warning, error, debug];

  static AxState forValue(int value) {
    for (final s in all) {
      if (s.value == value) return s;
    }
    return AxState(value, 'STATE=$value', Severity.info);
  }

  /// Human-readable category that the analyzer uses on emitted
  /// `SuspiciousEvent`s. Stable (used in the report).
  String get category {
    switch (value) {
      case 0:
        return 'AX ok';
      case 1:
        return 'AX warning';
      case 2:
        return 'AX error';
      case 3:
        return 'AX debug';
      default:
        return 'AX state=$value';
    }
  }
}

class AxLogRules {
  AxLogRules({
    required this.defaultIncludedStates,
  });

  /// States included in an analysis when the UI does not override the
  /// selection. Defaults to WARNING + ERROR.
  final Set<int> defaultIncludedStates;

  factory AxLogRules.fromJson(Map<String, dynamic> json) {
    final raw = json['defaultIncludedStates'] as List<dynamic>?;
    final parsed = raw?.map((e) => e as int).toSet();
    return AxLogRules(
      defaultIncludedStates: parsed ?? const {1, 2},
    );
  }
}

class ReportRules {
  ReportRules({required this.timelineLimit, required this.excerptMaxChars});

  final int timelineLimit;
  final int excerptMaxChars;

  factory ReportRules.fromJson(Map<String, dynamic> json) {
    return ReportRules(
      timelineLimit: (json['timelineLimit'] as int?) ?? 200,
      excerptMaxChars: (json['excerptMaxChars'] as int?) ?? 240,
    );
  }
}

class RulesConfig {
  RulesConfig({
    required this.mariadb,
    required this.nodered,
    required this.slowQuery,
    required this.axLog,
    required this.report,
  });

  final MariadbRules mariadb;
  final NoderedRules nodered;
  final SlowQueryRules slowQuery;
  final AxLogRules axLog;
  final ReportRules report;

  factory RulesConfig.fromJson(Map<String, dynamic> json) {
    return RulesConfig(
      mariadb: MariadbRules.fromJson(json['mariadb'] as Map<String, dynamic>),
      nodered: NoderedRules.fromJson(json['nodered'] as Map<String, dynamic>),
      slowQuery: SlowQueryRules.fromJson(json['slowQuery'] as Map<String, dynamic>),
      axLog: AxLogRules.fromJson((json['axLog'] as Map<String, dynamic>?) ?? const {}),
      report: ReportRules.fromJson((json['report'] as Map<String, dynamic>?) ?? const {}),
    );
  }
}
