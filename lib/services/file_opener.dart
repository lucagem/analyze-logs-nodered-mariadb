import 'dart:io';

/// Opens a directory (or file) in the host platform's file manager.
///
/// - Windows: `explorer.exe <path>`
/// - macOS:   `open <path>`
/// - Linux:   `xdg-open <path>`
class FileOpener {
  Future<void> openDirectory(String path) async {
    if (Platform.isWindows) {
      // Use the Windows shell so paths with spaces resolve correctly. We
      // don't await exit because explorer detaches itself.
      await Process.start('explorer', [path]);
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
