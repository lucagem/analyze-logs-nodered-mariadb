import 'dart:convert';

class JsonMatch {
  JsonMatch({
    required this.start,
    required this.end,
    required this.raw,
    required this.parsed,
  });

  /// Start index (inclusive) within the source string.
  final int start;

  /// End index (exclusive) within the source string.
  final int end;

  /// The raw JSON substring as it appears in the log line.
  final String raw;

  /// The decoded value (Map, List, primitive…).
  final dynamic parsed;

  /// Pretty-printed (2-space indent) representation of [parsed].
  String get pretty => const JsonEncoder.withIndent('  ').convert(parsed);

  /// Short label for buttons / chips: `{name, age, …}` or `[3 items]`.
  String get label {
    final v = parsed;
    if (v is Map) {
      final keys = v.keys.take(3).join(', ');
      final more = v.length > 3 ? ', …' : '';
      return '{ $keys$more }';
    }
    if (v is List) {
      return '[ ${v.length} item${v.length == 1 ? '' : 's'} ]';
    }
    return raw.length > 30 ? '${raw.substring(0, 30)}…' : raw;
  }
}

/// Scans a string for balanced JSON objects (`{ ... }`) and arrays
/// (`[ ... ]`) and returns the ones that successfully `jsonDecode`.
///
/// Tries to be practical about real log content: ignores text before/after
/// the candidate and skips substrings that fail to parse instead of aborting.
class JsonExtractor {
  /// Minimum length for a candidate to be considered (avoids `{}` or `[]`
  /// noise in normal sentences).
  static const _minLength = 4;

  static List<JsonMatch> findAll(String text) {
    final results = <JsonMatch>[];
    var i = 0;
    while (i < text.length) {
      final c = text.codeUnitAt(i);
      // '{' = 0x7B, '[' = 0x5B
      if (c == 0x7B || c == 0x5B) {
        final end = _findMatchingBracket(text, i);
        if (end != -1 && (end - i) >= _minLength) {
          final snippet = text.substring(i, end + 1);
          try {
            final parsed = jsonDecode(snippet);
            results.add(JsonMatch(
              start: i,
              end: end + 1,
              raw: snippet,
              parsed: parsed,
            ));
            i = end + 1;
            continue;
          } catch (_) {
            // Not valid JSON — try the next opening bracket.
          }
        }
      }
      i++;
    }
    return results;
  }

  /// Tries to parse the entire string as JSON. Useful for the "manual
  /// paste" path where the user already trimmed the relevant snippet.
  static JsonMatch? tryParseWhole(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    try {
      final parsed = jsonDecode(trimmed);
      return JsonMatch(
        start: 0,
        end: trimmed.length,
        raw: trimmed,
        parsed: parsed,
      );
    } catch (_) {
      return null;
    }
  }

  /// Finds the index of the matching closing bracket starting at [start].
  /// Honors string literals and escapes. Returns -1 if unbalanced.
  static int _findMatchingBracket(String s, int start) {
    final open = s.codeUnitAt(start);
    final close = open == 0x7B ? 0x7D : 0x5D;
    var depth = 0;
    var inStr = false;
    for (var i = start; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (inStr) {
        if (c == 0x5C /* \ */) {
          i++; // skip escaped char
          continue;
        }
        if (c == 0x22 /* " */) inStr = false;
      } else {
        if (c == 0x22) {
          inStr = true;
        } else if (c == open) {
          depth++;
        } else if (c == close) {
          depth--;
          if (depth == 0) return i;
        }
      }
    }
    return -1;
  }
}
