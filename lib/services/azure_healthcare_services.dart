import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/app_models.dart';

String _envValue(String key) {
  if (!dotenv.isInitialized) return '';
  return dotenv.env[key]?.trim() ?? '';
}

class ConnectionTestResult {
  const ConnectionTestResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}

class LogProcessingResult {
  const LogProcessingResult({
    required this.transcript,
    required this.entities,
    this.error,
  });

  final String transcript;
  final Map<String, dynamic> entities;
  final String? error;

  bool get success => error == null;
}

class AzureHealthcareServices {
  String get azureSpeechEndpoint => _envValue('AZURE_SPEECH_ENDPOINT');
  String get azureTextAnalyticsEndpoint => _envValue('AZURE_TA_ENDPOINT');
  String get azureOpenAIEndpoint => _envValue('AZURE_OPENAI_ENDPOINT');
  String get azureOpenAIDeployment => _envValue('AZURE_OPENAI_DEPLOYMENT');
  String get azureOpenAIApiVersion =>
      _envValue('AZURE_OPENAI_API_VERSION').isEmpty
          ? '2024-10-21'
          : _envValue('AZURE_OPENAI_API_VERSION');
  String get azureSpeechKey => _envValue('AZURE_SPEECH_KEY');
  String get azureTextAnalyticsKey => _envValue('AZURE_TA_KEY');
  String get azureOpenAIKey => _envValue('AZURE_OPENAI_KEY');

  bool get isCloudConfigured =>
      azureSpeechEndpoint.isNotEmpty &&
      azureTextAnalyticsEndpoint.isNotEmpty &&
      azureOpenAIEndpoint.isNotEmpty &&
      azureSpeechKey.isNotEmpty &&
      azureTextAnalyticsKey.isNotEmpty &&
      azureOpenAIKey.isNotEmpty;

  Future<String> transcribeAudio(String audioFilePath) async {
    if (azureSpeechEndpoint.isEmpty || azureSpeechKey.isEmpty) {
      throw HttpException(
        'Azure Speech is not configured. Set AZURE_SPEECH_ENDPOINT and AZURE_SPEECH_KEY.',
      );
    }

    final speechUri = _buildSpeechRecognitionUri();
    final file = File(audioFilePath);
    final bytes = await file.readAsBytes();
    final response = await http.post(
      speechUri,
      headers: {
        'Ocp-Apim-Subscription-Key': azureSpeechKey,
        'Content-Type': 'audio/wav; codecs=audio/pcm; samplerate=16000',
        'Accept': 'application/json',
      },
      body: bytes,
    );

    if (response.statusCode >= 400) {
      throw HttpException('Speech transcription failed: ${response.body}');
    }

    final data = _decodeJsonMap(
      response.body,
      context: 'Speech transcription response',
      statusCode: response.statusCode,
    );
    return data['DisplayText'] as String? ?? '';
  }

  Uri _buildSpeechRecognitionUri() {
    final endpoint = azureSpeechEndpoint.trim();
    if (endpoint.isEmpty) {
      throw HttpException('Azure Speech endpoint is empty.');
    }
    final parsed = Uri.parse(endpoint);
    final host = parsed.host.toLowerCase();
    if (!host.contains('speech.microsoft.com')) {
      throw HttpException(
        'Azure Speech endpoint must be a Speech resource host (for example: '
        'https://<region>.stt.speech.microsoft.com). Current host: ${parsed.host}',
      );
    }

    final base = parsed.replace(path: '', query: '');
    return base.replace(
      path: '/speech/recognition/conversation/cognitiveservices/v1',
      queryParameters: const {
        'language': 'en-US',
        'format': 'detailed',
      },
    );
  }

  Future<Map<String, dynamic>> extractHealthEntities(String text) async {
    if (azureTextAnalyticsEndpoint.isEmpty || azureTextAnalyticsKey.isEmpty) {
      throw HttpException(
        'Azure Text Analytics is not configured. Set AZURE_TA_ENDPOINT and AZURE_TA_KEY.',
      );
    }

    final response = await http.post(
      Uri.parse(azureTextAnalyticsEndpoint),
      headers: {
        'Ocp-Apim-Subscription-Key': azureTextAnalyticsKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'analysisInput': {
          'documents': [
            {'id': '1', 'text': text},
          ],
        },
      }),
    );

