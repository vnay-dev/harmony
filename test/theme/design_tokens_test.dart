import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/material.dart';
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

  test('listeningAccent stays in the warm listening family, not blue accent', () {
    expect(DesignTokens.listeningAccent, isNot(DesignTokens.accent));
    expect(DesignTokens.listeningAccent, isNot(DesignTokens.listeningEdge));
    // Soft apricot between rim and edge — lighter than the orb's darkest rim.
    expect(DesignTokens.listeningAccent, const Color(0xFFE5B584));
  });
}
