import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
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

void main() {
  runApp(const ProviderScope(child: HealthcareApp()));
}
