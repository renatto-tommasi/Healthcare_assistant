import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

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

  double get baselineScore =>
      (100 * (1 - ((fatigueScore + anxietyScore) / 2))).clamp(0, 100).toDouble();

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
        if (faces.isEmpty) return;

        final face = faces.first;
        final left = face.leftEyeOpenProbability ?? 1;
        final right = face.rightEyeOpenProbability ?? 1;
        final eyesClosed = left < 0.35 && right < 0.35;

        if (!eyesClosed && _lastEyesClosed) {
          _blinkCount += 1;
          onMetricsUpdated();
        }
        _lastEyesClosed = eyesClosed;
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

    final metadata = InputImageMetadata(
      size: size,
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(
      bytes: Uint8List.fromList(bytes),
      metadata: metadata,
    );
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
    return 'Synthetic transcript: patient reports moderate stress and disrupted sleep.';
  }

  Future<Map<String, dynamic>> extractHealthEntities(String text) async {
    return {
      'symptoms': ['stress', 'poor sleep'],
      'medications': <String>[],
      'diagnoses': <String>[],
    };
  }

  Future<String> generateSOAPNote(
    String clinicianTranscript,
    Map<String, dynamic> patientMetrics,
  ) async {
    return '''
## Subjective
Patient reports elevated stress and reduced sleep quality.

## Objective
Blink rate: ${(patientMetrics['blink_rate_bpm'] ?? 0).toStringAsFixed(1)} BPM.
Fatigue score: ${(patientMetrics['fatigue_score'] ?? 0).toStringAsFixed(2)}.
Anxiety score: ${(patientMetrics['anxiety_score'] ?? 0).toStringAsFixed(2)}.

## Assessment
Pattern consistent with stress-related fatigue.

## Plan
Reinforce sleep hygiene, monitor diary trend, and re-evaluate in 2 weeks.
''';
  }
}

enum UserRole { patient, clinician }

class TrendData {
  const TrendData({
    required this.day,
    required this.mood,
    required this.blinkRate,
  });

  final String day;
  final double mood;
  final double blinkRate;
}

class PatientAlert {
  const PatientAlert({
    required this.id,
    required this.name,
    required this.alert,
  });

  final String id;
  final String name;
  final String alert;
}

class AppState {
  const AppState({
    required this.role,
    required this.selectedPatientId,
    required this.edgeTrackingEnabled,
    required this.diarySummary,
    required this.soapNote,
    required this.errorMessage,
    required this.metrics,
    required this.trends,
    required this.patientAlerts,
  });

  final UserRole? role;
  final String? selectedPatientId;
  final bool edgeTrackingEnabled;
  final String diarySummary;
  final String soapNote;
  final String errorMessage;
  final EdgeMetrics metrics;
  final List<TrendData> trends;
  final List<PatientAlert> patientAlerts;

  factory AppState.initial() => AppState(
        role: null,
        selectedPatientId: null,
        edgeTrackingEnabled: true,
        diarySummary: '',
        soapNote: '',
        errorMessage: '',
        metrics: EdgeMetrics.empty,
        trends: const [
          TrendData(day: 'Mon', mood: 6.3, blinkRate: 16),
          TrendData(day: 'Tue', mood: 5.8, blinkRate: 18),
          TrendData(day: 'Wed', mood: 6.6, blinkRate: 15),
          TrendData(day: 'Thu', mood: 6.1, blinkRate: 20),
          TrendData(day: 'Fri', mood: 6.7, blinkRate: 14),
          TrendData(day: 'Sat', mood: 7.0, blinkRate: 13),
          TrendData(day: 'Sun', mood: 6.5, blinkRate: 17),
        ],
        patientAlerts: const [
          PatientAlert(
            id: 'p001',
            name: 'Patient A',
            alert: 'High fatigue score detected',
          ),
          PatientAlert(
            id: 'p002',
            name: 'Patient B',
            alert: 'Sustained anxiety trend',
          ),
          PatientAlert(
            id: 'p003',
            name: 'Patient C',
            alert: 'Missed diary updates (2 days)',
          ),
        ],
      );

  AppState copyWith({
    UserRole? role,
    String? selectedPatientId,
    bool? edgeTrackingEnabled,
    String? diarySummary,
    String? soapNote,
    String? errorMessage,
    EdgeMetrics? metrics,
    List<TrendData>? trends,
    List<PatientAlert>? patientAlerts,
  }) {
    return AppState(
      role: role ?? this.role,
      selectedPatientId: selectedPatientId ?? this.selectedPatientId,
      edgeTrackingEnabled: edgeTrackingEnabled ?? this.edgeTrackingEnabled,
      diarySummary: diarySummary ?? this.diarySummary,
      soapNote: soapNote ?? this.soapNote,
      errorMessage: errorMessage ?? this.errorMessage,
      metrics: metrics ?? this.metrics,
      trends: trends ?? this.trends,
      patientAlerts: patientAlerts ?? this.patientAlerts,
    );
  }
}

class AppStateNotifier extends StateNotifier<AppState> {
  AppStateNotifier() : super(AppState.initial());

