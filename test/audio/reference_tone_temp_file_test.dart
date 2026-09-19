import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/audio/reference_tone_temp_file.dart';
import 'package:harmony/audio/reference_tone_wav.dart';

void main() {
  test('writeReferenceToneTempFile persists WAV bytes and is deletable', () async {
    final dir = await Directory.systemTemp.createTemp('harmony_ref_test_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final wav = buildReferenceToneWav(
      frequencyHz: 130.81,
      duration: const Duration(milliseconds: 200),
    );

    final file = await writeReferenceToneTempFile(wav, directory: dir);
    expect(await file.exists(), isTrue);
    expect(await file.length(), wav.length);
    expect(file.path.toLowerCase().endsWith('.wav'), isTrue);

    final roundTrip = await file.readAsBytes();
    expect(roundTrip, wav);
    expect(inspectReferenceToneWav(roundTrip).isValid, isTrue);

    await deleteReferenceToneTempFile(file);
    expect(await file.exists(), isFalse);
  });
}
