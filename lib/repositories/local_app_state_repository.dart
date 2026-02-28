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

    final decodedSnapshot = PersistedAppSnapshot(
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

    // If this key exists, honor stored state even when the list is empty.
    // This avoids re-seeding demo data after user-triggered data purges.
    if (prefs.containsKey(_prefsPatients)) {
      return decodedSnapshot;
    }

    return _loadLegacySnapshot(prefs);
  }

  PersistedAppSnapshot oncologyDemoSnapshot({
    required bool edgeTrackingEnabled,
  }) {
    return _buildOncologyDemoSnapshot(
      edgeTrackingEnabled: edgeTrackingEnabled,
    );
  }

  Future<PersistedAppSnapshot> loadOncologyDemoData() async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = oncologyDemoSnapshot(
      edgeTrackingEnabled: prefs.getBool(_prefsEdgeTracking) ?? true,
    );
    await _saveSnapshotToPrefs(prefs, snapshot);
    return snapshot;
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
      final demoSnapshot = _buildOncologyDemoSnapshot(
        edgeTrackingEnabled: prefs.getBool(_prefsEdgeTracking) ?? true,
      );
      await _saveSnapshotToPrefs(prefs, demoSnapshot);
      return demoSnapshot;
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

  PersistedAppSnapshot _buildOncologyDemoSnapshot({
    required bool edgeTrackingEnabled,
  }) {
    final now = DateTime.now();
    final stablePatient = PatientProfile(
      id: 'demo_onc_stable',
      displayName: 'Jordan Lee - Oncology (Stable)',
      createdAtIso: now.subtract(const Duration(days: 45)).toIso8601String(),
    );
    final severePatient = PatientProfile(
      id: 'demo_onc_severe',
      displayName: 'Maya Patel - Oncology (Severe Depression)',
      createdAtIso: now.subtract(const Duration(days: 60)).toIso8601String(),
    );
    final averagePatient = PatientProfile(
      id: 'demo_onc_average',
      displayName: 'Carlos Rivera - Oncology (Moderate Symptoms)',
      createdAtIso: now.subtract(const Duration(days: 30)).toIso8601String(),
    );

    final stableMetrics = EdgeMetrics(
      blinksPerMinute: 16.2,
      fatigueScore: 0.18,
      anxietyScore: 0.16,
      totalBlinks: 64,
      trackingUptimePercent: 97.0,
      sampleRateHz: 29.0,
      eyeClosureRatePercent: 2.1,
      gazeDriftDegrees: 1.8,
      fixationInstabilityDegrees: 1.1,
      trackingQualityScore: 0.93,
    );
    final severeMetrics = EdgeMetrics(
      blinksPerMinute: 31.5,
      fatigueScore: 0.84,
      anxietyScore: 0.79,
      totalBlinks: 121,
      trackingUptimePercent: 88.5,
      sampleRateHz: 25.3,
      eyeClosureRatePercent: 8.4,
      gazeDriftDegrees: 6.8,
      fixationInstabilityDegrees: 4.9,
      trackingQualityScore: 0.58,
    );
    final averageMetrics = EdgeMetrics(
      blinksPerMinute: 22.8,
      fatigueScore: 0.47,
      anxietyScore: 0.42,
      totalBlinks: 89,
      trackingUptimePercent: 93.4,
      sampleRateHz: 27.6,
      eyeClosureRatePercent: 4.8,
      gazeDriftDegrees: 3.6,
      fixationInstabilityDegrees: 2.7,
      trackingQualityScore: 0.76,
    );

    const swingPattern = <double>[0.0, 1.0, -0.7, 1.4, -1.1, 0.6, -0.4];

    EdgeMetrics metricsForDay({
      required EdgeMetrics base,
      required int dayIndex,
      required double fatigueSwing,
      required double anxietySwing,
    }) {
      final swing = swingPattern[dayIndex % swingPattern.length];
      return EdgeMetrics(
        blinksPerMinute: (base.blinksPerMinute + (0.35 * swing)).toDouble(),
        fatigueScore:
            (base.fatigueScore + (fatigueSwing * swing)).clamp(0, 1).toDouble(),
        anxietyScore:
            (base.anxietyScore + (anxietySwing * swing)).clamp(0, 1).toDouble(),
        totalBlinks: (base.totalBlinks + (3 * swing).round()).clamp(0, 1000000),
        trackingUptimePercent: base.trackingUptimePercent,
        sampleRateHz: base.sampleRateHz,
        eyeClosureRatePercent: base.eyeClosureRatePercent,
        gazeDriftDegrees: base.gazeDriftDegrees,
        fixationInstabilityDegrees: base.fixationInstabilityDegrees,
        trackingQualityScore: base.trackingQualityScore,
      );
    }

    List<PatientLogEntry> sevenDayLogs({
      required String patientId,
      required String idPrefix,
      required EdgeMetrics baseMetrics,
      required List<String> transcripts,
      required List<double> depressionScores,
      required List<DepressionMarker> depressionMarkers,
      required String sentimentLabel,
      required List<String> symptoms,
      required String notePrefix,
      required double fatigueSwing,
      required double anxietySwing,
    }) {
      final logs = <PatientLogEntry>[];
      for (var dayIndex = 0; dayIndex < 7; dayIndex++) {
        final startedAt = DateTime(now.year, now.month, now.day, 9, 0).subtract(
          Duration(days: dayIndex, hours: dayIndex % 2),
        );
        final durationSeconds = 540 + (dayIndex * 30);
        final metrics = metricsForDay(
          base: baseMetrics,
          dayIndex: dayIndex,
          fatigueSwing: fatigueSwing,
          anxietySwing: anxietySwing,
        );
        logs.add(
          PatientLogEntry(
            id: '${idPrefix}_day_$dayIndex',
            patientId: patientId,
            startedAtIso: startedAt.toIso8601String(),
            endedAtIso: startedAt
                .add(Duration(seconds: durationSeconds))
                .toIso8601String(),
            durationSeconds: durationSeconds,
            audioPath: null,
            patientNote: '$notePrefix - day ${dayIndex + 1}',
            transcript: transcripts[dayIndex],
            entitiesJson: <String, dynamic>{
              'specialty': 'oncology',
              'sentiment_label': sentimentLabel,
              'symptoms': symptoms,
            },
            metricsSnapshot: metrics,
            baselineScore: metrics.baselineScore,
            depressionScore: depressionScores[dayIndex],
            depressionMarker: depressionMarkers[dayIndex],
            processingStatus: PatientLogProcessingStatus.complete,
            errorMessage: null,
          ),
        );
      }
      return logs;
    }

    final stableLogs = sevenDayLogs(
      patientId: stablePatient.id,
      idPrefix: 'demo_log_onc_stable',
      baseMetrics: stableMetrics,
      transcripts: const <String>[
        'Oncology follow-up today: appetite is stable, slept well, and I feel calm.',
        'Chemo recovery has been manageable and mood stayed mostly positive.',
        'I felt slightly tired after treatment but rested well overnight.',
        'Energy improved and anxiety stayed low during oncology check-in.',
        'Mild nausea, but still motivated and supported by family.',
        'Radiation session went smoothly and mood was steady.',
        'I felt good overall and hopeful about this week.',
      ],
      depressionScores: const <double>[
        0.19,
        0.21,
        0.20,
        0.22,
        0.20,
        0.18,
        0.19
      ],
      depressionMarkers: const <DepressionMarker>[
        DepressionMarker.low,
        DepressionMarker.low,
        DepressionMarker.low,
        DepressionMarker.low,
        DepressionMarker.low,
        DepressionMarker.low,
        DepressionMarker.low,
      ],
      sentimentLabel: 'neutral_or_positive',
      symptoms: const <String>['mild nausea'],
      notePrefix: 'Post-infusion check-in',
      fatigueSwing: 0.012,
      anxietySwing: 0.010,
    );
    final severeLogs = sevenDayLogs(
      patientId: severePatient.id,
      idPrefix: 'demo_log_onc_severe',
      baseMetrics: severeMetrics,
      transcripts: const <String>[
        'Oncology treatment feels overwhelming. I feel hopeless and exhausted today.',
        'I had poor sleep, high anxiety, and no motivation after chemo.',
        'Mood stayed very low and I felt empty most of the day.',
        'I am still feeling depressed, worn out, and worried about everything.',
        'Another difficult day with panic, insomnia, and heavy fatigue.',
        'I felt down all day and struggled to get out of bed.',
        'I remain overwhelmed and emotionally drained from treatment.',
      ],
      depressionScores: const <double>[
        0.86,
        0.88,
        0.87,
        0.85,
        0.89,
        0.90,
        0.84
      ],
      depressionMarkers: const <DepressionMarker>[
        DepressionMarker.high,
        DepressionMarker.high,
        DepressionMarker.high,
        DepressionMarker.high,
        DepressionMarker.high,
        DepressionMarker.high,
        DepressionMarker.high,
      ],
      sentimentLabel: 'negative',
      symptoms: const <String>['fatigue', 'anxiety', 'insomnia'],
      notePrefix: 'Cycle 4 emotional check-in',
      fatigueSwing: 0.028,
      anxietySwing: 0.024,
    );
    final averageLogs = sevenDayLogs(
      patientId: averagePatient.id,
      idPrefix: 'demo_log_onc_average',
      baseMetrics: averageMetrics,
      transcripts: const <String>[
        'Oncology update: treatment was hard today but I am managing.',
        'Mood was mixed with moderate fatigue after radiation.',
        'I felt anxious in the afternoon but better by evening.',
        'Energy dipped today, though I stayed engaged with daily tasks.',
        'Sleep was okay, mood was up and down, and stress felt moderate.',
        'I handled treatment day with support but still felt tired.',
        'Overall average day: some worry, some relief, and manageable symptoms.',
      ],
      depressionScores: const <double>[
        0.51,
        0.53,
        0.50,
        0.55,
        0.49,
        0.52,
        0.48
      ],
      depressionMarkers: const <DepressionMarker>[
        DepressionMarker.watch,
        DepressionMarker.watch,
        DepressionMarker.watch,
        DepressionMarker.watch,
        DepressionMarker.watch,
        DepressionMarker.watch,
        DepressionMarker.watch,
      ],
      sentimentLabel: 'mixed',
      symptoms: const <String>['moderate fatigue', 'variable mood'],
      notePrefix: 'Radiation week update',
      fatigueSwing: 0.020,
      anxietySwing: 0.018,
    );

    return PersistedAppSnapshot(
      edgeTrackingEnabled: edgeTrackingEnabled,
      activePatientId: stablePatient.id,
      patients: <PatientProfile>[
        stablePatient,
        severePatient,
        averagePatient,
      ],
      patientLogs: <String, List<PatientLogEntry>>{
        stablePatient.id: stableLogs,
        severePatient.id: severeLogs,
        averagePatient.id: averageLogs,
      },
      clinicianEntries: const <String, List<ClinicianEntry>>{},
      medicationPlans: const <String, List<MedicationPlan>>{},
      medicationIntakes: const <String, List<MedicationIntakeEntry>>{},
      healthSignals: const <String, List<HealthSignalEntry>>{},
      recordingSession: RecordingSessionDraft.empty,
    );
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
    if (raw == null || raw.isEmpty) {
      return const <String, List<PatientLogEntry>>{};
    }
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
