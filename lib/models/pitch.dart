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

  /// Display label for the pitch.
  final String label;

  /// Swara name shown under this note in the Shruti picker.
  final String swara;

  /// Default Sa for V1.
  static const Pitch defaultPitch = Pitch.c;

  /// Next pitch in chromatic order, wrapping from B to C.
  Pitch get next => Pitch.values[(index + 1) % Pitch.values.length];

  /// Previous pitch in chromatic order, wrapping from C to B.
  Pitch get previous =>
      Pitch.values[(index - 1 + Pitch.values.length) % Pitch.values.length];
}
