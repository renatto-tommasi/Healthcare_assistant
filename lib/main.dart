import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:fl_chart/fl_chart.dart';
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

enum UserRole { patient, clinician }

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

  double get baselineScore =>
      ((1 - ((fatigueScore + anxietyScore) / 2)) * 100).clamp(0, 100);

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

class AppState {
  const AppState({
    this.role,
    this.selectedPatient,
    this.edgeTrackingEnabled = true,
    this.purgeCounter = 0,
  });

  final UserRole? role;
  final String? selectedPatient;
  final bool edgeTrackingEnabled;
  final int purgeCounter;

  AppState copyWith({
    UserRole? role,
    String? selectedPatient,
    bool? edgeTrackingEnabled,
    int? purgeCounter,
  }) {
    return AppState(
      role: role ?? this.role,
      selectedPatient: selectedPatient ?? this.selectedPatient,
      edgeTrackingEnabled: edgeTrackingEnabled ?? this.edgeTrackingEnabled,
      purgeCounter: purgeCounter ?? this.purgeCounter,
    );
  }
}

class AppStateNotifier extends StateNotifier<AppState> {
  AppStateNotifier() : super(const AppState());

  void setRole(UserRole role) => state = state.copyWith(role: role);

  void selectPatient(String patient) =>
      state = state.copyWith(selectedPatient: patient);

  void setEdgeTrackingEnabled(bool enabled) =>
      state = state.copyWith(edgeTrackingEnabled: enabled);

  void purgeData() => state = state.copyWith(
        purgeCounter: state.purgeCounter + 1,
        selectedPatient: null,
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
    if (_cameraController?.value.isInitialized == true) return;
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
    _sessionStartedAt ??= DateTime.now();
  }

  Future<void> startFaceTrackingStream(VoidCallback onMetricsUpdated) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('Camera not initialized.');
    }
    if (controller.value.isStreamingImages) return;

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
    final bytes = image.planes.expand((p) => p.bytes).toList();
    final size = Size(image.width.toDouble(), image.height.toDouble());
    final rotation = InputImageRotationValue.fromRawValue(
          controller.description.sensorOrientation,
        ) ??
        InputImageRotation.rotation0deg;
    final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
        InputImageFormat.nv21;

    final metadata = InputImageMetadata(
      size: size,
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
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

    return jsonDecode(response.body) as Map<String, dynamic>;
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
      }),
    );

    if (response.statusCode >= 400) {
      throw HttpException('OpenAI SOAP generation failed: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['choices'] as List).first['message']['content'] as String;
  }
}

final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier();
});

final edgeTrackerProvider = Provider<MentalHealthEdgeTracker>((ref) {
  final tracker = MentalHealthEdgeTracker();
  ref.onDispose(() => unawaited(tracker.dispose()));
  return tracker;
});

final azureServicesProvider = Provider<AzureHealthcareServices>((_) {
  return AzureHealthcareServices();
});

final edgeMetricsProvider = StateProvider<EdgeMetrics>((_) => EdgeMetrics.empty);

class HealthcareApp extends ConsumerWidget {
  const HealthcareApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      initialRoute: '/',
      routes: {
        '/': (context) => const RoleSelectionView(),
        '/patient_dashboard': (context) => const PatientDashboardView(),
        '/patient_diary': (context) => const PatientDiaryView(),
        '/clinician_patients': (context) => const ClinicianPatientListView(),
        '/settings': (context) => const SettingsView(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/clinician_dictation') {
          final patient = settings.arguments as String?;
          return MaterialPageRoute(
            builder: (_) => ClinicianDictationView(patientName: patient),
          );
        }
        return null;
      },
    );
  }
}

