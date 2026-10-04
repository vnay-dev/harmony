/// Shared compliment-word detection for Tutor Mode on-screen text.
///
/// Spoken dialogue is never rewritten. The UI inserts the Stage 1 celebration
/// treatment (` 💙!`) after a recognized compliment adjective and drops a
/// following period when present.
abstract final class TutorCompliment {
  const TutorCompliment._();

  /// Positive adjectives that receive the Stage 1 celebration treatment.
  static const List<String> words = <String>[
    'Beautiful',
    'Wonderful',
    'Amazing',
    'Lovely',
    'Great',
    'Excellent',
    'Fantastic',
  ];

  static final RegExp _wordPattern = RegExp(
    '\\b(${words.map(RegExp.escape).join('|')})\\b',
    caseSensitive: false,
  );

  /// Whether [text] contains a recognized compliment adjective.
  static bool containsCompliment(String text) =>
      celebrationInsertIndex(text) >= 0;

  /// Character index immediately after the first compliment word, or `-1`.
  ///
  /// Callers insert ` 💙!` at this index and skip a following `.` so
  /// `"Beautiful. You did it."` renders as `"Beautiful 💙! You did it."`.
  static int celebrationInsertIndex(String text) {
    final match = _wordPattern.firstMatch(text);
    return match?.end ?? -1;
  }
}
