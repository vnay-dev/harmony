/// Deterministic timing for tutor transcript reveal.
///
/// Paced from the text itself so the typewriter does not wait on audio
/// generation, playback, or bundled clip lengths.
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
    // A short lead-in keeps the first word from flashing in at t=0.
    // The on-screen typewriter still starts on the first frame.
    final leadInMs = (duration.inMilliseconds * 0.04).round().clamp(0, 120);
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

/// Looks up text-paced timing for tutor dialogue lines.
class TutorDialogueTiming {
  const TutorDialogueTiming._();

  /// About 11 characters per second, bounded so short lines stay readable
  /// and long lines do not hold the screen.
  static const minReveal = Duration(milliseconds: 700);
  static const maxReveal = Duration(milliseconds: 8000);
  static const millisecondsPerCharacter = 90;

  static TutorLineTiming? forLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return TutorLineTiming.proportional(trimmed, durationFor(trimmed));
  }

  /// Reveal length for [line], independent of recordings and TTS.
  static Duration durationFor(String line) {
    final estimatedMs = (line.trim().length * millisecondsPerCharacter).clamp(
      minReveal.inMilliseconds,
      maxReveal.inMilliseconds,
    );
    return Duration(milliseconds: estimatedMs);
  }
}
