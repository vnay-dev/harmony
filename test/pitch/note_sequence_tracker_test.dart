import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/note_sequence_tracker.dart';

void main() {
  late NoteSequenceTracker tracker;

  setUp(() {
    tracker = NoteSequenceTracker();
  });

  test('starts empty', () {
    expect(tracker.notes, isEmpty);
    expect(tracker.displayLabel, '—');
  });

  test('records the first stable note once', () {
    tracker.onStablePitch(Pitch.d);
    tracker.onStablePitch(Pitch.d);
    tracker.onStablePitch(Pitch.d);

    expect(tracker.notes, [Pitch.d]);
    expect(tracker.displayLabel, 'D');
  });

  test('appends a new stable note when the pitch changes', () {
    tracker.onStablePitch(Pitch.d);
    tracker.onStablePitch(Pitch.e);
    tracker.onStablePitch(Pitch.fSharp);
    tracker.onStablePitch(Pitch.e);
    tracker.onStablePitch(Pitch.d);

    expect(tracker.notes, [Pitch.d, Pitch.e, Pitch.fSharp, Pitch.e, Pitch.d]);
    expect(tracker.displayLabel, 'D → E → F# → E → D');
  });

  test('does not append when the same note restabilizes immediately', () {
    tracker.onStablePitch(Pitch.d);
    tracker.onStablePitch(Pitch.d);

    expect(tracker.notes, [Pitch.d]);
  });

  test('reset clears the sequence', () {
    tracker.onStablePitch(Pitch.a);
    tracker.onStablePitch(Pitch.b);
    tracker.reset();

    expect(tracker.notes, isEmpty);
    expect(tracker.displayLabel, '—');
  });
}
