import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_continuum_app/models/app_models.dart';
import 'package:healthcare_continuum_app/state/app_state_notifier.dart';

import 'test_support/in_memory_repository.dart';

void main() {
  const lowRiskMetrics = EdgeMetrics(
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

  test('start/stop log creates processing entry and clears recording session',
      () async {
    final repo = InMemoryLocalAppStateRepository();
    final notifier = AppStateNotifier(repo);
    await notifier.loadFromDisk();

    final patientId = notifier.createPatientProfile('Alex');
    notifier.startPatientLog(
      patientId: patientId,
      optionalNote: 'note',
      tempAudioPath: '/tmp/a.wav',
    );
    expect(notifier.state.recordingSession.isRecording, true);

    final entryId = notifier.stopPatientLog(
      patientId: patientId,
      audioPath: '/tmp/a.wav',
      metrics: lowRiskMetrics,
    );
    final created = notifier.logById(entryId);

    expect(created, isNotNull);
    expect(created!.processingStatus, PatientLogProcessingStatus.processing);
    expect(created.patientNote, 'note');
    expect(notifier.state.recordingSession.isRecording, false);
  });

  test('failed STT keeps log persisted with failed status', () async {
    final repo = InMemoryLocalAppStateRepository();
    final notifier = AppStateNotifier(repo);
    await notifier.loadFromDisk();

    final patientId = notifier.createPatientProfile('Alex');
    notifier.startPatientLog(patientId: patientId, tempAudioPath: '/tmp/a.wav');
    final entryId = notifier.stopPatientLog(
      patientId: patientId,
      audioPath: '/tmp/a.wav',
      metrics: lowRiskMetrics,
    );
    notifier.finalizePatientLog(
      entryId: entryId,
      transcript: '',
      entities: const <String, dynamic>{},
      error: 'Speech service unavailable',
    );

    final failed = notifier.logById(entryId);
    expect(failed, isNotNull);
    expect(failed!.processingStatus, PatientLogProcessingStatus.failed);
    expect(failed.errorMessage, contains('Speech service unavailable'));
  });

  test('multiple SOAP entries append in patient timeline', () async {
    final repo = InMemoryLocalAppStateRepository();
    final notifier = AppStateNotifier(repo);
    await notifier.loadFromDisk();

    final patientId = notifier.createPatientProfile('Alex');
    notifier.addClinicianSoapEntry(patientId: patientId, content: 'Entry one');
    notifier.addClinicianSoapEntry(patientId: patientId, content: 'Entry two');

    final entries = notifier.clinicianEntriesForPatient(patientId);
    expect(entries.length, 2);
    expect(entries.map((e) => e.content).toSet(),
        <String>{'Entry one', 'Entry two'});
  });

  test('latest score uses latest completed log baseline', () async {
    final repo = InMemoryLocalAppStateRepository();
    final notifier = AppStateNotifier(repo);
    await notifier.loadFromDisk();

    final patientId = notifier.createPatientProfile('Alex');
    notifier.startPatientLog(patientId: patientId, tempAudioPath: '/tmp/1.wav');
    final completeLog = notifier.stopPatientLog(
      patientId: patientId,
      audioPath: '/tmp/1.wav',
      metrics: lowRiskMetrics,
    );
    notifier.finalizePatientLog(
      entryId: completeLog,
      transcript: 'done',
      entities: const <String, dynamic>{},
    );

    notifier.startPatientLog(patientId: patientId, tempAudioPath: '/tmp/2.wav');
    final failedLog = notifier.stopPatientLog(
      patientId: patientId,
      audioPath: '/tmp/2.wav',
      metrics: highRiskMetrics,
    );
    notifier.finalizePatientLog(
      entryId: failedLog,
      transcript: '',
      entities: const <String, dynamic>{},
      error: 'processing failed',
    );

    final latestScore = notifier.latestPatientScore(patientId);
    expect(latestScore, lowRiskMetrics.baselineScore);
  });

  test('depression marker thresholds map to low/watch/high', () async {
    final repo = InMemoryLocalAppStateRepository();
    final notifier = AppStateNotifier(repo);
    await notifier.loadFromDisk();

    expect(notifier.depressionMarkerFromScore(0.10), DepressionMarker.low);
    expect(notifier.depressionMarkerFromScore(0.45), DepressionMarker.watch);
    expect(notifier.depressionMarkerFromScore(0.85), DepressionMarker.high);
  });

  test('finalize log computes depression fields', () async {
    final repo = InMemoryLocalAppStateRepository();
    final notifier = AppStateNotifier(repo);
    await notifier.loadFromDisk();

    final patientId = notifier.createPatientProfile('Alex');
    notifier.startPatientLog(patientId: patientId, tempAudioPath: '/tmp/a.wav');
    final entryId = notifier.stopPatientLog(
      patientId: patientId,
      audioPath: '/tmp/a.wav',
      metrics: highRiskMetrics,
    );
    notifier.finalizePatientLog(
      entryId: entryId,
      transcript: 'I feel hopeless and depressed and have no motivation',
      entities: const <String, dynamic>{},
    );

    final log = notifier.logById(entryId);
    expect(log, isNotNull);
    expect(log!.depressionScore, greaterThan(0));
    expect(log.depressionMarker, isNot(DepressionMarker.low));
  });

  test('finalize log applies transcript sentiment to fatigue and anxiety',
      () async {
    final repo = InMemoryLocalAppStateRepository();
    final notifier = AppStateNotifier(repo);
    await notifier.loadFromDisk();

    final patientId = notifier.createPatientProfile('Alex');
    notifier.startPatientLog(patientId: patientId, tempAudioPath: '/tmp/a.wav');
    final entryId = notifier.stopPatientLog(
      patientId: patientId,
      audioPath: '/tmp/a.wav',
      metrics: lowRiskMetrics,
    );
    notifier.finalizePatientLog(
      entryId: entryId,
      transcript:
          'I feel hopeless, anxious, exhausted, and have no motivation.',
      entities: const <String, dynamic>{},
    );

    final log = notifier.logById(entryId);
    expect(log, isNotNull);
    expect(log!.metricsSnapshot.fatigueScore,
        greaterThan(lowRiskMetrics.fatigueScore));
    expect(log.metricsSnapshot.anxietyScore,
        greaterThan(lowRiskMetrics.anxietyScore));
    expect(log.baselineScore, lessThan(lowRiskMetrics.baselineScore));
    expect(
      (log.entitiesJson['sentiment_risk_score'] as num?)?.toDouble() ?? 0,
      greaterThan(0),
    );
    expect(log.entitiesJson['sentiment_label'], isNotNull);
  });

  test('medication intake classifies on-time late and overdue', () async {
    final repo = InMemoryLocalAppStateRepository();
    final notifier = AppStateNotifier(repo);
    await notifier.loadFromDisk();
    final patientId = notifier.createPatientProfile('Alex');

    final onTimePlanId = notifier.createMedicationPlan(
      patientId: patientId,
      name: 'Med A',
      dosage: '10mg',
      instructions: '',
      dailyTimes: const <String>['08:00'],
      startDate: DateTime.now(),
    );
    final now = DateTime.now();
    final onTimeTaken = DateTime(now.year, now.month, now.day, 8, 30);
    notifier.recordMedicationIntake(
      patientId: patientId,
      planId: onTimePlanId,
      takenAt: onTimeTaken,
      scheduledAt: DateTime(now.year, now.month, now.day, 8, 0),
    );
    var schedule = notifier.todayMedicationSchedule(patientId, now: now);
    final onTimeDose =
        schedule.firstWhere((d) => d.medicationPlanId == onTimePlanId);
    expect(onTimeDose.status, MedicationDoseStatus.onTime);

    final latePlanId = notifier.createMedicationPlan(
      patientId: patientId,
      name: 'Med B',
      dosage: '10mg',
      instructions: '',
      dailyTimes: const <String>['06:00'],
      startDate: DateTime.now(),
    );
    final lateTaken = DateTime(now.year, now.month, now.day, 11, 30);
    notifier.recordMedicationIntake(
      patientId: patientId,
      planId: latePlanId,
      takenAt: lateTaken,
      scheduledAt: DateTime(now.year, now.month, now.day, 6, 0),
    );
    schedule = notifier.todayMedicationSchedule(patientId, now: now);
    final lateDose =
        schedule.firstWhere((d) => d.medicationPlanId == latePlanId);
    expect(lateDose.status, MedicationDoseStatus.late);

    final overduePlanId = notifier.createMedicationPlan(
      patientId: patientId,
      name: 'Med C',
      dosage: '10mg',
      instructions: '',
      dailyTimes: const <String>['00:01'],
      startDate: DateTime.now(),
    );
    schedule = notifier.todayMedicationSchedule(
      patientId,
      now: DateTime(now.year, now.month, now.day, 23, 0),
    );
    final overdueDose =
        schedule.firstWhere((d) => d.medicationPlanId == overduePlanId);
    expect(overdueDose.status, MedicationDoseStatus.overdue);
  });

  test('same-day backfill allowed and previous-day rejected', () async {
    final repo = InMemoryLocalAppStateRepository();
    final notifier = AppStateNotifier(repo);
    await notifier.loadFromDisk();
    final patientId = notifier.createPatientProfile('Alex');
    final planId = notifier.createMedicationPlan(
      patientId: patientId,
      name: 'Med A',
      dosage: '10mg',
      instructions: '',
      dailyTimes: const <String>['08:00'],
      startDate: DateTime.now(),
    );
    final now = DateTime.now();

    expect(
      () => notifier.recordMedicationIntake(
        patientId: patientId,
        planId: planId,
        takenAt: DateTime(now.year, now.month, now.day, 7, 0),
        scheduledAt: DateTime(now.year, now.month, now.day, 8, 0),
      ),
      returnsNormally,
    );

    expect(
      () => notifier.recordMedicationIntake(
        patientId: patientId,
        planId: planId,
        takenAt: now.subtract(const Duration(days: 1)),
        scheduledAt: now.subtract(const Duration(days: 1)),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('patient can add health signal readings and retrieve latest first',
      () async {
    final repo = InMemoryLocalAppStateRepository();
    final notifier = AppStateNotifier(repo);
    await notifier.loadFromDisk();
    final patientId = notifier.createPatientProfile('Alex');

    notifier.addHealthSignal(
      patientId: patientId,
      systolicBp: 120,
      diastolicBp: 80,
      heartRateBpm: 70,
      recordedAt: DateTime.now().subtract(const Duration(minutes: 10)),
    );
    notifier.addHealthSignal(
      patientId: patientId,
      systolicBp: 128,
      diastolicBp: 84,
      heartRateBpm: 76,
      recordedAt: DateTime.now(),
      note: 'After walking',
    );

    final list = notifier.healthSignalsForPatient(patientId);
    expect(list.length, 2);
    expect(list.first.systolicBp, 128);
    expect(list.first.note, 'After walking');
    expect(notifier.latestHealthSignal(patientId)?.heartRateBpm, 76);
  });

  test('health signal rejects invalid blood pressure combinations', () async {
    final repo = InMemoryLocalAppStateRepository();
    final notifier = AppStateNotifier(repo);
    await notifier.loadFromDisk();
    final patientId = notifier.createPatientProfile('Alex');

    expect(
      () => notifier.addHealthSignal(
        patientId: patientId,
        systolicBp: 70,
        diastolicBp: 90,
        heartRateBpm: 70,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
