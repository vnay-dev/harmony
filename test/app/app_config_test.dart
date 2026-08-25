import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/app/app_config.dart';

void main() {
  test('AppConfig exposes Harmony branding', () {
    expect(AppConfig.appName, 'Harmony');
    expect(AppConfig.description, isNotEmpty);
  });
}
