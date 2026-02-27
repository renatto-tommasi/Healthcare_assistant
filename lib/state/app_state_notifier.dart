import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../repositories/local_app_state_repository.dart';

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
      recordingSession: snapshot.recordingSession,
    );
  }

  String _generateId(String prefix) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(1 << 20).toRadixString(16);
    return '${prefix}_$now$suffix';
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
    final cleanedName = displayName.trim().isEmpty ? 'New Patient' : displayName.trim();
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
      recordingSession: state.recordingSession.copyWith(optionalNoteDraft: note),
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
    final duration = startedAt == null ? 0 : endedAt.difference(startedAt).inSeconds;
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
      processingStatus: PatientLogProcessingStatus.processing,
      errorMessage: null,
    );

    final updatedLogs = Map<String, List<PatientLogEntry>>.from(state.patientLogs);
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

  void finalizePatientLog({
    required String entryId,
    required String transcript,
    required Map<String, dynamic> entities,
    String? error,
  }) {
    final updatedLogs = Map<String, List<PatientLogEntry>>.from(state.patientLogs);
    for (final entry in updatedLogs.entries) {
      final index = entry.value.indexWhere((log) => log.id == entryId);
      if (index == -1) {
        continue;
      }
      final previous = entry.value[index];
      final status = error == null
          ? PatientLogProcessingStatus.complete
          : PatientLogProcessingStatus.failed;
      entry.value[index] = previous.copyWith(
        transcript: transcript,
        entitiesJson: entities,
        processingStatus: status,
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
    final entries = Map<String, List<ClinicianEntry>>.from(state.clinicianEntries);
    final list = <ClinicianEntry>[...(entries[patientId] ?? const <ClinicianEntry>[]), entry];
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
    if (metrics.fatigueScore >= 0.60 || metrics.anxietyScore >= 0.60) {
      return 'high risk';
    }
    if (metrics.fatigueScore >= 0.40 || metrics.anxietyScore >= 0.40) {
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
      recordingSession: RecordingSessionDraft.empty,
    );
    unawaited(_repository.save(state));
  }
}
