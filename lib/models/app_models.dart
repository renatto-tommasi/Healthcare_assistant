class EdgeMetrics {
  const EdgeMetrics({
    required this.blinksPerMinute,
    required this.fatigueScore,
    required this.anxietyScore,
    required this.totalBlinks,
  });

  final double blinksPerMinute;
  final double fatigueScore;
  final double anxietyScore;
  final int totalBlinks;

  Map<String, dynamic> toJson() => {
        'blink_rate_bpm': blinksPerMinute,
        'fatigue_score': fatigueScore,
        'anxiety_score': anxietyScore,
        'total_blinks': totalBlinks,
      };

  double get baselineScore =>
      (100 * (1 - ((fatigueScore + anxietyScore) / 2))).clamp(0, 100).toDouble();

  static const empty = EdgeMetrics(
    blinksPerMinute: 0,
    fatigueScore: 0,
    anxietyScore: 0,
    totalBlinks: 0,
  );
}

enum UserRole { patient, clinician }

class TrendData {
  const TrendData({
    required this.day,
    required this.mood,
    required this.blinkRate,
  });

  final String day;
  final double mood;
  final double blinkRate;

  Map<String, dynamic> toJson() => {
        'day': day,
        'mood': mood,
        'blinkRate': blinkRate,
      };

  factory TrendData.fromJson(Map<String, dynamic> json) {
    return TrendData(
      day: json['day'] as String? ?? '',
      mood: (json['mood'] as num? ?? 0).toDouble(),
      blinkRate: (json['blinkRate'] as num? ?? 0).toDouble(),
    );
  }
}

class PatientAlert {
  const PatientAlert({
    required this.id,
    required this.name,
    required this.alert,
  });

  final String id;
  final String name;
  final String alert;
}

class AppState {
  const AppState({
    required this.role,
    required this.selectedPatientId,
    required this.edgeTrackingEnabled,
    required this.diarySummary,
    required this.soapNote,
    required this.errorMessage,
    required this.metrics,
    required this.trends,
    required this.patientAlerts,
  });

  final UserRole? role;
  final String? selectedPatientId;
  final bool edgeTrackingEnabled;
  final String diarySummary;
  final String soapNote;
  final String errorMessage;
  final EdgeMetrics metrics;
  final List<TrendData> trends;
  final List<PatientAlert> patientAlerts;

  factory AppState.initial() => AppState(
        role: null,
        selectedPatientId: null,
        edgeTrackingEnabled: true,
        diarySummary: '',
        soapNote: '',
        errorMessage: '',
        metrics: EdgeMetrics.empty,
        trends: const [],
        patientAlerts: const [],
      );

  AppState copyWith({
    UserRole? role,
    String? selectedPatientId,
    bool? edgeTrackingEnabled,
    String? diarySummary,
    String? soapNote,
    String? errorMessage,
    EdgeMetrics? metrics,
    List<TrendData>? trends,
    List<PatientAlert>? patientAlerts,
  }) {
    return AppState(
      role: role ?? this.role,
      selectedPatientId: selectedPatientId ?? this.selectedPatientId,
      edgeTrackingEnabled: edgeTrackingEnabled ?? this.edgeTrackingEnabled,
      diarySummary: diarySummary ?? this.diarySummary,
      soapNote: soapNote ?? this.soapNote,
      errorMessage: errorMessage ?? this.errorMessage,
      metrics: metrics ?? this.metrics,
      trends: trends ?? this.trends,
      patientAlerts: patientAlerts ?? this.patientAlerts,
    );
  }
}
