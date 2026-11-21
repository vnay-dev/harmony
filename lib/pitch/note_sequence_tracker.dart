import 'package:harmony/models/pitch.dart';

/// Builds an ordered sequence of distinct stable sung notes.
///
/// Call [onStablePitch] only when a pitch newly becomes stable. Holding the
/// same stable note does not append duplicates. Returning to a previous note
/// after a different stable note does append it again.
class NoteSequenceTracker {
  final List<Pitch> _notes = <Pitch>[];

  /// Notes in the order they became stable.
  List<Pitch> get notes => List<Pitch>.unmodifiable(_notes);

  /// Human-readable sequence, e.g. `D → E → F#`.
  String get displayLabel {
    if (_notes.isEmpty) {
      return '—';
    }
    return _notes.map((pitch) => pitch.label).join(' → ');
  }

  /// Clears the sequence. Call when a listening session starts.
  void reset() {
    _notes.clear();
  }

  /// Records [pitch] if it is a new stable observation in the sequence.
  void onStablePitch(Pitch pitch) {
    if (_notes.isNotEmpty && _notes.last == pitch) {
      return;
    }
    _notes.add(pitch);
  }
}
