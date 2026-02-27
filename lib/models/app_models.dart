enum UserRole { patient, clinician }

const Object _unset = Object();

class EdgeMetrics {
  const EdgeMetrics({
    required this.blinksPerMinute,
    required this.fatigueScore,
    required this.anxietyScore,
    required this.totalBlinks,
    required this.trackingUptimePercent,
    required this.sampleRateHz,
    required this.eyeClosureRatePercent,
    required this.gazeDriftDegrees,
    required this.fixationInstabilityDegrees,
    required this.trackingQualityScore,
  });

  final double blinksPerMinute;
  final double fatigueScore;
  final double anxietyScore;
  final int totalBlinks;
  final double trackingUptimePercent;
  final double sampleRateHz;
  final double eyeClosureRatePercent;
  final double gazeDriftDegrees;
  final double fixationInstabilityDegrees;
  final double trackingQualityScore;

  Map<String, dynamic> toJson() => {
        'blink_rate_bpm': blinksPerMinute,
        'fatigue_score': fatigueScore,
        'anxiety_score': anxietyScore,
        'total_blinks': totalBlinks,
        'tracking_uptime_percent': trackingUptimePercent,
        'sample_rate_hz': sampleRateHz,
        'eye_closure_rate_percent': eyeClosureRatePercent,
        'gaze_drift_degrees': gazeDriftDegrees,
        'fixation_instability_degrees': fixationInstabilityDegrees,
        'tracking_quality_score': trackingQualityScore,
      };

  factory EdgeMetrics.fromJson(Map<String, dynamic> json) {
    return EdgeMetrics(
      blinksPerMinute: (json['blink_rate_bpm'] as num? ?? 0).toDouble(),
      fatigueScore: (json['fatigue_score'] as num? ?? 0).toDouble(),
      anxietyScore: (json['anxiety_score'] as num? ?? 0).toDouble(),
      totalBlinks: (json['total_blinks'] as num? ?? 0).toInt(),
      trackingUptimePercent:
          (json['tracking_uptime_percent'] as num? ?? 0).toDouble(),
      sampleRateHz: (json['sample_rate_hz'] as num? ?? 0).toDouble(),
      eyeClosureRatePercent:
          (json['eye_closure_rate_percent'] as num? ?? 0).toDouble(),
      gazeDriftDegrees: (json['gaze_drift_degrees'] as num? ?? 0).toDouble(),
      fixationInstabilityDegrees:
          (json['fixation_instability_degrees'] as num? ?? 0).toDouble(),
      trackingQualityScore:
          (json['tracking_quality_score'] as num? ?? 0).toDouble(),
    );
  }

  double get baselineScore => (100 * (1 - ((fatigueScore + anxietyScore) / 2)))
      .clamp(0, 100)
      .toDouble();

  static const empty = EdgeMetrics(
    blinksPerMinute: 0,
    fatigueScore: 0,
    anxietyScore: 0,
    totalBlinks: 0,
    trackingUptimePercent: 0,
    sampleRateHz: 0,
    eyeClosureRatePercent: 0,
    gazeDriftDegrees: 0,
    fixationInstabilityDegrees: 0,
    trackingQualityScore: 0,
  );
}

enum PatientLogProcessingStatus { recording, processing, complete, failed }

String _processingStatusToString(PatientLogProcessingStatus status) {
  switch (status) {
    case PatientLogProcessingStatus.recording:
      return 'recording';
    case PatientLogProcessingStatus.processing:
      return 'processing';
    case PatientLogProcessingStatus.complete:
      return 'complete';
    case PatientLogProcessingStatus.failed:
      return 'failed';
  }
}

PatientLogProcessingStatus _processingStatusFromString(String raw) {
  switch (raw) {
    case 'recording':
      return PatientLogProcessingStatus.recording;
    case 'processing':
      return PatientLogProcessingStatus.processing;
    case 'failed':
      return PatientLogProcessingStatus.failed;
    case 'complete':
    default:
      return PatientLogProcessingStatus.complete;
  }
}

class PatientProfile {
  const PatientProfile({
    required this.id,
    required this.displayName,
    required this.createdAtIso,
  });

