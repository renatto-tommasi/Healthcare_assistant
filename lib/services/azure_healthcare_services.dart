import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const String azureSpeechEndpoint = String.fromEnvironment('AZURE_SPEECH_ENDPOINT');
const String azureTextAnalyticsEndpoint = String.fromEnvironment('AZURE_TA_ENDPOINT');
const String azureOpenAIEndpoint = String.fromEnvironment('AZURE_OPENAI_ENDPOINT');
const String azureSpeechKey = String.fromEnvironment('AZURE_SPEECH_KEY');
const String azureTextAnalyticsKey = String.fromEnvironment('AZURE_TA_KEY');
const String azureOpenAIKey = String.fromEnvironment('AZURE_OPENAI_KEY');

class ConnectionTestResult {
  const ConnectionTestResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}

class AzureHealthcareServices {
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

    final file = File(audioFilePath);
    final bytes = await file.readAsBytes();
    final response = await http.post(
      Uri.parse(azureSpeechEndpoint),
      headers: {
        'Ocp-Apim-Subscription-Key': azureSpeechKey,
        'Content-Type': 'audio/wav',
      },
      body: bytes,
    );

    if (response.statusCode >= 400) {
      throw HttpException('Speech transcription failed: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['DisplayText'] as String? ?? '';
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

    return jsonDecode(response.body) as Map<String, dynamic>;
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

    final data = jsonDecode(response.body) as Map<String, dynamic>;
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
    if (lower.contains('fatigue') || lower.contains('tired')) symptoms.add('fatigue');
    return {
      'symptoms': symptoms,
      'medications': <String>[],
      'diagnoses': <String>[],
    };
  }

  String localSoapFallback(Map<String, dynamic> patientMetrics) {
    final blinkRate = (patientMetrics['blink_rate_bpm'] as num? ?? 0).toDouble();
    final fatigueScore = (patientMetrics['fatigue_score'] as num? ?? 0).toDouble();
    final anxietyScore = (patientMetrics['anxiety_score'] as num? ?? 0).toDouble();
    return '''
## Subjective
Patient reports elevated stress and reduced sleep quality from diary narrative.

## Objective
Blink rate: ${blinkRate.toStringAsFixed(1)} BPM.
Fatigue score: ${fatigueScore.toStringAsFixed(2)}.
Anxiety score: ${anxietyScore.toStringAsFixed(2)}.

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
      final response = await http
          .get(
            Uri.parse(endpoint),
            headers: {keyHeader: requiredKey},
          )
          .timeout(const Duration(seconds: 8));

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
}
