/// Development-only generator for the Stage 1 sustained "Saaaa..." demo.
///
/// This is intentionally not ElevenLabs spoken TTS. It writes a soft, stable
/// vocal-like hum (~2 seconds) as `assets/audio/tutor/S69.mp3` via ffmpeg,
/// or a WAV fallback if ffmpeg is unavailable.
///
///   dart run tools/generate_saa_demo_audio.dart
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const String _outputDirectory = 'assets/audio/tutor';
const String _assetId = 'S69';
const int _sampleRate = 44100;
const double _durationSeconds = 2.05;
const double _fundamentalHz = 196.0; // G3 — example only, not a target Shruti

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    stderr.writeln('Usage: dart run tools/generate_saa_demo_audio.dart');
    exitCode = 64;
    return;
  }

  final root = _projectRoot();
  if (root == null) {
    stderr.writeln('Could not find the Harmony project root (pubspec.yaml).');
    exitCode = 1;
    return;
  }

  final directory = Directory('${root.path}/$_outputDirectory');
  await directory.create(recursive: true);
  final wavPath = '${directory.path}/$_assetId.wav';
  final mp3Path = '${directory.path}/$_assetId.mp3';

  final pcm = _renderSoftVocal();
  await File(wavPath).writeAsBytes(_wrapWav(pcm), flush: true);

  final ffmpeg = await _findFfmpeg();
  if (ffmpeg == null) {
    stderr.writeln(
      'ffmpeg not found. Wrote $wavPath — convert to MP3 manually, '
      'or install ffmpeg and re-run.',
    );
    // Keep a playable copy name for Flutter assets that expect .mp3 by renaming
    // is wrong; leave WAV and copy bytes only if an mp3 already exists.
    exitCode = 1;
    return;
  }

  final result = await Process.run(ffmpeg, <String>[
    '-y',
    '-i',
    wavPath,
    '-codec:a',
    'libmp3lame',
    '-qscale:a',
    '4',
    mp3Path,
  ]);
  if (result.exitCode != 0) {
    stderr.writeln('ffmpeg failed: ${result.stderr}');
    exitCode = 1;
    return;
  }

  await File(wavPath).delete();
  stdout.writeln('Wrote $mp3Path (${_durationSeconds.toStringAsFixed(2)}s).');
}

Uint8List _renderSoftVocal() {
  final sampleCount = (_sampleRate * _durationSeconds).round();
  final bytes = ByteData(sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    final t = i / _sampleRate;
    final env = _envelope(t, _durationSeconds);
    // Soft vowel-ish mix: fundamental + gentle harmonics (not a pure beep).
    final sample =
        0.55 * math.sin(2 * math.pi * _fundamentalHz * t) +
        0.28 * math.sin(2 * math.pi * _fundamentalHz * 2 * t) +
        0.12 * math.sin(2 * math.pi * _fundamentalHz * 3 * t) +
        0.05 * math.sin(2 * math.pi * _fundamentalHz * 4.2 * t);
    final value = (sample * env * 0.55 * 32767).round().clamp(-32768, 32767);
    bytes.setInt16(i * 2, value, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

double _envelope(double t, double duration) {
  const attack = 0.18;
  const release = 0.35;
  if (t < attack) {
    return _smoothstep(t / attack);
  }
  if (t > duration - release) {
    return _smoothstep((duration - t) / release);
  }
  // Tiny natural shimmer so it does not feel synthetic-static.
  return 0.92 + 0.08 * math.sin(2 * math.pi * 2.1 * t);
}

double _smoothstep(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

Uint8List _wrapWav(Uint8List pcm) {
  final dataSize = pcm.length;
  final buffer = BytesBuilder();
  void writeString(String value) => buffer.add(value.codeUnits);
  void writeUint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    buffer.add(data.buffer.asUint8List());
  }

  void writeUint16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    buffer.add(data.buffer.asUint8List());
  }

  writeString('RIFF');
  writeUint32(36 + dataSize);
  writeString('WAVE');
  writeString('fmt ');
  writeUint32(16);
  writeUint16(1); // PCM
  writeUint16(1); // mono
  writeUint32(_sampleRate);
  writeUint32(_sampleRate * 2);
  writeUint16(2);
  writeUint16(16);
  writeString('data');
  writeUint32(dataSize);
  buffer.add(pcm);
  return buffer.toBytes();
}

Future<String?> _findFfmpeg() async {
  for (final name in <String>['ffmpeg', 'ffmpeg.exe']) {
    final result = await Process.run(name, <String>['-version']);
    if (result.exitCode == 0) {
      return name;
    }
  }
  return null;
}

Directory? _projectRoot() {
  var directory = Directory.current;
  while (true) {
    if (File('${directory.path}/pubspec.yaml').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      return null;
    }
    directory = parent;
  }
}