class RoleSelectionView extends ConsumerWidget {
  const RoleSelectionView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Care Continuum: Role Selection'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Select your role',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _RoleButton(
              title: 'I am a Patient',
              icon: Icons.person,
              onTap: () {
                ref.read(appStateProvider.notifier).setRole(UserRole.patient);
                Navigator.pushReplacementNamed(context, '/patient_dashboard');
              },
            ),
            const SizedBox(height: 16),
            _RoleButton(
              title: 'I am a Clinician',
              icon: Icons.medical_services,
              onTap: () {
                ref.read(appStateProvider.notifier).setRole(UserRole.clinician);
                Navigator.pushReplacementNamed(context, '/clinician_patients');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  const _RoleButton({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 80,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 32),
        label: Text(title, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

class PatientDashboardView extends ConsumerWidget {
  const PatientDashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(edgeMetricsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, '/patient_diary'),
        icon: const Icon(Icons.mic),
        label: const Text('Open Diary'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Mental Health Baseline Score: ${metrics.baselineScore.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('7-Day Mood Trend (Synthetic)'),
          SizedBox(height: 180, child: _MoodChart()),
          const SizedBox(height: 16),
          const Text('7-Day Blink Rate Trend (Synthetic)'),
          SizedBox(height: 180, child: _BlinkChart()),
        ],
      ),
    );
  }
}

class _MoodChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final points = [7.2, 6.8, 7.0, 6.5, 6.9, 7.3, 7.1];
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 10,
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              points.length,
              (index) => FlSpot(index.toDouble(), points[index]),
            ),
            isCurved: true,
            dotData: const FlDotData(show: true),
          ),
        ],
        titlesData: const FlTitlesData(show: true),
      ),
    );
  }
}

class _BlinkChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final points = [16.0, 14.5, 15.2, 12.9, 13.5, 14.1, 15.0];
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 30,
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              points.length,
              (index) => FlSpot(index.toDouble(), points[index]),
            ),
            isCurved: true,
            color: Colors.purple,
            dotData: const FlDotData(show: true),
          ),
        ],
        titlesData: const FlTitlesData(show: true),
      ),
    );
  }
}

class PatientDiaryView extends ConsumerStatefulWidget {
  const PatientDiaryView({super.key});

  @override
  ConsumerState<PatientDiaryView> createState() => _PatientDiaryViewState();
}

class _PatientDiaryViewState extends ConsumerState<PatientDiaryView> {
  final _audioRecorder = AudioRecorder();
  String _summary = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_setupTracker());
  }

  Future<void> _setupTracker() async {
    final appState = ref.read(appStateProvider);
    if (!appState.edgeTrackingEnabled) return;
    final tracker = ref.read(edgeTrackerProvider);
    try {
      await tracker.initializeFrontCamera();
      await tracker.startFaceTrackingStream(() {
        ref.read(edgeMetricsProvider.notifier).state = tracker.getAnonymizedMetrics();
      });
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _recordDiary() async {
    setState(() => _busy = true);
    final azure = ref.read(azureServicesProvider);
    try {
      const path = 'patient_diary.m4a';
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        throw const FileSystemException('Microphone permission denied.');
      }
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      await Future<void>.delayed(const Duration(seconds: 4));
      final audioPath = (await _audioRecorder.stop()) ?? path;
      final transcript = await azure.transcribeAudio(audioPath);
      final entities = await azure.extractHealthEntities(transcript);
      setState(() {
        _summary = 'Transcript: $transcript\nEntities: ${jsonEncode(entities)}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = ref.watch(edgeMetricsProvider);
    final tracker = ref.watch(edgeTrackerProvider);
    final edgeEnabled = ref.watch(appStateProvider).edgeTrackingEnabled;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Diary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!edgeEnabled)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('Edge eye tracking is disabled in Settings.'),
              ),
            )
          else
            AspectRatio(
              aspectRatio: 3 / 4,
              child: tracker.controller != null &&
                      tracker.controller!.value.isInitialized
                  ? CameraPreview(tracker.controller!)
                  : const Center(child: Text('Front camera unavailable')),
            ),
          const SizedBox(height: 12),
          Text('Blink rate: ${metrics.blinksPerMinute.toStringAsFixed(1)} BPM'),
          Text('Fatigue score: ${metrics.fatigueScore.toStringAsFixed(2)}'),
          Text('Anxiety score: ${metrics.anxietyScore.toStringAsFixed(2)}'),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _busy ? null : _recordDiary,
            icon: const Icon(Icons.mic),
            label: const Text('Record Daily Audio Log'),
          ),
          if (_summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_summary),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }
}