  final String id;
  final String displayName;
  final String createdAtIso;

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'createdAtIso': createdAtIso,
      };

  factory PatientProfile.fromJson(Map<String, dynamic> json) {
    return PatientProfile(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      createdAtIso: json['createdAtIso'] as String? ?? '',
    );
  }
}

class PatientLogEntry {
  const PatientLogEntry({
    required this.id,
    required this.patientId,
    required this.startedAtIso,
    required this.endedAtIso,
    required this.durationSeconds,
    required this.audioPath,
    required this.patientNote,
    required this.transcript,
    required this.entitiesJson,
    required this.metricsSnapshot,
    required this.baselineScore,
    required this.processingStatus,
    required this.errorMessage,
  });

  final String id;
  final String patientId;
  final String startedAtIso;
  final String endedAtIso;
  final int durationSeconds;
  final String? audioPath;
  final String? patientNote;
  final String transcript;
  final Map<String, dynamic> entitiesJson;
  final EdgeMetrics metricsSnapshot;
  final double baselineScore;
  final PatientLogProcessingStatus processingStatus;
  final String? errorMessage;

  PatientLogEntry copyWith({
    String? id,
    String? patientId,
    String? startedAtIso,
    String? endedAtIso,
    int? durationSeconds,
    String? audioPath,
    String? patientNote,
    String? transcript,
    Map<String, dynamic>? entitiesJson,
    EdgeMetrics? metricsSnapshot,
    double? baselineScore,
    PatientLogProcessingStatus? processingStatus,
    Object? errorMessage = _unset,
  }) {
    return PatientLogEntry(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      startedAtIso: startedAtIso ?? this.startedAtIso,
      endedAtIso: endedAtIso ?? this.endedAtIso,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      audioPath: audioPath ?? this.audioPath,
      patientNote: patientNote ?? this.patientNote,
      transcript: transcript ?? this.transcript,
      entitiesJson: entitiesJson ?? this.entitiesJson,
      metricsSnapshot: metricsSnapshot ?? this.metricsSnapshot,
      baselineScore: baselineScore ?? this.baselineScore,
      processingStatus: processingStatus ?? this.processingStatus,
      errorMessage:
          errorMessage == _unset ? this.errorMessage : errorMessage as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'patientId': patientId,
        'startedAtIso': startedAtIso,
        'endedAtIso': endedAtIso,
        'durationSeconds': durationSeconds,
        'audioPath': audioPath,
        'patientNote': patientNote,
        'transcript': transcript,
        'entitiesJson': entitiesJson,
        'metricsSnapshot': metricsSnapshot.toJson(),
        'baselineScore': baselineScore,
        'processingStatus': _processingStatusToString(processingStatus),
        'errorMessage': errorMessage,
      };

  factory PatientLogEntry.fromJson(Map<String, dynamic> json) {
    final rawEntities = json['entitiesJson'];
    return PatientLogEntry(
      id: json['id'] as String? ?? '',
      patientId: json['patientId'] as String? ?? '',
      startedAtIso: json['startedAtIso'] as String? ?? '',
      endedAtIso: json['endedAtIso'] as String? ?? '',
      durationSeconds: (json['durationSeconds'] as num? ?? 0).toInt(),
      audioPath: json['audioPath'] as String?,
      patientNote: json['patientNote'] as String?,
      transcript: json['transcript'] as String? ?? '',
      entitiesJson: rawEntities is Map<String, dynamic>
          ? rawEntities
          : const <String, dynamic>{},
      metricsSnapshot: EdgeMetrics.fromJson(
        json['metricsSnapshot'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      ),
      baselineScore: (json['baselineScore'] as num? ?? 0).toDouble(),
      processingStatus: _processingStatusFromString(
        json['processingStatus'] as String? ?? 'complete',
      ),
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

class ClinicianEntry {
  const ClinicianEntry({
    required this.id,
    required this.patientId,
    required this.createdAtIso,
    required this.entryType,
    required this.content,
    required this.sourceLogId,
  });

  final String id;
  final String patientId;
  final String createdAtIso;
  final String entryType;
  final String content;
  final String? sourceLogId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'patientId': patientId,
        'createdAtIso': createdAtIso,
        'entryType': entryType,
        'content': content,
        'sourceLogId': sourceLogId,
      };

  factory ClinicianEntry.fromJson(Map<String, dynamic> json) {
    return ClinicianEntry(
      id: json['id'] as String? ?? '',
      patientId: json['patientId'] as String? ?? '',
      createdAtIso: json['createdAtIso'] as String? ?? '',
      entryType: json['entryType'] as String? ?? 'soap',
      content: json['content'] as String? ?? '',
      sourceLogId: json['sourceLogId'] as String?,
    );
  }
}

class RecordingSessionDraft {
  const RecordingSessionDraft({
    required this.isRecording,
    required this.patientId,
    required this.startedAtIso,
    required this.tempAudioPath,
    required this.optionalNoteDraft,
  });

  final bool isRecording;
  final String? patientId;
  final String? startedAtIso;
  final String? tempAudioPath;
  final String optionalNoteDraft;

  static const empty = RecordingSessionDraft(
    isRecording: false,
    patientId: null,
    startedAtIso: null,
    tempAudioPath: null,
    optionalNoteDraft: '',
  );

  RecordingSessionDraft copyWith({
    bool? isRecording,
    Object? patientId = _unset,
    Object? startedAtIso = _unset,
    Object? tempAudioPath = _unset,
    String? optionalNoteDraft,
  }) {
    return RecordingSessionDraft(
      isRecording: isRecording ?? this.isRecording,
      patientId: patientId == _unset ? this.patientId : patientId as String?,
      startedAtIso:
          startedAtIso == _unset ? this.startedAtIso : startedAtIso as String?,
      tempAudioPath:
          tempAudioPath == _unset ? this.tempAudioPath : tempAudioPath as String?,
      optionalNoteDraft: optionalNoteDraft ?? this.optionalNoteDraft,
    );
  }

  Map<String, dynamic> toJson() => {
        'isRecording': isRecording,
        'patientId': patientId,
        'startedAtIso': startedAtIso,
        'tempAudioPath': tempAudioPath,
        'optionalNoteDraft': optionalNoteDraft,
      };

  factory RecordingSessionDraft.fromJson(Map<String, dynamic> json) {
    return RecordingSessionDraft(
      isRecording: json['isRecording'] as bool? ?? false,
      patientId: json['patientId'] as String?,
      startedAtIso: json['startedAtIso'] as String?,
      tempAudioPath: json['tempAudioPath'] as String?,
      optionalNoteDraft: json['optionalNoteDraft'] as String? ?? '',
    );
  }
}

class AppState {
  const AppState({
    required this.role,
    required this.edgeTrackingEnabled,
    required this.errorMessage,
    required this.activePatientId,
    required this.patients,
    required this.patientLogs,
    required this.clinicianEntries,
    required this.recordingSession,
  });

  final UserRole? role;
  final bool edgeTrackingEnabled;
  final String errorMessage;
  final String? activePatientId;
  final List<PatientProfile> patients;
  final Map<String, List<PatientLogEntry>> patientLogs;
  final Map<String, List<ClinicianEntry>> clinicianEntries;
  final RecordingSessionDraft recordingSession;

  factory AppState.initial() => const AppState(
        role: null,
        edgeTrackingEnabled: true,
        errorMessage: '',
        activePatientId: null,
        patients: <PatientProfile>[],
        patientLogs: <String, List<PatientLogEntry>>{},
        clinicianEntries: <String, List<ClinicianEntry>>{},
        recordingSession: RecordingSessionDraft.empty,
      );

  AppState copyWith({
    Object? role = _unset,
    bool? edgeTrackingEnabled,
    String? errorMessage,
    Object? activePatientId = _unset,
    List<PatientProfile>? patients,
    Map<String, List<PatientLogEntry>>? patientLogs,
    Map<String, List<ClinicianEntry>>? clinicianEntries,
    RecordingSessionDraft? recordingSession,
  }) {
    return AppState(
      role: role == _unset ? this.role : role as UserRole?,
      edgeTrackingEnabled: edgeTrackingEnabled ?? this.edgeTrackingEnabled,
      errorMessage: errorMessage ?? this.errorMessage,
      activePatientId: activePatientId == _unset
          ? this.activePatientId
          : activePatientId as String?,
      patients: patients ?? this.patients,
      patientLogs: patientLogs ?? this.patientLogs,
      clinicianEntries: clinicianEntries ?? this.clinicianEntries,
      recordingSession: recordingSession ?? this.recordingSession,
    );
  }
}
