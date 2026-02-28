import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_models.dart';

class PersistedAppSnapshot {
  const PersistedAppSnapshot({
    required this.edgeTrackingEnabled,
    required this.activePatientId,
    required this.patients,
    required this.patientLogs,
    required this.clinicianEntries,
    required this.medicationPlans,
    required this.medicationIntakes,
    required this.healthSignals,
    required this.recordingSession,
  });

  final bool edgeTrackingEnabled;
  final String? activePatientId;
  final List<PatientProfile> patients;
  final Map<String, List<PatientLogEntry>> patientLogs;
  final Map<String, List<ClinicianEntry>> clinicianEntries;
  final Map<String, List<MedicationPlan>> medicationPlans;
  final Map<String, List<MedicationIntakeEntry>> medicationIntakes;
  final Map<String, List<HealthSignalEntry>> healthSignals;
  final RecordingSessionDraft recordingSession;
}

class LocalAppStateRepository {
  static const _prefsEdgeTracking = 'edge_tracking_enabled';
  static const _prefsActivePatientId = 'active_patient_id';
  static const _prefsPatients = 'patients_json';
  static const _prefsPatientLogs = 'patient_logs_json';
  static const _prefsClinicianEntries = 'clinician_entries_json';
  static const _prefsMedicationPlans = 'medication_plans_json';
  static const _prefsMedicationIntakes = 'medication_intakes_json';
  static const _prefsHealthSignals = 'health_signals_json';
  static const _prefsRecordingSessionDraft = 'recording_session_draft';

  static const _legacyPrefsDiarySummary = 'diary_summary';
  static const _legacyPrefsSoapNote = 'soap_note';
  static const _legacyPrefsSelectedPatientId = 'selected_patient_id';
  static const _legacyPrefsMetrics = 'edge_metrics_json';

  Future<PersistedAppSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();

    final patients = _decodePatients(prefs.getString(_prefsPatients));
    final logs = _decodePatientLogs(prefs.getString(_prefsPatientLogs));
    final clinicianEntries =
        _decodeClinicianEntries(prefs.getString(_prefsClinicianEntries));
    final medicationPlans =
        _decodeMedicationPlans(prefs.getString(_prefsMedicationPlans));
    final medicationIntakes =
        _decodeMedicationIntakes(prefs.getString(_prefsMedicationIntakes));
    final healthSignals =
        _decodeHealthSignals(prefs.getString(_prefsHealthSignals));
    final recordingSession = _decodeRecordingSession(
      prefs.getString(_prefsRecordingSessionDraft),
    );
    final activePatientId = prefs.getString(_prefsActivePatientId);

    if (patients.isNotEmpty) {
      return PersistedAppSnapshot(
        edgeTrackingEnabled: prefs.getBool(_prefsEdgeTracking) ?? true,
        activePatientId: activePatientId,
        patients: patients,
        patientLogs: logs,
        clinicianEntries: clinicianEntries,
        medicationPlans: medicationPlans,
        medicationIntakes: medicationIntakes,
        healthSignals: healthSignals,
        recordingSession: recordingSession,
      );
    }

