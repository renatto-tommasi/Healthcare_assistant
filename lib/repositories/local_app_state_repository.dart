import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_models.dart';

class PersistedAppSnapshot {
  const PersistedAppSnapshot({
    required this.edgeTrackingEnabled,
    required this.diarySummary,
    required this.soapNote,
    required this.selectedPatientId,
    required this.trends,
  });

  final bool edgeTrackingEnabled;
  final String diarySummary;
  final String soapNote;
  final String? selectedPatientId;
  final List<TrendData> trends;
}

class LocalAppStateRepository {
  static const _prefsEdgeTracking = 'edge_tracking_enabled';
  static const _prefsDiarySummary = 'diary_summary';
  static const _prefsSoapNote = 'soap_note';
  static const _prefsSelectedPatientId = 'selected_patient_id';
  static const _prefsTrends = 'trends_json';

  Future<PersistedAppSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final trendJsonList = prefs.getStringList(_prefsTrends) ?? const [];
    final trends = trendJsonList
        .map((item) => TrendData.fromJson(jsonDecode(item) as Map<String, dynamic>))
        .toList();
    return PersistedAppSnapshot(
      edgeTrackingEnabled: prefs.getBool(_prefsEdgeTracking) ?? true,
      diarySummary: prefs.getString(_prefsDiarySummary) ?? '',
      soapNote: prefs.getString(_prefsSoapNote) ?? '',
      selectedPatientId: prefs.getString(_prefsSelectedPatientId),
      trends: trends,
    );
  }

  Future<void> save(AppState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEdgeTracking, state.edgeTrackingEnabled);
    await prefs.setString(_prefsDiarySummary, state.diarySummary);
    await prefs.setString(_prefsSoapNote, state.soapNote);
    final selectedPatientId = state.selectedPatientId;
    if (selectedPatientId == null) {
      await prefs.remove(_prefsSelectedPatientId);
    } else {
      await prefs.setString(_prefsSelectedPatientId, selectedPatientId);
    }
    await prefs.setStringList(
      _prefsTrends,
      state.trends.map((t) => jsonEncode(t.toJson())).toList(),
    );
  }
}
