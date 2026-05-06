import 'log_source.dart';

class LogEvent {
  LogEvent({
    required this.timestamp,
    required this.sourceKind,
    required this.sourceName,
    required this.content,
    this.stream,
  });

  final DateTime timestamp;
  final LogSourceKind sourceKind;
  final String sourceName;
  final String content;
  final String? stream;
}

class AxLogEvent extends LogEvent {
  AxLogEvent({
    required super.timestamp,
    required super.sourceName,
    required super.content,
    required this.state,
    required this.unitName,
    required this.routineName,
    this.keyTag,
    this.recordId,
  }) : super(sourceKind: LogSourceKind.axLog);

  /// 0=OK, 1=WARNING, 2=ERROR, 3=DEBUG.
  final int state;
  final String unitName;
  final String routineName;
  final String? keyTag;
  final String? recordId;
}

class SlowQueryEvent extends LogEvent {
  SlowQueryEvent({
    required super.timestamp,
    required super.sourceName,
    required super.content,
    required this.queryTime,
    required this.lockTime,
    required this.rowsSent,
    required this.rowsExamined,
    required this.rowsAffected,
    required this.user,
    required this.host,
    this.schema,
    this.threadId,
  }) : super(sourceKind: LogSourceKind.mariadbSlowQuery);

  final double queryTime;
  final double lockTime;
  final int rowsSent;
  final int rowsExamined;
  final int rowsAffected;
  final String user;
  final String host;
  final String? schema;
  final int? threadId;
}
