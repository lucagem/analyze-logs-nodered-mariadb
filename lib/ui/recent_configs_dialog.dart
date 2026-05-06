import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/saved_config.dart';
import '../services/settings_service.dart';

/// Modal that lists the most recent (up to 10) saved configurations.
///
/// Returns the [SavedConfig] the user picked, or `null` if the dialog
/// was dismissed without a selection.
class RecentConfigsDialog extends StatefulWidget {
  const RecentConfigsDialog({super.key, required this.settings});

  final SettingsService settings;

  @override
  State<RecentConfigsDialog> createState() => _RecentConfigsDialogState();
}

class _RecentConfigsDialogState extends State<RecentConfigsDialog> {
  static final _tsFmt = DateFormat('yyyy-MM-dd HH:mm');
  late Future<List<SavedConfig>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.settings.getRecentConfigs();
  }

  void _reload() {
    setState(() {
      _future = widget.settings.getRecentConfigs();
    });
  }

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear recent configurations?'),
        content: const Text(
            'This removes every saved configuration. Files on disk are not deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.settings.clearRecentConfigs();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.history),
                  const SizedBox(width: 8),
                  Text('Recent configurations',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<SavedConfig>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final list = snap.data ?? const [];
                  if (list.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No saved configurations yet.\nRun an analysis and it will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) =>
                        _row(list[i], i, isLatest: i == 0),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _confirmClearAll,
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text('Clear all'),
                  ),
                  const Spacer(),
                  Text(
                    'Tap an entry to load it',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(SavedConfig c, int index, {required bool isLatest}) {
    final missing = c.sources.where((s) => !File(s.path).existsSync()).length;
    final rangeText = (c.from != null || c.to != null)
        ? '${c.from != null ? _tsFmt.format(c.from!) : '−∞'} → ${c.to != null ? _tsFmt.format(c.to!) : '+∞'}'
        : 'open range';
    final folder = _commonFolder(c);

    return InkWell(
      onTap: () => Navigator.of(context).pop(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                isLatest ? Icons.star : Icons.history,
                color: isLatest ? Colors.amber.shade700 : Colors.grey.shade500,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(_tsFmt.format(c.savedAt),
                          style: const TextStyle(
                              fontFeatures: [FontFeature.tabularFigures()],
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text('· ${c.summary}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black87)),
                      ),
                      if (isLatest) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('LAST',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF7B5E00))),
                        ),
                      ],
                    ],
                  ),
                  Text(rangeText,
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  if (folder != null)
                    Text(folder,
                        style: const TextStyle(
                            fontSize: 11, fontFamily: 'monospace', color: Colors.black45),
                        overflow: TextOverflow.ellipsis),
                  if (missing > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('$missing file(s) missing on disk',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w500)),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove from history',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () async {
                await widget.settings.removeRecentConfigAt(index);
                _reload();
              },
            ),
          ],
        ),
      ),
    );
  }

  String? _commonFolder(SavedConfig c) {
    if (c.sources.isEmpty) return null;
    String? common;
    for (final s in c.sources) {
      var idx = s.path.lastIndexOf(r'\');
      final fwd = s.path.lastIndexOf('/');
      if (fwd > idx) idx = fwd;
      final folder = idx > 0 ? s.path.substring(0, idx) : s.path;
      if (common == null) {
        common = folder;
      } else if (common != folder) {
        return null; // mixed folders — don't show a misleading single value
      }
    }
    return common;
  }
}