class ClinicianPatientListView extends ConsumerWidget {
  const ClinicianPatientListView({super.key});

  static const _patients = [
    ('Patient A', 'High fatigue score detected'),
    ('Patient B', 'Blink variability spike in last 24h'),
    ('Patient C', 'Diary indicates increased stress'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinician Patients'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _patients.length,
        itemBuilder: (context, index) {
          final patient = _patients[index];
          return Card(
            child: ListTile(
              title: Text(patient.$1),
              subtitle: Text(patient.$2),
              trailing: const Chip(
                label: Text('Alert'),
                avatar: Icon(Icons.warning, size: 16),
              ),
              onTap: () {
                ref.read(appStateProvider.notifier).selectPatient(patient.$1);
                Navigator.pushNamed(
                  context,
                  '/clinician_dictation',
                  arguments: patient.$1,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class ClinicianDictationView extends ConsumerStatefulWidget {
  const ClinicianDictationView({super.key, this.patientName});

  final String? patientName;

  @override
  ConsumerState<ClinicianDictationView> createState() =>
      _ClinicianDictationViewState();
}

class _ClinicianDictationViewState extends ConsumerState<ClinicianDictationView> {
  final _audioRecorder = AudioRecorder();
  String _soap = '';
  bool _busy = false;

  Future<void> _recordAndGenerateSoap() async {
    setState(() => _busy = true);
    final azure = ref.read(azureServicesProvider);
    final metrics = ref.read(edgeMetricsProvider).toJson();
    try {
      const path = 'clinician_dictation.m4a';
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        throw const FileSystemException('Microphone permission denied.');
      }
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      await Future<void>.delayed(const Duration(seconds: 4));
      final audioPath = (await _audioRecorder.stop()) ?? path;
      final transcript = await azure.transcribeAudio(audioPath);
      final note = await azure.generateSOAPNote(transcript, metrics);
      setState(() => _soap = note);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientName = widget.patientName ??
        ref.watch(appStateProvider).selectedPatient ??
        'Unknown Patient';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinician Dictation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Selected Patient: $patientName',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('Recent diary summary (mock):'),
          const Text('- Reports stress after poor sleep\n- Mild daytime fatigue'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _busy ? null : _recordAndGenerateSoap,
            icon: const Icon(Icons.mic),
            label: const Text('Record Dictation & Generate SOAP'),
          ),
          const SizedBox(height: 16),
          Text(_soap.isEmpty ? 'SOAP note will appear here.' : _soap),
        ],
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }
}

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings & Privacy')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Enable Edge Eye Tracking'),
            subtitle: const Text('Process camera frames locally with ML Kit.'),
            value: appState.edgeTrackingEnabled,
            onChanged: (enabled) =>
                ref.read(appStateProvider.notifier).setEdgeTrackingEnabled(enabled),
          ),
          ListTile(
            title: const Text('Data Purge'),
            subtitle: const Text('Clear selected patient context and session state.'),
            trailing: const Icon(Icons.delete_forever),
            onTap: () {
              ref.read(appStateProvider.notifier).purgeData();
              ref.read(edgeMetricsProvider.notifier).state = EdgeMetrics.empty;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Session data purged.')),
              );
            },
          ),
          ListTile(
            title: const Text('Purge Count'),
            subtitle: Text('${appState.purgeCounter}'),
          ),
        ],
      ),
    );
  }
}

void main() {
  runApp(const ProviderScope(child: HealthcareApp()));
}
