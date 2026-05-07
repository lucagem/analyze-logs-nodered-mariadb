import 'dart:convert';

import 'package:flutter/material.dart';

/// Builds a syntax-highlighted [TextSpan] tree from a parsed JSON value
/// (Map / List / primitives). Mirrors the VSCode "Light+" palette so it
/// reads well on the report viewer's default light theme.
class JsonHighlighter {
  JsonHighlighter({this.indent = 2});

  /// Number of spaces per nesting level.
  final int indent;

  static const Color _bracket = Color(0xFF24292E); // near black
  static const Color _key = Color(0xFF005CC5); // blue
  static const Color _string = Color(0xFF22863A); // green
  static const Color _number = Color(0xFFB31D28); // dark red
  static const Color _boolean = Color(0xFF6F42C1); // purple
  static const Color _nullColor = Color(0xFFD73A49); // red/pink
  static const Color _punct = Color(0xFF586069); // gray

  static const _baseStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    height: 1.45,
    color: _bracket,
  );

  /// Returns a single root span containing the whole tree of children.
  TextSpan highlight(dynamic value) {
    final children = <InlineSpan>[];
    _emit(value, 0, children);
    return TextSpan(style: _baseStyle, children: children);
  }

  void _emit(dynamic v, int depth, List<InlineSpan> out) {
    if (v == null) {
      out.add(const TextSpan(text: 'null', style: TextStyle(color: _nullColor, fontStyle: FontStyle.italic)));
    } else if (v is bool) {
      out.add(TextSpan(text: '$v', style: const TextStyle(color: _boolean, fontStyle: FontStyle.italic)));
    } else if (v is num) {
      out.add(TextSpan(text: '$v', style: const TextStyle(color: _number)));
    } else if (v is String) {
      out.add(TextSpan(text: jsonEncode(v), style: const TextStyle(color: _string)));
    } else if (v is Map) {
      _emitMap(v, depth, out);
    } else if (v is List) {
      _emitList(v, depth, out);
    } else {
      out.add(TextSpan(text: jsonEncode(v.toString()), style: const TextStyle(color: _string)));
    }
  }

  void _emitMap(Map m, int depth, List<InlineSpan> out) {
    if (m.isEmpty) {
      out.add(const TextSpan(text: '{}', style: TextStyle(color: _bracket)));
      return;
    }
    out.add(const TextSpan(text: '{\n', style: TextStyle(color: _bracket)));
    final keys = m.keys.toList();
    for (var i = 0; i < keys.length; i++) {
      out.add(TextSpan(text: _pad(depth + 1)));
      out.add(TextSpan(
        text: jsonEncode(keys[i].toString()),
        style: const TextStyle(color: _key, fontWeight: FontWeight.w600),
      ));
      out.add(const TextSpan(text: ': ', style: TextStyle(color: _punct)));
      _emit(m[keys[i]], depth + 1, out);
      if (i < keys.length - 1) {
        out.add(const TextSpan(text: ',', style: TextStyle(color: _punct)));
      }
      out.add(const TextSpan(text: '\n'));
    }
    out.add(TextSpan(text: _pad(depth), style: const TextStyle(color: _bracket)));
    out.add(const TextSpan(text: '}', style: TextStyle(color: _bracket)));
  }

  void _emitList(List l, int depth, List<InlineSpan> out) {
    if (l.isEmpty) {
      out.add(const TextSpan(text: '[]', style: TextStyle(color: _bracket)));
      return;
    }
    out.add(const TextSpan(text: '[\n', style: TextStyle(color: _bracket)));
    for (var i = 0; i < l.length; i++) {
      out.add(TextSpan(text: _pad(depth + 1)));
      _emit(l[i], depth + 1, out);
      if (i < l.length - 1) {
        out.add(const TextSpan(text: ',', style: TextStyle(color: _punct)));
      }
      out.add(const TextSpan(text: '\n'));
    }
    out.add(TextSpan(text: _pad(depth), style: const TextStyle(color: _bracket)));
    out.add(const TextSpan(text: ']', style: TextStyle(color: _bracket)));
  }

  String _pad(int depth) => ' ' * (depth * indent);
}
