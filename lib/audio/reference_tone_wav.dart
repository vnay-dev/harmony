import 'dart:math' as math;
import 'dart:typed_data';

/// Builds a short mono WAV for a Stage 2 pitch reference.
///
/// Synthesis is intentionally simple and frequency-driven (no sample assets):
/// a clear fundamental with soft lower harmonics and a gentle amplitude
/// envelope — warm enough to avoid a bare sine, stable enough for matching.
Uint8List buildReferenceToneWav({
  required double frequencyHz,
  Duration duration = const Duration(seconds: 5),
  int sampleRate = 44100,
}) {
  assert(frequencyHz > 0 && frequencyHz.isFinite);
  assert(sampleRate > 0);
  assert(duration > Duration.zero);

  final totalSamples = math.max(
    1,
    (sampleRate * duration.inMicroseconds / Duration.microsecondsPerSecond)
        .round(),
  );

  final pcm = Int16List(totalSamples);
  final twoPi = 2 * math.pi;
  final attackSamples = math.min(
    totalSamples ~/ 8,
    (sampleRate * 0.045).round(),
  );
  final releaseSamples = math.min(
    totalSamples ~/ 6,
    (sampleRate * 0.09).round(),
  );

  // Soft harmonic stack inspired by a warm pad (saw-ish), but capped so the
  // fundamental stays obvious and we avoid splashy high content.
  const fundamentalAmp = 0.62;
  const secondHarmonicAmp = 0.28;
  const thirdHarmonicAmp = 0.12;
  const fourthHarmonicAmp = 0.05;
  const peakScale = 0.85;

  for (var i = 0; i < totalSamples; i++) {
    final t = i / sampleRate;
    final phase = twoPi * frequencyHz * t;

    var sample =
        fundamentalAmp * math.sin(phase) +
        secondHarmonicAmp * math.sin(2 * phase) +
        thirdHarmonicAmp * math.sin(3 * phase) +
        fourthHarmonicAmp * math.sin(4 * phase);

    var envelope = 1.0;
    if (i < attackSamples) {
      envelope = i / attackSamples;
    } else if (i >= totalSamples - releaseSamples) {
      envelope = (totalSamples - 1 - i) / releaseSamples;
    }
    sample *= envelope * peakScale;

    pcm[i] = (sample.clamp(-1.0, 1.0) * 32767).round();
  }

  return _wrapPcm16MonoWav(pcm, sampleRate);
}

/// Parsed RIFF/WAV header fields for diagnostic logging and tests.
class ReferenceToneWavInfo {
  const ReferenceToneWavInfo({
    required this.isValid,
    required this.byteCount,
    required this.riffId,
    required this.riffChunkSize,
    required this.waveId,
    required this.fmtId,
    required this.fmtChunkSize,
    required this.audioFormat,
    required this.channels,
    required this.sampleRate,
    required this.byteRate,
    required this.blockAlign,
    required this.bitsPerSample,
    required this.dataId,
    required this.dataChunkSize,
    required this.expectedTotalBytes,
    required this.issues,
  });

  final bool isValid;
  final int byteCount;
  final String riffId;
  final int? riffChunkSize;
  final String waveId;
  final String fmtId;
  final int? fmtChunkSize;
  final int? audioFormat;
  final int? channels;
  final int? sampleRate;
  final int? byteRate;
  final int? blockAlign;
  final int? bitsPerSample;
  final String dataId;
  final int? dataChunkSize;
  final int? expectedTotalBytes;
  final List<String> issues;

  String get summary {
    final formatLabel = switch (audioFormat) {
      1 => 'PCM',
      null => 'unknown',
      final other => 'format=$other',
    };
    return 'bytes=$byteCount '
        'riff=$riffId/$waveId '
        'fmt=$fmtId($fmtChunkSize) '
        'audio=$formatLabel '
        'ch=$channels '
        'rate=$sampleRate '
        'bits=$bitsPerSample '
        'byteRate=$byteRate '
        'blockAlign=$blockAlign '
        'data=$dataId($dataChunkSize) '
        'expectedTotal=$expectedTotalBytes '
        'valid=$isValid'
        '${issues.isEmpty ? '' : ' issues=${issues.join(';')}'}';
  }
}

