import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/rules_config.dart';

/// Loads the bundled `assets/rules.json` from a Flutter app context.
Future<RulesConfig> loadDefaultRules() async {
  final raw = await rootBundle.loadString('assets/rules.json');
  return RulesConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
