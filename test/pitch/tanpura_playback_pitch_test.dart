import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/tanpura_playback_pitch.dart';

void main() {
  test('paForSa is a perfect fifth above Sa', () {
    expect(TanpuraPlaybackPitch.paForSa(Pitch.c), Pitch.g);
    expect(TanpuraPlaybackPitch.paForSa(Pitch.d), Pitch.a);
    expect(TanpuraPlaybackPitch.paForSa(Pitch.fSharp), Pitch.cSharp);
  });

  test('detects frequencies near the Pa of the playing Sa sample', () {
    final paHz = frequencyHzForPitch(Pitch.g, octave: 3);

    expect(
      TanpuraPlaybackPitch.isNearPlaybackFundamental(
        frequencyHz: paHz,
        saPitch: Pitch.c,
      ),
      isTrue,
    );
    expect(
      TanpuraPlaybackPitch.isNearPlaybackFundamental(
        frequencyHz: paHz * 1.01,
        saPitch: Pitch.c,
      ),
      isTrue,
    );
  });

  test('does not treat an unrelated sung pitch as playback leakage', () {
    final userHz = frequencyHzForPitch(Pitch.d);

    expect(
      TanpuraPlaybackPitch.isNearPlaybackFundamental(
        frequencyHz: userHz,
        saPitch: Pitch.c,
      ),
      isFalse,
    );
  });

  test('matches Pa across nearby octaves', () {
    final paOctave2 = frequencyHzForPitch(Pitch.g, octave: 2);
    final paOctave4 = frequencyHzForPitch(Pitch.g, octave: 4);

    expect(
      TanpuraPlaybackPitch.isNearPlaybackFundamental(
        frequencyHz: paOctave2,
        saPitch: Pitch.c,
      ),
      isTrue,
    );
    expect(
      TanpuraPlaybackPitch.isNearPlaybackFundamental(
        frequencyHz: paOctave4,
        saPitch: Pitch.c,
      ),
      isTrue,
    );
  });
}
