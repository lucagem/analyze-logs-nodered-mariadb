import 'dart:io';

/// Opens a directory (or file) in the host platform's file manager.
///
/// - Windows: `explorer.exe <path>`
/// - macOS:   `open <path>`
/// - Linux:   `xdg-open <path>`
class FileOpener {
  Future<void> openDirectory(String path) async {
    if (Platform.isWindows) {
      // Windows Explorer silently falls back to "Documents" when a path
      // contains forward-slash separators in the middle, so normalize to
      // backslashes first.
      final normalized = path.replaceAll('/', r'\');
      await Process.start('explorer', [normalized]);
      return;
    }
    if (Platform.isMacOS) {
      await Process.start('open', [path]);
      return;
    }
    if (Platform.isLinux) {
      await Process.start('xdg-open', [path]);
      return;
    }
    throw UnsupportedError(
        'openDirectory is not supported on ${Platform.operatingSystem}.');
  }
}
