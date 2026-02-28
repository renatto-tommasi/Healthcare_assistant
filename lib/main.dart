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

final appStateProvider =
    StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier(ref.read(appStateRepositoryProvider));
});

const _brandInk = Color(0xFF102336);
const _brandBlue = Color(0xFF1F6FEB);
const _brandMint = Color(0xFF2FBF9B);
const _brandWarm = Color(0xFFF4A259);
const _paper = Color(0xFFF4F8FF);

ThemeData _buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: _brandBlue,
    brightness: Brightness.light,
    primary: _brandBlue,
    secondary: _brandMint,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: 'Montserrat',
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: _brandInk,
      ),
      titleLarge: TextStyle(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: _brandInk,
      ),
      titleMedium: TextStyle(
        fontWeight: FontWeight.w700,
        color: _brandInk,
      ),
      bodyLarge: TextStyle(
        height: 1.35,
        color: Color(0xFF213549),
      ),
      bodyMedium: TextStyle(
        height: 1.35,
        color: Color(0xFF334E68),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white.withOpacity(0.82),
      foregroundColor: _brandInk,
      elevation: 0,
      centerTitle: false,
      scrolledUnderElevation: 0,
      titleTextStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: _brandInk,
      ),
      shape: const Border(
        bottom: BorderSide(color: Color(0x223B5B75), width: 1),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white.withOpacity(0.92),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0x223B5B75), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _brandBlue,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _brandInk,
        side: const BorderSide(color: Color(0x55446A8B)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _brandMint,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF7FAFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0x33446A8B)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0x33446A8B)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _brandBlue, width: 1.2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: _brandInk,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      behavior: SnackBarBehavior.floating,
    ),
    dividerColor: const Color(0x223B5B75),
  );
}

class HealthcareApp extends ConsumerWidget {
  const HealthcareApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Healthcare Continuum',
      theme: _buildAppTheme(),
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
    this.showMainPageButton = false,
  });

  final String title;
  final Widget body;
  final Widget? fab;
  final bool showMainPageButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (showMainPageButton)
            IconButton(
              onPressed: () => Navigator.pushNamedAndRemoveUntil(
                context,
                '/login',
                (route) => false,
              ),
              icon: const Icon(Icons.home_outlined),
              tooltip: 'Main page',
            ),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Stack(
        children: [
          const _AmbientBackdrop(),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: body,
          ),
        ],
      ),
      floatingActionButton: fab,
    );
  }
}

class _HealthSignalDraft {
  const _HealthSignalDraft({
    required this.systolicBp,
    required this.diastolicBp,
    required this.heartRateBpm,
    required this.note,
  });

  final int systolicBp;
  final int diastolicBp;
  final int heartRateBpm;
  final String note;
}

class _MedicationPlanDraft {
  const _MedicationPlanDraft({
    required this.name,
    required this.dosage,
    required this.instructions,
    required this.dailyTimes,
    required this.startDate,
    required this.endDate,
    required this.isPrn,
  });

  final String name;
  final String dosage;
  final String instructions;
  final List<String> dailyTimes;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isPrn;
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xFF1F6FEB),
                    Color(0xFF2FBF9B),
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x331F6FEB),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Healthcare Continuum',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Privacy-first tracking for patients and clinicians.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xE6FFFFFF),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  notifier.setRole(UserRole.patient);
                  Navigator.pushReplacementNamed(context, '/patient_dashboard');
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person, size: 20),
                    SizedBox(width: 10),
                    Text('I am a Patient'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  notifier.setRole(UserRole.clinician);
                  Navigator.pushReplacementNamed(
                      context, '/clinician_patients');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandWarm,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.health_and_safety, size: 20),
                    SizedBox(width: 10),
                    Text('I am a Clinician'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            _paper,
            Color(0xFFEFF4FB),
            Color(0xFFEAF8F4),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -70,
            child: _glowBlob(
              size: 220,
              color: const Color(0x331F6FEB),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -90,
            child: _glowBlob(
              size: 260,
              color: const Color(0x332FBF9B),
            ),
          ),
          Positioned(
            top: 220,
            left: -40,
            child: _glowBlob(
              size: 130,
              color: const Color(0x22F4A259),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glowBlob({required double size, required Color color}) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              color,
              color.withOpacity(0),
            ],
          ),
        ),
      ),
    );
  }
}

