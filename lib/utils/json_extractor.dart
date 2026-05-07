import 'dart:convert';

class JsonMatch {
  JsonMatch({
    required this.start,
    required this.end,
    required this.raw,
    required this.parsed,
    this.unescaped = false,
    this.bestEffort = false,
    this.bestEffortText,
  });

  /// Start index (inclusive) within the source string.
  final int start;

  /// End index (exclusive) within the source string.
  final int end;

  /// The raw substring as it appears in the log line (may still contain
  /// `\"` escapes when [unescaped] is true).
  final String raw;

  /// The decoded value (Map, List, primitive…). `null` when the snippet
  /// could not be parsed and is being surfaced in best-effort mode.
  final dynamic parsed;

  /// True when the snippet had to be un-escaped (it was logged as a
  /// JSON-encoded string, e.g. `{\"uuid\":null,…}`) before parsing
  /// could succeed.
  final bool unescaped;

  /// True for "best-effort" matches: the bracketed region looked like
  /// JSON but failed to parse. [parsed] is `null` and [bestEffortText]
  /// holds the un-escaped raw text so the user can at least read it.
  final bool bestEffort;

  /// Un-escaped raw text used when [bestEffort] is true.
  final String? bestEffortText;

  /// Pretty-printed (2-space indent) representation of [parsed], or the
  /// best-effort un-escaped text when the snippet couldn't be parsed.
  String get pretty {
    if (parsed != null) return const JsonEncoder.withIndent('  ').convert(parsed);
    return bestEffortText ?? raw;
  }

