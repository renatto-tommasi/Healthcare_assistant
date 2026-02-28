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
      medicationPlans: state.medicationPlans,
      medicationIntakes: state.medicationIntakes,
      healthSignals: state.healthSignals,
      recordingSession: state.recordingSession,
    );
  }

  @override
  Future<PersistedAppSnapshot> loadOncologyDemoData() async {
    _snapshot = oncologyDemoSnapshot(
      edgeTrackingEnabled: _snapshot.edgeTrackingEnabled,
    );
    return _snapshot;
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
  Map<String, List<MedicationPlan>> medicationPlans =
      const <String, List<MedicationPlan>>{},
  Map<String, List<MedicationIntakeEntry>> medicationIntakes =
      const <String, List<MedicationIntakeEntry>>{},
  Map<String, List<HealthSignalEntry>> healthSignals =
      const <String, List<HealthSignalEntry>>{},
  RecordingSessionDraft recordingSession = RecordingSessionDraft.empty,
}) {
  return PersistedAppSnapshot(
    edgeTrackingEnabled: edgeTrackingEnabled,
    activePatientId: activePatientId,
    patients: patients,
    patientLogs: patientLogs,
    clinicianEntries: clinicianEntries,
    medicationPlans: medicationPlans,
    medicationIntakes: medicationIntakes,
    healthSignals: healthSignals,
    recordingSession: recordingSession,
  );
}
