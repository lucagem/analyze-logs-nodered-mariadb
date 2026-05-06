enum Severity {
  info,
  warn,
  error,
  critical;

  static Severity parse(String value) {
    switch (value.toUpperCase()) {
      case 'CRITICAL':
        return Severity.critical;
      case 'ERROR':
        return Severity.error;
      case 'WARN':
      case 'WARNING':
        return Severity.warn;
      default:
        return Severity.info;
    }
  }

  String get label {
    switch (this) {
      case Severity.critical:
        return 'CRITICAL';
      case Severity.error:
        return 'ERROR';
      case Severity.warn:
        return 'WARN';
      case Severity.info:
        return 'INFO';
    }
  }

  int get rank {
    switch (this) {
      case Severity.critical:
        return 3;
      case Severity.error:
        return 2;
      case Severity.warn:
        return 1;
      case Severity.info:
        return 0;
    }
  }
}