  void setRole(UserRole role) {
    state = state.copyWith(role: role, errorMessage: '');
  }

  void setSelectedPatient(String id) {
    state = state.copyWith(selectedPatientId: id, errorMessage: '');
  }

  void setMetrics(EdgeMetrics metrics) {
    state = state.copyWith(metrics: metrics);
  }

  void setDiarySummary(String summary) {
    state = state.copyWith(diarySummary: summary, errorMessage: '');
  }

  void setSoapNote(String soap) {
    state = state.copyWith(soapNote: soap, errorMessage: '');
  }

  void setError(String error) {
    state = state.copyWith(errorMessage: error);
  }

  void toggleEdgeTracking(bool enabled) {
    state = state.copyWith(edgeTrackingEnabled: enabled);
  }

  void purgeData() {
    state = state.copyWith(
      diarySummary: '',
      soapNote: '',
      errorMessage: '',
      selectedPatientId: null,
    );
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

final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((_) {
  return AppStateNotifier();
});

class HealthcareApp extends ConsumerWidget {
  const HealthcareApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Healthcare Continuum',
      initialRoute: '/login',
      routes: {
        '/': (_) => const RoleSelectionView(),
        '/login': (_) => const RoleSelectionView(),
        '/patient_dashboard': (_) => const PatientDashboardView(),
        '/patient_diary': (_) => const PatientDiaryView(),
        '/clinician_patients': (_) => const ClinicianPatientListView(),
        '/settings': (_) => const SettingsView(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/clinician_dictation') {
          final patientId = settings.arguments as String?;
          return MaterialPageRoute<void>(
            builder: (_) => ClinicianDictationView(patientId: patientId),
          );
        }
        return null;
      },
    );
  }
}

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.fab,
  });

  final String title;
  final Widget body;
  final Widget? fab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: body,
      floatingActionButton: fab,
    );
  }
}

class RoleSelectionView extends ConsumerWidget {
  const RoleSelectionView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appStateProvider.notifier);
    return AppScaffold(
      title: 'Role Selection',
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Welcome to Healthcare Continuum',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  notifier.setRole(UserRole.patient);
                  Navigator.pushReplacementNamed(context, '/patient_dashboard');
                },
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(24)),
                child: const Text('I am a Patient'),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  notifier.setRole(UserRole.clinician);
                  Navigator.pushReplacementNamed(context, '/clinician_patients');
                },
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(24)),
                child: const Text('I am a Clinician'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PatientDashboardView extends ConsumerWidget {
  const PatientDashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final trends = state.trends;
    return AppScaffold(
      title: 'Patient Dashboard',
      fab: FloatingActionButton(
        onPressed: () => Navigator.pushNamed(context, '/patient_diary'),
        child: const Icon(Icons.edit_note),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.psychology_alt),
              title: const Text('Mental Health Baseline Score'),
              subtitle: Text('${state.metrics.baselineScore.toStringAsFixed(0)} / 100'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: 260,
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: 25,
                    gridData: const FlGridData(show: true),
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= trends.length) return const SizedBox();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(trends[idx].day),
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (var i = 0; i < trends.length; i++)
                            FlSpot(i.toDouble(), trends[i].mood * 2.5),
                        ],
                        color: Colors.blue,
                        isCurved: true,
                        dotData: const FlDotData(show: false),
                      ),
                      LineChartBarData(
                        spots: [
                          for (var i = 0; i < trends.length; i++)
                            FlSpot(i.toDouble(), trends[i].blinkRate),
                        ],
                        color: Colors.green,
                        isCurved: true,
                        dotData: const FlDotData(show: false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Blue: Mood trend (scaled)   Green: Blink rate trend'),
        ],
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
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeTracker());
  }

  Future<void> _initializeTracker() async {
    final appState = ref.read(appStateProvider);
    if (!appState.edgeTrackingEnabled) {
      return;
    }
    final tracker = ref.read(edgeTrackerProvider);
    try {
      await tracker.initializeFrontCamera();
      await tracker.startFaceTrackingStream(() {
        ref.read(appStateProvider.notifier).setMetrics(tracker.getAnonymizedMetrics());
      });
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      ref
          .read(appStateProvider.notifier)
          .setError('Edge tracking unavailable. Camera permission may be denied.');
    }
  }

  Future<String> _recordShortClip() async {
    final tempDir = await getTemporaryDirectory();
    final filePath =
        '${tempDir.path}${Platform.pathSeparator}diary_${DateTime.now().millisecondsSinceEpoch}.m4a';
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

  Future<void> _runDiaryFlow() async {
    setState(() => _isBusy = true);
    final azure = ref.read(azureServicesProvider);
    final notifier = ref.read(appStateProvider.notifier);
    try {
      final audioPath = await _recordShortClip();
      final transcript = await azure.transcribeAudio(audioPath);
      final entities = await azure.extractHealthEntities(transcript);
      notifier.setDiarySummary(
        'Transcript: $transcript\nEntities: ${jsonEncode(entities)}',
      );
    } catch (e) {
      notifier.setError('Diary recording failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  @override
  void dispose() {
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracker = ref.watch(edgeTrackerProvider);
    final state = ref.watch(appStateProvider);

    return AppScaffold(
      title: 'Patient Diary',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!state.edgeTrackingEnabled)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('Edge eye tracking is disabled in Settings.'),
              ),
            ),
          AspectRatio(
            aspectRatio: 3 / 4,
            child: state.edgeTrackingEnabled &&
                    tracker.controller != null &&
                    tracker.controller!.value.isInitialized
                ? CameraPreview(tracker.controller!)
                : const Center(child: Text('Front camera unavailable')),
          ),
          const SizedBox(height: 12),
          Text('Blink rate: ${state.metrics.blinksPerMinute.toStringAsFixed(1)} BPM'),
          Text('Fatigue score: ${state.metrics.fatigueScore.toStringAsFixed(2)}'),
          Text('Anxiety score: ${state.metrics.anxietyScore.toStringAsFixed(2)}'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isBusy ? null : _runDiaryFlow,
            icon: const Icon(Icons.mic),
            label: const Text('Record Daily Audio Log (4s)'),
          ),
          const SizedBox(height: 10),
          const Text(
            'Privacy: eye tracking remains on-device and cloud responses are synthetic.',
          ),
          if (state.diarySummary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(state.diarySummary),
          ],
          if (state.errorMessage.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              state.errorMessage,
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ],
      ),
    );
  }
}

