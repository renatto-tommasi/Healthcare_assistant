import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'models/app_models.dart';
import 'repositories/local_app_state_repository.dart';
import 'services/azure_healthcare_services.dart';
import 'services/mental_health_edge_tracker.dart';
import 'state/app_state_notifier.dart';

final edgeTrackerProvider = Provider<MentalHealthEdgeTracker>((ref) {
  final tracker = MentalHealthEdgeTracker();
  ref.onDispose(() => unawaited(tracker.dispose()));
  return tracker;
});

final azureServicesProvider = Provider<AzureHealthcareServices>((_) {
  return AzureHealthcareServices();
});

final appStateRepositoryProvider = Provider<LocalAppStateRepository>((_) {
  return LocalAppStateRepository();
});

final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier(ref.read(appStateRepositoryProvider));
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
        if (settings.name == '/clinician_patient_detail') {
          final patientId = settings.arguments as String?;
          return MaterialPageRoute<void>(
            builder: (_) => ClinicianPatientDetailView(patientId: patientId),
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
    final patientId =
        state.activePatientId ?? (state.patients.isNotEmpty ? state.patients.first.id : 'self');
    final patient = state.patients.where((p) => p.id == patientId).toList();
    final patientName = patient.isEmpty ? 'Current Patient' : patient.first.displayName;
    final notifier = ref.read(appStateProvider.notifier);
    final logs = notifier.logsForPatient(patientId);

    return AppScaffold(
      title: 'Patient Dashboard',
      fab: FloatingActionButton(
        onPressed: () => Navigator.pushNamed(context, '/patient_diary'),
        child: const Icon(Icons.mic),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.person),
              title: Text(patientName),
              subtitle: Text('${logs.length} total log(s)'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recent Logs',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (logs.isEmpty)
                    const Text('No logs yet. Start your first log from the microphone button.')
                  else
                    ...logs.take(5).map((log) {
                      final status = log.processingStatus.name.toUpperCase();
                      final snippet = log.transcript.trim().isEmpty
                          ? (log.patientNote?.trim().isNotEmpty ?? false)
                              ? 'Note: ${log.patientNote}'
                              : 'No transcript available.'
                          : log.transcript.trim();
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(_formatIsoDate(log.startedAtIso)),
                        subtitle: Text(
                          snippet.length > 90 ? '${snippet.substring(0, 90)}...' : snippet,
                        ),
                        trailing: Text(status),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Privacy: feature extraction runs locally; detailed metrics are visible only to clinicians.',
          ),
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

class PatientDiaryView extends ConsumerStatefulWidget {
  const PatientDiaryView({super.key});

  @override
  ConsumerState<PatientDiaryView> createState() => _PatientDiaryViewState();
}

class _PatientDiaryViewState extends ConsumerState<PatientDiaryView> {
  final _audioRecorder = AudioRecorder();
  final _noteController = TextEditingController();
  final _maxDuration = const Duration(minutes: 5);
  Timer? _elapsedTimer;
  Timer? _maxDurationTimer;
  Duration _elapsed = Duration.zero;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeTracker());
  }

  Future<void> _initializeTracker() async {
    final notifier = ref.read(appStateProvider.notifier);
    final appState = ref.read(appStateProvider);
    if (!appState.edgeTrackingEnabled) {
      notifier.ensureDefaultPatient();
      return;
    }
    final tracker = ref.read(edgeTrackerProvider);
    try {
      await tracker.initializeFrontCamera();
      await tracker.startFaceTrackingStream(() {});
      notifier.ensureDefaultPatient();
      if (mounted) setState(() {});
    } catch (_) {
      notifier.setError('Edge tracking unavailable. Camera permission may be denied.');
    }
  }

  Future<String?> _buildAudioPath() async {
    final tempDir = await getTemporaryDirectory();
    return '${tempDir.path}${Platform.pathSeparator}'
        'diary_${DateTime.now().millisecondsSinceEpoch}.wav';
  }

  void _startElapsedClock() {
    _elapsedTimer?.cancel();
    _elapsed = Duration.zero;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = _elapsed + const Duration(seconds: 1));
    });
    _maxDurationTimer?.cancel();
    _maxDurationTimer = Timer(_maxDuration, () {
      if (mounted) {
        unawaited(_stopLog());
      }
    });
  }

  void _stopElapsedClock() {
    _elapsedTimer?.cancel();
    _maxDurationTimer?.cancel();
  }

  Future<void> _startLog() async {
    if (_isBusy) return;
    final notifier = ref.read(appStateProvider.notifier);
    final patientId = ref.read(appStateProvider).activePatientId ?? notifier.ensureDefaultPatient();
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      notifier.setError('Microphone permission denied.');
      return;
    }

    final path = await _buildAudioPath();
    if (path == null) {
      notifier.setError('Unable to create audio file path.');
      return;
    }

    setState(() => _isBusy = true);
    try {
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: path,
      );
      ref.read(edgeTrackerProvider).beginLogSession();
      notifier.startPatientLog(
        patientId: patientId,
        optionalNote: _noteController.text,
        tempAudioPath: path,
      );
      _startElapsedClock();
      notifier.clearError();
    } catch (e) {
      notifier.setError('Failed to start recording: $e');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _stopLog() async {
    if (_isBusy) return;
    final notifier = ref.read(appStateProvider.notifier);
    final currentState = ref.read(appStateProvider);
    if (!currentState.recordingSession.isRecording) {
      return;
    }
    final patientId = currentState.recordingSession.patientId ??
        currentState.activePatientId ??
        notifier.ensureDefaultPatient();

    setState(() => _isBusy = true);
    try {
      final stoppedPath =
          await _audioRecorder.stop() ?? currentState.recordingSession.tempAudioPath;
      _stopElapsedClock();
      final metrics = ref.read(edgeTrackerProvider).endLogSession();
      final entryId = notifier.stopPatientLog(
        patientId: patientId,
        audioPath: stoppedPath,
        metrics: metrics,
      );

      if (stoppedPath == null || stoppedPath.isEmpty) {
        notifier.finalizePatientLog(
          entryId: entryId,
          transcript: '',
          entities: const <String, dynamic>{},
          error: 'Audio file path unavailable after stop.',
        );
        return;
      }

      final persistedLog = notifier.logById(entryId);
      if (persistedLog == null) {
        notifier.finalizePatientLog(
          entryId: entryId,
          transcript: '',
          entities: const <String, dynamic>{},
          error: 'Could not locate persisted log for processing.',
        );
        return;
      }
      final processing = await ref.read(azureServicesProvider).transcribeAndExtract(
            persistedLog,
          );
      notifier.finalizePatientLog(
        entryId: entryId,
        transcript: processing.transcript,
        entities: processing.entities,
        error: processing.error,
      );
      if (processing.error == null && mounted) {
        _noteController.clear();
      }
    } catch (e) {
      notifier.setError('Failed to stop recording: $e');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  @override
  void dispose() {
    _stopElapsedClock();
    unawaited(_audioRecorder.dispose());
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final notifier = ref.read(appStateProvider.notifier);
    final patientId =
        state.activePatientId ?? (state.patients.isNotEmpty ? state.patients.first.id : 'self');
    final logs = notifier.logsForPatient(patientId);
    final tracker = state.edgeTrackingEnabled ? ref.watch(edgeTrackerProvider) : null;
    final recording = state.recordingSession.isRecording;
    final elapsedLabel =
        '${_elapsed.inMinutes.toString().padLeft(2, '0')}:${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

    return AppScaffold(
      title: 'Patient Diary',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: state.edgeTrackingEnabled &&
                    tracker != null &&
                    tracker.controller != null &&
                    tracker.controller!.value.isInitialized
                ? CameraPreview(tracker.controller!)
                : const Center(child: Text('Front camera unavailable')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Optional note',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => notifier.updateRecordingNoteDraft(value),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: recording || _isBusy ? null : _startLog,
                  icon: const Icon(Icons.fiber_manual_record),
                  label: const Text('Start Log'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (!recording || _isBusy) ? null : _stopLog,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop Log'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            recording ? 'Recording... $elapsedLabel' : 'Not recording',
            style: TextStyle(
              color: recording ? Colors.red : Colors.black87,
              fontWeight: recording ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 12),
          const Text('Log History', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (logs.isEmpty)
            const Text('No logs yet.')
          else
            ...logs.map((log) {
              final transcript = log.transcript.trim();
              return Card(
                child: ListTile(
                  title: Text(_formatIsoDate(log.startedAtIso)),
                  subtitle: Text(
                    transcript.isEmpty
                        ? (log.errorMessage ?? 'Transcript pending...')
                        : (transcript.length > 110
                            ? '${transcript.substring(0, 110)}...'
                            : transcript),
                  ),
                  trailing: _StatusPill(label: log.processingStatus.name),
                ),
              );
            }),
          const SizedBox(height: 10),
          const Text(
            'Privacy: Patients cannot view feature-level analytics. Detailed breakdown is clinician-only.',
          ),
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

  Future<void> _createPatientDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Patient'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Patient name',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                ref.read(appStateProvider.notifier).createPatientProfile(controller.text);
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final notifier = ref.read(appStateProvider.notifier);
    final patients = state.patients;

    return AppScaffold(
      title: 'Clinician Patients',
      fab: FloatingActionButton(
        onPressed: () => _createPatientDialog(context, ref),
        child: const Icon(Icons.person_add),
      ),
      body: patients.isEmpty
          ? const Center(
              child: Text('No patient profiles yet. Add a patient to begin.'),
            )
          : ListView.builder(
              itemCount: patients.length,
              itemBuilder: (context, index) {
                final patient = patients[index];
                final score = notifier.latestPatientScore(patient.id);
                final risk = notifier.riskBadgeForPatient(patient.id);
                final scoreText =
                    score == null ? '--' : score.clamp(0, 100).toStringAsFixed(0);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(patient.displayName),
                    subtitle: Text('Score: $scoreText   Risk: $risk'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      notifier.selectActivePatient(patient.id);
                      Navigator.pushNamed(
                        context,
                        '/clinician_patient_detail',
                        arguments: patient.id,
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

class ClinicianPatientDetailView extends ConsumerStatefulWidget {
  const ClinicianPatientDetailView({super.key, this.patientId});

  final String? patientId;

  @override
  ConsumerState<ClinicianPatientDetailView> createState() =>
      _ClinicianPatientDetailViewState();
}

class _ClinicianPatientDetailViewState extends ConsumerState<ClinicianPatientDetailView> {
  final _audioRecorder = AudioRecorder();
  bool _isBusy = false;

  Future<String> _recordShortClip() async {
    final tempDir = await getTemporaryDirectory();
    final filePath =
        '${tempDir.path}${Platform.pathSeparator}dictation_${DateTime.now().millisecondsSinceEpoch}.wav';
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      throw const FileSystemException('Microphone permission denied.');
    }
    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.wav),
      path: filePath,
    );
    await Future<void>.delayed(const Duration(seconds: 4));
    return (await _audioRecorder.stop()) ?? filePath;
  }

  Future<void> _runSoapFlow(String patientId) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    final notifier = ref.read(appStateProvider.notifier);
    final azure = ref.read(azureServicesProvider);
    try {
      final logs = notifier.logsForPatient(patientId)
          .where((e) => e.processingStatus == PatientLogProcessingStatus.complete)
          .toList();
      final sourceLog = logs.isEmpty ? null : logs.first;
      final metrics = sourceLog?.metricsSnapshot.toJson() ?? EdgeMetrics.empty.toJson();
      final audioPath = await _recordShortClip();
      final transcript = await azure.transcribeAudio(audioPath);
      String soap;
      try {
        soap = await azure.generateSOAPNote(transcript, metrics);
      } catch (_) {
        soap = azure.localSoapFallback(metrics);
      }
      notifier.addClinicianSoapEntry(
        patientId: patientId,
        content: soap,
        sourceLogId: sourceLog?.id,
      );
    } catch (e) {
      notifier.setError('SOAP generation failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  void _showFeatureBreakdown(BuildContext context, EdgeMetrics metrics) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Feature Breakdown',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
              const SizedBox(height: 8),
              _metricRow('Blink rate', '${metrics.blinksPerMinute.toStringAsFixed(1)} BPM'),
              _metricRow('Fatigue score', metrics.fatigueScore.toStringAsFixed(2)),
              _metricRow('Anxiety score', metrics.anxietyScore.toStringAsFixed(2)),
              _metricRow(
                'Tracking uptime',
                '${metrics.trackingUptimePercent.toStringAsFixed(1)}%',
              ),
              _metricRow('Sample rate', '${metrics.sampleRateHz.toStringAsFixed(1)} Hz'),
              _metricRow(
                'Eye closure rate',
                '${metrics.eyeClosureRatePercent.toStringAsFixed(1)}%',
              ),
              _metricRow('Gaze drift', '${metrics.gazeDriftDegrees.toStringAsFixed(1)} deg'),
              _metricRow(
                'Fixation instability',
                '${metrics.fixationInstabilityDegrees.toStringAsFixed(1)} deg',
              ),
              _metricRow('Tracking quality', metrics.trackingQualityScore.toStringAsFixed(2)),
              _metricRow('Baseline score', metrics.baselineScore.toStringAsFixed(0)),
            ],
          ),
        );
      },
    );
  }

  Widget _metricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final notifier = ref.read(appStateProvider.notifier);
    final patientId = widget.patientId ?? state.activePatientId;
    if (patientId == null) {
      return const AppScaffold(
        title: 'Patient Detail',
        body: Center(child: Text('No patient selected.')),
      );
    }
    final patient = state.patients.where((p) => p.id == patientId).toList();
    final patientName = patient.isEmpty ? patientId : patient.first.displayName;
    final logs = notifier.logsForPatient(patientId);
    final soapEntries = notifier.clinicianEntriesForPatient(patientId);
    final trend = notifier.scoreTrend(patientId, 7);

    return AppScaffold(
      title: 'Clinician Detail',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            patientName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Latest score: ${notifier.latestPatientScore(patientId)?.toStringAsFixed(0) ?? '--'}',
          ),
          Text('Risk: ${notifier.riskBadgeForPatient(patientId)}'),
          const SizedBox(height: 12),
          const Text('Score Trend (last 7 complete logs)'),
          const SizedBox(height: 8),
          if (trend.isEmpty)
            const Text('No completed logs for trend yet.')
          else
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: 100,
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < trend.length; i++) FlSpot(i.toDouble(), trend[i]),
                      ],
                      isCurved: true,
                      color: Colors.blue,
                      dotData: const FlDotData(show: true),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
          const Text('Log Timeline', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (logs.isEmpty)
            const Text('No logs yet.')
          else
            ...logs.map((log) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(_formatIsoDate(log.startedAtIso))),
                          _StatusPill(label: log.processingStatus.name),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Score: ${log.baselineScore.toStringAsFixed(0)}'),
                      if (log.errorMessage != null && log.errorMessage!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(log.errorMessage!, style: const TextStyle(color: Colors.red)),
                      ],
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => _showFeatureBreakdown(context, log.metricsSnapshot),
                        child: const Text('View Feature Breakdown'),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text('SOAP Entries', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              ElevatedButton.icon(
                onPressed: _isBusy ? null : () => _runSoapFlow(patientId),
                icon: const Icon(Icons.mic, size: 16),
                label: const Text('Add SOAP'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (soapEntries.isEmpty)
            const Text('No SOAP entries yet.')
          else
            ...soapEntries.map((entry) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatIsoDate(entry.createdAtIso),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(entry.content),
                    ],
                  ),
                ),
              );
            }),
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

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  String _speechStatus = 'Not tested';
  String _textAnalyticsStatus = 'Not tested';
  String _openAIStatus = 'Not tested';
  bool _testingSpeech = false;
  bool _testingTextAnalytics = false;
  bool _testingOpenAI = false;

  Future<void> _runServiceTest({
    required Future<ConnectionTestResult> Function() test,
    required void Function(String status) updateStatus,
    required void Function(bool loading) updateLoading,
  }) async {
    updateLoading(true);
    try {
      final result = await test();
      updateStatus(result.message);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    } finally {
      updateLoading(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final notifier = ref.read(appStateProvider.notifier);
    final azure = ref.read(azureServicesProvider);
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
            subtitle: const Text('Clear local patient profiles, logs, and SOAP entries.'),
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
              azure.isCloudConfigured
                  ? 'Configured and active.'
                  : 'Not fully configured. Local fallback generation will be used.',
            ),
          ),
          _ConnectionTestTile(
            title: 'Speech Service',
            status: _speechStatus,
            loading: _testingSpeech,
            onTest: () => _runServiceTest(
              test: azure.testSpeechConnection,
              updateStatus: (value) => setState(() => _speechStatus = value),
              updateLoading: (value) => setState(() => _testingSpeech = value),
            ),
          ),
          _ConnectionTestTile(
            title: 'Text Analytics Service',
            status: _textAnalyticsStatus,
            loading: _testingTextAnalytics,
            onTest: () => _runServiceTest(
              test: azure.testTextAnalyticsConnection,
              updateStatus: (value) => setState(() => _textAnalyticsStatus = value),
              updateLoading: (value) => setState(() => _testingTextAnalytics = value),
            ),
          ),
          _ConnectionTestTile(
            title: 'OpenAI Service',
            status: _openAIStatus,
            loading: _testingOpenAI,
            onTest: () => _runServiceTest(
              test: azure.testOpenAIConnection,
              updateStatus: (value) => setState(() => _openAIStatus = value),
              updateLoading: (value) => setState(() => _testingOpenAI = value),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionTestTile extends StatelessWidget {
  const _ConnectionTestTile({
    required this.title,
    required this.status,
    required this.loading,
    required this.onTest,
  });

  final String title;
  final String status;
  final bool loading;
  final Future<void> Function() onTest;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(status),
      trailing: SizedBox(
        width: 88,
        child: OutlinedButton(
          onPressed: loading ? null : onTest,
          child: loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Test'),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (label) {
      case 'failed':
        color = Colors.red.shade100;
        break;
      case 'processing':
      case 'recording':
        color = Colors.orange.shade100;
        break;
      default:
        color = Colors.green.shade100;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

String _formatIsoDate(String iso) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '${dt.year}-$month-$day $hour:$minute';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Allow startup in environments where .env is unavailable (for example tests).
  }
  runApp(const ProviderScope(child: HealthcareApp()));
}
