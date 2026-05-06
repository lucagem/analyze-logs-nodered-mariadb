import 'log_source.dart';

/// One file entry inside a saved configuration.
class SavedSource {
  SavedSource({
    required this.kind,
    required this.path,
    required this.displayName,
  });

  final LogSourceKind kind;
  final String path;
  final String displayName;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'path': path,
        'displayName': displayName,
      };

  factory SavedSource.fromJson(Map<String, dynamic> json) {
    return SavedSource(
      kind: LogSourceKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => LogSourceKind.mariadbContainer,
      ),
      path: json['path'] as String,
      displayName: json['displayName'] as String,
    );
  }

  LogSource toLogSource() => LogSource(
        kind: kind,
        path: path,
        displayName: displayName,
      );
}

/// A user-recoverable analysis setup: file list + AX state filter +
/// optional time range. Persisted in the settings file as part of a
/// most-recent-first list (capped at 10).
class SavedConfig {
  SavedConfig({
    required this.savedAt,
    required this.sources,
    required this.axIncludedStates,
    this.from,
    this.to,
  });

  final DateTime savedAt;
  final List<SavedSource> sources;
  final Set<int> axIncludedStates;
  final DateTime? from;
  final DateTime? to;

  /// Stable identity used to dedupe successive Analyze runs with the
  /// exact same inputs. `savedAt` is intentionally excluded.
  String get fingerprint {
    final files = sources
        .map((s) => '${s.kind.name}|${s.path}')
        .toList()
      ..sort();
    final ax = (axIncludedStates.toList()..sort()).join(',');
    return '${files.join(';')}##$ax##${from?.toIso8601String() ?? ''}##${to?.toIso8601String() ?? ''}';
  }

  Map<String, dynamic> toJson() => {
        'savedAt': savedAt.toIso8601String(),
        'sources': sources.map((s) => s.toJson()).toList(),
        'axIncludedStates': axIncludedStates.toList(),
        if (from != null) 'from': from!.toIso8601String(),
        if (to != null) 'to': to!.toIso8601String(),
      };

  factory SavedConfig.fromJson(Map<String, dynamic> json) {
    final sources = (json['sources'] as List<dynamic>)
        .map((e) => SavedSource.fromJson(e as Map<String, dynamic>))
        .toList();
    final ax = (json['axIncludedStates'] as List<dynamic>?)
            ?.map((e) => e as int)
            .toSet() ??
        const <int>{};
    return SavedConfig(
      savedAt: DateTime.parse(json['savedAt'] as String),
      sources: sources,
      axIncludedStates: ax,
      from: json['from'] != null ? DateTime.parse(json['from'] as String) : null,
      to: json['to'] != null ? DateTime.parse(json['to'] as String) : null,
    );
  }

  /// Short human description used in the picker dialog.
  String get summary {
    final mariadb = sources.where((s) => s.kind == LogSourceKind.mariadbContainer).length;
    final nodered = sources.where((s) => s.kind == LogSourceKind.noderedContainer).length;
    final slow = sources.where((s) => s.kind == LogSourceKind.mariadbSlowQuery).length;
    final ax = sources.where((s) => s.kind == LogSourceKind.axLog).length;
    final parts = <String>[
      if (mariadb > 0) 'MariaDB',
      if (nodered > 0) '$nodered Node-RED',
      if (slow > 0) 'slow log',
      if (ax > 0) '$ax AX log${ax == 1 ? '' : 's'}',
    ];
    return parts.isEmpty ? '(no files)' : parts.join(' · ');
  }
}