class ClinicianPatientListView extends ConsumerWidget {
  const ClinicianPatientListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final notifier = ref.read(appStateProvider.notifier);
    return AppScaffold(
      title: 'Clinician Patients',
      body: ListView.builder(
        itemCount: state.patientAlerts.length,
        itemBuilder: (context, index) {
          final patient = state.patientAlerts[index];
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(patient.name),
            subtitle: Text(patient.alert),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              notifier.setSelectedPatient(patient.id);
              Navigator.pushNamed(context, '/clinician_dictation', arguments: patient.id);
            },
          );
        },
      ),
    );
  }
}

class ClinicianDictationView extends ConsumerStatefulWidget {
  const ClinicianDictationView({super.key, this.patientId});

  final String? patientId;

  @override
  ConsumerState<ClinicianDictationView> createState() => _ClinicianDictationViewState();
}

class _ClinicianDictationViewState extends ConsumerState<ClinicianDictationView> {
  final _audioRecorder = AudioRecorder();
  bool _isBusy = false;

  Future<String> _recordShortClip() async {
    final tempDir = await getTemporaryDirectory();
    final filePath =
        '${tempDir.path}${Platform.pathSeparator}dictation_${DateTime.now().millisecondsSinceEpoch}.m4a';
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

  Future<void> _runSoapFlow() async {
    setState(() => _isBusy = true);
    final notifier = ref.read(appStateProvider.notifier);
    final state = ref.read(appStateProvider);
    final azure = ref.read(azureServicesProvider);
    try {
      final audioPath = await _recordShortClip();
      final transcript = await azure.transcribeAudio(audioPath);
      final soap = await azure.generateSOAPNote(
        transcript,
        state.metrics.toJson(),
      );
      notifier.setSoapNote(soap);
    } catch (e) {
      notifier.setError('SOAP generation failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  @override
  void dispose() {
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final patientId = widget.patientId ?? state.selectedPatientId ?? 'Unknown';
    final patient = state.patientAlerts.where((p) => p.id == patientId).firstOrNull;
    return AppScaffold(
      title: 'Clinician Dictation',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Patient: ${patient?.name ?? patientId}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Alert: ${patient?.alert ?? 'No active alert'}'),
            const SizedBox(height: 12),
            const Text(
              'Recent diary summary:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(state.diarySummary.isEmpty ? 'No diary summary available yet.' : state.diarySummary),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isBusy ? null : _runSoapFlow,
              icon: const Icon(Icons.mic),
              label: const Text('Record Dictation & Generate SOAP'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  state.soapNote.isEmpty ? 'SOAP note will appear here.' : state.soapNote,
                ),
              ),
            ),
            if (state.errorMessage.isNotEmpty)
              Text(
                state.errorMessage,
                style: const TextStyle(color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }
}

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final notifier = ref.read(appStateProvider.notifier);
    return AppScaffold(
      title: 'Privacy & Compliance',
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Enable Edge Eye Tracking'),
            subtitle: const Text('Run gaze/blink analytics only on this device.'),
            value: state.edgeTrackingEnabled,
            onChanged: notifier.toggleEdgeTracking,
          ),
          SwitchListTile(
            title: const Text('Data Purge'),
            subtitle: const Text('Clear local summaries and generated SOAP note.'),
            value: false,
            onChanged: (value) {
              if (!value) return;
              notifier.purgeData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Local health context purged.')),
              );
            },
          ),
          const ListTile(
            title: Text('Synthetic Cloud Mode'),
            subtitle: Text('Transcription/entity extraction/SOAP are mock-generated to protect privacy.'),
          ),
        ],
      ),
    );
  }
}

void main() {
  runApp(const ProviderScope(child: HealthcareApp()));
}
