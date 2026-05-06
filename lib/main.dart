import 'package:flutter/material.dart';

import 'services/settings_service.dart';
import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LogAnalyzerApp());
}

class LogAnalyzerApp extends StatelessWidget {
  const LogAnalyzerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();
    return MaterialApp(
      title: 'Log Analyzer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: HomeScreen(settings: settings),
    );
  }
}
