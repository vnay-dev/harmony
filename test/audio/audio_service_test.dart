import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/audio/audio_service.dart';

void main() {
  test('AudioService starts idle', () {
    final service = AudioService();

    expect(service.isPlaying, isFalse);
  });

  test('play is not implemented yet', () async {
    final service = AudioService();

    expect(service.play, throwsA(isA<UnimplementedError>()));
  });

  test('pause is not implemented yet', () async {
    final service = AudioService();

    expect(service.pause, throwsA(isA<UnimplementedError>()));
  });

  test('dispose resets playing state', () async {
    final service = AudioService();

    await service.dispose();

    expect(service.isPlaying, isFalse);
  });
}
