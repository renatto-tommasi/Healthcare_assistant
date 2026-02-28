import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../repositories/local_app_state_repository.dart';

enum MedicationDoseStatus { due, onTime, late, overdue, taken }

class MedicationDoseScheduleItem {
  const MedicationDoseScheduleItem({
    required this.patientId,
    required this.medicationPlanId,
    required this.medicationName,
    required this.dosage,
    required this.instructions,
    required this.scheduledAt,
    required this.status,
    this.takenAt,
    required this.isPrn,
  });

  final String patientId;
  final String medicationPlanId;
  final String medicationName;
  final String dosage;
  final String instructions;
  final DateTime scheduledAt;
  final MedicationDoseStatus status;
  final DateTime? takenAt;
  final bool isPrn;
}

class MedicationAdherenceSummary {
  const MedicationAdherenceSummary({
    required this.onTime,
    required this.late,
    required this.overdue,
    required this.totalDue,
  });

  final int onTime;
  final int late;
  final int overdue;
  final int totalDue;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'on_time': onTime,
        'late': late,
        'overdue': overdue,
        'total_due': totalDue,
      };
}

class _ScheduledDose {
  const _ScheduledDose({
    required this.plan,
    required this.scheduledAt,
  });

  final MedicationPlan plan;
  final DateTime scheduledAt;
}

class AppStateNotifier extends StateNotifier<AppState> {
  AppStateNotifier(this._repository) : super(AppState.initial()) {
    unawaited(loadFromDisk());
  }

  final LocalAppStateRepository _repository;
  final Random _random = Random();

  Future<void> loadFromDisk() async {
    final snapshot = await _repository.load();
    state = state.copyWith(
      edgeTrackingEnabled: snapshot.edgeTrackingEnabled,
      activePatientId: snapshot.activePatientId,
      patients: snapshot.patients,
      patientLogs: snapshot.patientLogs,
      clinicianEntries: snapshot.clinicianEntries,
      medicationPlans: snapshot.medicationPlans,
      medicationIntakes: snapshot.medicationIntakes,
      healthSignals: snapshot.healthSignals,
      recordingSession: snapshot.recordingSession,
    );
  }

