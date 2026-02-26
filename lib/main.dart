import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

const String azureSpeechEndpoint = String.fromEnvironment(
  'AZURE_SPEECH_ENDPOINT',
  defaultValue: 'mock_speech_url',
);
const String azureTextAnalyticsEndpoint = String.fromEnvironment(
  'AZURE_TA_ENDPOINT',
  defaultValue: 'mock_ta_url',
);
const String azureOpenAIEndpoint = String.fromEnvironment(
  'AZURE_OPENAI_ENDPOINT',
  defaultValue: 'mock_openai_url',
);
const String azureSpeechKey = String.fromEnvironment('AZURE_SPEECH_KEY');
const String azureTextAnalyticsKey = String.fromEnvironment('AZURE_TA_KEY');
const String azureOpenAIKey = String.fromEnvironment('AZURE_OPENAI_KEY');

class EdgeMetrics {
  const EdgeMetrics({
    required this.blinksPerMinute,
    required this.fatigueScore,
    required this.anxietyScore,
    required this.totalBlinks,
  });

  final double blinksPerMinute;
  final double fatigueScore;
  final double anxietyScore;
  final int totalBlinks;

  Map<String, dynamic> toJson() => {
        'blink_rate_bpm': blinksPerMinute,
        'fatigue_score': fatigueScore,
        'anxiety_score': anxietyScore,
        'total_blinks': totalBlinks,
      };

  static const empty = EdgeMetrics(
    blinksPerMinute: 0,
    fatigueScore: 0,
    anxietyScore: 0,
    totalBlinks: 0,
  );
}

