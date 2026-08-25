import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/app/app.dart';
import 'package:harmony/app/app_config.dart';

void main() {
  testWidgets('HarmonyApp shows the app name', (WidgetTester tester) async {
    await tester.pumpWidget(const HarmonyApp());

    expect(find.text(AppConfig.appName), findsOneWidget);
  });
}
