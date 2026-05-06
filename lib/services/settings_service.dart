import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persistent settings stored as JSON in `<applicationSupportDir>/settings.json`.
///
/// The file is plaintext on disk. The Anthropic API key is therefore protected
/// only by the operating-system user-account permissions; treat the host
/// machine as part of the trust boundary.
class SettingsService {
  static const _kApiKey = 'anthropic_api_key';
  static const _kModel = 'anthropic_model';
  static const _kIncludeAi = 'include_ai_insights';

  static const defaultModel = 'claude-sonnet-4-6';
  static const supportedModels = <String>[
    'claude-opus-4-7',
    'claude-sonnet-4-6',
    'claude-haiku-4-5-20251001',
  ];

  Map<String, dynamic>? _cache;
  Future<File>? _fileFuture;

  Future<File> _file() {
    return _fileFuture ??= () async {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      return File('${dir.path}/settings.json');
    }();
  }

  Future<Map<String, dynamic>> _read() async {
    if (_cache != null) return _cache!;
    final file = await _file();
    if (!await file.exists()) {
      _cache = <String, dynamic>{};
      return _cache!;
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      _cache = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      _cache = <String, dynamic>{};
    }
    return _cache!;
  }

  Future<void> _write() async {
    final file = await _file();
    await file.writeAsString(jsonEncode(_cache ?? const {}));
  }

  Future<String?> getApiKey() async {
    final m = await _read();
    final v = m[_kApiKey];
    return v is String && v.isNotEmpty ? v : null;
  }

  Future<void> setApiKey(String? value) async {
    final m = await _read();
    if (value == null || value.isEmpty) {
      m.remove(_kApiKey);
    } else {
      m[_kApiKey] = value;
    }
    await _write();
  }

  Future<String> getModel() async {
    final m = await _read();
    final v = m[_kModel];
    return (v is String && v.isNotEmpty) ? v : defaultModel;
  }

  Future<void> setModel(String value) async {
    final m = await _read();
    m[_kModel] = value;
    await _write();
  }

  Future<bool> getIncludeAi() async {
    final m = await _read();
    return m[_kIncludeAi] == true;
  }

  Future<void> setIncludeAi(bool value) async {
    final m = await _read();
    m[_kIncludeAi] = value;
    await _write();
  }
}
