/// The 12 Sa pitch options (C through B).
enum Pitch {
  c('C', 'Sa'),
  cSharp('C#', 're (k)'),
  d('D', 'Re'),
  dSharp('D#', 'ga (k)'),
  e('E', 'Ga'),
  f('F', 'Ma'),
  fSharp('F#', 'Ma (t)'),
  g('G', 'Pa'),
  gSharp('G#', 'dha (k)'),
  a('A', 'Dha'),
  aSharp('A#', 'ni (k)'),
  b('B', 'Ni');

  const Pitch(this.label, this.swara);

  /// Machine / asset label for the pitch (`C`, `C#`, …).
  final String label;

  /// Swara name shown under this note in the Shruti picker.
  final String swara;

  /// On-screen pitch spelling (`C♯` instead of `C#`).
  String get displayLabel => formatShrutiDisplayLabel(label);

  /// Spoken pitch name for tutor dialogue (`C sharp` instead of `C#`).
  String get spokenLabel => formatShrutiSpokenLabel(label);

  /// Default Sa for V1.
  static const Pitch defaultPitch = Pitch.c;

  /// Next pitch in chromatic order, wrapping from B to C.
  Pitch get next => Pitch.values[(index + 1) % Pitch.values.length];

  /// Previous pitch in chromatic order, wrapping from C to B.
  Pitch get previous =>
      Pitch.values[(index - 1 + Pitch.values.length) % Pitch.values.length];
}

/// Pretty on-screen spelling for a pitch label (`C#` → `C♯`).
String formatShrutiDisplayLabel(String label) => label.replaceAll('#', '♯');

/// Natural spoken spelling for a pitch label (`C#` / `C♯` → `C sharp`).
String formatShrutiSpokenLabel(String label) {
  return label
      .replaceAll('♯', '#')
      .replaceAllMapped(
        RegExp(r'([A-Ga-g])#'),
        (match) => '${match[1]!.toUpperCase()} sharp',
      );
}