/// Inspects a generated reference WAV for Android-relevant header fields.
ReferenceToneWavInfo inspectReferenceToneWav(Uint8List wav) {
  final issues = <String>[];
  if (wav.length < 44) {
    return ReferenceToneWavInfo(
      isValid: false,
      byteCount: wav.length,
      riffId: '',
      riffChunkSize: null,
      waveId: '',
      fmtId: '',
      fmtChunkSize: null,
      audioFormat: null,
      channels: null,
      sampleRate: null,
      byteRate: null,
      blockAlign: null,
      bitsPerSample: null,
      dataId: '',
      dataChunkSize: null,
      expectedTotalBytes: null,
      issues: <String>['wav shorter than 44-byte header (${wav.length})'],
    );
  }

  String readFourCc(int offset) {
    return String.fromCharCodes(wav.sublist(offset, offset + 4));
  }

  final data = ByteData.sublistView(wav);
  final riffId = readFourCc(0);
  final riffChunkSize = data.getUint32(4, Endian.little);
  final waveId = readFourCc(8);
  final fmtId = readFourCc(12);
  final fmtChunkSize = data.getUint32(16, Endian.little);
  final audioFormat = data.getUint16(20, Endian.little);
  final channels = data.getUint16(22, Endian.little);
  final sampleRate = data.getUint32(24, Endian.little);
  final byteRate = data.getUint32(28, Endian.little);
  final blockAlign = data.getUint16(32, Endian.little);
  final bitsPerSample = data.getUint16(34, Endian.little);
  final dataId = readFourCc(36);
  final dataChunkSize = data.getUint32(40, Endian.little);
  final expectedTotalBytes = 8 + riffChunkSize;

  if (riffId != 'RIFF') {
    issues.add('riffId=$riffId');
  }
  if (waveId != 'WAVE') {
    issues.add('waveId=$waveId');
  }
  if (fmtId != 'fmt ') {
    issues.add('fmtId=$fmtId');
  }
  if (fmtChunkSize != 16) {
    issues.add('fmtChunkSize=$fmtChunkSize');
  }
  if (audioFormat != 1) {
    issues.add('audioFormat=$audioFormat (want PCM=1)');
  }
  if (channels != 1) {
    issues.add('channels=$channels (want 1)');
  }
  if (sampleRate != 44100) {
    issues.add('sampleRate=$sampleRate (want 44100)');
  }
  if (bitsPerSample != 16) {
    issues.add('bitsPerSample=$bitsPerSample (want 16)');
  }
  if (blockAlign != channels * bitsPerSample ~/ 8) {
    issues.add('blockAlign=$blockAlign');
  }
  if (byteRate != sampleRate * blockAlign) {
    issues.add('byteRate=$byteRate');
  }
  if (dataId != 'data') {
    issues.add('dataId=$dataId');
  }
  if (expectedTotalBytes != wav.length) {
    issues.add(
      'riffSize mismatch expectedTotal=$expectedTotalBytes actual=${wav.length}',
    );
  }
  if (44 + dataChunkSize != wav.length) {
    issues.add(
      'dataSize mismatch header=$dataChunkSize payload=${wav.length - 44}',
    );
  }

  return ReferenceToneWavInfo(
    isValid: issues.isEmpty,
    byteCount: wav.length,
    riffId: riffId,
    riffChunkSize: riffChunkSize,
    waveId: waveId,
    fmtId: fmtId,
    fmtChunkSize: fmtChunkSize,
    audioFormat: audioFormat,
    channels: channels,
    sampleRate: sampleRate,
    byteRate: byteRate,
    blockAlign: blockAlign,
    bitsPerSample: bitsPerSample,
    dataId: dataId,
    dataChunkSize: dataChunkSize,
    expectedTotalBytes: expectedTotalBytes,
    issues: issues,
  );
}

/// Estimated fundamental frequency encoded in [wav] via zero-crossing rate.
///
/// Used only in tests as a coarse sanity check — not a production pitch
/// detector. Returns `null` when the signal is too short or silent.
double? estimateWavFundamentalHz(Uint8List wav, {int sampleRate = 44100}) {
  if (wav.length < 44) {
    return null;
  }

  final byteData = ByteData.sublistView(wav);
  final dataSize = byteData.getUint32(40, Endian.little);
  final sampleCount = dataSize ~/ 2;
  if (sampleCount < sampleRate ~/ 20) {
    return null;
  }

  // Skip the soft attack so zero-crossings reflect the sustained tone.
  final start = (sampleCount * 0.12).round().clamp(0, sampleCount - 1);
  final end = (sampleCount * 0.88).round().clamp(start + 1, sampleCount);

  var crossings = 0;
  var previous = byteData.getInt16(44 + start * 2, Endian.little);
  for (var i = start + 1; i < end; i++) {
    final sample = byteData.getInt16(44 + i * 2, Endian.little);
    if ((previous < 0 && sample >= 0) || (previous >= 0 && sample < 0)) {
      crossings += 1;
    }
    previous = sample;
  }

  final seconds = (end - start) / sampleRate;
  if (seconds <= 0 || crossings < 2) {
    return null;
  }

  // Full cycles ≈ half the zero crossings for a near-sinusoid.
  return (crossings / 2) / seconds;
}

Uint8List _wrapPcm16MonoWav(Int16List pcm, int sampleRate) {
  const channels = 1;
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final dataSize = pcm.length * 2;
  final fileSize = 36 + dataSize;

  final bytes = BytesBuilder(copy: false);
  void writeString(String value) => bytes.add(value.codeUnits);
  void writeUint16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  void writeUint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  writeString('RIFF');
  writeUint32(fileSize);
  writeString('WAVE');
  writeString('fmt ');
  writeUint32(16); // PCM fmt chunk size
  writeUint16(1); // PCM format
  writeUint16(channels);
  writeUint32(sampleRate);
  writeUint32(byteRate);
  writeUint16(blockAlign);
  writeUint16(bitsPerSample);
  writeString('data');
  writeUint32(dataSize);

  final pcmBytes = Uint8List(dataSize);
  final pcmView = ByteData.sublistView(pcmBytes);
  for (var i = 0; i < pcm.length; i++) {
    pcmView.setInt16(i * 2, pcm[i], Endian.little);
  }
  bytes.add(pcmBytes);

  return bytes.toBytes();
}
