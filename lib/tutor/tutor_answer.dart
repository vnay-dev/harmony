/// Semantic answers the tutor accepts for spoken / typed questions.
enum TutorYesNoAnswer { yes, no, unclear }

/// Comfort answers for the upper-sound question.
enum TutorComfortAnswer { comfortable, notComfortable, unclear }

/// Parses natural-language yes/no and comfort replies without technical jargon.
class TutorAnswerParser {
  const TutorAnswerParser();

  /// Interprets a yes/no reply (e.g. audibility).
  TutorYesNoAnswer parseYesNo(String raw) {
    final text = _normalize(raw);
    if (text.isEmpty) {
      return TutorYesNoAnswer.unclear;
    }

    // Check NO first so phrases like "I couldn't" are not matched as "I could".
    if (_matchesAny(text, const [
      'no',
      'nope',
      'nah',
      'not really',
      'couldn\'t',
      'could not',
      'i couldn\'t',
      'i couldn\'t hear',
      'i couldn\'t hear it',
      'couldn\'t hear',
      'didn\'t',
      'did not',
      'too low',
      'too quiet',
      'not comfortable',
      'uncomfortable',
      'that felt uncomfortable',
    ])) {
      return TutorYesNoAnswer.no;
    }

    if (_matchesAny(text, const [
      'yes',
      'yeah',
      'yep',
      'yup',
      'sure',
      'ok',
      'okay',
      'i could',
      'yes i could',
      'i heard',
      'heard it',
      'i heard it',
      'yes i heard it',
      'comfortable',
      'that felt comfortable',
    ])) {
      return TutorYesNoAnswer.yes;
    }

    return TutorYesNoAnswer.unclear;
  }

  /// Interprets a comfort reply for the higher sound.
  TutorComfortAnswer parseComfort(String raw) {
    final text = _normalize(raw);
    if (text.isEmpty) {
      return TutorComfortAnswer.unclear;
    }

    if (_matchesAny(text, const [
      'not comfortable',
      'uncomfortable',
      'that felt uncomfortable',
      'strained',
      'strain',
      'too high',
      'too much',
      'hard',
      'difficult',
      'no',
      'nope',
    ])) {
      return TutorComfortAnswer.notComfortable;
    }

    if (_matchesAny(text, const [
      'comfortable',
      'that felt comfortable',
      'comfort',
      'fine',
      'good',
      'easy',
      'feels good',
      'okay',
      'ok',
      'yes',
      'yeah',
      'great',
    ])) {
      return TutorComfortAnswer.comfortable;
    }

    return TutorComfortAnswer.unclear;
  }

  String _normalize(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp("[^\\w\\s']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _matchesAny(String text, List<String> needles) {
    final padded = ' $text ';
    for (final needle in needles) {
      if (padded.contains(' $needle ')) {
        return true;
      }
    }
    return false;
  }
}
