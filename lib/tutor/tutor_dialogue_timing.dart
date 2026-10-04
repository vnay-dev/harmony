import 'package:harmony/tutor/tutor_audio_catalog.dart';

/// Deterministic timing for tutor transcript reveal.
///
/// Tied to measured recording durations via [TutorAudioCatalog]. Characters are
/// paced evenly across the clip so the visual transcript tracks speech without
/// runtime audio analysis.
class TutorLineTiming {
  const TutorLineTiming({
    required this.duration,
    required this.words,
    required this.wordEndTimes,
  });

  final Duration duration;
  final List<String> words;
  final List<Duration> wordEndTimes;

  /// Builds proportional word end-times for [text] spanning [duration].
  factory TutorLineTiming.proportional(String text, Duration duration) {
    final words = text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty || duration <= Duration.zero) {
      return TutorLineTiming(
        duration: duration,
        words: words,
        wordEndTimes: const <Duration>[],
      );
    }

    final weights = words
        .map(
          (word) => word.replaceAll(RegExp(r"[^\w']"), '').length.clamp(1, 32),
        )
        .toList(growable: false);
    final totalWeight = weights.fold<int>(0, (sum, weight) => sum + weight);
    // Leave a short lead-in so the first word does not appear before speech.
    final leadInMs = (duration.inMilliseconds * 0.04).round().clamp(40, 180);
    final speakMs = (duration.inMilliseconds - leadInMs).clamp(
      1,
      duration.inMilliseconds,
    );

    var consumed = 0;
    final ends = <Duration>[];
    for (var i = 0; i < words.length; i++) {
      consumed += weights[i];
      final endMs = leadInMs + ((speakMs * consumed) / totalWeight).round();
      ends.add(Duration(milliseconds: endMs.clamp(0, duration.inMilliseconds)));
    }
    return TutorLineTiming(
      duration: duration,
      words: words,
      wordEndTimes: ends,
    );
  }

  /// Visible prefix of [words] for [elapsed] speech time.
  String visibleTextAt(Duration elapsed) {
    if (words.isEmpty) {
      return '';
    }
    if (elapsed >= duration) {
      return words.join(' ');
    }
    var count = 0;
    for (var i = 0; i < wordEndTimes.length; i++) {
      if (elapsed >= wordEndTimes[i]) {
        count = i + 1;
      } else {
        break;
      }
    }
    if (count <= 0) {
      return '';
    }
    return words.take(count).join(' ');
  }

  /// 0–1 progress through the spoken line.
  double progressAt(Duration elapsed) {
    if (duration <= Duration.zero) {
      return 1;
    }
    return (elapsed.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }
}

/// Looks up timing metadata for tutor dialogue lines.
class TutorDialogueTiming {
  const TutorDialogueTiming._();

  /// Measured clip lengths for bundled tutor recordings (`ffprobe`).
  static const Map<String, Duration> _clipDurations = <String, Duration>{
    'S01': Duration(milliseconds: 3204),
    'S02': Duration(milliseconds: 2833),
    'S03': Duration(milliseconds: 2415),
    'S04': Duration(milliseconds: 1765),
    'S05': Duration(milliseconds: 3158),
    'S06': Duration(milliseconds: 2276),
    'S07': Duration(milliseconds: 2647),
    'S08': Duration(milliseconds: 882),
    'S09': Duration(milliseconds: 789),
    'S10': Duration(milliseconds: 2647),
    'S11': Duration(milliseconds: 3529),
    'S12': Duration(milliseconds: 2601),
    'S13': Duration(milliseconds: 2833),
    'S14': Duration(milliseconds: 3576),
    'S15': Duration(milliseconds: 1486),
    'S17': Duration(milliseconds: 1904),
    'S18': Duration(milliseconds: 1765),
    'S19': Duration(milliseconds: 2740),
    'S20': Duration(milliseconds: 2647),
    'S21': Duration(milliseconds: 1858),
    'S22': Duration(milliseconds: 1904),
    'S23': Duration(milliseconds: 1811),
    'S24': Duration(milliseconds: 1858),
    'S25': Duration(milliseconds: 2786),
    'S26': Duration(milliseconds: 1533),
    'S27': Duration(milliseconds: 2786),
    'S28': Duration(milliseconds: 2740),
    'S29': Duration(milliseconds: 1672),
    'S30': Duration(milliseconds: 1811),
    'S31': Duration(milliseconds: 3111),
    'S32': Duration(milliseconds: 3297),
    'S33': Duration(milliseconds: 1811),
    'S34': Duration(milliseconds: 5573),
    'S35': Duration(milliseconds: 3158),
    'S36': Duration(milliseconds: 1950),
    'S37': Duration(milliseconds: 3994),
    'S38': Duration(milliseconds: 2276),
    'S39': Duration(milliseconds: 3947),
    'S40': Duration(milliseconds: 1765),
    'S41': Duration(milliseconds: 1904),
    'S42': Duration(milliseconds: 1765),
    'S43': Duration(milliseconds: 1904),
    'S44': Duration(milliseconds: 1718),
    'S45': Duration(milliseconds: 1765),
    'S46': Duration(milliseconds: 1904),
    'S47': Duration(milliseconds: 1904),
    'S48': Duration(milliseconds: 1950),
    'S49': Duration(milliseconds: 1858),
    'S50': Duration(milliseconds: 1765),
    'S51': Duration(milliseconds: 1765),
    'S52': Duration(milliseconds: 3019),
    'S53': Duration(milliseconds: 2647),
    'S60': Duration(milliseconds: 2229),
    'S61': Duration(milliseconds: 3808),
    'S62': Duration(milliseconds: 2740),
    'S63': Duration(milliseconds: 4458),
    'S64': Duration(milliseconds: 5062),
    'S65': Duration(milliseconds: 2926),
    'S66': Duration(milliseconds: 4505),
    'S67': Duration(milliseconds: 2322),
    'S68': Duration(milliseconds: 1533),
    'S69': Duration(milliseconds: 2050),
    'S70': Duration(milliseconds: 2879),
    'S71': Duration(milliseconds: 5155),
    'S72': Duration(milliseconds: 4505),
    'S73': Duration(milliseconds: 3808),
    'S74': Duration(milliseconds: 7663),
    'S75': Duration(milliseconds: 2136),
    'S76': Duration(milliseconds: 2926),
  };

  static TutorLineTiming? forLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final duration = _durationForLine(trimmed);
    return TutorLineTiming.proportional(trimmed, duration);
  }

  static Duration _durationForLine(String line) {
    final assetIds = _assetIdsForLine(line);
    if (assetIds != null && assetIds.isNotEmpty) {
      var totalMs = 0;
      var allKnown = true;
      for (final id in assetIds) {
        final clip = _clipDurations[id];
        if (clip == null) {
          allKnown = false;
          break;
        }
        totalMs += clip.inMilliseconds;
      }
      if (allKnown && totalMs > 0) {
        return Duration(milliseconds: totalMs);
      }
    }
    // Fallback for unmapped / silent lines (~11 chars/sec tutor pace).
    final estimatedMs = (line.length * 90).clamp(700, 8000);
    return Duration(milliseconds: estimatedMs);
  }

  static List<String>? _assetIdsForLine(String line) {
    try {
      return TutorAudioCatalog.assetIdsForSpokenLine(line);
    } on StateError {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}
