enum LogSourceKind {
  mariadbContainer,
  noderedContainer,
  mariadbSlowQuery,
  axLog;

  String get label {
    switch (this) {
      case LogSourceKind.mariadbContainer:
        return 'MariaDB';
      case LogSourceKind.noderedContainer:
        return 'Node-RED';
      case LogSourceKind.mariadbSlowQuery:
        return 'Slow query';
      case LogSourceKind.axLog:
        return 'AX log';
    }
  }
}

class LogSource {
  LogSource({
    required this.kind,
    required this.path,
    required this.displayName,
  });

  final LogSourceKind kind;
  final String path;
  final String displayName;
}
