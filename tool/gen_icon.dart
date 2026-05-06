import 'dart:io';

import 'package:image/image.dart' as img;

/// Generates the app icon assets.
///
/// Design: a rounded indigo square containing three "log line" bars stacked
/// vertically. Each bar has a colored severity tag on its left side
/// (green = OK, amber = WARN, red = ERROR) — visually evokes a log viewer
/// with a severity column.
///
/// Outputs:
/// - `assets/icons/app_icon_<size>.png`  (16/24/32/48/64/128/256/1024)
/// - `windows/runner/resources/app_icon.ico` (256-px)
///
/// Usage: `dart run tool/gen_icon.dart`
Future<void> main() async {
  await Directory('assets/icons').create(recursive: true);

  final master = _drawIcon(1024);

  final sizes = [16, 24, 32, 48, 64, 128, 256, 512, 1024];
  for (final s in sizes) {
    final resized = s == 1024
        ? master
        : img.copyResize(master,
            width: s, height: s, interpolation: img.Interpolation.cubic);
    await File('assets/icons/app_icon_$s.png')
        .writeAsBytes(img.encodePng(resized));
  }

  final ico = img.encodeIco(img.copyResize(master,
      width: 256, height: 256, interpolation: img.Interpolation.cubic));
  await File('windows/runner/resources/app_icon.ico').writeAsBytes(ico);

  // macOS app icon set — overwrite the matching size files.
  const macSet = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
  if (await Directory(macSet).exists()) {
    for (final s in [16, 32, 64, 128, 256, 512, 1024]) {
      final src = File('assets/icons/app_icon_$s.png');
      if (await src.exists()) {
        await src.copy('$macSet/app_icon_$s.png');
      }
    }
  }

  stdout.writeln('Icon generated: master 1024x1024 + .ico (256x256) + macOS appiconset.');
}

img.Image _drawIcon(int size) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));

  // Background — rounded square in Material indigo 600.
  final bg = img.ColorRgba8(0x39, 0x49, 0xAB, 0xFF);
  final cornerR = (size * 0.18).round();
  _fillRoundedRect(image, 0, 0, size, size, cornerR, bg);

  // Three horizontal "log line" bars, light, with a colored severity tag.
  final barColor = img.ColorRgba8(0xFF, 0xFF, 0xFF, 0xF0);
  final tagColors = [
    img.ColorRgba8(0x4C, 0xAF, 0x50, 0xFF), // green   — OK
    img.ColorRgba8(0xFB, 0xC0, 0x2D, 0xFF), // amber   — WARN
    img.ColorRgba8(0xE5, 0x39, 0x35, 0xFF), // red     — ERROR
  ];

  final centerYs = [0.32, 0.50, 0.68];
  final barH = (size * 0.10).round();
  final barLeft = (size * 0.30).round();
  final barRight = size - (size * 0.16).round();
  final tagLeft = (size * 0.16).round();
  final tagRight = barLeft - (size * 0.04).round();

  for (var i = 0; i < 3; i++) {
    final cy = (size * centerYs[i]).round();
    final top = cy - barH ~/ 2;
    final bottom = cy + barH ~/ 2;

    // Severity tag (rounded rect on the left).
    _fillRoundedRect(
      image,
      tagLeft,
      top,
      tagRight - tagLeft,
      bottom - top,
      barH ~/ 3,
      tagColors[i],
    );

    // Log line bar.
    _fillRoundedRect(
      image,
      barLeft,
      top,
      barRight - barLeft,
      bottom - top,
      barH ~/ 3,
      barColor,
    );
  }

  return image;
}

void _fillRoundedRect(
  img.Image image,
  int x,
  int y,
  int w,
  int h,
  int radius,
  img.Color color,
) {
  if (w <= 0 || h <= 0) return;
  final r = radius.clamp(0, (w / 2).floor()).clamp(0, (h / 2).floor()).toInt();
  // Center column.
  img.fillRect(image,
      x1: x + r, y1: y, x2: x + w - r - 1, y2: y + h - 1, color: color);
  // Left strip (above and below corners).
  img.fillRect(image,
      x1: x, y1: y + r, x2: x + r - 1, y2: y + h - r - 1, color: color);
  // Right strip.
  img.fillRect(image,
      x1: x + w - r,
      y1: y + r,
      x2: x + w - 1,
      y2: y + h - r - 1,
      color: color);
  if (r > 0) {
    img.fillCircle(image,
        x: x + r, y: y + r, radius: r, color: color);
    img.fillCircle(image,
        x: x + w - r - 1, y: y + r, radius: r, color: color);
    img.fillCircle(image,
        x: x + r, y: y + h - r - 1, radius: r, color: color);
    img.fillCircle(image,
        x: x + w - r - 1, y: y + h - r - 1, radius: r, color: color);
  }
}