class PatientDashboardView extends ConsumerWidget {
  const PatientDashboardView({super.key});

  Future<void> _showAddHealthSignalDialog(
      BuildContext context, WidgetRef ref, String patientId) async {
    final systolicController = TextEditingController();
    final diastolicController = TextEditingController();
    final heartRateController = TextEditingController();
    final noteController = TextEditingController();
    var validationError = '';

    final draft = await showDialog<_HealthSignalDraft>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Add Health Signal'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: systolicController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Systolic BP (mmHg)',
                      ),
                    ),
                    TextField(
                      controller: diastolicController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Diastolic BP (mmHg)',
                      ),
                    ),
                    TextField(
                      controller: heartRateController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Heart Rate (bpm)',
                      ),
                    ),
                    TextField(
                      controller: noteController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Optional note',
                      ),
                    ),
                    if (validationError.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        validationError,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final systolic = int.tryParse(systolicController.text.trim());
                    final diastolic =
                        int.tryParse(diastolicController.text.trim());
                    final heartRate =
                        int.tryParse(heartRateController.text.trim());
                    if (systolic == null ||
                        diastolic == null ||
                        heartRate == null) {
                      setDialogState(() {
                        validationError =
                            'Enter numeric values for blood pressure and heart rate.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _HealthSignalDraft(
                        systolicBp: systolic,
                        diastolicBp: diastolic,
                        heartRateBpm: heartRate,
                        note: noteController.text,
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (draft == null) return;
    try {
      ref.read(appStateProvider.notifier).addHealthSignal(
            patientId: patientId,
            systolicBp: draft.systolicBp,
            diastolicBp: draft.diastolicBp,
            heartRateBpm: draft.heartRateBpm,
            note: draft.note,
          );
    } catch (e) {
      ref.read(appStateProvider.notifier).setError('$e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final patientId = state.activePatientId ??
        (state.patients.isNotEmpty ? state.patients.first.id : 'self');
    final patient = state.patients.where((p) => p.id == patientId).toList();
    final patientName =
        patient.isEmpty ? 'Current Patient' : patient.first.displayName;
    final notifier = ref.read(appStateProvider.notifier);
    final logs = notifier.logsForPatient(patientId);
    final medsToday = notifier.todayMedicationSchedule(patientId);
    final signals = notifier.healthSignalsForPatient(patientId);

    return AppScaffold(
      title: 'Patient Dashboard',
      showMainPageButton: true,
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
                    const Text(
                        'No logs yet. Start your first log from the microphone button.')
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
                          snippet.length > 90
                              ? '${snippet.substring(0, 90)}...'
                              : snippet,
                        ),
                        trailing: Text(status),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Health Signals',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _showAddHealthSignalDialog(context, ref, patientId),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Reading'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (signals.isEmpty)
                    const Text('No blood pressure or heart rate readings yet.')
                  else
                    ...signals.take(5).map((signal) {
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${signal.systolicBp}/${signal.diastolicBp} mmHg · ${signal.heartRateBpm} bpm',
                        ),
                        subtitle: Text(
                          '${_formatIsoDate(signal.recordedAtIso)}${signal.note?.trim().isNotEmpty == true ? '\n${signal.note}' : ''}',
                        ),
                      );
                    }),
                ],
              ),
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
                    'Today\'s Medications',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (medsToday.isEmpty)
                    const Text('No medications scheduled for today.')
                  else
                    ...medsToday.map((dose) {
                      final isTaken =
                          dose.status == MedicationDoseStatus.onTime ||
                              dose.status == MedicationDoseStatus.late ||
                              dose.status == MedicationDoseStatus.taken;
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${dose.medicationName}${dose.dosage.trim().isEmpty ? '' : ' (${dose.dosage})'}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  _MedicationStatusBadge(status: dose.status),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                dose.isPrn
                                    ? 'PRN intake'
                                    : 'Scheduled: ${_formatLocalTime(dose.scheduledAt)}',
                              ),
                              if (dose.instructions.trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('Instructions: ${dose.instructions}'),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  OutlinedButton(
                                    onPressed: isTaken
                                        ? null
                                        : () async {
                                            try {
                                              notifier.recordMedicationIntake(
                                                patientId: patientId,
                                                planId: dose.medicationPlanId,
                                                takenAt: DateTime.now(),
                                                scheduledAt: dose.isPrn
                                                    ? null
                                                    : dose.scheduledAt,
                                              );
                                            } catch (e) {
                                              notifier.setError('$e');
                                            }
                                          },
                                    child: const Text('Take now'),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: isTaken
                                        ? null
                                        : () async {
                                            final picked = await showTimePicker(
                                              context: context,
                                              initialTime:
                                                  TimeOfDay.fromDateTime(
                                                dose.scheduledAt,
                                              ),
                                            );
                                            if (picked == null) return;
                                            final now = DateTime.now();
                                            final chosen = DateTime(
                                              now.year,
                                              now.month,
                                              now.day,
                                              picked.hour,
                                              picked.minute,
                                            );
                                            if (chosen.isAfter(now)) {
                                              notifier.setError(
                                                'Selected time cannot be in the future.',
                                              );
                                              return;
                                            }
                                            try {
                                              notifier.recordMedicationIntake(
                                                patientId: patientId,
                                                planId: dose.medicationPlanId,
                                                takenAt: chosen,
                                                scheduledAt: dose.isPrn
                                                    ? null
                                                    : dose.scheduledAt,
                                              );
                                            } catch (e) {
                                              notifier.setError('$e');
                                            }
                                          },
                                    child: const Text('Log earlier'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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
      notifier.setError(
          'Edge tracking unavailable. Camera permission may be denied.');
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
    final patientId = ref.read(appStateProvider).activePatientId ??
        notifier.ensureDefaultPatient();
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
      final stoppedPath = await _audioRecorder.stop() ??
          currentState.recordingSession.tempAudioPath;
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
      final processing =
          await ref.read(azureServicesProvider).transcribeAndExtract(
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
    final patientId = state.activePatientId ??
        (state.patients.isNotEmpty ? state.patients.first.id : 'self');
    final logs = notifier.logsForPatient(patientId);
    final tracker =
        state.edgeTrackingEnabled ? ref.watch(edgeTrackerProvider) : null;
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
          const Text('Log History',
              style: TextStyle(fontWeight: FontWeight.w700)),
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
                ref
                    .read(appStateProvider.notifier)
                    .createPatientProfile(controller.text);
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
      showMainPageButton: true,
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
                final scoreText = score == null
                    ? '--'
                    : score.clamp(0, 100).toStringAsFixed(0);
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

class _ClinicianPatientDetailViewState
    extends ConsumerState<ClinicianPatientDetailView> {
  final _audioRecorder = AudioRecorder();
  bool _isBusy = false;
  bool _isDictationRecording = false;
  String? _dictationPath;
  Duration _dictationElapsed = Duration.zero;
  Timer? _dictationTimer;

  Future<String> _buildDictationPath() async {
    final tempDir = await getTemporaryDirectory();
    return '${tempDir.path}${Platform.pathSeparator}'
        'dictation_${DateTime.now().millisecondsSinceEpoch}.wav';
  }

  void _startDictationClock() {
    _dictationTimer?.cancel();
    _dictationElapsed = Duration.zero;
    _dictationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _dictationElapsed += const Duration(seconds: 1));
    });
  }

  void _stopDictationClock() {
    _dictationTimer?.cancel();
    _dictationTimer = null;
  }

  Future<void> _startSoapDictation() async {
    if (_isBusy || _isDictationRecording) return;
    final notifier = ref.read(appStateProvider.notifier);
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      notifier.setError('Microphone permission denied.');
      return;
    }
    final filePath = await _buildDictationPath();
    try {
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: filePath,
      );
      notifier.clearError();
      if (mounted) {
        setState(() {
          _isDictationRecording = true;
          _dictationPath = filePath;
          _dictationElapsed = Duration.zero;
        });
      }
      _startDictationClock();
    } catch (e) {
      notifier.setError('Failed to start dictation: $e');
    }
  }

  Future<void> _stopSoapDictationAndGenerate(String patientId) async {
    if (_isBusy || !_isDictationRecording) return;
    final notifier = ref.read(appStateProvider.notifier);
    setState(() => _isBusy = true);
    String? audioPath;
    try {
      audioPath = await _audioRecorder.stop() ?? _dictationPath;
    } catch (e) {
      notifier.setError('Failed to stop dictation: $e');
      if (mounted) {
        setState(() => _isBusy = false);
      }
      return;
    } finally {
      _stopDictationClock();
      if (mounted) {
        setState(() {
          _isDictationRecording = false;
          _dictationPath = null;
          _dictationElapsed = Duration.zero;
        });
      }
    }
    if (audioPath == null || audioPath.isEmpty) {
      notifier.setError('Dictation audio path unavailable.');
      if (mounted) {
        setState(() => _isBusy = false);
      }
      return;
    }
    await _generateSoapFromAudio(patientId, audioPath);
    if (mounted) {
      setState(() => _isBusy = false);
    }
  }

  Future<void> _generateSoapFromAudio(
      String patientId, String audioPath) async {
    final notifier = ref.read(appStateProvider.notifier);
    final azure = ref.read(azureServicesProvider);
    try {
      final logs = notifier
          .logsForPatient(patientId)
          .where(
              (e) => e.processingStatus == PatientLogProcessingStatus.complete)
          .toList();
      final sourceLog = logs.isEmpty ? null : logs.first;
      final metrics =
          sourceLog?.metricsSnapshot.toJson() ?? EdgeMetrics.empty.toJson();
      final soapContext = notifier.soapContextForPatient(patientId);
      final transcript = await azure.transcribeAudio(audioPath);
      String soap;
      String? cloudSoapError;
      try {
        soap = await azure.generateSOAPNote(
          transcript,
          metrics,
          context: soapContext,
        );
      } catch (e) {
        cloudSoapError = '$e';
        soap = azure.localSoapFallback(
          metrics,
          context: soapContext,
        );
      }
      notifier.addClinicianSoapEntry(
        patientId: patientId,
        content: soap,
        sourceLogId: sourceLog?.id,
      );
      if (cloudSoapError == null) {
        notifier.clearError();
      } else {
        notifier.setError(
          'Cloud SOAP generation failed; saved local template instead. $cloudSoapError',
        );
      }
    } catch (e) {
      notifier.setError('SOAP generation failed: $e');
    }
  }

  String _dictationElapsedLabel() {
    final minutes = _dictationElapsed.inMinutes.toString().padLeft(2, '0');
    final seconds =
        (_dictationElapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _showMedicationPlanDialog(String patientId) async {
    final nameController = TextEditingController();
    final dosageController = TextEditingController();
    final instructionsController = TextEditingController();
    final selectedTimes = <String>[];
    var isPrn = false;
    DateTime startDate = DateTime.now();
    DateTime? endDate;

    final draft = await showDialog<_MedicationPlanDraft>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Add Medication Plan'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration:
                          const InputDecoration(labelText: 'Medication name'),
                    ),
                    TextField(
                      controller: dosageController,
                      decoration: const InputDecoration(labelText: 'Dosage'),
                    ),
                    TextField(
                      controller: instructionsController,
                      decoration:
                          const InputDecoration(labelText: 'Instructions'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      value: isPrn,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('PRN (as needed)'),
                      onChanged: (value) => setDialogState(() => isPrn = value),
                    ),
                    if (!isPrn) ...[
                      const Text(
                        'Daily times',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: selectedTimes
                            .map(
                              (time) => Chip(
                                label: Text(time),
                                onDeleted: () {
                                  setDialogState(
                                      () => selectedTimes.remove(time));
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: dialogContext,
                            initialTime: TimeOfDay.now(),
                          );
                          if (picked == null) return;
                          final value =
                              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                          if (!selectedTimes.contains(value)) {
                            setDialogState(() {
                              selectedTimes.add(value);
                              selectedTimes.sort();
                            });
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add time'),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              'Start: ${_formatIsoDate(startDate.toIso8601String())}'),
                        ),
                        TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate: startDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setDialogState(() => startDate = picked);
                            }
                          },
                          child: const Text('Change'),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            endDate == null
                                ? 'End: none'
                                : 'End: ${_formatIsoDate(endDate!.toIso8601String())}',
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate: endDate ?? startDate,
                              firstDate: startDate,
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setDialogState(() => endDate = picked);
                            }
                          },
                          child: const Text('Set'),
                        ),
                        if (endDate != null)
                          TextButton(
                            onPressed: () =>
                                setDialogState(() => endDate = null),
                            child: const Text('Clear'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(
                      _MedicationPlanDraft(
                        name: nameController.text,
                        dosage: dosageController.text,
                        instructions: instructionsController.text,
                        dailyTimes: List<String>.from(selectedTimes),
                        startDate: startDate,
                        endDate: endDate,
                        isPrn: isPrn,
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (draft == null) return;
    try {
      ref.read(appStateProvider.notifier).createMedicationPlan(
            patientId: patientId,
            name: draft.name,
            dosage: draft.dosage,
            instructions: draft.instructions,
            dailyTimes: draft.dailyTimes,
            startDate: draft.startDate,
            endDate: draft.endDate,
            isPrn: draft.isPrn,
          );
    } catch (e) {
      ref.read(appStateProvider.notifier).setError('$e');
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
              _metricRow('Blink rate',
                  '${metrics.blinksPerMinute.toStringAsFixed(1)} BPM'),
              _metricRow(
                  'Fatigue score', metrics.fatigueScore.toStringAsFixed(2)),
              _metricRow(
                  'Anxiety score', metrics.anxietyScore.toStringAsFixed(2)),
              _metricRow(
                'Tracking uptime',
                '${metrics.trackingUptimePercent.toStringAsFixed(1)}%',
              ),
              _metricRow('Sample rate',
                  '${metrics.sampleRateHz.toStringAsFixed(1)} Hz'),
              _metricRow(
                'Eye closure rate',
                '${metrics.eyeClosureRatePercent.toStringAsFixed(1)}%',
              ),
              _metricRow('Gaze drift',
                  '${metrics.gazeDriftDegrees.toStringAsFixed(1)} deg'),
              _metricRow(
                'Fixation instability',
                '${metrics.fixationInstabilityDegrees.toStringAsFixed(1)} deg',
              ),
              _metricRow('Tracking quality',
                  metrics.trackingQualityScore.toStringAsFixed(2)),
              _metricRow(
                  'Baseline score', metrics.baselineScore.toStringAsFixed(0)),
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
    _stopDictationClock();
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
    final medicationPlans = notifier.activeMedicationPlansForPatient(patientId);
    final adherence = notifier.todayAdherenceSummary(patientId);

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
                        for (var i = 0; i < trend.length; i++)
                          FlSpot(i.toDouble(), trend[i]),
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
          const Text('Log Timeline',
              style: TextStyle(fontWeight: FontWeight.w700)),
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
                          Expanded(
                              child: Text(_formatIsoDate(log.startedAtIso))),
                          _StatusPill(label: log.processingStatus.name),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Score: ${log.baselineScore.toStringAsFixed(0)}'),
                      if (log.processingStatus ==
                          PatientLogProcessingStatus.complete)
                        Text(
                          'Depression marker: ${log.depressionMarker.name} '
                          '(${(log.depressionScore * 100).toStringAsFixed(0)}%)',
                        ),
                      if (log.errorMessage != null &&
                          log.errorMessage!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(log.errorMessage!,
                            style: const TextStyle(color: Colors.red)),
                      ],
                      const SizedBox(height: 8),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Transcript'),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                log.transcript.trim().isEmpty
                                    ? 'Transcript pending...'
                                    : log.transcript,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () =>
                            _showFeatureBreakdown(context, log.metricsSnapshot),
                        child: const Text('View Feature Breakdown'),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 14),
          const Text('Medication Adherence',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Today: ${adherence.onTime} on-time, ${adherence.late} late, '
                '${adherence.overdue} overdue out of ${adherence.totalDue} due doses.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text('Medication Plans',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              OutlinedButton.icon(
                onPressed: () => _showMedicationPlanDialog(patientId),
                icon: const Icon(Icons.add),
                label: const Text('Add Plan'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (medicationPlans.isEmpty)
            const Text('No active medication plans.')
          else
            ...medicationPlans.map((plan) {
              return Card(
                child: ListTile(
                  title: Text(
                    '${plan.name}${plan.dosage.trim().isEmpty ? '' : ' (${plan.dosage})'}',
                  ),
                  subtitle: Text(
                    plan.isPrn
                        ? 'PRN${plan.instructions.trim().isEmpty ? '' : ' - ${plan.instructions}'}'
                        : '${plan.dailyTimes.join(', ')}${plan.instructions.trim().isEmpty ? '' : ' - ${plan.instructions}'}',
                  ),
                  trailing: TextButton(
                    onPressed: () =>
                        notifier.archiveMedicationPlan(patientId, plan.id),
                    child: const Text('Archive'),
                  ),
                ),
              );
            }),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  _isDictationRecording
                      ? 'SOAP Dictation (${_dictationElapsedLabel()})'
                      : 'SOAP Dictation',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              OutlinedButton.icon(
                onPressed: (_isBusy || _isDictationRecording)
                    ? null
                    : _startSoapDictation,
                icon: const Icon(Icons.mic, size: 16),
                label: const Text('Start'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: (_isBusy || !_isDictationRecording)
                    ? null
                    : () => _stopSoapDictationAndGenerate(patientId),
                icon: const Icon(Icons.stop, size: 16),
                label: const Text('Stop'),
              ),
            ],
          ),
          if (_isBusy) ...[
            const SizedBox(height: 8),
            const Text('Processing dictation and generating SOAP...'),
          ],
          const SizedBox(height: 12),
          const Text('SOAP Entries',
              style: TextStyle(fontWeight: FontWeight.w700)),
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
            subtitle:
                const Text('Run gaze/blink analytics only on this device.'),
            value: state.edgeTrackingEnabled,
            onChanged: notifier.toggleEdgeTracking,
          ),
          SwitchListTile(
            title: const Text('Data Purge'),
            subtitle: const Text(
                'Clear local patient profiles, logs, and SOAP entries.'),
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
              updateStatus: (value) =>
                  setState(() => _textAnalyticsStatus = value),
              updateLoading: (value) =>
                  setState(() => _testingTextAnalytics = value),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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

class _MedicationStatusBadge extends StatelessWidget {
  const _MedicationStatusBadge({required this.status});

  final MedicationDoseStatus status;

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color color;
    late final Color border;
    switch (status) {
      case MedicationDoseStatus.onTime:
        label = 'on-time';
        color = const Color(0xFFD9F7EA);
        border = const Color(0xFF50B38C);
        break;
      case MedicationDoseStatus.late:
        label = 'late';
        color = const Color(0xFFFFE7CB);
        border = const Color(0xFFE69A3B);
        break;
      case MedicationDoseStatus.overdue:
        label = 'overdue';
        color = const Color(0xFFFFDDE0);
        border = const Color(0xFFD16A75);
        break;
      case MedicationDoseStatus.taken:
        label = 'taken';
        color = const Color(0xFFDDEBFF);
        border = const Color(0xFF4D7CC9);
        break;
      case MedicationDoseStatus.due:
        label = 'due';
        color = const Color(0xFFE6ECF4);
        border = const Color(0xFF7E93A8);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: border.withOpacity(0.6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
    Color border;
    Color text;
    switch (label) {
      case 'failed':
        color = const Color(0xFFFFDDE0);
        border = const Color(0xFFD16A75);
        text = const Color(0xFF8A2C35);
        break;
      case 'processing':
      case 'recording':
        color = const Color(0xFFFFE7CB);
        border = const Color(0xFFE69A3B);
        text = const Color(0xFF7E4A0C);
        break;
      default:
        color = const Color(0xFFD9F7EA);
        border = const Color(0xFF50B38C);
        text = const Color(0xFF1E6248);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: border.withOpacity(0.6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
    );
  }
}

String _formatLocalTime(DateTime dt) {
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
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
