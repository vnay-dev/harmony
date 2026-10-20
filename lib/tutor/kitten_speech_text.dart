/// Normalizes tutor dialogue text before KittenTTS phonemization.
///
/// Kitten's CE phonemizer historically treated title-case words whose only
/// vowel letter is Y (for example "Try") as mixed-case abbreviations and spelled
/// them as letter names ("T", "R", "Y"). Lowercasing those title-case tokens
/// keeps ordinary English pronunciation without rewriting dialogue scripts.
///
/// Leaves true abbreviations with internal capitals (for example "PhD") and
/// normal title-case words that contain A/E/I/O/U unchanged.
String normalizeKittenSpeechText(String text) {
  return text.replaceAllMapped(RegExp(r"\b([A-Z][a-z']*)\b"), (match) {
    final word = match[1]!;
    if (RegExp(r'[aeiouAEIOU]').hasMatch(word)) {
      return word;
    }
    return word.toLowerCase();
  });
}