    return _loadLegacySnapshot(prefs);
  }

  Future<PersistedAppSnapshot> _loadLegacySnapshot(
    SharedPreferences prefs,
  ) async {
    final diarySummary = prefs.getString(_legacyPrefsDiarySummary) ?? '';
    final soapNote = prefs.getString(_legacyPrefsSoapNote) ?? '';
    final legacySelectedPatientId =
        prefs.getString(_legacyPrefsSelectedPatientId) ?? 'self';
    final legacyMetricsJson = prefs.getString(_legacyPrefsMetrics);
    final hasLegacyContent = diarySummary.isNotEmpty ||
        soapNote.isNotEmpty ||
        (legacyMetricsJson?.isNotEmpty ?? false);

    if (!hasLegacyContent) {
      return PersistedAppSnapshot(
        edgeTrackingEnabled: prefs.getBool(_prefsEdgeTracking) ?? true,
        activePatientId: null,
        patients: const <PatientProfile>[],
        patientLogs: const <String, List<PatientLogEntry>>{},
        clinicianEntries: const <String, List<ClinicianEntry>>{},
        medicationPlans: const <String, List<MedicationPlan>>{},
        medicationIntakes: const <String, List<MedicationIntakeEntry>>{},
        healthSignals: const <String, List<HealthSignalEntry>>{},
        recordingSession: RecordingSessionDraft.empty,
      );
    }

    final now = DateTime.now();
    final profile = PatientProfile(
      id: legacySelectedPatientId,
      displayName: 'Current Patient',
      createdAtIso: now.toIso8601String(),
    );

    final metrics = legacyMetricsJson == null
        ? EdgeMetrics.empty
        : EdgeMetrics.fromJson(
            jsonDecode(legacyMetricsJson) as Map<String, dynamic>,
          );
    final entryId = 'legacy_log_${now.microsecondsSinceEpoch}';
    final legacyLog = PatientLogEntry(
      id: entryId,
      patientId: profile.id,
      startedAtIso: now.toIso8601String(),
      endedAtIso: now.toIso8601String(),
      durationSeconds: 0,
      audioPath: null,
      patientNote: null,
      transcript: diarySummary,
      entitiesJson: const <String, dynamic>{},
      metricsSnapshot: metrics,
      baselineScore: metrics.baselineScore,
      processingStatus: PatientLogProcessingStatus.complete,
      errorMessage: null,
    );

    final legacySoap = soapNote.isEmpty
        ? <ClinicianEntry>[]
        : <ClinicianEntry>[
            ClinicianEntry(
              id: 'legacy_soap_${now.microsecondsSinceEpoch}',
              patientId: profile.id,
              createdAtIso: now.toIso8601String(),
              entryType: 'soap',
              content: soapNote,
              sourceLogId: entryId,
            ),
          ];

    final snapshot = PersistedAppSnapshot(
      edgeTrackingEnabled: prefs.getBool(_prefsEdgeTracking) ?? true,
      activePatientId: profile.id,
      patients: <PatientProfile>[profile],
      patientLogs: <String, List<PatientLogEntry>>{
        profile.id: <PatientLogEntry>[legacyLog],
      },
      clinicianEntries: <String, List<ClinicianEntry>>{
        profile.id: legacySoap,
      },
      medicationPlans: const <String, List<MedicationPlan>>{},
      medicationIntakes: const <String, List<MedicationIntakeEntry>>{},
      healthSignals: const <String, List<HealthSignalEntry>>{},
      recordingSession: RecordingSessionDraft.empty,
    );
    await _saveSnapshotToPrefs(prefs, snapshot);
    return snapshot;
  }

  Future<void> save(AppState state) async {
    final prefs = await SharedPreferences.getInstance();
    await _saveSnapshotToPrefs(
      prefs,
      PersistedAppSnapshot(
        edgeTrackingEnabled: state.edgeTrackingEnabled,
        activePatientId: state.activePatientId,
        patients: state.patients,
        patientLogs: state.patientLogs,
        clinicianEntries: state.clinicianEntries,
        medicationPlans: state.medicationPlans,
        medicationIntakes: state.medicationIntakes,
        healthSignals: state.healthSignals,
        recordingSession: state.recordingSession,
      ),
    );
  }

  List<PatientProfile> _decodePatients(String? raw) {
    if (raw == null || raw.isEmpty) return const <PatientProfile>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) return const <PatientProfile>[];
    return decoded
        .whereType<Map>()
        .map((item) => item.map((k, v) => MapEntry('$k', v)))
        .map(PatientProfile.fromJson)
        .toList();
  }

  Map<String, List<PatientLogEntry>> _decodePatientLogs(String? raw) {
    if (raw == null || raw.isEmpty)
      return const <String, List<PatientLogEntry>>{};
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const <String, List<PatientLogEntry>>{};
    }
    return decoded.map((patientId, value) {
      final list = value is List<dynamic>
          ? value
              .whereType<Map>()
              .map((item) => item.map((k, v) => MapEntry('$k', v)))
              .map(PatientLogEntry.fromJson)
              .toList()
          : <PatientLogEntry>[];
      return MapEntry(patientId, list);
    });
  }

  Map<String, List<ClinicianEntry>> _decodeClinicianEntries(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <String, List<ClinicianEntry>>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const <String, List<ClinicianEntry>>{};
    }
    return decoded.map((patientId, value) {
      final list = value is List<dynamic>
          ? value
              .whereType<Map>()
              .map((item) => item.map((k, v) => MapEntry('$k', v)))
              .map(ClinicianEntry.fromJson)
              .toList()
          : <ClinicianEntry>[];
      return MapEntry(patientId, list);
    });
  }

  Map<String, List<MedicationPlan>> _decodeMedicationPlans(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <String, List<MedicationPlan>>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const <String, List<MedicationPlan>>{};
    }
    return decoded.map((patientId, value) {
      final list = value is List<dynamic>
          ? value
              .whereType<Map>()
              .map((item) => item.map((k, v) => MapEntry('$k', v)))
              .map(MedicationPlan.fromJson)
              .toList()
          : <MedicationPlan>[];
      return MapEntry(patientId, list);
    });
  }

  Map<String, List<MedicationIntakeEntry>> _decodeMedicationIntakes(
      String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <String, List<MedicationIntakeEntry>>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const <String, List<MedicationIntakeEntry>>{};
    }
    return decoded.map((patientId, value) {
      final list = value is List<dynamic>
          ? value
              .whereType<Map>()
              .map((item) => item.map((k, v) => MapEntry('$k', v)))
              .map(MedicationIntakeEntry.fromJson)
              .toList()
          : <MedicationIntakeEntry>[];
      return MapEntry(patientId, list);
    });
  }

  Map<String, List<HealthSignalEntry>> _decodeHealthSignals(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <String, List<HealthSignalEntry>>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const <String, List<HealthSignalEntry>>{};
    }
    return decoded.map((patientId, value) {
      final list = value is List<dynamic>
          ? value
              .whereType<Map>()
              .map((item) => item.map((k, v) => MapEntry('$k', v)))
              .map(HealthSignalEntry.fromJson)
              .toList()
          : <HealthSignalEntry>[];
      return MapEntry(patientId, list);
    });
  }

  RecordingSessionDraft _decodeRecordingSession(String? raw) {
    if (raw == null || raw.isEmpty) return RecordingSessionDraft.empty;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return RecordingSessionDraft.empty;
    return RecordingSessionDraft.fromJson(decoded);
  }

  Future<void> _saveSnapshotToPrefs(
    SharedPreferences prefs,
    PersistedAppSnapshot snapshot,
  ) async {
    await prefs.setBool(_prefsEdgeTracking, snapshot.edgeTrackingEnabled);

    final activePatientId = snapshot.activePatientId;
    if (activePatientId == null) {
      await prefs.remove(_prefsActivePatientId);
    } else {
      await prefs.setString(_prefsActivePatientId, activePatientId);
    }

    await prefs.setString(
      _prefsPatients,
      jsonEncode(snapshot.patients.map((p) => p.toJson()).toList()),
    );
    await prefs.setString(
      _prefsPatientLogs,
      jsonEncode(
        snapshot.patientLogs.map(
          (patientId, logs) => MapEntry(
            patientId,
            logs.map((entry) => entry.toJson()).toList(),
          ),
        ),
      ),
    );
    await prefs.setString(
      _prefsClinicianEntries,
      jsonEncode(
        snapshot.clinicianEntries.map(
          (patientId, entries) => MapEntry(
            patientId,
            entries.map((entry) => entry.toJson()).toList(),
          ),
        ),
      ),
    );
    await prefs.setString(
      _prefsMedicationPlans,
      jsonEncode(
        snapshot.medicationPlans.map(
          (patientId, plans) => MapEntry(
            patientId,
            plans.map((entry) => entry.toJson()).toList(),
          ),
        ),
      ),
    );
    await prefs.setString(
      _prefsMedicationIntakes,
      jsonEncode(
        snapshot.medicationIntakes.map(
          (patientId, intakes) => MapEntry(
            patientId,
            intakes.map((entry) => entry.toJson()).toList(),
          ),
        ),
      ),
    );
    await prefs.setString(
      _prefsHealthSignals,
      jsonEncode(
        snapshot.healthSignals.map(
          (patientId, signals) => MapEntry(
            patientId,
            signals.map((entry) => entry.toJson()).toList(),
          ),
        ),
      ),
    );
    await prefs.setString(
      _prefsRecordingSessionDraft,
      jsonEncode(snapshot.recordingSession.toJson()),
    );
  }
}
