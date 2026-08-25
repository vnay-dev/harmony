import 'package:flutter/material.dart';

import 'package:harmony/app/app_config.dart';
import 'package:harmony/theme/app_theme.dart';
import 'package:harmony/ui/screens/home_screen.dart';

/// Root widget for the Harmony app.
class HarmonyApp extends StatelessWidget {
  const HarmonyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      theme: AppTheme.light(),
      home: const HomeScreen(),
    );
  }
}
