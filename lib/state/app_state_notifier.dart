import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../repositories/local_app_state_repository.dart';

class AppStateNotifier extends StateNotifier<AppState> {
  AppStateNotifier(this._repository) : super(AppState.initial()) {
    unawaited(loadFromDisk());
  }

  final LocalAppStateRepository _repository;

  Future<void> loadFromDisk() async {
    final snapshot = await _repository.load();
    final alerts = _derivePatientAlerts(
      state.metrics,
      snapshot.trends,
      snapshot.diarySummary.isNotEmpty,
    );

    state = state.copyWith(
      edgeTrackingEnabled: snapshot.edgeTrackingEnabled,
      diarySummary: snapshot.diarySummary,
      soapNote: snapshot.soapNote,
      selectedPatientId: snapshot.selectedPatientId,
      trends: snapshot.trends,
      patientAlerts: alerts,
    );
  }

  List<PatientAlert> _derivePatientAlerts(
    EdgeMetrics metrics,
    List<TrendData> trends,
    bool hasDiary,
  ) {
    String alert;
    if (!hasDiary) {
      alert = 'No diary data recorded yet';
    } else if (metrics.fatigueScore >= 0.60) {
      alert = 'High fatigue score detected';
    } else if (metrics.anxietyScore >= 0.60) {
      alert = 'High anxiety score detected';
    } else if (trends.length >= 2 && trends.last.mood < trends[trends.length - 2].mood) {
      alert = 'Mood trend decreased since last entry';
    } else {
      alert = 'Stable metrics';
    }

    return [
      PatientAlert(
        id: 'self',
        name: 'Current Patient',
        alert: alert,
      ),
    ];
  }

  String _dayLabel(DateTime now) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[now.weekday - 1];
  }

  void _syncAlertsAndPersist() {
    state = state.copyWith(
      patientAlerts: _derivePatientAlerts(
        state.metrics,
        state.trends,
        state.diarySummary.isNotEmpty,
      ),
    );
    unawaited(_repository.save(state));
  }

  void setRole(UserRole role) {
    state = state.copyWith(role: role, errorMessage: '');
    _syncAlertsAndPersist();
  }

  void setSelectedPatient(String id) {
    state = state.copyWith(selectedPatientId: id, errorMessage: '');
    _syncAlertsAndPersist();
  }

  void setMetrics(EdgeMetrics metrics) {
    state = state.copyWith(
      metrics: metrics,
      patientAlerts: _derivePatientAlerts(
        metrics,
        state.trends,
        state.diarySummary.isNotEmpty,
      ),
    );
  }

  void setDiarySummary(String summary) {
    final mood =
        (10 - ((state.metrics.fatigueScore + state.metrics.anxietyScore) * 5)).clamp(1, 10);
    final entry = TrendData(
      day: _dayLabel(DateTime.now()),
      mood: mood.toDouble(),
      blinkRate: state.metrics.blinksPerMinute,
    );

    final updatedTrends = List<TrendData>.from(state.trends);
    if (updatedTrends.isNotEmpty && updatedTrends.last.day == entry.day) {
      updatedTrends[updatedTrends.length - 1] = entry;
    } else {
      updatedTrends.add(entry);
    }
    while (updatedTrends.length > 7) {
      updatedTrends.removeAt(0);
    }

    state = state.copyWith(
      diarySummary: summary,
      trends: updatedTrends,
      errorMessage: '',
    );
    _syncAlertsAndPersist();
  }

  void setSoapNote(String soap) {
    state = state.copyWith(soapNote: soap, errorMessage: '');
    _syncAlertsAndPersist();
  }

  void setError(String error) {
    state = state.copyWith(errorMessage: error);
    _syncAlertsAndPersist();
  }

  void toggleEdgeTracking(bool enabled) {
    state = state.copyWith(edgeTrackingEnabled: enabled);
    _syncAlertsAndPersist();
  }

  void purgeData() {
    state = state.copyWith(
      diarySummary: '',
      soapNote: '',
      errorMessage: '',
      selectedPatientId: null,
      trends: const [],
    );
    _syncAlertsAndPersist();
  }
}
