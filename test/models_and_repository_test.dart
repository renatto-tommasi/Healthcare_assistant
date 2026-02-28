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

  test(
      'model serialization round-trip works for patient/profile/clinician types',
      () {
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
      entitiesJson: <String, dynamic>{
        'symptoms': <String>['fatigue']
      },
      metricsSnapshot: metrics,
      baselineScore: 75,
      depressionScore: 0.52,
      depressionMarker: DepressionMarker.watch,
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
    const medPlan = MedicationPlan(
      id: 'm1',
      patientId: 'p1',
      name: 'Sertraline',
      dosage: '50mg',
      instructions: 'After breakfast',
      dailyTimes: <String>['08:00'],
      startDateIso: '2026-01-01T00:00:00.000Z',
      endDateIso: null,
      isPrn: false,
      isActive: true,
    );
    const medIntake = MedicationIntakeEntry(
      id: 'mi1',
      patientId: 'p1',
      medicationPlanId: 'm1',
      scheduledAtIso: '2026-01-01T08:00:00.000Z',
      takenAtIso: '2026-01-01T08:15:00.000Z',
      status: MedicationIntakeStatus.onTime,
      note: null,
    );
    const signal = HealthSignalEntry(
      id: 'hs1',
      patientId: 'p1',
      recordedAtIso: '2026-01-01T08:05:00.000Z',
      systolicBp: 122,
      diastolicBp: 80,
      heartRateBpm: 72,
      note: 'Morning check',
    );

    final decodedProfile = PatientProfile.fromJson(profile.toJson());
    final decodedLog = PatientLogEntry.fromJson(log.toJson());
    final decodedClinician = ClinicianEntry.fromJson(clinicianEntry.toJson());
    final decodedPlan = MedicationPlan.fromJson(medPlan.toJson());
    final decodedIntake = MedicationIntakeEntry.fromJson(medIntake.toJson());
    final decodedSignal = HealthSignalEntry.fromJson(signal.toJson());

    expect(decodedProfile.id, profile.id);
    expect(decodedProfile.displayName, profile.displayName);
    expect(decodedLog.id, log.id);
    expect(decodedLog.processingStatus, PatientLogProcessingStatus.complete);
    expect(decodedLog.metricsSnapshot.fatigueScore, metrics.fatigueScore);
    expect(decodedLog.depressionMarker, DepressionMarker.watch);
    expect(decodedLog.depressionScore, 0.52);
    expect(decodedClinician.entryType, 'soap');
    expect(decodedClinician.sourceLogId, 'l1');
    expect(decodedPlan.name, 'Sertraline');
    expect(decodedPlan.dailyTimes.single, '08:00');
    expect(decodedIntake.status, MedicationIntakeStatus.onTime);
    expect(decodedSignal.systolicBp, 122);
    expect(decodedSignal.heartRateBpm, 72);
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
            entitiesJson: <String, dynamic>{
              'symptoms': <String>['fatigue']
            },
            metricsSnapshot: metrics,
            baselineScore: 75,
            depressionScore: 0.48,
            depressionMarker: DepressionMarker.watch,
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
      medicationPlans: const <String, List<MedicationPlan>>{
        'p1': <MedicationPlan>[
          MedicationPlan(
            id: 'm1',
            patientId: 'p1',
            name: 'Sertraline',
            dosage: '50mg',
            instructions: 'After breakfast',
            dailyTimes: <String>['08:00'],
            startDateIso: '2026-01-01T00:00:00.000Z',
            endDateIso: null,
            isPrn: false,
            isActive: true,
          ),
        ],
      },
      medicationIntakes: const <String, List<MedicationIntakeEntry>>{
        'p1': <MedicationIntakeEntry>[
          MedicationIntakeEntry(
            id: 'i1',
            patientId: 'p1',
            medicationPlanId: 'm1',
            scheduledAtIso: '2026-01-01T08:00:00.000Z',
            takenAtIso: '2026-01-01T08:10:00.000Z',
            status: MedicationIntakeStatus.onTime,
            note: null,
          ),
        ],
      },
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
    expect(loaded.medicationPlans['p1']!.single.name, 'Sertraline');
    expect(loaded.medicationIntakes['p1']!.single.status,
        MedicationIntakeStatus.onTime);
    expect(loaded.healthSignals['p1']!.single.systolicBp, 122);
    expect(loaded.recordingSession.isRecording, true);
  });

  test('legacy migration creates default patient/log/soap and stores new keys',
      () async {
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
    expect(loaded.medicationPlans, isEmpty);
    expect(loaded.medicationIntakes, isEmpty);
    expect(loaded.healthSignals, isEmpty);
    expect(prefs.getString('patients_json'), isNotNull);
    expect(prefs.getString('patient_logs_json'), isNotNull);
    expect(prefs.getString('clinician_entries_json'), isNotNull);
    expect(prefs.getString('medication_plans_json'), isNotNull);
    expect(prefs.getString('medication_intakes_json'), isNotNull);
    expect(prefs.getString('health_signals_json'), isNotNull);
    expect(prefs.getString('diary_summary'), 'Legacy diary entry');
    expect(prefs.getString('soap_note'), 'Legacy SOAP note');
  });
}
