import 'package:healthcare_continuum_app/models/app_models.dart';
import 'package:healthcare_continuum_app/repositories/local_app_state_repository.dart';

class InMemoryLocalAppStateRepository extends LocalAppStateRepository {
  InMemoryLocalAppStateRepository({
    PersistedAppSnapshot? initialSnapshot,
  }) : _snapshot = initialSnapshot ?? emptySnapshot();

  PersistedAppSnapshot _snapshot;

  PersistedAppSnapshot get snapshot => _snapshot;

  @override
  Future<PersistedAppSnapshot> load() async => _snapshot;

  @override
  Future<void> save(AppState state) async {
    _snapshot = PersistedAppSnapshot(
      edgeTrackingEnabled: state.edgeTrackingEnabled,
      activePatientId: state.activePatientId,
      patients: state.patients,
      patientLogs: state.patientLogs,
      clinicianEntries: state.clinicianEntries,
      recordingSession: state.recordingSession,
    );
  }
}

PersistedAppSnapshot emptySnapshot({
  bool edgeTrackingEnabled = true,
  String? activePatientId,
  List<PatientProfile> patients = const <PatientProfile>[],
  Map<String, List<PatientLogEntry>> patientLogs =
      const <String, List<PatientLogEntry>>{},
  Map<String, List<ClinicianEntry>> clinicianEntries =
      const <String, List<ClinicianEntry>>{},
  RecordingSessionDraft recordingSession = RecordingSessionDraft.empty,
}) {
  return PersistedAppSnapshot(
    edgeTrackingEnabled: edgeTrackingEnabled,
    activePatientId: activePatientId,
    patients: patients,
    patientLogs: patientLogs,
    clinicianEntries: clinicianEntries,
    recordingSession: recordingSession,
  );
}
