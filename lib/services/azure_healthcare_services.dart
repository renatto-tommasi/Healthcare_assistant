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

  Future<LogProcessingResult> transcribeAndExtract(PatientLogEntry logEntry) async {
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

  Future<LogProcessingResult> transcribeAndExtractPath(String audioFilePath) async {
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
    String clinicianTranscript,
    Map<String, dynamic> patientMetrics,
  ) async {
    if (azureOpenAIEndpoint.isEmpty || azureOpenAIKey.isEmpty) {
      throw HttpException(
        'Azure OpenAI is not configured. Set AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_KEY.',
      );
    }

    final prompt = '''
You are a clinical documentation assistant.
Output strictly in SOAP markdown format with headings:
- Subjective
- Objective
- Assessment
- Plan
Use this transcript: $clinicianTranscript
Use objective metrics: ${jsonEncode(patientMetrics)}
Do not include patient identifiers.
''';

    final response = await http.post(
      Uri.parse(azureOpenAIEndpoint),
      headers: {
        'api-key': azureOpenAIKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'messages': [
          {'role': 'system', 'content': prompt},
        ],
        'temperature': 0.2,
      }),
    );

    if (response.statusCode >= 400) {
      throw HttpException('OpenAI SOAP generation failed: ${response.body}');
    }

    final data = _decodeJsonMap(
      response.body,
      context: 'OpenAI SOAP response',
      statusCode: response.statusCode,
    );
    final choices = (data['choices'] as List<dynamic>? ?? []);
    if (choices.isEmpty) {
      throw HttpException('OpenAI SOAP generation returned no choices.');
    }
    final message = choices.first as Map<String, dynamic>;
    final content = message['message'] as Map<String, dynamic>? ?? const {};
    final soap = content['content'] as String? ?? '';
    if (soap.isEmpty) {
      throw HttpException('OpenAI SOAP generation returned empty content.');
    }
    return soap;
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

  String localSoapFallback(Map<String, dynamic> patientMetrics) {
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

## Plan
Reinforce sleep hygiene, monitor diary trend, and re-evaluate in 2 weeks.
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
    return _probe(
      serviceName: 'OpenAI',
      endpoint: azureOpenAIEndpoint,
      requiredKey: azureOpenAIKey,
      keyHeader: 'api-key',
    );
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
