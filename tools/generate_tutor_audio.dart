/// Development-only ElevenLabs generator for local tutor recordings.
///
/// Run from the Harmony project root:
///   dart run tools/generate_tutor_audio.dart
///   dart run tools/generate_tutor_audio.dart --force
///
/// Without --force, existing MP3 files are left untouched.
/// With --force, every line is generated again.
///
/// Reads ELEVENLABS_API_KEY and ELEVENLABS_VOICE_ID from the root .env.
/// The Flutter app does not call ElevenLabs.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:harmony/tutor/tutor_dialogue.dart';

/// Stable ElevenLabs model for natural English speech.
const String ttsModelId = 'eleven_multilingual_v2';

/// Explicit voice settings sent on every request.
const double voiceStability = 0.65;
const double voiceSimilarityBoost = 0.75;
const double voiceStyle = 0.0;
const bool voiceUseSpeakerBoost = true;
const double voiceSpeed = 0.80;

/// Best-effort sample seed. ElevenLabs does not guarantee identical audio.
const int generationSeed = 1;

const String audioOutputFormat = 'mp3_44100_128';

const String _apiHost = 'api.elevenlabs.io';
const String _outputDirectory = 'assets/audio/tutor';
const Duration _requestTimeout = Duration(seconds: 90);

/// Finalized tutor lines from [TutorDialogues] (single source of truth).
///
/// S69 was a sustained Sa demonstration and is no longer part of Stage 1.
final List<TutorLine> tutorLines = [
  for (final dialogue in TutorDialogues.all)
    TutorLine(dialogue.id, dialogue.text),
];

Future<void> main(List<String> args) async {
  final onlyIds = <String>{};
  var overwrite = false;
  for (final arg in args) {
    if (arg == '--force' || arg == '--overwrite') {
      overwrite = true;
      continue;
    }
    if (arg.startsWith('--only=')) {
      onlyIds.addAll(
        arg
            .substring('--only='.length)
            .split(',')
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty),
      );
      continue;
    }
    stderr.writeln(
      'Usage: dart run tools/generate_tutor_audio.dart '
      '[--force|--overwrite] [--only=S64,S65]',
    );
    exitCode = 64;
    return;
  }

  final root = _projectRoot();
  if (root == null) {
    stderr.writeln('Could not find the Harmony project root (pubspec.yaml).');
    exitCode = 1;
    return;
  }

  final envFile = File('${root.path}/.env');
  late final String apiKey;
  late final String voiceId;
  try {
    final env = _readEnv(envFile);
    apiKey = env['ELEVENLABS_API_KEY'] ?? '';
    voiceId = env['ELEVENLABS_VOICE_ID'] ?? '';
  } on FileSystemException {
    stderr.writeln('Could not read ${envFile.path}.');
    exitCode = 1;
    return;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
    return;
  }

  if (apiKey.isEmpty || voiceId.isEmpty) {
    stderr.writeln(
      'Root .env must define ELEVENLABS_API_KEY and ELEVENLABS_VOICE_ID.',
    );
    exitCode = 1;
    return;
  }

  final selected = onlyIds.isEmpty
      ? tutorLines
      : tutorLines.where((line) => onlyIds.contains(line.id)).toList();
  if (onlyIds.isNotEmpty && selected.length != onlyIds.length) {
    final found = selected.map((line) => line.id).toSet();
    final missing = onlyIds.where((id) => !found.contains(id)).join(', ');
    stderr.writeln('Unknown tutor line id(s): $missing');
    exitCode = 64;
    return;
  }

  final outputDirectory = Directory('${root.path}/$_outputDirectory');
  final generated = <String>[];
  final skipped = <String>[];
  final failed = <String>[];
  final total = selected.length;

  for (var index = 0; index < selected.length; index++) {
    final line = selected[index];
    final progress = '[${index + 1}/$total]';
    final output = File('${outputDirectory.path}/${line.id}.mp3');

    if (!overwrite && output.existsSync()) {
      stdout.writeln('$progress Skipping ${line.id}, already exists.');
      skipped.add(line.id);
      continue;
    }

    stdout.writeln('$progress Generating ${line.id}...');
    try {
      final bytes = await _synthesize(
        apiKey: apiKey,
        voiceId: voiceId,
        text: line.text,
      );
      await outputDirectory.create(recursive: true);
      await output.writeAsBytes(bytes, flush: true);
      generated.add(line.id);
    } on TtsException catch (error) {
      stderr.writeln(_redact('${line.id}: ${error.message}', apiKey));
      failed.add(line.id);
    } catch (error) {
      stderr.writeln(_redact('Could not generate ${line.id}: $error', apiKey));
      failed.add(line.id);
    }
  }

  stdout.writeln('Generated (${generated.length}): ${_ids(generated)}');
  stdout.writeln('Skipped (${skipped.length}): ${_ids(skipped)}');
  stdout.writeln('Failed (${failed.length}): ${_ids(failed)}');
  if (failed.isNotEmpty) {
    exitCode = 1;
  }
}

