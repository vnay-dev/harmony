import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/theme/design_tokens.dart';

void main() {
  test('DesignTokens define core spacing scale', () {
    expect(DesignTokens.spaceXs, 4);
    expect(DesignTokens.spaceSm, 8);
    expect(DesignTokens.spaceMd, 16);
    expect(DesignTokens.spaceLg, 24);
    expect(DesignTokens.spaceXl, 32);
  });

  test('DesignTokens define core typography sizes', () {
    expect(DesignTokens.fontSizeBody, 16);
    expect(DesignTokens.fontSizeTitle, 24);
    expect(DesignTokens.fontSizeDisplay, 32);
  });
}
