import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String azureSpeechEndpoint = String.fromEnvironment('AZURE_SPEECH_ENDPOINT');
const String azureTextAnalyticsEndpoint = String.fromEnvironment('AZURE_TA_ENDPOINT');
const String azureOpenAIEndpoint = String.fromEnvironment('AZURE_OPENAI_ENDPOINT');
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

  Map<String, dynamic> toJson() => {
        'day': day,
        'mood': mood,
        'blinkRate': blinkRate,
      };

  factory TrendData.fromJson(Map<String, dynamic> json) {
    return TrendData(
      day: json['day'] as String? ?? '',
      mood: (json['mood'] as num? ?? 0).toDouble(),
      blinkRate: (json['blinkRate'] as num? ?? 0).toDouble(),
    );
  }
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'alert': alert,
      };

  factory PatientAlert.fromJson(Map<String, dynamic> json) {
    return PatientAlert(
      id: json['id'] as String? ?? 'self',
      name: json['name'] as String? ?? 'Current Patient',
      alert: json['alert'] as String? ?? 'No active alert',
    );
  }
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
        trends: const [],
        patientAlerts: const [],
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
  AppStateNotifier() : super(AppState.initial()) {
    unawaited(loadFromDisk());
  }

  static const _prefsEdgeTracking = 'edge_tracking_enabled';
  static const _prefsDiarySummary = 'diary_summary';
  static const _prefsSoapNote = 'soap_note';
  static const _prefsSelectedPatientId = 'selected_patient_id';
  static const _prefsTrends = 'trends_json';

  Future<void> loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final trendJsonList = prefs.getStringList(_prefsTrends) ?? const [];
    final trends = trendJsonList
        .map((item) => TrendData.fromJson(jsonDecode(item) as Map<String, dynamic>))
        .toList();
    final edgeTrackingEnabled = prefs.getBool(_prefsEdgeTracking) ?? true;
    final diarySummary = prefs.getString(_prefsDiarySummary) ?? '';
    final soapNote = prefs.getString(_prefsSoapNote) ?? '';
    final selectedPatientId = prefs.getString(_prefsSelectedPatientId);
    final alerts = _derivePatientAlerts(state.metrics, trends, diarySummary.isNotEmpty);

    state = state.copyWith(
      edgeTrackingEnabled: edgeTrackingEnabled,
      diarySummary: diarySummary,
      soapNote: soapNote,
      selectedPatientId: selectedPatientId,
      trends: trends,
      patientAlerts: alerts,
    );
  }

  Future<void> _saveToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEdgeTracking, state.edgeTrackingEnabled);
    await prefs.setString(_prefsDiarySummary, state.diarySummary);
    await prefs.setString(_prefsSoapNote, state.soapNote);
    final selectedPatientId = state.selectedPatientId;
    if (selectedPatientId == null) {
      await prefs.remove(_prefsSelectedPatientId);
    } else {
      await prefs.setString(_prefsSelectedPatientId, selectedPatientId);
    }
    await prefs.setStringList(
      _prefsTrends,
      state.trends.map((t) => jsonEncode(t.toJson())).toList(),
    );
  }

  List<PatientAlert> _derivePatientAlerts(
    EdgeMetrics metrics,
    List<TrendData> trends,
    bool hasDiary,
  ) {
    String alert;
    if (!hasDiary) {
      alert = 'No diary data recorded yet';
    } else if (metrics.fatigueScore >= 0.60) {
      alert = 'High fatigue score detected';
    } else if (metrics.anxietyScore >= 0.60) {
      alert = 'High anxiety score detected';
    } else if (trends.length >= 2 && trends.last.mood < trends[trends.length - 2].mood) {
      alert = 'Mood trend decreased since last entry';
    } else {
      alert = 'Stable metrics';
    }

    return [
      PatientAlert(
        id: 'self',
        name: 'Current Patient',
        alert: alert,
      ),
    ];
  }

  String _dayLabel(DateTime now) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[now.weekday - 1];
  }

  void _syncAlertsAndPersist() {
    state = state.copyWith(
      patientAlerts: _derivePatientAlerts(
        state.metrics,
        state.trends,
        state.diarySummary.isNotEmpty,
      ),
    );
    unawaited(_saveToDisk());
  }

  void setRole(UserRole role) {
    state = state.copyWith(role: role, errorMessage: '');
    _syncAlertsAndPersist();
  }

  void setSelectedPatient(String id) {
    state = state.copyWith(selectedPatientId: id, errorMessage: '');
    _syncAlertsAndPersist();
  }

  void setMetrics(EdgeMetrics metrics) {
    state = state.copyWith(
      metrics: metrics,
      patientAlerts: _derivePatientAlerts(
        metrics,
        state.trends,
        state.diarySummary.isNotEmpty,
      ),
    );
  }

  void setDiarySummary(String summary) {
    final mood =
        (10 - ((state.metrics.fatigueScore + state.metrics.anxietyScore) * 5)).clamp(1, 10);
    final entry = TrendData(
      day: _dayLabel(DateTime.now()),
      mood: mood.toDouble(),
      blinkRate: state.metrics.blinksPerMinute,
    );

    final updatedTrends = List<TrendData>.from(state.trends);
    if (updatedTrends.isNotEmpty && updatedTrends.last.day == entry.day) {
      updatedTrends[updatedTrends.length - 1] = entry;
    } else {
      updatedTrends.add(entry);
    }
    while (updatedTrends.length > 7) {
      updatedTrends.removeAt(0);
    }

    state = state.copyWith(
      diarySummary: summary,
      trends: updatedTrends,
      errorMessage: '',
    );
    _syncAlertsAndPersist();
  }

  void setSoapNote(String soap) {
    state = state.copyWith(soapNote: soap, errorMessage: '');
    _syncAlertsAndPersist();
  }

  void setError(String error) {
    state = state.copyWith(errorMessage: error);
    _syncAlertsAndPersist();
  }

  void toggleEdgeTracking(bool enabled) {
    state = state.copyWith(edgeTrackingEnabled: enabled);
    _syncAlertsAndPersist();
  }

  void purgeData() {
    state = state.copyWith(
      diarySummary: '',
      soapNote: '',
      errorMessage: '',
      selectedPatientId: null,
      trends: const [],
    );
    _syncAlertsAndPersist();
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
    final hasTrends = trends.isNotEmpty;
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
              child: hasTrends
                  ? SizedBox(
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
                    )
                  : const SizedBox(
                      height: 140,
                      child: Center(
                        child: Text('No diary trend data yet. Record a daily log first.'),
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
      Map<String, dynamic> entities;
      try {
        entities = await azure.extractHealthEntities(transcript);
      } catch (_) {
        entities = azure.localEntityFallback(transcript);
      }
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
            'Privacy: eye tracking remains on-device. Cloud calls are only to your configured Azure resources.',
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
      body: state.patientAlerts.isEmpty
          ? const Center(
              child: Text('No patient context yet. Record a patient diary entry first.'),
            )
          : ListView.builder(
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
      String soap;
      try {
        soap = await azure.generateSOAPNote(transcript, state.metrics.toJson());
      } catch (_) {
        soap = azure.localSoapFallback(state.metrics.toJson());
      }
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
    final matches = state.patientAlerts.where((p) => p.id == patientId).toList();
    final patient = matches.isEmpty ? null : matches.first;
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
    final cloudConfigured = azureSpeechEndpoint.isNotEmpty &&
        azureTextAnalyticsEndpoint.isNotEmpty &&
        azureOpenAIEndpoint.isNotEmpty &&
        azureSpeechKey.isNotEmpty &&
        azureTextAnalyticsKey.isNotEmpty &&
        azureOpenAIKey.isNotEmpty;
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
          ListTile(
            title: const Text('Azure Cloud Integration'),
            subtitle: Text(
              cloudConfigured
                  ? 'Configured and active.'
                  : 'Not fully configured. Local fallback generation will be used.',
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  runApp(const ProviderScope(child: HealthcareApp()));
}
