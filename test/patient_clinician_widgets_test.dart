import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_continuum_app/main.dart';
import 'package:healthcare_continuum_app/models/app_models.dart';
import 'package:healthcare_continuum_app/services/mental_health_edge_tracker.dart';

import 'test_support/in_memory_repository.dart';

void main() {
  const stableMetrics = EdgeMetrics(
    blinksPerMinute: 16,
    fatigueScore: 0.20,
    anxietyScore: 0.20,
    totalBlinks: 10,
    trackingUptimePercent: 95,
    sampleRateHz: 28,
    eyeClosureRatePercent: 3,
    gazeDriftDegrees: 2,
    fixationInstabilityDegrees: 1,
    trackingQualityScore: 0.9,
  );
  const highRiskMetrics = EdgeMetrics(
    blinksPerMinute: 30,
    fatigueScore: 0.70,
    anxietyScore: 0.30,
    totalBlinks: 15,
    trackingUptimePercent: 90,
    sampleRateHz: 26,
    eyeClosureRatePercent: 7,
    gazeDriftDegrees: 6,
    fixationInstabilityDegrees: 4,
    trackingQualityScore: 0.6,
  );

  Future<void> pumpView(
    WidgetTester tester, {
    required InMemoryLocalAppStateRepository repository,
    required Widget child,
  }) async {
    final container = ProviderContainer(
      overrides: <Override>[
        appStateRepositoryProvider.overrideWithValue(repository),
        edgeTrackerProvider.overrideWithValue(_FakeEdgeTracker()),
      ],
    );
    addTearDown(() async {
      // Unmount dependents before disposing the container to avoid
      // `_dependents.isEmpty` assertion failures in test teardown.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: child),
      ),
    );
    await tester.pump();
  }

  Future<void> scrollToStartLog(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Start Log'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
  }

  testWidgets('patient diary hides score and feature labels', (tester) async {
    final repository = InMemoryLocalAppStateRepository(
      initialSnapshot: emptySnapshot(
        edgeTrackingEnabled: false,
        activePatientId: 'p1',
        patients: const <PatientProfile>[
          PatientProfile(
            id: 'p1',
            displayName: 'Patient One',
            createdAtIso: '2026-01-01T00:00:00.000Z',
          ),
        ],
      ),
    );

    await pumpView(
      tester,
      repository: repository,
      child: const PatientDiaryView(),
    );
    await scrollToStartLog(tester);

    expect(find.text('Start Log'), findsOneWidget);
    expect(find.text('Stop Log'), findsOneWidget);
    expect(find.textContaining('Fatigue score'), findsNothing);
    expect(find.textContaining('Anxiety score'), findsNothing);
    expect(find.textContaining('Baseline score'), findsNothing);
  });

  testWidgets('patient has manual start and stop controls', (tester) async {
    final repository = InMemoryLocalAppStateRepository(
      initialSnapshot: emptySnapshot(
        edgeTrackingEnabled: false,
        activePatientId: 'p1',
        patients: const <PatientProfile>[
          PatientProfile(
            id: 'p1',
            displayName: 'Patient One',
            createdAtIso: '2026-01-01T00:00:00.000Z',
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: <Override>[
        appStateRepositoryProvider.overrideWithValue(repository),
        edgeTrackerProvider.overrideWithValue(_FakeEdgeTracker()),
      ],
    );
    addTearDown(() async {
      // Unmount dependents before disposing the container to avoid
      // `_dependents.isEmpty` assertion failures in test teardown.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PatientDiaryView()),
      ),
    );
    await tester.pump();
    await scrollToStartLog(tester);

    final notifier = container.read(appStateProvider.notifier);
    notifier.startPatientLog(
      patientId: 'p1',
      optionalNote: 'note',
      tempAudioPath: '/tmp/a.wav',
    );
    await tester.pump();
    await scrollToStartLog(tester);

    expect(find.textContaining('Recording...'), findsOneWidget);
    final stopRecordingButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Stop Log'));
    expect(stopRecordingButton.onPressed, isNotNull);

    notifier.stopPatientLog(
      patientId: 'p1',
      audioPath: '/tmp/a.wav',
      metrics: stableMetrics,
    );
    await tester.pump();
    await scrollToStartLog(tester);

    expect(find.text('Not recording'), findsOneWidget);
    final startRecordingButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Start Log'));
    expect(startRecordingButton.onPressed, isNotNull);
  });

  testWidgets('clinician patient list shows latest score per patient',
      (tester) async {
    final repository = InMemoryLocalAppStateRepository(
      initialSnapshot: emptySnapshot(
        edgeTrackingEnabled: false,
        patients: const <PatientProfile>[
          PatientProfile(
            id: 'p1',
            displayName: 'Patient One',
            createdAtIso: '2026-01-01T00:00:00.000Z',
          ),
          PatientProfile(
            id: 'p2',
            displayName: 'Patient Two',
            createdAtIso: '2026-01-01T00:00:00.000Z',
          ),
        ],
        patientLogs: const <String, List<PatientLogEntry>>{
          'p1': <PatientLogEntry>[
            PatientLogEntry(
              id: 'l1',
              patientId: 'p1',
              startedAtIso: '2026-01-01T00:00:00.000Z',
              endedAtIso: '2026-01-01T00:01:00.000Z',
              durationSeconds: 60,
              audioPath: '/tmp/1.wav',
              patientNote: null,
              transcript: 'ok',
              entitiesJson: <String, dynamic>{},
              metricsSnapshot: stableMetrics,
              baselineScore: 80,
              processingStatus: PatientLogProcessingStatus.complete,
              errorMessage: null,
            ),
          ],
          'p2': <PatientLogEntry>[
            PatientLogEntry(
              id: 'l2',
              patientId: 'p2',
              startedAtIso: '2026-01-01T00:00:00.000Z',
              endedAtIso: '2026-01-01T00:01:00.000Z',
              durationSeconds: 60,
              audioPath: '/tmp/2.wav',
              patientNote: null,
              transcript: 'alert',
              entitiesJson: <String, dynamic>{},
              metricsSnapshot: highRiskMetrics,
              baselineScore: 50,
              processingStatus: PatientLogProcessingStatus.complete,
              errorMessage: null,
            ),
          ],
        },
      ),
    );

    await pumpView(
      tester,
      repository: repository,
      child: const ClinicianPatientListView(),
    );

    expect(find.textContaining('Score: 80'), findsOneWidget);
    expect(find.textContaining('Risk: stable'), findsOneWidget);
    expect(find.textContaining('Score: 50'), findsOneWidget);
    expect(find.textContaining('Risk: high risk'), findsOneWidget);
  });

  testWidgets('feature breakdown only appears after clinician action',
      (tester) async {
    final repository = InMemoryLocalAppStateRepository(
      initialSnapshot: emptySnapshot(
        edgeTrackingEnabled: false,
        activePatientId: 'p1',
        patients: const <PatientProfile>[
          PatientProfile(
            id: 'p1',
            displayName: 'Patient One',
            createdAtIso: '2026-01-01T00:00:00.000Z',
          ),
        ],
        patientLogs: const <String, List<PatientLogEntry>>{
          'p1': <PatientLogEntry>[
            PatientLogEntry(
              id: 'l1',
              patientId: 'p1',
              startedAtIso: '2026-01-01T00:00:00.000Z',
              endedAtIso: '2026-01-01T00:01:00.000Z',
              durationSeconds: 60,
              audioPath: '/tmp/1.wav',
              patientNote: null,
              transcript: 'ok',
              entitiesJson: <String, dynamic>{},
              metricsSnapshot: stableMetrics,
              baselineScore: 80,
              processingStatus: PatientLogProcessingStatus.complete,
              errorMessage: null,
            ),
          ],
        },
      ),
    );

    await pumpView(
      tester,
      repository: repository,
      child: const ClinicianPatientDetailView(patientId: 'p1'),
    );

    expect(find.text('Feature Breakdown'), findsNothing);
    await tester.scrollUntilVisible(
      find.widgetWithText(OutlinedButton, 'View Feature Breakdown'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester
        .tap(find.widgetWithText(OutlinedButton, 'View Feature Breakdown'));
    await tester.pumpAndSettle();

    expect(find.text('Feature Breakdown'), findsOneWidget);
    expect(find.textContaining('Blink rate'), findsOneWidget);
  });

  testWidgets(
      'clinician can expand and read transcript and see depression marker',
      (tester) async {
    final repository = InMemoryLocalAppStateRepository(
      initialSnapshot: emptySnapshot(
        edgeTrackingEnabled: false,
        activePatientId: 'p1',
        patients: const <PatientProfile>[
          PatientProfile(
            id: 'p1',
            displayName: 'Patient One',
            createdAtIso: '2026-01-01T00:00:00.000Z',
          ),
        ],
        patientLogs: const <String, List<PatientLogEntry>>{
          'p1': <PatientLogEntry>[
            PatientLogEntry(
              id: 'l1',
              patientId: 'p1',
              startedAtIso: '2026-01-01T00:00:00.000Z',
              endedAtIso: '2026-01-01T00:01:00.000Z',
              durationSeconds: 60,
              audioPath: '/tmp/1.wav',
              patientNote: null,
              transcript: 'Patient reports low mood for several days.',
              entitiesJson: <String, dynamic>{},
              metricsSnapshot: stableMetrics,
              baselineScore: 80,
              depressionScore: 0.55,
              depressionMarker: DepressionMarker.watch,
              processingStatus: PatientLogProcessingStatus.complete,
              errorMessage: null,
            ),
          ],
        },
      ),
    );

    await pumpView(
      tester,
      repository: repository,
      child: const ClinicianPatientDetailView(patientId: 'p1'),
    );

    expect(find.textContaining('Depression marker: watch'), findsOneWidget);
    expect(
        find.text('Patient reports low mood for several days.'), findsNothing);
    await tester.tap(find.text('Transcript').first);
    await tester.pumpAndSettle();
    expect(find.text('Patient reports low mood for several days.'),
        findsOneWidget);
  });

  testWidgets('patient dashboard shows medication section', (tester) async {
    final repository = InMemoryLocalAppStateRepository(
      initialSnapshot: emptySnapshot(
        edgeTrackingEnabled: false,
        activePatientId: 'p1',
        patients: const <PatientProfile>[
          PatientProfile(
            id: 'p1',
            displayName: 'Patient One',
            createdAtIso: '2026-01-01T00:00:00.000Z',
          ),
        ],
        medicationPlans: <String, List<MedicationPlan>>{
          'p1': <MedicationPlan>[
            MedicationPlan(
              id: 'm1',
              patientId: 'p1',
              name: 'Sertraline',
              dosage: '50mg',
              instructions: '',
              dailyTimes: <String>[
                '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}'
              ],
              startDateIso: DateTime.now().toIso8601String(),
              endDateIso: null,
              isPrn: false,
              isActive: true,
            ),
          ],
        },
      ),
    );

    await pumpView(
      tester,
      repository: repository,
      child: const PatientDashboardView(),
    );

    expect(find.text('Today\'s Medications'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Take now'), findsWidgets);
    expect(find.textContaining('Depression marker'), findsNothing);
  });

  testWidgets('patient dashboard shows health signal readings', (tester) async {
    final repository = InMemoryLocalAppStateRepository(
      initialSnapshot: emptySnapshot(
        edgeTrackingEnabled: false,
        activePatientId: 'p1',
        patients: const <PatientProfile>[
          PatientProfile(
            id: 'p1',
            displayName: 'Patient One',
            createdAtIso: '2026-01-01T00:00:00.000Z',
          ),
        ],
        healthSignals: const <String, List<HealthSignalEntry>>{
          'p1': <HealthSignalEntry>[
            HealthSignalEntry(
              id: 'hs1',
              patientId: 'p1',
              recordedAtIso: '2026-01-01T08:05:00.000Z',
              systolicBp: 122,
              diastolicBp: 80,
              heartRateBpm: 72,
              note: 'Morning check',
            ),
          ],
        },
      ),
    );

    await pumpView(
      tester,
      repository: repository,
      child: const PatientDashboardView(),
    );

    expect(find.text('Health Signals'), findsOneWidget);
    expect(find.textContaining('122/80 mmHg · 72 bpm'), findsOneWidget);
    expect(find.textContaining('Morning check'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Add Reading'), findsOneWidget);
  });

  testWidgets('clinician can create medication plan', (tester) async {
    final repository = InMemoryLocalAppStateRepository(
      initialSnapshot: emptySnapshot(
        edgeTrackingEnabled: false,
        activePatientId: 'p1',
        patients: const <PatientProfile>[
          PatientProfile(
            id: 'p1',
            displayName: 'Patient One',
            createdAtIso: '2026-01-01T00:00:00.000Z',
          ),
        ],
      ),
    );

    await pumpView(
      tester,
      repository: repository,
      child: const ClinicianPatientDetailView(patientId: 'p1'),
    );

    await tester.scrollUntilVisible(
      find.widgetWithText(OutlinedButton, 'Add Plan'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Add Plan'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Sertraline');
    await tester.enterText(find.byType(TextField).at(1), '50mg');
    await tester.tap(find.text('PRN (as needed)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sertraline'), findsOneWidget);
  });
}

class _FakeEdgeTracker extends MentalHealthEdgeTracker {
  @override
  CameraController? get controller => null;

  @override
  Future<void> initializeFrontCamera() async {}

  @override
  Future<void> startFaceTrackingStream(VoidCallback onMetricsUpdated) async {}

  @override
  void beginLogSession() {}

  @override
  EdgeMetrics endLogSession() => EdgeMetrics.empty;

  @override
  Future<void> dispose() async {}
}
