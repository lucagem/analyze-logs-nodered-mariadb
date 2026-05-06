import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../analyzers/analyzer.dart';
import '../models/analysis_result.dart';
import '../models/log_source.dart';
import '../models/rules_config.dart';
import '../reporters/markdown_reporter.dart';
import '../services/anthropic_client.dart';
import '../services/rules_loader.dart';
import '../services/settings_service.dart';
import 'report_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.settings});

  final SettingsService settings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  LogSource? _mariadbCsv;
  final List<LogSource> _noderedCsvs = [];
  LogSource? _slowQueryLog;
  final List<LogSource> _axLogs = [];

  DateTime? _from;
  DateTime? _to;

  RulesConfig? _rules;
  bool _running = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    final r = await loadDefaultRules();
    if (!mounted) return;
    setState(() => _rules = r);
  }

  bool get _canAnalyze =>
      _rules != null &&
      !_running &&
      (_mariadbCsv != null ||
          _noderedCsvs.isNotEmpty ||
          _slowQueryLog != null ||
          _axLogs.isNotEmpty);

  Future<void> _pickMariadbCsv() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select MariaDB container CSV',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _mariadbCsv = LogSource(
        kind: LogSourceKind.mariadbContainer,
        path: path,
        displayName: result!.files.single.name,
      );
    });
  }

  Future<void> _addNoderedCsv() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Node-RED container CSV',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _noderedCsvs.add(LogSource(
        kind: LogSourceKind.noderedContainer,
        path: path,
        displayName: result!.files.single.name,
      ));
    });
  }

  Future<void> _addAxLog() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select AX log CSV',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _axLogs.add(LogSource(
        kind: LogSourceKind.axLog,
        path: path,
        displayName: result!.files.single.name,
      ));
    });
  }

  Future<void> _pickSlowQueryLog() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select MariaDB slow query log',
      type: FileType.custom,
      allowedExtensions: ['log', 'txt'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _slowQueryLog = LogSource(
        kind: LogSourceKind.mariadbSlowQuery,
        path: path,
        displayName: result!.files.single.name,
      );
    });
  }

  Future<void> _pickFrom() async {
    final dt = await _pickDateTime(_from ?? DateTime.now());
    if (dt != null) setState(() => _from = dt);
  }

  Future<void> _pickTo() async {
    final dt = await _pickDateTime(_to ?? DateTime.now());
    if (dt != null) setState(() => _to = dt);
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _runAnalysis() async {
    final rules = _rules;
    if (rules == null) return;
    setState(() {
      _running = true;
      _statusMessage = 'Parsing logs…';
    });

    try {
      final sources = <LogSource>[
        ?_mariadbCsv,
        ..._noderedCsvs,
        ?_slowQueryLog,
        ..._axLogs,
      ];

      final analyzer = Analyzer(rules);
      final result = await analyzer.run(AnalysisInput(
        sources: sources,
        from: _from,
        to: _to,
      ));

      setState(() => _statusMessage = 'Building report…');
      final markdown = MarkdownReporter(rules).render(result);

      final include = await widget.settings.getIncludeAi();
      final apiKey = await widget.settings.getApiKey();
      var finalMd = markdown;
      String? aiInsights;

      if (include && apiKey != null && apiKey.isNotEmpty) {
        setState(() => _statusMessage = 'Calling Anthropic API…');
        final model = await widget.settings.getModel();
        final client = AnthropicClient(apiKey: apiKey, model: model);
        try {
          aiInsights = await client.generateInsights(result);
          finalMd = '$markdown\n\n## AI Insights\n\n$aiInsights\n';
        } catch (e) {
          aiInsights = '> _AI insights failed: ${e}_';
          finalMd = '$markdown\n\n## AI Insights\n\n$aiInsights\n';
        } finally {
          client.close();
        }
      } else if (include) {
        aiInsights =
            '> _Skipped: no API key configured. Open Settings to add one._';
        finalMd = '$markdown\n\n## AI Insights\n\n$aiInsights\n';
      }

      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReportScreen(
          result: result,
          markdown: finalMd,
          aiInsights: aiInsights,
        ),
      ));
    } catch (e, st) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Analysis failed: $e')),
      );
      debugPrint('Analysis error: $e\n$st');
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _statusMessage = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Analyzer'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SettingsScreen(settings: widget.settings),
            )),
          ),
        ],
      ),
      body: _rules == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('1 · MariaDB container CSV (1 file)'),
                  _filePickerRow(
                    label: 'Choose MariaDB CSV…',
                    source: _mariadbCsv,
                    onPick: _pickMariadbCsv,
                    onClear: () => setState(() => _mariadbCsv = null),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('2 · Node-RED container CSVs (1+ files)'),
                  ..._noderedCsvs.asMap().entries.map(
                        (e) => _selectedFileRow(
                          source: e.value,
                          onClear: () =>
                              setState(() => _noderedCsvs.removeAt(e.key)),
                        ),
                      ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _addNoderedCsv,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Node-RED CSV'),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('3 · MariaDB slow query log (optional)'),
                  _filePickerRow(
                    label: 'Choose slow query log…',
                    source: _slowQueryLog,
                    onPick: _pickSlowQueryLog,
                    onClear: () => setState(() => _slowQueryLog = null),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('4 · AX_LOG CSVs (optional, 1+ files)'),
                  ..._axLogs.asMap().entries.map(
                        (e) => _selectedFileRow(
                          source: e.value,
                          onClear: () =>
                              setState(() => _axLogs.removeAt(e.key)),
                        ),
                      ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _addAxLog,
                    icon: const Icon(Icons.add),
                    label: const Text('Add AX log CSV'),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('5 · Time range (optional)'),
                  Row(
                    children: [
                      Expanded(
                        child: _dateField(
                          label: 'From',
                          value: _from,
                          fmt: fmt,
                          onPick: _pickFrom,
                          onClear: () => setState(() => _from = null),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _dateField(
                          label: 'To',
                          value: _to,
                          fmt: fmt,
                          onPick: _pickTo,
                          onClear: () => setState(() => _to = null),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Range is intersected with the CSV span; the slow log is filtered to '
                    'the same effective window so events stay correlated.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      FilledButton.icon(
                        icon: _running
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.analytics),
                        label: Text(_running ? 'Analyzing…' : 'Analyze'),
                        onPressed: _canAnalyze ? _runAnalysis : null,
                      ),
                      const SizedBox(width: 16),
                      if (_statusMessage != null)
                        Text(_statusMessage!,
                            style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _filePickerRow({
    required String label,
    required LogSource? source,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    if (source == null) {
      return OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.upload_file),
        label: Text(label),
      );
    }
    return _selectedFileRow(source: source, onClear: onClear);
  }

  Widget _selectedFileRow({required LogSource source, required VoidCallback onClear}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: source.path,
              child: Text(source.displayName, overflow: TextOverflow.ellipsis),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Remove',
            onPressed: onClear,
          ),
        ],
      ),
    );
  }

  Widget _dateField({
    required String label,
    required DateTime? value,
    required DateFormat fmt,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(value == null ? '—' : fmt.format(value)),
          ),
          IconButton(
            icon: const Icon(Icons.event),
            onPressed: onPick,
          ),
          if (value != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: onClear,
            ),
        ],
      ),
    );
  }
}