  /// Short label for buttons / chips: `{name, age, …}` or `[3 items]`.
  String get label {
    if (bestEffort) {
      final n = (bestEffortText ?? raw).length;
      return '~$n chars';
    }
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
/// (`[ ... ]`). Handles two real-world cases found in container logs:
///
/// 1. **Plain JSON** — e.g. `info: {"id":42}`.
/// 2. **JSON-encoded JSON** — values that were `JSON.stringify`'d before
///    being logged inside another field, so every `"` becomes `\"`
///    (and every `\` becomes `\\`). Example from a Node-RED log:
///    `{\"uuid\":null,\"query\":\"UPDATE …\",\"retryMax\":0}`.
///    These are recovered by wrapping the snippet in surrounding `"`
///    and decoding it twice — `jsonDecode` itself does the un-escape.
class JsonExtractor {
  /// Minimum length for a candidate to be considered (avoids `{}` or `[]`
  /// noise in normal sentences).
  static const _minLength = 4;

  /// Minimum size for a best-effort match — we don't want to surface
  /// tiny `{...}` regions that just happened to contain malformed text.
  static const _bestEffortMinLength = 100;

  static List<JsonMatch> findAll(String text) {
    // Pass 1 — quote-aware scanner; works for plain JSON.
    final out = _scanWith(text, _findMatchingBracketStandard);
    if (out.isNotEmpty) return out;

    // Pass 2 — only run if the text shows escape-encoded markers. Uses a
    // backslash-aware scanner so `\"` doesn't open/close a string.
    if (text.contains(r'\"')) {
      out.addAll(_scanWith(text, _findMatchingBracketBackslashAware));
    }
    return out;
  }

  /// Like [findAll], plus surfaces large bracketed regions that *look*
  /// like JSON but failed to parse — useful for the loose pseudo-JSON
  /// dumps some loggers emit (unclosed string values, arrays serialised
  /// as quoted strings, etc.). The extra entries carry [bestEffort] =
  /// true and a [bestEffortText] field holding the un-escaped raw text.
  static List<JsonMatch> findAllWithBestEffort(String text) {
    final valid = findAll(text);
    final exact = valid.map((m) => '${m.start}-${m.end}').toSet();
    final out = [...valid];

    var i = 0;
    while (i < text.length) {
      final c = text.codeUnitAt(i);
      if (c == 0x7B || c == 0x5B) {
        final end = _findMatchingBracketBackslashAware(text, i);
        if (end != -1 && (end - i + 1) >= _bestEffortMinLength) {
          final key = '$i-${end + 1}';
          if (!exact.contains(key)) {
            // Skip if entirely contained in a successfully-parsed entry
            // (those are usually small valid JSONs nested in big malformed
            // ones — we still want the big one as best-effort).
            final containedInValid = valid.any(
              (m) => m.start <= i && m.end >= end + 1 && (m.end - m.start) > (end - i + 1) ~/ 2,
            );
            if (!containedInValid) {
              final snippet = text.substring(i, end + 1);
              final un = tryUnescapeOnly(snippet);
              if (un != null && un.length >= _bestEffortMinLength) {
                out.add(JsonMatch(
                  start: i,
                  end: end + 1,
                  raw: snippet,
                  parsed: null,
                  unescaped: snippet != un,
                  bestEffort: true,
                  bestEffortText: un,
                ));
                i = end + 1;
                continue;
              }
            }
          }
        }
      }
      i++;
    }

    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  /// Best-effort un-escape that doesn't try to parse the result as JSON.
  /// Wraps [text] in `"…"` and decodes once via `jsonDecode` (handles
  /// `\"`, `\\`, `\n`, `\uXXXX`); falls back to a literal replacement
  /// when the wrap-decode trick can't be applied.
  static String? tryUnescapeOnly(String text) {
    try {
      final wrapped = '"$text"';
      final un = jsonDecode(wrapped);
      if (un is String) return un;
    } catch (_) {}
    if (text.contains(r'\"')) {
      // Naive fallback: protect existing escaped backslashes, swap the
      // remaining `\"`, then restore. Imperfect but readable.
      const sentinel = '';
      return text
          .replaceAll(r'\\', sentinel)
          .replaceAll(r'\"', '"')
          .replaceAll(sentinel, r'\');
    }
    return null;
  }

  /// Tries to parse the entire string as JSON. Falls back to:
  ///  - re-decoding when the first parse returned a JSON-shaped String
  ///    (text was double-encoded with surrounding quotes);
  ///  - wrapping in `"` and double-decoding when the text contains `\"`
  ///    escapes but no surrounding string quotes.
  static JsonMatch? tryParseWhole(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // 1) Direct decode.
    final direct = _tryDecode(trimmed);
    if (direct != null) {
      if (direct is String && _looksLikeJsonContainer(direct)) {
        final inner = _tryDecode(direct);
        if (inner != null && inner is! String) {
          return JsonMatch(
            start: 0,
            end: trimmed.length,
            raw: trimmed,
            parsed: inner,
            unescaped: true,
          );
        }
      }
      return JsonMatch(
        start: 0,
        end: trimmed.length,
        raw: trimmed,
        parsed: direct,
      );
    }

    // 2) Wrap and double-decode (`\"` → `"`).
    if (trimmed.contains(r'\"')) {
      final un = _tryUnescapeAndDecode(trimmed);
      if (un != null) {
        return JsonMatch(
          start: 0,
          end: trimmed.length,
          raw: trimmed,
          parsed: un,
          unescaped: true,
        );
      }
    }

    // 3) Maybe the text starts/ends mid-line; pick the first JSON
    //    snippet found by findAll.
    final all = findAll(trimmed);
    if (all.isNotEmpty) return all.first;

    // 4) Best-effort: at least un-escape the content so the user can
    //    read it even when it's malformed JSON-ish output.
    final un = tryUnescapeOnly(trimmed);
    if (un != null && un != trimmed) {
      return JsonMatch(
        start: 0,
        end: trimmed.length,
        raw: trimmed,
        parsed: null,
        unescaped: true,
        bestEffort: true,
        bestEffortText: un,
      );
    }

    return null;
  }

  // ───────── internals ─────────

  static List<JsonMatch> _scanWith(
    String text,
    int Function(String, int) findEnd,
  ) {
    final results = <JsonMatch>[];
    var i = 0;
    while (i < text.length) {
      final c = text.codeUnitAt(i);
      // '{' = 0x7B, '[' = 0x5B
      if (c == 0x7B || c == 0x5B) {
        final end = findEnd(text, i);
        if (end != -1 && (end - i) >= _minLength) {
          final snippet = text.substring(i, end + 1);
          final parsed = _tryDecode(snippet);
          if (parsed != null) {
            results.add(JsonMatch(
              start: i,
              end: end + 1,
              raw: snippet,
              parsed: parsed,
            ));
            i = end + 1;
            continue;
          }
          if (snippet.contains(r'\"')) {
            final un = _tryUnescapeAndDecode(snippet);
            if (un != null) {
              results.add(JsonMatch(
                start: i,
                end: end + 1,
                raw: snippet,
                parsed: un,
                unescaped: true,
              ));
              i = end + 1;
              continue;
            }
          }
        }
      }
      i++;
    }
    return results;
  }

  static dynamic _tryDecode(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  /// Wraps [s] in `"…"` so jsonDecode performs JSON-string unescaping
  /// (handles `\"`, `\\`, `\n`, `\u00..`, etc.), then decodes the
  /// resulting string as JSON. Returns the inner value or null on failure.
  static dynamic _tryUnescapeAndDecode(String s) {
    try {
      final wrapped = '"$s"';
      final un = jsonDecode(wrapped);
      if (un is String) return jsonDecode(un);
    } catch (_) {}
    return null;
  }

  static bool _looksLikeJsonContainer(String s) {
    final t = s.trim();
    return t.startsWith('{') || t.startsWith('[');
  }

  /// Standard quote-aware bracket matcher (ignores `{`/`}` inside JSON
  /// strings).
  static int _findMatchingBracketStandard(String s, int start) {
    final open = s.codeUnitAt(start);
    final close = open == 0x7B ? 0x7D : 0x5D;
    var depth = 0;
    var inStr = false;
    for (var i = start; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (inStr) {
        if (c == 0x5C /* \ */) {
          i++; // skip the escaped char
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

  /// Backslash-aware scanner for content where every `"` is escaped to
  /// `\"`. Treats `\X` as a 2-char literal escape (so `\"` doesn't open
  /// or close a JSON string) and counts brackets directly.
  static int _findMatchingBracketBackslashAware(String s, int start) {
    final open = s.codeUnitAt(start);
    final close = open == 0x7B ? 0x7D : 0x5D;
    var depth = 0;
    var i = start;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x5C /* \ */ && i + 1 < s.length) {
        i += 2;
        continue;
      }
      if (c == open) {
        depth++;
      } else if (c == close) {
        depth--;
        if (depth == 0) return i;
      }
      i++;
    }
    return -1;
  }
}
