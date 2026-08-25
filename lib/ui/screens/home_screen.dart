import 'package:flutter/material.dart';

import 'package:harmony/app/app_config.dart';
import 'package:harmony/theme/design_tokens.dart';

/// App entry screen shell.
///
/// Feature UI (pitch selection, note toggles, play/pause) will be added here
/// when Shruti functionality is implemented.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceLg),
            child: Text(
              AppConfig.appName,
              style: Theme.of(context).textTheme.displaySmall,
            ),
          ),
        ),
      ),
    );
  }
}