class MentalHealthEdgeTracker {
  MentalHealthEdgeTracker()
      : _faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            enableClassification: true,
            performanceMode: FaceDetectorMode.fast,
          ),
        );

  CameraController? _cameraController;
  final FaceDetector _faceDetector;
  bool _processingFrame = false;
  bool _lastEyesClosed = false;
  int _blinkCount = 0;
  DateTime? _sessionStartedAt;

  CameraController? get controller => _cameraController;

  Future<void> initializeFrontCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => throw StateError('No front-facing camera available.'),
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _cameraController!.initialize();
    _sessionStartedAt = DateTime.now();
  }

  Future<void> startFaceTrackingStream(VoidCallback onMetricsUpdated) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('Camera not initialized.');
    }
    if (controller.value.isStreamingImages) {
      return;
    }

    await controller.startImageStream((cameraImage) async {
      if (_processingFrame) return;
      _processingFrame = true;
      try {
        final inputImage = _cameraImageToInputImage(cameraImage, controller);
        final faces = await _faceDetector.processImage(inputImage);

        if (faces.isNotEmpty) {
          final face = faces.first;
          final left = face.leftEyeOpenProbability ?? 1;
          final right = face.rightEyeOpenProbability ?? 1;
          final eyesClosed = left < 0.35 && right < 0.35;

          if (!eyesClosed && _lastEyesClosed) {
            _blinkCount += 1;
            onMetricsUpdated();
          }
          _lastEyesClosed = eyesClosed;
        }
      } finally {
        _processingFrame = false;
      }
    });
  }

  InputImage _cameraImageToInputImage(
    CameraImage image,
    CameraController controller,
  ) {
    final bytes = image.planes.map((p) => p.bytes).expand((e) => e).toList();
    final size = Size(image.width.toDouble(), image.height.toDouble());

    final rotation = InputImageRotationValue.fromRawValue(
          controller.description.sensorOrientation,
        ) ??
        InputImageRotation.rotation0deg;

    final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
        InputImageFormat.nv21;

    final planeData = image.planes
        .map(
          (plane) => InputImagePlaneMetadata(
            bytesPerRow: plane.bytesPerRow,
            height: plane.height,
            width: plane.width,
          ),
        )
        .toList();

    final metadata = InputImageMetadata(
      size: size,
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
      planeData: planeData,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  EdgeMetrics getAnonymizedMetrics() {
    final startedAt = _sessionStartedAt;
    if (startedAt == null) return EdgeMetrics.empty;

    final elapsedMinutes =
        DateTime.now().difference(startedAt).inSeconds.clamp(1, 36000) / 60;
    final bpm = _blinkCount / elapsedMinutes;

    final fatigueScore = (bpm < 8 ? (8 - bpm) / 8 : 0).clamp(0, 1).toDouble();
    final anxietyScore = (bpm > 30 ? (bpm - 30) / 30 : 0).clamp(0, 1).toDouble();

    return EdgeMetrics(
      blinksPerMinute: bpm,
      fatigueScore: fatigueScore,
      anxietyScore: anxietyScore,
      totalBlinks: _blinkCount,
    );
  }

  Future<void> dispose() async {
    if (_cameraController?.value.isStreamingImages == true) {
      await _cameraController?.stopImageStream();
    }
    await _cameraController?.dispose();
    await _faceDetector.close();
  }
}

class AzureHealthcareServices {
  Future<String> transcribeAudio(String audioFilePath) async {
    if (azureSpeechEndpoint.startsWith('mock_') || azureSpeechKey.isEmpty) {
      return 'Mock transcript: patient reports interrupted sleep and stress.';
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
    if (azureTextAnalyticsEndpoint.startsWith('mock_') ||
        azureTextAnalyticsKey.isEmpty) {
      return {
        'symptoms': ['stress', 'poor sleep'],
        'medications': <String>[],
        'diagnoses': <String>[],
      };
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

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data;
  }

  Future<String> generateSOAPNote(
    String clinicianTranscript,
    Map<String, dynamic> patientMetrics,
  ) async {
    final prompt = '''
You are a clinical documentation assistant.
Output STRICTLY in SOAP markdown format with headings:
- Subjective
- Objective
- Assessment
- Plan
Use this transcript: $clinicianTranscript
Use objective metrics: ${jsonEncode(patientMetrics)}
Do not include patient identifiers.
''';

    if (azureOpenAIEndpoint.startsWith('mock_') || azureOpenAIKey.isEmpty) {
      return '''
## Subjective
Patient reports stress and reduced sleep quality.

## Objective
Blink rate: ${patientMetrics['blink_rate_bpm'] ?? 0} BPM.
Fatigue score: ${patientMetrics['fatigue_score'] ?? 0}.

## Assessment
Possible stress-related fatigue symptoms.

## Plan
Recommend sleep hygiene counseling, hydration, and follow-up in 2 weeks.
''';
    }

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
    return (data['choices'] as List).first['message']['content'] as String;
  }
}

final edgeTrackerProvider = Provider<MentalHealthEdgeTracker>((ref) {
  final tracker = MentalHealthEdgeTracker();
  ref.onDispose(() => unawaited(tracker.dispose()));
  return tracker;
});

final azureServicesProvider = Provider<AzureHealthcareServices>((_) {
  return AzureHealthcareServices();
});

final edgeMetricsProvider = StateProvider<EdgeMetrics>((_) => EdgeMetrics.empty);

class HealthcareContinuumApp extends ConsumerStatefulWidget {
  const HealthcareContinuumApp({super.key});

  @override
  ConsumerState<HealthcareContinuumApp> createState() =>
      _HealthcareContinuumAppState();
}

class _HealthcareContinuumAppState extends ConsumerState<HealthcareContinuumApp> {
  final _audioRecorder = AudioRecorder();
  int _tabIndex = 0;
  String _patientSummary = '';
  String _soapNote = '';
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeTracker());
  }

  Future<void> _initializeTracker() async {
    final tracker = ref.read(edgeTrackerProvider);
    try {
      await tracker.initializeFrontCamera();
      await tracker.startFaceTrackingStream(() {
        ref.read(edgeMetricsProvider.notifier).state = tracker.getAnonymizedMetrics();
      });
      if (mounted) setState(() {});
    } catch (_) {
      // Keep UI usable on camera permission or hardware failure.
    }
  }

  Future<String> _recordShortClip() async {
    const filePath = 'patient_clip.m4a';
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      throw const FileSystemException('Microphone permission denied.');
    }

    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: filePath,
    );
    await Future<void>.delayed(const Duration(seconds: 4));
    return (await _audioRecorder.stop()) ?? filePath;
  }

  Future<void> _runPatientDiaryFlow() async {
    setState(() => _isBusy = true);
    final azure = ref.read(azureServicesProvider);
    try {
      final audioPath = await _recordShortClip();
      final transcript = await azure.transcribeAudio(audioPath);
      final entities = await azure.extractHealthEntities(transcript);
      setState(() {
        _patientSummary = 'Transcript: $transcript\nEntities: ${jsonEncode(entities)}';
      });
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _runSoapFlow() async {
    setState(() => _isBusy = true);
    final azure = ref.read(azureServicesProvider);
    final metrics = ref.read(edgeMetricsProvider).toJson();
    try {
      final audioPath = await _recordShortClip();
      final transcript = await azure.transcribeAudio(audioPath);
      final soap = await azure.generateSOAPNote(transcript, metrics);
      setState(() => _soapNote = soap);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = ref.watch(edgeMetricsProvider);
    final tracker = ref.watch(edgeTrackerProvider);

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Care Continuum')),
        body: IndexedStack(
          index: _tabIndex,
          children: [
            _PatientView(
              cameraController: tracker.controller,
              metrics: metrics,
              summary: _patientSummary,
              isBusy: _isBusy,
              onRecordDiary: _runPatientDiaryFlow,
            ),
            _ClinicianView(
              metrics: metrics,
              soapNote: _soapNote,
              isBusy: _isBusy,
              onGenerateSoap: _runSoapFlow,
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _tabIndex,
          onTap: (index) => setState(() => _tabIndex = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Patient'),
            BottomNavigationBarItem(
              icon: Icon(Icons.medical_services),
              label: 'Clinician',
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientView extends StatelessWidget {
  const _PatientView({
    required this.cameraController,
    required this.metrics,
    required this.summary,
    required this.isBusy,
    required this.onRecordDiary,
  });

  final CameraController? cameraController;
  final EdgeMetrics metrics;
  final String summary;
  final bool isBusy;
  final Future<void> Function() onRecordDiary;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: cameraController != null && cameraController!.value.isInitialized
              ? CameraPreview(cameraController!)
              : const Center(child: Text('Front camera unavailable')),
        ),
        const SizedBox(height: 12),
        Text('Blink rate: ${metrics.blinksPerMinute.toStringAsFixed(1)} BPM'),
        Text('Fatigue score: ${metrics.fatigueScore.toStringAsFixed(2)}'),
        Text('Anxiety score: ${metrics.anxietyScore.toStringAsFixed(2)}'),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: isBusy ? null : onRecordDiary,
          icon: const Icon(Icons.mic),
          label: const Text('Record Diary (4s)'),
        ),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(summary),
        ],
      ],
    );
  }
}

class _ClinicianView extends StatelessWidget {
  const _ClinicianView({
    required this.metrics,
    required this.soapNote,
    required this.isBusy,
    required this.onGenerateSoap,
  });

  final EdgeMetrics metrics;
  final String soapNote;
  final bool isBusy;
  final Future<void> Function() onGenerateSoap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edge Metrics: ${jsonEncode(metrics.toJson())}'),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: isBusy ? null : onGenerateSoap,
            icon: const Icon(Icons.edit_note),
            label: const Text('Record Dictation & Generate SOAP'),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Text(soapNote.isEmpty ? 'SOAP note will appear here.' : soapNote),
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  runApp(const ProviderScope(child: HealthcareContinuumApp()));
}
