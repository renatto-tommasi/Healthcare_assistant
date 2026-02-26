# Unified Healthcare Continuum App (Flutter)

A privacy-first Flutter mobile application for patients and clinicians.

## Overview

This app provides a single mobile interface for two primary workflows:

- **Patient mode**
  - Uses the **front-facing camera only** for on-device eye-state analysis.
  - Tracks blink-derived mental health indicators locally (e.g., blinks per minute, fatigue/anxiety heuristics).
  - Records short diary audio clips and supports Azure-based transcription + health entity extraction.

- **Clinician mode**
  - Records clinician dictation.
  - Transcribes dictation through Azure Speech-to-Text.
  - Generates structured SOAP notes with Azure OpenAI using transcript context and local edge metrics.

## Privacy and Compliance Principles

1. **Edge processing only for camera frames**
   - Face/eye analysis is performed on-device using ML Kit.
   - Camera frames are processed in memory and are not uploaded or persisted by design.

2. **Synthetic data readiness**
   - The app supports mock response fallbacks for development/testing to avoid real PHI usage.

3. **No hardcoded cloud secrets**
   - Azure endpoints and keys are provided via compile-time environment variables.
   - Do not commit production credentials to source control.

## Tech Stack

- Flutter + Dart
- `camera` (front camera access)
- `google_mlkit_face_detection` (on-device face + eye open probability)
- `record` (audio capture)
- `http` (Azure REST calls)
- `flutter_riverpod` (state management)

## Implemented Modules

### 1) Edge Mental Health Tracker

- Initializes and uses `CameraLensDirection.front`.
- Streams camera frames to ML Kit face detector.
- Uses `leftEyeOpenProbability` and `rightEyeOpenProbability` for blink detection.
- Calculates local-only aggregate metrics:
  - Blink rate (BPM)
  - Fatigue score (simple heuristic)
  - Anxiety score (simple heuristic)

### 2) Patient Diary + Azure Integration

- Records a short patient audio clip.
- Sends audio to Azure Speech-to-Text.
- Sends transcript to Azure Text Analytics for Health.
- Displays extracted entities and transcript summary in the app.

### 3) Clinician Note Cleaner (SOAP)

- Records clinician dictation.
- Transcribes with Azure Speech-to-Text.
- Sends transcript + edge metrics to Azure OpenAI.
- Enforces strict SOAP structure in prompt constraints.


## App Navigation (Multi-Page)

The app now supports a full navigation flow with named routes:

- `/` → Role selection
- `/patient_dashboard` → Patient dashboard (baseline + synthetic trend charts)
- `/patient_diary` → Patient diary (front camera + diary recording)
- `/clinician_patients` → Clinician patient list with alert badges
- `/clinician_dictation` → Clinician dictation + SOAP generation
- `/settings` → Privacy controls (edge tracking toggle + data purge)

## Configuration

Provide Azure values at runtime/build via `--dart-define`:

```bash
flutter run \
  --dart-define=AZURE_SPEECH_ENDPOINT=https://<speech-endpoint> \
  --dart-define=AZURE_TA_ENDPOINT=https://<text-analytics-endpoint> \
  --dart-define=AZURE_OPENAI_ENDPOINT=https://<openai-endpoint> \
  --dart-define=AZURE_SPEECH_KEY=<speech-key> \
  --dart-define=AZURE_TA_KEY=<text-analytics-key> \
  --dart-define=AZURE_OPENAI_KEY=<openai-key>
```

If these values are omitted, the app uses mock behavior for safer local testing.

## Running the App

1. Ensure Flutter SDK is installed.
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Launch on a physical device/emulator (camera + microphone permissions required):
   ```bash
   flutter run
   ```

## Current Limitations / Notes

- The repository currently provides a functional scaffold and integration flow.
- Production healthcare deployments should add:
  - stronger device-level security controls,
  - audited logging policies,
  - managed secret delivery/token broker patterns,
  - robust error handling and test coverage.
