/// Prepares tutor dialogue text for KittenTTS synthesis.
///
/// Kitten's public API accepts only text, voice, and speed — there is no SSML
/// or pause parameter. Prosody comes from punctuation the phonemizer preserves
/// (commas, full stops, questions, exclamations, ellipses). This helper keeps
/// those cues clear for the model without rewriting dialogue scripts or the
/// on-screen transcript.
///
/// Also lowercases title-case words whose only vowel letter is Y (for example
/// "Try"). Kitten's CE phonemizer historically treated those as mixed-case
/// abbreviations and spelled them as letter names ("T", "R", "Y").
///
/// Leaves true abbreviations with internal capitals (for example "PhD") and
/// normal title-case words that contain A/E/I/O/U unchanged. Does not invent
/// punctuation where the source has none, and does not stack pause markers on
/// top of existing sentence or dialogue boundaries.
String normalizeKittenSpeechText(String text) {
  final modulated = _modulateKittenPunctuation(text);
  return modulated.replaceAllMapped(RegExp(r"\b([A-Z][a-z']*)\b"), (match) {
    final word = match[1]!;
    if (RegExp(r'[aeiouAEIOU]').hasMatch(word)) {
      return word;
    }
    return word.toLowerCase();
  });
}

/// Lightweight punctuation cues for Kitten/Kokoro prosody.
///
/// - Full stops / `?` / `!`: keep a single terminator and a clear space before
///   the next sentence so the model can end and pause naturally.
/// - Commas: keep a single comma with a following space for a short breath.
/// - `…` → `...`: ASCII ellipsis is the trailing-pause form the model expects.
/// - Stacked `!!` / `??`: collapse to one mark (gentle emphasis, not theatrical).
/// - No extra silence markers when punctuation is already present.
String _modulateKittenPunctuation(String text) {
  var output = text;

  // Unicode ellipsis → ASCII trailing-pause cue Kitten's vocabulary knows.
  output = output.replaceAll('…', '...');

  // Fancy dashes → em dash token already in Kitten's punctuation set.
  output = output.replaceAll('\u2013', '\u2014');
  output = output.replaceAll(' - ', ' \u2014 ');

  // Gentle, not theatrical. Leave `...` alone — that is the trailing-pause cue.
  output = output.replaceAllMapped(RegExp(r'!{2,}'), (_) => '!');
  output = output.replaceAllMapped(RegExp(r'\?{2,}'), (_) => '?');

  // "word.Next" → "word. Next" (sentence boundary). Skips decimals (digit after).
  output = output.replaceAllMapped(
    RegExp(r'([.!?])([A-Za-z])'),
    (match) => '${match[1]} ${match[2]}',
  );

  // "word,word" → "word, word" (comma breath). Leaves ", " unchanged.
  output = output.replaceAllMapped(
    RegExp(r',([^\s])'),
    (match) => ', ${match[1]}',
  );

  // Collapse runs of spaces only — do not strip intentional ellipsis dots.
  output = output.replaceAll(RegExp(r' {2,}'), ' ');
  return output.trim();
}
