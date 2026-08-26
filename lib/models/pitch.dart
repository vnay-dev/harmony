/// The 12 Sa pitch options (C through B).
enum Pitch {
  c('C'),
  cSharp('C#'),
  d('D'),
  dSharp('D#'),
  e('E'),
  f('F'),
  fSharp('F#'),
  g('G'),
  gSharp('G#'),
  a('A'),
  aSharp('A#'),
  b('B');

  const Pitch(this.label);

  /// Display label for the pitch.
  final String label;

  /// Default Sa for V1.
  static const Pitch defaultPitch = Pitch.c;
}
