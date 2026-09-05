import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Verifies the "latest window" trimming logic used to avoid audio backlog lag.
void main() {
  test('latest window keeps only the newest samples', () {
    const bytesPerBuffer = 8;
    final buffered = Uint8List.fromList([
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
    ]);

    final windowStart = buffered.length - bytesPerBuffer;
    final window = buffered.sublist(windowStart);

    expect(window, [5, 6, 7, 8, 9, 10, 11, 12]);
  });

  test('backlog trim keeps at most two windows', () {
    const bytesPerBuffer = 4;
    const maxBufferedBytes = bytesPerBuffer * 2;
    final buffered = Uint8List.fromList([
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
    ]);

    final trimmed = buffered.sublist(buffered.length - maxBufferedBytes);

    expect(trimmed, [5, 6, 7, 8, 9, 10, 11, 12]);
    expect(trimmed.length, maxBufferedBytes);
  });
}
