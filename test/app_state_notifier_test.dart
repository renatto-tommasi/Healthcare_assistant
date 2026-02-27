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

  test('start/stop log creates processing entry and clears recording session', () async {
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
    expect(entries.map((e) => e.content).toSet(), <String>{'Entry one', 'Entry two'});
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
}