String _ids(List<String> ids) {
  if (ids.isEmpty) {
    return 'none';
  }
  return ids.join(', ');
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

Map<String, String> _readEnv(File file) {
  if (!file.existsSync()) {
    throw FormatException('Missing ${file.path}.');
  }

  var contents = file.readAsStringSync();
  if (contents.startsWith('\uFEFF')) {
    contents = contents.substring(1);
  }

  final values = <String, String>{};
  for (final rawLine in const LineSplitter().convert(contents)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }

    final normalized = line.startsWith('export ')
        ? line.substring('export '.length).trim()
        : line;
    final separator = normalized.indexOf('=');
    if (separator <= 0) {
      continue;
    }

    final key = normalized.substring(0, separator).trim();
    var value = normalized.substring(separator + 1).trim();
    if (value.length >= 2) {
      final quote = value[0];
      if ((quote == '"' || quote == "'") && value.endsWith(quote)) {
        value = value.substring(1, value.length - 1);
      }
    }
    values[key] = value.trim();
  }
  return values;
}

Future<List<int>> _synthesize({
  required String apiKey,
  required String voiceId,
  required String text,
}) async {
  final client = HttpClient();
  try {
    return await _requestAudio(
      client,
      apiKey: apiKey,
      voiceId: voiceId,
      text: text,
    ).timeout(_requestTimeout);
  } on TimeoutException {
    throw TtsException('ElevenLabs request timed out.');
  } on SocketException catch (error) {
    throw TtsException('Could not reach ElevenLabs: ${error.message}');
  } finally {
    client.close(force: true);
  }
}

Future<List<int>> _requestAudio(
  HttpClient client, {
  required String apiKey,
  required String voiceId,
  required String text,
}) async {
  final uri = Uri(
    scheme: 'https',
    host: _apiHost,
    pathSegments: ['v1', 'text-to-speech', voiceId],
    queryParameters: {'output_format': audioOutputFormat},
  );
  final request = await client.postUrl(uri);
  request.followRedirects = false;
  request.headers.set('xi-api-key', apiKey);
  request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  request.headers.set(HttpHeaders.acceptHeader, 'audio/mpeg');
  request.add(
    utf8.encode(
      jsonEncode({
        'text': text,
        'model_id': ttsModelId,
        'seed': generationSeed,
        'voice_settings': {
          'stability': voiceStability,
          'similarity_boost': voiceSimilarityBoost,
          'style': voiceStyle,
          'use_speaker_boost': voiceUseSpeakerBoost,
          'speed': voiceSpeed,
        },
      }),
    ),
  );

  final response = await request.close();
  final bytes = await _readBody(response);
  final mimeType = response.headers.contentType?.mimeType ?? '';
  if (response.statusCode != HttpStatus.ok || mimeType == 'application/json') {
    throw TtsException(_failureMessage(response, bytes));
  }
  if (bytes.length < 128) {
    throw TtsException('ElevenLabs returned an empty audio file.');
  }
  return bytes;
}

Future<List<int>> _readBody(HttpClientResponse response) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in response) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

String _failureMessage(HttpClientResponse response, List<int> bytes) {
  final body = utf8.decode(bytes, allowMalformed: true).trim();
  final preview = body.length <= 2000 ? body : '${body.substring(0, 2000)}...';
  final requestId = response.headers.value('request-id');
  final details = StringBuffer(
    'ElevenLabs request failed (${response.statusCode}).',
  );
  if (requestId != null && requestId.isNotEmpty) {
    details.write(' request-id: $requestId.');
  }
  if (preview.isNotEmpty) {
    details.write('\n$preview');
  }
  return details.toString();
}

String _redact(String message, String apiKey) {
  if (apiKey.isEmpty) {
    return message;
  }
  return message
      .replaceAll(apiKey, '[redacted]')
      .replaceAll(Uri.encodeQueryComponent(apiKey), '[redacted]');
}

class TutorLine {
  const TutorLine(this.id, this.text);

  final String id;
  final String text;
}

class TtsException implements Exception {
  TtsException(this.message);

  final String message;
}
