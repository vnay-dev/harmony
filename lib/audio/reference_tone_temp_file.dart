import 'dart:io';
import 'dart:typed_data';

/// Writes [wavBytes] to a unique temp file under [directory].
///
/// Used by Stage 2 reference playback so just_audio can load via [setFilePath]
/// instead of an in-memory stream (which fails on Android cleartext HTTP).
Future<File> writeReferenceToneTempFile(
  Uint8List wavBytes, {
  Directory? directory,
  String prefix = 'harmony_ref_',
}) async {
  final dir = directory ?? Directory.systemTemp;
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  final file = File(
    '${dir.path}${Platform.pathSeparator}'
    '$prefix${DateTime.now().microsecondsSinceEpoch}.wav',
  );
  await file.writeAsBytes(wavBytes, flush: true);
  return file;
}

/// Best-effort delete of a previously written reference tone temp file.
Future<void> deleteReferenceToneTempFile(File? file) async {
  if (file == null) {
    return;
  }
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // Ignore cleanup failures; next play replaces the active file.
  }
}
