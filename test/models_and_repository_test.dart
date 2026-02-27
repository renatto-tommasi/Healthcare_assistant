import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_continuum_app/models/app_models.dart';
import 'package:healthcare_continuum_app/repositories/local_app_state_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const metrics = EdgeMetrics(
    blinksPerMinute: 18.5,
    fatigueScore: 0.30,
    anxietyScore: 0.20,
    totalBlinks: 22,
    trackingUptimePercent: 96,
    sampleRateHz: 29.7,
    eyeClosureRatePercent: 4.1,
    gazeDriftDegrees: 3.6,
    fixationInstabilityDegrees: 1.8,
    trackingQualityScore: 0.87,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('model serialization round-trip works for patient/profile/clinician types', () {
    const profile = PatientProfile(
      id: 'p1',
      displayName: 'Alex Doe',
      createdAtIso: '2026-01-01T00:00:00.000Z',
    );
    const log = PatientLogEntry(
      id: 'l1',
      patientId: 'p1',
      startedAtIso: '2026-01-01T00:00:00.000Z',
      endedAtIso: '2026-01-01T00:05:00.000Z',
      durationSeconds: 300,
      audioPath: '/tmp/audio.wav',
      patientNote: 'note',
      transcript: 'transcript',
      entitiesJson: <String, dynamic>{'symptoms': <String>['fatigue']},
      metricsSnapshot: metrics,
      baselineScore: 75,
      processingStatus: PatientLogProcessingStatus.complete,
      errorMessage: null,
    );
    const clinicianEntry = ClinicianEntry(
      id: 'c1',
      patientId: 'p1',
      createdAtIso: '2026-01-01T00:06:00.000Z',
      entryType: 'soap',
      content: 'SOAP content',
      sourceLogId: 'l1',
    );

    final decodedProfile = PatientProfile.fromJson(profile.toJson());
    final decodedLog = PatientLogEntry.fromJson(log.toJson());
    final decodedClinician = ClinicianEntry.fromJson(clinicianEntry.toJson());

    expect(decodedProfile.id, profile.id);
    expect(decodedProfile.displayName, profile.displayName);
    expect(decodedLog.id, log.id);
    expect(decodedLog.processingStatus, PatientLogProcessingStatus.complete);
    expect(decodedLog.metricsSnapshot.fatigueScore, metrics.fatigueScore);
    expect(decodedClinician.entryType, 'soap');
    expect(decodedClinician.sourceLogId, 'l1');
  });

  test('repository save/load round-trip persists new AppState shape', () async {
    final repository = LocalAppStateRepository();
    final appState = AppState(
      role: UserRole.clinician,
      edgeTrackingEnabled: false,
      errorMessage: '',
      activePatientId: 'p1',
      patients: const <PatientProfile>[
        PatientProfile(
          id: 'p1',
          displayName: 'Alex Doe',
          createdAtIso: '2026-01-01T00:00:00.000Z',
        ),
      ],
      patientLogs: const <String, List<PatientLogEntry>>{
        'p1': <PatientLogEntry>[
          PatientLogEntry(
            id: 'l1',
            patientId: 'p1',
            startedAtIso: '2026-01-01T00:00:00.000Z',
            endedAtIso: '2026-01-01T00:05:00.000Z',
            durationSeconds: 300,
            audioPath: '/tmp/audio.wav',
            patientNote: 'note',
            transcript: 'transcript',
            entitiesJson: <String, dynamic>{'symptoms': <String>['fatigue']},
            metricsSnapshot: metrics,
            baselineScore: 75,
            processingStatus: PatientLogProcessingStatus.complete,
            errorMessage: null,
          ),
        ],
      },
      clinicianEntries: const <String, List<ClinicianEntry>>{
        'p1': <ClinicianEntry>[
          ClinicianEntry(
            id: 'c1',
            patientId: 'p1',
            createdAtIso: '2026-01-01T00:06:00.000Z',
            entryType: 'soap',
            content: 'SOAP content',
            sourceLogId: 'l1',
          ),
        ],
      },
      recordingSession: const RecordingSessionDraft(
        isRecording: true,
        patientId: 'p1',
        startedAtIso: '2026-01-01T00:00:00.000Z',
        tempAudioPath: '/tmp/audio.wav',
        optionalNoteDraft: 'draft',
      ),
    );

    await repository.save(appState);
    final loaded = await repository.load();

    expect(loaded.edgeTrackingEnabled, false);
    expect(loaded.activePatientId, 'p1');
    expect(loaded.patients.single.displayName, 'Alex Doe');
    expect(loaded.patientLogs['p1']!.single.transcript, 'transcript');
    expect(loaded.clinicianEntries['p1']!.single.content, 'SOAP content');
    expect(loaded.recordingSession.isRecording, true);
  });

  test('legacy migration creates default patient/log/soap and stores new keys', () async {
    final legacyMetrics = jsonEncode(<String, dynamic>{
      'blink_rate_bpm': 12,
      'fatigue_score': 0.45,
      'anxiety_score': 0.25,
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      'edge_tracking_enabled': true,
      'selected_patient_id': 'self',
      'diary_summary': 'Legacy diary entry',
      'soap_note': 'Legacy SOAP note',
      'edge_metrics_json': legacyMetrics,
    });

    final repository = LocalAppStateRepository();
    final loaded = await repository.load();
    final prefs = await SharedPreferences.getInstance();

    expect(loaded.patients.length, 1);
    expect(loaded.patients.single.id, 'self');
    expect(loaded.patientLogs['self']!.single.transcript, 'Legacy diary entry');
    expect(loaded.clinicianEntries['self']!.single.content, 'Legacy SOAP note');
    expect(prefs.getString('patients_json'), isNotNull);
    expect(prefs.getString('patient_logs_json'), isNotNull);
    expect(prefs.getString('clinician_entries_json'), isNotNull);
    expect(prefs.getString('diary_summary'), 'Legacy diary entry');
    expect(prefs.getString('soap_note'), 'Legacy SOAP note');
  });
}
