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

/// Finalized tutor lines. Wording is fixed; this script does not read the doc.
const List<TutorLine> tutorLines = [
  TutorLine('S01', 'Hi. I\'ll help you find a comfortable Shruti.'),
  TutorLine('S02', 'You don\'t need to know anything about singing.'),
  TutorLine('S03', 'Settle in, and follow my voice.'),
  TutorLine('S04', 'Let\'s begin gently.'),
  TutorLine('S05', 'Sing or hum a sound that feels comfortable.'),
  TutorLine('S06', 'Stay with it for a few seconds.'),
  TutorLine('S07', 'Let\'s try singing it again in 3...'),
  TutorLine('S08', '2...'),
  TutorLine('S09', '1...'),
  TutorLine('S10', 'Beautiful. You can stop there.'),
  TutorLine('S11', 'Now let\'s find a comfortable place for your voice.'),
  TutorLine('S12', 'That\'s okay. Let\'s try once more.'),
  TutorLine('S13', 'A soft, steady hum is enough.'),
  TutorLine('S14', 'That\'s all right. I\'ll let you hear a sound first.'),
  TutorLine('S15', 'Just listen.'),
  TutorLine('S16', 'Now try that sound.'),
  TutorLine('S17', 'We\'ll take this more gently.'),
  TutorLine('S18', 'Let\'s listen once more.'),
  TutorLine('S19', 'That\'s okay. Let\'s listen once more.'),
  TutorLine('S20', 'Let\'s try a slightly lower sound.'),
  TutorLine('S21', 'Let\'s try one in the middle.'),
  TutorLine('S22', 'Now a slightly higher sound.'),
  TutorLine('S23', 'Let\'s move a little higher.'),
  TutorLine('S24', 'Let\'s move a little lower.'),
  TutorLine('S25', 'Could you hear that sound clearly?'),
  TutorLine('S26', 'That\'s lovely.'),
  TutorLine('S27', 'That\'s okay. Let\'s try a little higher.'),
  TutorLine('S28', 'Sorry, I didn\'t quite catch that.'),
  TutorLine('S29', 'Yes or no is enough.'),
  TutorLine('S30', 'How did that feel?'),
  TutorLine('S31', 'That\'s all right. We\'ll keep this comfortable.'),
  TutorLine('S32', 'You can say comfortable, or not comfortable.'),
  TutorLine('S33', 'There\'s no hurry.'),
  TutorLine(
    'S34',
    'That\'s okay. Let\'s practice it together so you can get familiar with the sound.',
  ),
  TutorLine('S35', 'Listen carefully, and sing along with me.'),
  TutorLine('S36', 'Let\'s sing together in 3...'),
  TutorLine(
    'S37',
    'That\'s okay. Let\'s practice that sound together once more.',
  ),
  TutorLine('S38', 'Now try that sound on your own.'),
  TutorLine('S39', 'Wonderful. We found a comfortable Shruti for you.'),
  TutorLine('S40', 'Your Shruti is C.'),
  TutorLine('S41', 'Your Shruti is C sharp.'),
  TutorLine('S42', 'Your Shruti is D.'),
  TutorLine('S43', 'Your Shruti is D sharp.'),
  TutorLine('S44', 'Your Shruti is E.'),
  TutorLine('S45', 'Your Shruti is F.'),
  TutorLine('S46', 'Your Shruti is F sharp.'),
  TutorLine('S47', 'Your Shruti is G.'),
  TutorLine('S48', 'Your Shruti is G sharp.'),
  TutorLine('S49', 'Your Shruti is A.'),
  TutorLine('S50', 'Your Shruti is A sharp.'),
  TutorLine('S51', 'Your Shruti is B.'),
  TutorLine('S52', 'We haven\'t found a comfortable Shruti just yet.'),
  TutorLine('S53', 'We can try again whenever you like.'),
  TutorLine('S54', 'First, I\'ll listen to your voice.'),
  TutorLine('S55', 'Then, we\'ll explore a few sounds around it.'),
  TutorLine('S56', 'You\'ll tell me how each one feels.'),
  TutorLine(
    'S57',
    'We\'ll keep going until we find a comfortable place for your voice.',
  ),
  TutorLine(
    'S58',
    'There\'s no right or wrong answer. Just sing naturally and tell me how it feels.',
  ),
  TutorLine('S59', 'That\'s okay. Let\'s make this a little easier.'),
  TutorLine(
    'S60',
    'That sound didn\'t feel quite right. Would you like to try a different one?',
  ),
  TutorLine('S61', 'Lovely. Let\'s try this one.'),
  TutorLine(
    'S62',
    'That\'s perfectly okay. Let\'s stay with this one for now.',
  ),
  TutorLine(
    'S63',
    'Let\'s take a small step back and listen to your voice once more.',
  ),
];

Future<void> main(List<String> args) async {
  const overwriteFlags = {'--force', '--overwrite'};
  if (args.any((arg) => !overwriteFlags.contains(arg))) {
    stderr.writeln(
      'Usage: dart run tools/generate_tutor_audio.dart [--force|--overwrite]',
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

  final overwrite = args.isNotEmpty;
  final outputDirectory = Directory('${root.path}/$_outputDirectory');
  final generated = <String>[];
  final skipped = <String>[];
  final failed = <String>[];
  final total = tutorLines.length;

  for (var index = 0; index < tutorLines.length; index++) {
    final line = tutorLines[index];
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