    if (response.statusCode >= 400) {
      throw HttpException('Text analytics failed: ${response.body}');
    }

    return _decodeJsonMap(
      response.body,
      context: 'Text analytics response',
      statusCode: response.statusCode,
    );
  }

  Future<LogProcessingResult> transcribeAndExtract(
      PatientLogEntry logEntry) async {
    final audioFilePath = logEntry.audioPath;
    if (audioFilePath == null || audioFilePath.isEmpty) {
      return const LogProcessingResult(
        transcript: '',
        entities: <String, dynamic>{},
        error: 'Audio file path unavailable for processing.',
      );
    }
    return transcribeAndExtractPath(audioFilePath);
  }

  Future<LogProcessingResult> transcribeAndExtractPath(
      String audioFilePath) async {
    try {
      final transcript = await transcribeAudio(audioFilePath);
      Map<String, dynamic> entities;
      try {
        entities = await extractHealthEntities(transcript);
      } catch (_) {
        entities = localEntityFallback(transcript);
      }
      return LogProcessingResult(
        transcript: transcript,
        entities: entities,
      );
    } catch (e) {
      return LogProcessingResult(
        transcript: '',
        entities: const <String, dynamic>{},
        error: '$e',
      );
    }
  }

  Future<String> generateSOAPNote(
      String clinicianTranscript, Map<String, dynamic> patientMetrics,
      {Map<String, dynamic>? context}) async {
    if (azureOpenAIEndpoint.isEmpty || azureOpenAIKey.isEmpty) {
      throw HttpException(
        'Azure OpenAI is not configured. Set AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_KEY.',
      );
    }

    final openAiUri = _buildOpenAIChatCompletionsUri();
    final response = await http.post(
      openAiUri,
      headers: {
        'api-key': azureOpenAIKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'messages': [
          {
            'role': 'system',
            'content': '''
You are a clinical documentation assistant.
Return strictly markdown with exactly these headings:
## Subjective
## Objective
## Assessment
## Plan
Do not include patient identifiers.
''',
          },
          {
            'role': 'user',
            'content': '''
Transcript:
$clinicianTranscript

Objective metrics JSON:
${jsonEncode(patientMetrics)}

Additional context JSON:
${jsonEncode(context ?? const <String, dynamic>{})}
''',
          },
        ],
        'temperature': 0.2,
        'max_tokens': 700,
      }),
    );

    if (response.statusCode >= 400) {
      final responseBody = response.body.trim();
      final deploymentHint = azureOpenAIDeployment.isEmpty
          ? ''
          : ' deployment="$azureOpenAIDeployment".';
      final notFoundHint = response.statusCode == 404
          ? ' Resource not found usually means endpoint/deployment mismatch.'
          : '';
      throw HttpException(
        'OpenAI SOAP generation failed (HTTP ${response.statusCode}) '
        'at ${openAiUri.host}${openAiUri.path}${openAiUri.hasQuery ? '?${openAiUri.query}' : ''}.'
        '$deploymentHint$notFoundHint Response: $responseBody',
      );
    }

    final data = _decodeJsonMap(
      response.body,
      context: 'OpenAI SOAP response',
      statusCode: response.statusCode,
    );
    final choices = data['choices'];
    if (choices is! List<dynamic> || choices.isEmpty) {
      throw HttpException('OpenAI SOAP generation returned no choices.');
    }
    final first = choices.first;
    if (first is! Map) {
      throw HttpException('OpenAI SOAP generation returned malformed choices.');
    }
    final firstMap = first.map((k, v) => MapEntry('$k', v));

    final message = firstMap['message'];
    if (message is Map) {
      final messageMap = message.map((k, v) => MapEntry('$k', v));
      final soap = (messageMap['content'] as String? ?? '').trim();
      if (soap.isNotEmpty) {
        return soap;
      }
    }

    final legacyText = (firstMap['text'] as String? ?? '').trim();
    if (legacyText.isNotEmpty) {
      return legacyText;
    }
    throw HttpException('OpenAI SOAP generation returned empty content.');
  }

  Uri _buildOpenAIChatCompletionsUri() {
    final endpoint = azureOpenAIEndpoint.trim();
    if (endpoint.isEmpty) {
      throw HttpException('Azure OpenAI endpoint is empty.');
    }
    final parsed = Uri.parse(endpoint);
    if (parsed.host.isEmpty) {
      throw HttpException(
        'Azure OpenAI endpoint is invalid: "$endpoint".',
      );
    }
    final lowerHost = parsed.host.toLowerCase();
    final looksLikeAzureOpenAIHost = lowerHost.contains('openai.azure.com') ||
        lowerHost.contains('cognitiveservices.azure.com');
    if (!looksLikeAzureOpenAIHost) {
      throw HttpException(
        'Azure OpenAI endpoint host looks incorrect: "${parsed.host}". '
        'Expected *.openai.azure.com (preferred) or *.cognitiveservices.azure.com.',
      );
    }

    // Support either a full chat-completions URL or a resource base URL.
    final containsChatCompletionsPath =
        parsed.path.contains('/chat/completions');
    if (containsChatCompletionsPath) {
      final query = Map<String, String>.from(parsed.queryParameters);
      query.putIfAbsent('api-version', () => azureOpenAIApiVersion);
      return parsed.replace(queryParameters: query);
    }

    if (azureOpenAIDeployment.isEmpty) {
      throw HttpException(
        'AZURE_OPENAI_DEPLOYMENT is missing. Set it in .env or provide a full '
        'chat-completions URL in AZURE_OPENAI_ENDPOINT.',
      );
    }
    return parsed.replace(
      path: '/openai/deployments/$azureOpenAIDeployment/chat/completions',
      queryParameters: <String, String>{'api-version': azureOpenAIApiVersion},
    );
  }

  Map<String, dynamic> localEntityFallback(String text) {
    final lower = text.toLowerCase();
    final symptoms = <String>[];
    if (lower.contains('stress')) symptoms.add('stress');
    if (lower.contains('sleep')) symptoms.add('sleep disturbance');
    if (lower.contains('anx')) symptoms.add('anxiety');
    if (lower.contains('fatigue') || lower.contains('tired')) {
      symptoms.add('fatigue');
    }
    return {
      'symptoms': symptoms,
      'medications': <String>[],
      'diagnoses': <String>[],
    };
  }

  String localSoapFallback(
    Map<String, dynamic> patientMetrics, {
    Map<String, dynamic>? context,
  }) {
    final blinkRate =
        (patientMetrics['blink_rate_bpm'] as num? ?? 0).toDouble();
    final fatigueScore =
        (patientMetrics['fatigue_score'] as num? ?? 0).toDouble();
    final anxietyScore =
        (patientMetrics['anxiety_score'] as num? ?? 0).toDouble();
    final drift =
        (patientMetrics['gaze_drift_degrees'] as num? ?? 0).toDouble();
    final uptime =
        (patientMetrics['tracking_uptime_percent'] as num? ?? 0).toDouble();
    final trackingQuality =
        (patientMetrics['tracking_quality_score'] as num? ?? 0).toDouble();
    final ctx = context ?? const <String, dynamic>{};
    final marker = (ctx['latest_depression_marker'] as String? ?? 'low').trim();
    final markerScore =
        (ctx['latest_depression_score'] as num? ?? 0).toDouble();
    final adherence = (ctx['med_adherence_today'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final overdue =
        (ctx['overdue_medications'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => '$e')
            .toList();
    return '''
## Subjective
Patient reports elevated stress and reduced sleep quality from diary narrative.

## Objective
Blink rate: ${blinkRate.toStringAsFixed(1)} BPM.
Fatigue score: ${fatigueScore.toStringAsFixed(2)}.
Anxiety score: ${anxietyScore.toStringAsFixed(2)}.
Gaze drift: ${drift.toStringAsFixed(1)} deg.
Tracking uptime: ${uptime.toStringAsFixed(1)}%.
Tracking quality: ${trackingQuality.toStringAsFixed(2)}.

## Assessment
Pattern consistent with stress-related fatigue.
Depression marker: $marker (${(markerScore * 100).toStringAsFixed(0)}%).

## Plan
Reinforce sleep hygiene, monitor diary trend, and re-evaluate in 2 weeks.
Medication adherence today: on-time ${(adherence['on_time'] ?? 0)}, late ${(adherence['late'] ?? 0)}, overdue ${(adherence['overdue'] ?? 0)} out of ${(adherence['total_due'] ?? 0)} due doses.
Overdue medications: ${overdue.isEmpty ? 'none' : overdue.join(', ')}.
''';
  }

  Future<ConnectionTestResult> testSpeechConnection() {
    return _probe(
      serviceName: 'Speech',
      endpoint: azureSpeechEndpoint,
      requiredKey: azureSpeechKey,
      keyHeader: 'Ocp-Apim-Subscription-Key',
    );
  }

  Future<ConnectionTestResult> testTextAnalyticsConnection() {
    return _probe(
      serviceName: 'Text Analytics',
      endpoint: azureTextAnalyticsEndpoint,
      requiredKey: azureTextAnalyticsKey,
      keyHeader: 'Ocp-Apim-Subscription-Key',
    );
  }

  Future<ConnectionTestResult> testOpenAIConnection() {
    return _probeOpenAI();
  }

  Future<ConnectionTestResult> _probe({
    required String serviceName,
    required String endpoint,
    required String requiredKey,
    required String keyHeader,
  }) async {
    if (endpoint.isEmpty || requiredKey.isEmpty) {
      return ConnectionTestResult(
        success: false,
        message: '$serviceName is not configured.',
      );
    }

    try {
      final response = await http.get(
        Uri.parse(endpoint),
        headers: {keyHeader: requiredKey},
      ).timeout(const Duration(seconds: 8));

      final ok = response.statusCode < 500;
      return ConnectionTestResult(
        success: ok,
        message: '$serviceName reachable (HTTP ${response.statusCode}).',
      );
    } catch (e) {
      return ConnectionTestResult(
        success: false,
        message: '$serviceName connection failed: $e',
      );
    }
  }

  Future<ConnectionTestResult> _probeOpenAI() async {
    if (azureOpenAIEndpoint.isEmpty || azureOpenAIKey.isEmpty) {
      return const ConnectionTestResult(
        success: false,
        message: 'OpenAI is not configured.',
      );
    }

    try {
      final uri = _buildOpenAIChatCompletionsUri();
      final response = await http
          .post(
            uri,
            headers: {
              'api-key': azureOpenAIKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'messages': [
                {'role': 'user', 'content': 'ping'},
              ],
              'max_tokens': 1,
              'temperature': 0,
            }),
          )
          .timeout(const Duration(seconds: 8));

      final ok = response.statusCode >= 200 && response.statusCode < 400;
      final clippedBody = response.body.trim();
      final bodyPreview = clippedBody.isEmpty
          ? ''
          : ' Body: ${clippedBody.substring(0, clippedBody.length.clamp(0, 120))}';
      return ConnectionTestResult(
        success: ok,
        message:
            'OpenAI chat endpoint responded HTTP ${response.statusCode}.$bodyPreview',
      );
    } catch (e) {
      return ConnectionTestResult(
        success: false,
        message: 'OpenAI connection failed: $e',
      );
    }
  }

  Map<String, dynamic> _decodeJsonMap(
    String rawBody, {
    required String context,
    required int statusCode,
  }) {
    final body = rawBody.trim();
    if (body.isEmpty) {
      throw HttpException(
        '$context was empty (HTTP $statusCode). Check endpoint path, API version, and headers.',
      );
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw HttpException('$context was not a JSON object (HTTP $statusCode).');
    } on FormatException catch (e) {
      throw HttpException(
        '$context was not valid JSON (HTTP $statusCode): ${e.message}',
      );
    }
  }
}
