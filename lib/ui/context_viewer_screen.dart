import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/log_event.dart';
import '../models/log_source.dart';
import '../utils/json_extractor.dart';

/// Shows a sliding window of [contextBefore] + 1 + [contextAfter] events
/// around a focused [LogEvent], plus a JSON formatter pane on the right.
///
/// JSON snippets detected inside any visible line are surfaced as small
/// chips; clicking one loads the formatted value into the right pane.
/// The user can also paste arbitrary text into the pane and click
/// "Format" — useful for snippets that aren't strict JSON until cleaned
/// up by hand.
class ContextViewerScreen extends StatefulWidget {
  const ContextViewerScreen({
    super.key,
    required this.events,
    required this.focusedIndex,
    required this.sourceKind,
    required this.sourceName,
    this.contextBefore = 20,
    this.contextAfter = 10,
  });

  final List<LogEvent> events;
  final int focusedIndex;
  final LogSourceKind sourceKind;
  final String sourceName;
  final int contextBefore;
  final int contextAfter;

  @override
  State<ContextViewerScreen> createState() => _ContextViewerScreenState();
}

class _ContextViewerScreenState extends State<ContextViewerScreen> {
  static final _tsFmt = DateFormat('yyyy-MM-dd HH:mm:ss');

  final _pasteController = TextEditingController();
  String? _formatted; // pretty-printed JSON shown in the right pane
  String? _formatterError;
  String? _formatterTitle;

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  void _showJson(JsonMatch m, {String? title}) {
    setState(() {
      _formatted = m.pretty;
      _formatterError = null;
      _formatterTitle = title ?? 'JSON snippet';
    });
  }

  void _formatPasted() {
    final text = _pasteController.text;
    final m = JsonExtractor.tryParseWhole(text);
    if (m != null) {
      setState(() {
        _formatted = m.pretty;
        _formatterError = null;
        _formatterTitle = 'Pasted JSON';
      });
      return;
    }
    // Fallback: maybe the user pasted a whole log line — try to find the
    // first valid JSON snippet within it.
    final all = JsonExtractor.findAll(text);
    if (all.isNotEmpty) {
      setState(() {
        _formatted = all.first.pretty;
        _formatterError =
            all.length > 1 ? 'Showing first of ${all.length} JSON snippets' : null;
        _formatterTitle = 'Pasted JSON';
      });
      return;
    }
    setState(() {
      _formatted = null;
      _formatterError = 'No valid JSON found in the pasted text.';
      _formatterTitle = null;
    });
  }

  void _clearFormatter() {
    setState(() {
      _formatted = null;
      _formatterError = null;
      _formatterTitle = null;
      _pasteController.clear();
    });
  }

  Future<void> _copyFormatted() async {
    final v = _formatted;
    if (v == null) return;
    await Clipboard.setData(ClipboardData(text: v));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Formatted JSON copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final focused = widget.events[widget.focusedIndex];
    final start = (widget.focusedIndex - widget.contextBefore).clamp(0, widget.events.length);
    final end =
        (widget.focusedIndex + widget.contextAfter + 1).clamp(0, widget.events.length);
    final slice = widget.events.sublist(start, end);
    return Scaffold(
      appBar: AppBar(
        title: Text(
            'Context · ${widget.sourceKind.label} · ${widget.sourceName} · ${_tsFmt.format(focused.timestamp)}'),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: _contextPane(slice, start)),
          const VerticalDivider(width: 1),
          Expanded(flex: 2, child: _jsonPane()),
        ],
      ),
    );
  }

  Widget _contextPane(List<LogEvent> slice, int sliceStart) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              const Icon(Icons.list_alt, size: 18),
              const SizedBox(width: 8),
              Text(
                'Showing ${slice.length} events '
                '(${widget.contextBefore} before · 1 focused · ${widget.contextAfter} after)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: slice.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 24, endIndent: 24),
            itemBuilder: (context, i) {
              final relIndex = (sliceStart + i) - widget.focusedIndex;
              final isFocused = relIndex == 0;
              return _logRow(slice[i], relIndex: relIndex, isFocused: isFocused);
            },
          ),
        ),
      ],
    );
  }

  Widget _logRow(LogEvent e, {required int relIndex, required bool isFocused}) {
    final matches = JsonExtractor.findAll(e.content);
    final relLabel = relIndex == 0
        ? '★'
        : (relIndex < 0 ? '$relIndex' : '+$relIndex');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      color: isFocused ? Colors.indigo.withValues(alpha: 0.10) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text(relLabel,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: isFocused ? Colors.indigo.shade700 : Colors.black45,
                  fontWeight: isFocused ? FontWeight.w800 : FontWeight.w500,
                  fontFamily: 'monospace',
                )),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: Text(_tsFmt.format(e.timestamp),
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  e.content,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    fontWeight: isFocused ? FontWeight.w600 : FontWeight.normal,
                    height: 1.35,
                  ),
                ),
                if (matches.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (var idx = 0; idx < matches.length; idx++)
                        ActionChip(
                          avatar: const Icon(Icons.data_object, size: 14),
                          label: Text('JSON ${idx + 1} · ${matches[idx].label}',
                              style: const TextStyle(fontSize: 11)),
                          onPressed: () => _showJson(matches[idx],
                              title: 'JSON ${idx + 1} of ${matches.length}'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _jsonPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              const Icon(Icons.data_object, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_formatterTitle ?? 'JSON viewer',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (_formatted != null) ...[
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: _copyFormatted,
                ),
                IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: _clearFormatter,
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _formattedView(),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Or paste any text and try to format:',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 6),
              TextField(
                controller: _pasteController,
                minLines: 2,
                maxLines: 5,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  hintText: '{"key": "value"} or a whole log line containing JSON',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _formatPasted,
                    icon: const Icon(Icons.auto_fix_high, size: 18),
                    label: const Text('Format'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _pasteController.clear(),
                    icon: const Icon(Icons.backspace_outlined, size: 18),
                    label: const Text('Clear input'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _formattedView() {
    if (_formatterError != null && _formatted == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_formatterError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red.shade700)),
        ),
      );
    }
    if (_formatted == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Click any JSON chip on the left, or paste text below.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                _formatted!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4),
              ),
            ),
          ),
        ),
        if (_formatterError != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.amber.withValues(alpha: 0.2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(_formatterError!,
                  style: const TextStyle(fontSize: 12, color: Colors.black87)),
            ),
          ),
      ],
    );
  }
}