  String _generateId(String prefix) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(1 << 20).toRadixString(16);
    return '${prefix}_$now$suffix';
  }

  DateTime _dayStart(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _normalizeTime(String value) {
    final parts = value.trim().split(':');
    if (parts.length != 2) {
      throw FormatException('Time must use HH:mm.');
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      throw FormatException('Time must use HH:mm.');
    }
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  DateTime _dayAndTime(DateTime day, String hhmm) {
    final normalized = _normalizeTime(hhmm);
    final parts = normalized.split(':');
    return DateTime(
        day.year, day.month, day.day, int.parse(parts[0]), int.parse(parts[1]));
  }

  PatientProfile _defaultPatient() {
    return PatientProfile(
      id: 'self',
      displayName: 'Current Patient',
      createdAtIso: DateTime.now().toIso8601String(),
    );
  }

  String ensureDefaultPatient() {
    if (state.patients.isNotEmpty) {
      return state.activePatientId ?? state.patients.first.id;
    }
    final profile = _defaultPatient();
    state = state.copyWith(
      patients: <PatientProfile>[profile],
      activePatientId: profile.id,
      errorMessage: '',
    );
    unawaited(_repository.save(state));
    return profile.id;
  }

  void setRole(UserRole role) {
    var activePatientId = state.activePatientId;
    var patients = state.patients;
    if (role == UserRole.patient && patients.isEmpty) {
      final profile = _defaultPatient();
      patients = <PatientProfile>[profile];
      activePatientId = profile.id;
    }
    state = state.copyWith(
      role: role,
      errorMessage: '',
      patients: patients,
      activePatientId: activePatientId,
    );
    unawaited(_repository.save(state));
  }

  void setError(String error) {
    state = state.copyWith(errorMessage: error);
    unawaited(_repository.save(state));
  }

  void clearError() {
    if (state.errorMessage.isEmpty) return;
    state = state.copyWith(errorMessage: '');
    unawaited(_repository.save(state));
  }

  void toggleEdgeTracking(bool enabled) {
    state = state.copyWith(edgeTrackingEnabled: enabled);
    unawaited(_repository.save(state));
  }

  String createPatientProfile(String displayName) {
    final cleanedName =
        displayName.trim().isEmpty ? 'New Patient' : displayName.trim();
    final profile = PatientProfile(
      id: _generateId('patient'),
      displayName: cleanedName,
      createdAtIso: DateTime.now().toIso8601String(),
    );
    final patients = <PatientProfile>[...state.patients, profile];
    state = state.copyWith(
      patients: patients,
      activePatientId: profile.id,
      errorMessage: '',
    );
    unawaited(_repository.save(state));
    return profile.id;
  }

  void selectActivePatient(String id) {
    if (!state.patients.any((p) => p.id == id)) return;
    state = state.copyWith(activePatientId: id, errorMessage: '');
    unawaited(_repository.save(state));
  }

  void updateRecordingNoteDraft(String note) {
    state = state.copyWith(
      recordingSession:
          state.recordingSession.copyWith(optionalNoteDraft: note),
    );
    unawaited(_repository.save(state));
  }

  void startPatientLog({
    required String patientId,
    String? optionalNote,
    String? tempAudioPath,
  }) {
    state = state.copyWith(
      recordingSession: RecordingSessionDraft(
        isRecording: true,
        patientId: patientId,
        startedAtIso: DateTime.now().toIso8601String(),
        tempAudioPath: tempAudioPath,
        optionalNoteDraft: optionalNote ?? '',
      ),
      errorMessage: '',
    );
    unawaited(_repository.save(state));
  }

  String stopPatientLog({
    required String patientId,
    required String? audioPath,
    required EdgeMetrics metrics,
  }) {
    final startedAt = state.recordingSession.startedAtIso != null
        ? DateTime.tryParse(state.recordingSession.startedAtIso!)
        : null;
    final endedAt = DateTime.now();
    final duration =
        startedAt == null ? 0 : endedAt.difference(startedAt).inSeconds;
    final log = PatientLogEntry(
      id: _generateId('log'),
      patientId: patientId,
      startedAtIso: (startedAt ?? endedAt).toIso8601String(),
      endedAtIso: endedAt.toIso8601String(),
      durationSeconds: duration,
      audioPath: audioPath,
      patientNote: state.recordingSession.optionalNoteDraft.trim().isEmpty
          ? null
          : state.recordingSession.optionalNoteDraft.trim(),
      transcript: '',
      entitiesJson: const <String, dynamic>{},
      metricsSnapshot: metrics,
      baselineScore: metrics.baselineScore,
      depressionScore: 0,
      depressionMarker: DepressionMarker.low,
      processingStatus: PatientLogProcessingStatus.processing,
      errorMessage: null,
    );

    final updatedLogs =
        Map<String, List<PatientLogEntry>>.from(state.patientLogs);
    final patientLogList = <PatientLogEntry>[
      ...(updatedLogs[patientId] ?? const <PatientLogEntry>[]),
      log,
    ];
    patientLogList.sort((a, b) => b.startedAtIso.compareTo(a.startedAtIso));
    updatedLogs[patientId] = patientLogList;

    state = state.copyWith(
      patientLogs: updatedLogs,
      recordingSession: RecordingSessionDraft.empty,
      errorMessage: '',
    );
    unawaited(_repository.save(state));
    return log.id;
  }

  double computeDepressionScore({
    required EdgeMetrics metrics,
    required String transcript,
    required List<double> recentScores,
    double? sentimentRisk,
  }) {
    final computedSentimentRisk =
        sentimentRisk ?? _sentimentRiskFromTranscript(transcript);
    final base = (0.40 * metrics.fatigueScore) + (0.25 * metrics.anxietyScore);
    final trendDrop = _trendDropScore(recentScores);
    final transcriptCue = _transcriptCueScore(transcript);
    return (base +
            (0.15 * trendDrop) +
            (0.10 * transcriptCue) +
            (0.10 * computedSentimentRisk))
        .clamp(0, 1)
        .toDouble();
  }

  DepressionMarker depressionMarkerFromScore(double score) {
    if (score >= 0.70) return DepressionMarker.high;
    if (score >= 0.40) return DepressionMarker.watch;
    return DepressionMarker.low;
  }

  double _trendDropScore(List<double> recentScores) {
    if (recentScores.length < 3) return 0;
    final oldest = recentScores.first;
    final newest = recentScores.last;
    final decline = ((oldest - newest) / 100).clamp(0, 1).toDouble();
    var decreasingSteps = 0;
    for (var i = 1; i < recentScores.length; i++) {
      if (recentScores[i] < recentScores[i - 1]) {
        decreasingSteps += 1;
      }
    }
    final sustained = (decreasingSteps / (recentScores.length - 1)).clamp(0, 1);
    return ((decline * 0.6) + (sustained * 0.4)).clamp(0, 1).toDouble();
  }

  double _transcriptCueScore(String transcript) {
    final normalized = transcript.trim().toLowerCase();
    if (normalized.isEmpty) return 0;
    const cues = <String>[
      'hopeless',
      'down',
      'empty',
      'no motivation',
      'worthless',
      'can\'t get out',
      'depressed',
    ];
    final matches = cues.where(normalized.contains).length;
    return (matches / cues.length).clamp(0, 1).toDouble();
  }

  double _sentimentRiskFromTranscript(String transcript) {
    final normalized = transcript.trim().toLowerCase();
    if (normalized.isEmpty) return 0;
    const negativeCues = <String, double>{
      'hopeless': 1.0,
      'depressed': 1.0,
      'worthless': 1.0,
      'empty': 0.8,
      'sad': 0.6,
      'down': 0.6,
      'anxious': 0.9,
      'anxiety': 0.9,
      'panic': 0.9,
      'worried': 0.7,
      'overwhelmed': 0.8,
      'fatigue': 0.7,
      'tired': 0.6,
      'exhausted': 0.8,
      'no motivation': 0.9,
      'can\'t sleep': 0.7,
      'cannot sleep': 0.7,
      'insomnia': 0.8,
    };
    const positiveCues = <String, double>{
      'calm': 0.6,
      'better': 0.5,
      'improving': 0.6,
      'good': 0.4,
      'hopeful': 0.8,
      'rested': 0.6,
      'motivated': 0.8,
      'stable': 0.5,
      'slept well': 0.7,
      'okay': 0.3,
    };

    var negative = 0.0;
    for (final cue in negativeCues.entries) {
      if (normalized.contains(cue.key)) {
        negative += cue.value;
      }
    }
    var positive = 0.0;
    for (final cue in positiveCues.entries) {
      if (normalized.contains(cue.key)) {
        positive += cue.value;
      }
    }

    final maxNegative = negativeCues.values.reduce((a, b) => a + b);
    final maxPositive = positiveCues.values.reduce((a, b) => a + b);
    final negativeScore = (negative / maxNegative).clamp(0, 1).toDouble();
    final positiveScore = (positive / maxPositive).clamp(0, 1).toDouble();
    return (negativeScore - (0.7 * positiveScore)).clamp(0, 1).toDouble();
  }

  EdgeMetrics _metricsWithSentimentAdjustment(
    EdgeMetrics metrics,
    double sentimentRisk,
  ) {
    if (sentimentRisk <= 0) return metrics;
    return EdgeMetrics(
      blinksPerMinute: metrics.blinksPerMinute,
      fatigueScore: (metrics.fatigueScore + (0.20 * sentimentRisk))
          .clamp(0, 1)
          .toDouble(),
      anxietyScore: (metrics.anxietyScore + (0.30 * sentimentRisk))
          .clamp(0, 1)
          .toDouble(),
      totalBlinks: metrics.totalBlinks,
      trackingUptimePercent: metrics.trackingUptimePercent,
      sampleRateHz: metrics.sampleRateHz,
      eyeClosureRatePercent: metrics.eyeClosureRatePercent,
      gazeDriftDegrees: metrics.gazeDriftDegrees,
      fixationInstabilityDegrees: metrics.fixationInstabilityDegrees,
      trackingQualityScore: metrics.trackingQualityScore,
    );
  }

  String _sentimentLabel(double sentimentRisk) {
    if (sentimentRisk >= 0.67) return 'negative';
    if (sentimentRisk >= 0.33) return 'mixed';
    return 'neutral_or_positive';
  }

  void finalizePatientLog({
    required String entryId,
    required String transcript,
    required Map<String, dynamic> entities,
    String? error,
  }) {
    final updatedLogs =
        Map<String, List<PatientLogEntry>>.from(state.patientLogs);
    for (final entry in updatedLogs.entries) {
      final index = entry.value.indexWhere((log) => log.id == entryId);
      if (index == -1) {
        continue;
      }
      final previous = entry.value[index];
      final status = error == null
          ? PatientLogProcessingStatus.complete
          : PatientLogProcessingStatus.failed;
      final trendScores = logsForPatient(previous.patientId)
          .where(
              (e) => e.processingStatus == PatientLogProcessingStatus.complete)
          .take(7)
          .toList()
          .reversed
          .map((e) => e.baselineScore)
          .toList();
      final sentimentRisk = _sentimentRiskFromTranscript(transcript);
      final adjustedMetrics = _metricsWithSentimentAdjustment(
          previous.metricsSnapshot, sentimentRisk);
      final depressionScore = computeDepressionScore(
        metrics: adjustedMetrics,
        transcript: transcript,
        recentScores: trendScores,
        sentimentRisk: sentimentRisk,
      );
      final depressionMarker = depressionMarkerFromScore(depressionScore);
      final enrichedEntities = Map<String, dynamic>.from(entities)
        ..['sentiment_risk_score'] = sentimentRisk
        ..['sentiment_label'] = _sentimentLabel(sentimentRisk)
        ..['adjusted_fatigue_score'] = adjustedMetrics.fatigueScore
        ..['adjusted_anxiety_score'] = adjustedMetrics.anxietyScore;
      entry.value[index] = previous.copyWith(
        transcript: transcript,
        entitiesJson: enrichedEntities,
        metricsSnapshot: adjustedMetrics,
        baselineScore: adjustedMetrics.baselineScore,
        processingStatus: status,
        depressionScore: depressionScore,
        depressionMarker: depressionMarker,
        errorMessage: error,
      );
      state = state.copyWith(
        patientLogs: updatedLogs,
        errorMessage: error == null ? '' : error,
      );
      unawaited(_repository.save(state));
      return;
    }
  }

  void addClinicianSoapEntry({
    required String patientId,
    required String content,
    String? sourceLogId,
  }) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    final entry = ClinicianEntry(
      id: _generateId('soap'),
      patientId: patientId,
      createdAtIso: DateTime.now().toIso8601String(),
      entryType: 'soap',
      content: trimmed,
      sourceLogId: sourceLogId,
    );
    final entries =
        Map<String, List<ClinicianEntry>>.from(state.clinicianEntries);
    final list = <ClinicianEntry>[
      ...(entries[patientId] ?? const <ClinicianEntry>[]),
      entry
    ];
    list.sort((a, b) => b.createdAtIso.compareTo(a.createdAtIso));
    entries[patientId] = list;
    state = state.copyWith(clinicianEntries: entries, errorMessage: '');
    unawaited(_repository.save(state));
  }

  List<PatientLogEntry> logsForPatient(String patientId) {
    final list = state.patientLogs[patientId] ?? const <PatientLogEntry>[];
    return List<PatientLogEntry>.from(list)
      ..sort((a, b) => b.startedAtIso.compareTo(a.startedAtIso));
  }

  List<ClinicianEntry> clinicianEntriesForPatient(String patientId) {
    final list = state.clinicianEntries[patientId] ?? const <ClinicianEntry>[];
    return List<ClinicianEntry>.from(list)
      ..sort((a, b) => b.createdAtIso.compareTo(a.createdAtIso));
  }

  List<MedicationPlan> medicationPlansForPatient(String patientId) {
    final list = state.medicationPlans[patientId] ?? const <MedicationPlan>[];
    return List<MedicationPlan>.from(list)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<MedicationPlan> activeMedicationPlansForPatient(String patientId) {
    return medicationPlansForPatient(patientId)
        .where((plan) => plan.isActive)
        .toList();
  }

  MedicationPlan? medicationPlanById(String patientId, String planId) {
    for (final plan
        in state.medicationPlans[patientId] ?? const <MedicationPlan>[]) {
      if (plan.id == planId) return plan;
    }
    return null;
  }

  List<MedicationIntakeEntry> medicationIntakesForPatient(String patientId) {
    final list =
        state.medicationIntakes[patientId] ?? const <MedicationIntakeEntry>[];
    return List<MedicationIntakeEntry>.from(list)
      ..sort((a, b) => b.takenAtIso.compareTo(a.takenAtIso));
  }

  String addHealthSignal({
    required String patientId,
    required int systolicBp,
    required int diastolicBp,
    required int heartRateBpm,
    DateTime? recordedAt,
    String? note,
  }) {
    if (systolicBp <= 0 || diastolicBp <= 0 || heartRateBpm <= 0) {
      throw ArgumentError(
          'Blood pressure and heart rate must be positive values.');
    }
    if (systolicBp < diastolicBp) {
      throw ArgumentError(
          'Systolic pressure should be greater than diastolic.');
    }
    final entry = HealthSignalEntry(
      id: _generateId('signal'),
      patientId: patientId,
      recordedAtIso: (recordedAt ?? DateTime.now()).toIso8601String(),
      systolicBp: systolicBp,
      diastolicBp: diastolicBp,
      heartRateBpm: heartRateBpm,
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
    );
    final signals =
        Map<String, List<HealthSignalEntry>>.from(state.healthSignals);
    final list = <HealthSignalEntry>[
      ...(signals[patientId] ?? const <HealthSignalEntry>[]),
      entry,
    ];
    list.sort((a, b) => b.recordedAtIso.compareTo(a.recordedAtIso));
    signals[patientId] = list;
    state = state.copyWith(healthSignals: signals, errorMessage: '');
    unawaited(_repository.save(state));
    return entry.id;
  }

  List<HealthSignalEntry> healthSignalsForPatient(String patientId) {
    final list = state.healthSignals[patientId] ?? const <HealthSignalEntry>[];
    return List<HealthSignalEntry>.from(list)
      ..sort((a, b) => b.recordedAtIso.compareTo(a.recordedAtIso));
  }

  HealthSignalEntry? latestHealthSignal(String patientId) {
    final list = healthSignalsForPatient(patientId);
    if (list.isEmpty) return null;
    return list.first;
  }

  String createMedicationPlan({
    required String patientId,
    required String name,
    required String dosage,
    required String instructions,
    required List<String> dailyTimes,
    DateTime? startDate,
    DateTime? endDate,
    bool isPrn = false,
  }) {
    final cleanedName = name.trim();
    if (cleanedName.isEmpty) {
      throw ArgumentError('Medication name is required.');
    }
    final normalizedTimes =
        isPrn ? <String>[] : dailyTimes.map(_normalizeTime).toSet().toList();
    normalizedTimes.sort();
    if (!isPrn && normalizedTimes.isEmpty) {
      throw ArgumentError('At least one daily time is required.');
    }
    final start = _dayStart(startDate ?? DateTime.now()).toIso8601String();
    final end = endDate == null ? null : _dayStart(endDate).toIso8601String();
    final plan = MedicationPlan(
      id: _generateId('med_plan'),
      patientId: patientId,
      name: cleanedName,
      dosage: dosage.trim(),
      instructions: instructions.trim(),
      dailyTimes: normalizedTimes,
      startDateIso: start,
      endDateIso: end,
      isPrn: isPrn,
      isActive: true,
    );
    final plans = Map<String, List<MedicationPlan>>.from(state.medicationPlans);
    final list = <MedicationPlan>[
      ...(plans[patientId] ?? const <MedicationPlan>[]),
      plan
    ];
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    plans[patientId] = list;
    state = state.copyWith(medicationPlans: plans, errorMessage: '');
    unawaited(_repository.save(state));
    return plan.id;
  }

  void updateMedicationPlan({
    required String patientId,
    required MedicationPlan updatedPlan,
  }) {
    final plans = Map<String, List<MedicationPlan>>.from(state.medicationPlans);
    final list = <MedicationPlan>[
      ...(plans[patientId] ?? const <MedicationPlan>[])
    ];
    final index = list.indexWhere((plan) => plan.id == updatedPlan.id);
    if (index == -1) return;
    list[index] = updatedPlan;
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    plans[patientId] = list;
    state = state.copyWith(medicationPlans: plans, errorMessage: '');
    unawaited(_repository.save(state));
  }

  void archiveMedicationPlan(String patientId, String planId) {
    final plans = Map<String, List<MedicationPlan>>.from(state.medicationPlans);
    final list = <MedicationPlan>[
      ...(plans[patientId] ?? const <MedicationPlan>[])
    ];
    final index = list.indexWhere((plan) => plan.id == planId);
    if (index == -1) return;
    list[index] = list[index].copyWith(isActive: false);
    plans[patientId] = list;
    state = state.copyWith(medicationPlans: plans, errorMessage: '');
    unawaited(_repository.save(state));
  }

  DateTime? _nearestOpenScheduledDoseForPlan({
    required String patientId,
    required MedicationPlan plan,
    required DateTime takenAt,
  }) {
    final day = _dayStart(takenAt);
    final doses = _scheduledDosesForPlanOnDay(plan, day);
    final used = medicationIntakesForPatient(patientId)
        .where((entry) =>
            entry.medicationPlanId == plan.id &&
            entry.scheduledAtIso != null &&
            _isSameDay(DateTime.tryParse(entry.takenAtIso) ?? takenAt, day))
        .map((entry) => entry.scheduledAtIso!)
        .toSet();
    final open = doses
        .where((dose) => !used.contains(dose.scheduledAt.toIso8601String()))
        .toList();
    if (open.isEmpty) return null;
    open.sort((a, b) {
      final aDiff = (a.scheduledAt.millisecondsSinceEpoch -
              takenAt.millisecondsSinceEpoch)
          .abs();
      final bDiff = (b.scheduledAt.millisecondsSinceEpoch -
              takenAt.millisecondsSinceEpoch)
          .abs();
      return aDiff.compareTo(bDiff);
    });
    return open.first.scheduledAt;
  }

  String recordMedicationIntake({
    required String patientId,
    required String planId,
    required DateTime takenAt,
    DateTime? scheduledAt,
    String? note,
  }) {
    final now = DateTime.now();
    if (!_isSameDay(takenAt, now)) {
      throw ArgumentError('Only same-day medication logging is allowed.');
    }
    final plan = medicationPlanById(patientId, planId);
    if (plan == null || !plan.isActive) {
      throw StateError('Medication plan is unavailable.');
    }

    DateTime? resolvedScheduledAt;
    MedicationIntakeStatus status = MedicationIntakeStatus.onTime;

    if (!plan.isPrn) {
      if (scheduledAt != null && !_isSameDay(scheduledAt, now)) {
        throw ArgumentError('Scheduled time must be on the current day.');
      }
      resolvedScheduledAt = scheduledAt ??
          _nearestOpenScheduledDoseForPlan(
            patientId: patientId,
            plan: plan,
            takenAt: takenAt,
          );
      if (resolvedScheduledAt == null) {
        throw StateError('No remaining scheduled doses for today.');
      }
      final diffMinutes =
          takenAt.difference(resolvedScheduledAt).inMinutes.abs();
      status = diffMinutes <= 120
          ? MedicationIntakeStatus.onTime
          : MedicationIntakeStatus.late;
    }

    final entry = MedicationIntakeEntry(
      id: _generateId('med_intake'),
      patientId: patientId,
      medicationPlanId: planId,
      scheduledAtIso: resolvedScheduledAt?.toIso8601String(),
      takenAtIso: takenAt.toIso8601String(),
      status: status,
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
    );

    final intakes =
        Map<String, List<MedicationIntakeEntry>>.from(state.medicationIntakes);
    final list = <MedicationIntakeEntry>[
      ...(intakes[patientId] ?? const <MedicationIntakeEntry>[]),
      entry
    ];
    list.sort((a, b) => b.takenAtIso.compareTo(a.takenAtIso));
    intakes[patientId] = list;
    state = state.copyWith(medicationIntakes: intakes, errorMessage: '');
    unawaited(_repository.save(state));
    return entry.id;
  }

  bool _planAppliesOnDay(MedicationPlan plan, DateTime day) {
    if (!plan.isActive) return false;
    final start = DateTime.tryParse(plan.startDateIso);
    final dayDate = _dayStart(day);
    if (start != null && dayDate.isBefore(_dayStart(start))) {
      return false;
    }
    final end =
        plan.endDateIso == null ? null : DateTime.tryParse(plan.endDateIso!);
    if (end != null && dayDate.isAfter(_dayStart(end))) {
      return false;
    }
    return true;
  }

  List<_ScheduledDose> _scheduledDosesForPlanOnDay(
      MedicationPlan plan, DateTime day) {
    if (plan.isPrn || !_planAppliesOnDay(plan, day)) {
      return const <_ScheduledDose>[];
    }
    final doses = <_ScheduledDose>[];
    for (final hhmm in plan.dailyTimes) {
      try {
        doses.add(
          _ScheduledDose(
            plan: plan,
            scheduledAt: _dayAndTime(day, hhmm),
          ),
        );
      } on FormatException {
        continue;
      }
    }
    doses.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return doses;
  }

  List<_ScheduledDose> _buildScheduledDosesForDay(
      String patientId, DateTime day) {
    final doses = <_ScheduledDose>[];
    for (final plan in activeMedicationPlansForPatient(patientId)) {
      doses.addAll(_scheduledDosesForPlanOnDay(plan, day));
    }
    doses.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return doses;
  }

  List<MedicationIntakeEntry> _intakesForPatientOnDay(
      String patientId, DateTime day) {
    return medicationIntakesForPatient(patientId).where((entry) {
      final takenAt = DateTime.tryParse(entry.takenAtIso);
      if (takenAt == null) return false;
      return _isSameDay(takenAt, day);
    }).toList();
  }

  List<MedicationDoseScheduleItem> todayMedicationSchedule(String patientId,
      {DateTime? now}) {
    final current = now ?? DateTime.now();
    final day = _dayStart(current);
    final doses = _buildScheduledDosesForDay(patientId, day);
    final intakesToday = _intakesForPatientOnDay(patientId, day);

    final intakeByScheduledIso = <String, MedicationIntakeEntry>{};
    for (final intake in intakesToday) {
      final scheduledIso = intake.scheduledAtIso;
      if (scheduledIso == null) continue;
      final existing = intakeByScheduledIso[scheduledIso];
      if (existing == null) {
        intakeByScheduledIso[scheduledIso] = intake;
        continue;
      }
      final existingTaken = DateTime.tryParse(existing.takenAtIso);
      final currentTaken = DateTime.tryParse(intake.takenAtIso);
      if (existingTaken == null || currentTaken == null) continue;
      if (currentTaken.isAfter(existingTaken)) {
        intakeByScheduledIso[scheduledIso] = intake;
      }
    }

    final schedule = <MedicationDoseScheduleItem>[];
    for (final dose in doses) {
      final key = dose.scheduledAt.toIso8601String();
      final matchedIntake = intakeByScheduledIso[key];
      if (matchedIntake != null) {
        schedule.add(
          MedicationDoseScheduleItem(
            patientId: patientId,
            medicationPlanId: dose.plan.id,
            medicationName: dose.plan.name,
            dosage: dose.plan.dosage,
            instructions: dose.plan.instructions,
            scheduledAt: dose.scheduledAt,
            status: matchedIntake.status == MedicationIntakeStatus.onTime
                ? MedicationDoseStatus.onTime
                : MedicationDoseStatus.late,
            takenAt: DateTime.tryParse(matchedIntake.takenAtIso),
            isPrn: false,
          ),
        );
        continue;
      }
      final overdue =
          current.isAfter(dose.scheduledAt.add(const Duration(minutes: 120)));
      schedule.add(
        MedicationDoseScheduleItem(
          patientId: patientId,
          medicationPlanId: dose.plan.id,
          medicationName: dose.plan.name,
          dosage: dose.plan.dosage,
          instructions: dose.plan.instructions,
          scheduledAt: dose.scheduledAt,
          status:
              overdue ? MedicationDoseStatus.overdue : MedicationDoseStatus.due,
          takenAt: null,
          isPrn: false,
        ),
      );
    }

    final prnPlansById = {
      for (final plan
          in activeMedicationPlansForPatient(patientId).where((p) => p.isPrn))
        plan.id: plan,
    };
    for (final intake in intakesToday.where((e) => e.scheduledAtIso == null)) {
      final plan = prnPlansById[intake.medicationPlanId];
      if (plan == null) continue;
      final takenAt = DateTime.tryParse(intake.takenAtIso);
      if (takenAt == null) continue;
      schedule.add(
        MedicationDoseScheduleItem(
          patientId: patientId,
          medicationPlanId: plan.id,
          medicationName: plan.name,
          dosage: plan.dosage,
          instructions: plan.instructions,
          scheduledAt: takenAt,
          status: MedicationDoseStatus.taken,
          takenAt: takenAt,
          isPrn: true,
        ),
      );
    }

    schedule.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return schedule;
  }

  MedicationAdherenceSummary todayAdherenceSummary(String patientId,
      {DateTime? now}) {
    final schedule = todayMedicationSchedule(patientId, now: now)
        .where((d) => !d.isPrn)
        .toList();
    var onTime = 0;
    var late = 0;
    var overdue = 0;
    for (final dose in schedule) {
      switch (dose.status) {
        case MedicationDoseStatus.onTime:
          onTime += 1;
          break;
        case MedicationDoseStatus.late:
          late += 1;
          break;
        case MedicationDoseStatus.overdue:
          overdue += 1;
          break;
        case MedicationDoseStatus.due:
        case MedicationDoseStatus.taken:
          break;
      }
    }
    return MedicationAdherenceSummary(
      onTime: onTime,
      late: late,
      overdue: overdue,
      totalDue: schedule.length,
    );
  }

  List<MedicationIntakeEntry> recentMedicationActivity(
      String patientId, int nDays,
      {DateTime? now}) {
    final current = now ?? DateTime.now();
    final earliest = _dayStart(current.subtract(Duration(days: nDays)));
    final list = medicationIntakesForPatient(patientId).where((entry) {
      final takenAt = DateTime.tryParse(entry.takenAtIso);
      if (takenAt == null) return false;
      return !takenAt.isBefore(earliest);
    }).toList();
    list.sort((a, b) => b.takenAtIso.compareTo(a.takenAtIso));
    return list;
  }

  List<String> overdueMedicationLabelsToday(String patientId, {DateTime? now}) {
    return todayMedicationSchedule(patientId, now: now)
        .where((dose) => dose.status == MedicationDoseStatus.overdue)
        .map((dose) =>
            '${dose.medicationName} @ ${dose.scheduledAt.hour.toString().padLeft(2, '0')}:${dose.scheduledAt.minute.toString().padLeft(2, '0')}')
        .toList();
  }

  Map<String, dynamic> soapContextForPatient(String patientId) {
    final latest = logsForPatient(patientId)
        .where((e) => e.processingStatus == PatientLogProcessingStatus.complete)
        .cast<PatientLogEntry?>()
        .firstWhere((_) => true, orElse: () => null);
    final adherence = todayAdherenceSummary(patientId);
    return <String, dynamic>{
      'latest_depression_marker':
          latest?.depressionMarker.name ?? DepressionMarker.low.name,
      'latest_depression_score': latest?.depressionScore ?? 0.0,
      'med_adherence_today': adherence.toJson(),
      'overdue_medications': overdueMedicationLabelsToday(patientId),
    };
  }

  PatientLogEntry? latestPatientLog(String patientId) {
    final logs = logsForPatient(patientId);
    if (logs.isEmpty) return null;
    return logs.first;
  }

  double? latestPatientScore(String patientId) {
    final logs = logsForPatient(patientId)
        .where((e) => e.processingStatus == PatientLogProcessingStatus.complete)
        .toList();
    if (logs.isEmpty) return null;
    return logs.first.baselineScore;
  }

  List<double> scoreTrend(String patientId, int nEntries) {
    final logs = logsForPatient(patientId)
        .where((e) => e.processingStatus == PatientLogProcessingStatus.complete)
        .take(nEntries)
        .toList()
        .reversed;
    return logs.map((e) => e.baselineScore).toList();
  }

  EdgeMetrics? featureBreakdown(String logId) {
    return logById(logId)?.metricsSnapshot;
  }

  PatientLogEntry? logById(String logId) {
    for (final logs in state.patientLogs.values) {
      for (final log in logs) {
        if (log.id == logId) {
          return log;
        }
      }
    }
    return null;
  }

  String riskBadgeForPatient(String patientId) {
    final latest = logsForPatient(patientId)
        .where((e) => e.processingStatus == PatientLogProcessingStatus.complete)
        .cast<PatientLogEntry?>()
        .firstWhere((_) => true, orElse: () => null);
    if (latest == null) return 'stable';
    final metrics = latest.metricsSnapshot;
    if (latest.depressionMarker == DepressionMarker.high ||
        metrics.fatigueScore >= 0.60 ||
        metrics.anxietyScore >= 0.60) {
      return 'high risk';
    }
    if (latest.depressionMarker == DepressionMarker.watch ||
        metrics.fatigueScore >= 0.40 ||
        metrics.anxietyScore >= 0.40) {
      return 'watch';
    }
    return 'stable';
  }

  void purgeData() {
    state = state.copyWith(
      errorMessage: '',
      activePatientId: null,
      patients: const <PatientProfile>[],
      patientLogs: const <String, List<PatientLogEntry>>{},
      clinicianEntries: const <String, List<ClinicianEntry>>{},
      medicationPlans: const <String, List<MedicationPlan>>{},
      medicationIntakes: const <String, List<MedicationIntakeEntry>>{},
      healthSignals: const <String, List<HealthSignalEntry>>{},
      recordingSession: RecordingSessionDraft.empty,
    );
    unawaited(_repository.save(state));
  }
}
