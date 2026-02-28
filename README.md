# Healthcare Continuum App

Privacy-first healthcare monitoring app built with Flutter.  
It supports two role-based experiences:
- `Patient`: diary logging, medication tracking, and health signal entry.
- `Clinician`: patient oversight, risk monitoring, and SOAP note generation.

## Overview

The app combines:
- On-device eye and face signal extraction (camera-based).
- Audio diary and dictation recording.
- Cloud-assisted transcription/entity extraction/SOAP generation (Azure).
- Local-first state persistence with demo datasets and migration support.

## Feature Walkthrough

### 1. Role Selection
- Choose `I am a Patient` or `I am a Clinician`.
- Routes users into the correct dashboard and state context.

### 2. Patient Features
- **Patient Dashboard**
  - Recent diary logs with status (`recording`, `processing`, `complete`, `failed`).
  - Health signal capture (blood pressure + heart rate + optional note).
  - Medication schedule for today with status badges (`due`, `on-time`, `late`, `overdue`, `taken`).
  - Medication intake actions:
    - `Take now`
    - `Log earlier` (same-day backfill)
- **Patient Diary**
  - Front-camera preview (when edge tracking is enabled).
  - Audio recording workflow: `Start Log` / `Stop Log`.
  - Max recording duration: 5 minutes.
  - Optional note saved with each log.
  - Log history with transcript preview and processing state.
- **Privacy guardrails**
  - Patients do not see clinician-only feature analytics breakdown.

### 3. Clinician Features
- **Clinician Patient List**
  - View all patient profiles.
  - Latest score and risk badge per patient (`stable`, `watch`, `high risk`).
  - Create new patient profiles.
- **Clinician Patient Detail**
  - 7-log trend chart of baseline score.
  - Timeline of log records with status and transcript expansion.
  - Depression marker and score for completed logs.
  - Feature breakdown modal:
    - Blink rate
    - Fatigue/anxiety scores
    - Tracking uptime and sample rate
    - Eye closure rate
    - Gaze drift/fixation instability
    - Tracking quality and baseline score
  - Medication management:
    - Create medication plans (scheduled or PRN)
    - Archive active plans
    - View adherence summary (on-time/late/overdue/total due)
  - SOAP dictation:
    - Record clinician dictation
    - Transcribe and generate SOAP note
    - Store note in patient timeline

### 4. Settings and Compliance
- Toggle edge eye tracking on/off.
- Purge all local health data.
- Load oncology demo dataset (3 patient personas: stable/moderate/severe).
- Azure integration status display.
- Connection tests for:
  - Speech service
  - Text Analytics service
  - OpenAI service

## AI and Scoring Pipeline

### Edge tracking (on device)
- Uses camera + ML Kit face detection.
- Computes anonymized metrics (no raw video persisted):
  - Blinks per minute
  - Fatigue score
  - Anxiety score
  - Tracking quality and stability signals

### Patient log processing
- Audio is transcribed via Azure Speech.
- Entities are extracted via Azure Text Analytics.
- If Text Analytics fails, local entity fallback is used.
- Log finalization computes:
  - Sentiment risk from transcript cues
  - Adjusted fatigue/anxiety values
  - Depression score
  - Depression marker (`low`, `watch`, `high`)

### SOAP generation
- Transcribes clinician dictation via Azure Speech.
- Attempts SOAP generation with Azure OpenAI.
- If OpenAI generation fails, a structured local SOAP fallback template is saved.

## Medication Logic

- Scheduled dose classification:
  - `on-time`: intake within 120 minutes of scheduled time
  - `late`: intake outside 120-minute window
  - `overdue`: current time is 120+ minutes past scheduled and not taken
- Same-day intake logging is enforced.
- Supports PRN plans and PRN intake tracking.

## Data Storage and Startup Behavior

- Local persistence via `SharedPreferences`.
- Stored domains:
  - patients
  - logs
  - clinician entries
  - medication plans/intakes
  - health signals
  - in-progress recording draft
- First run seeds oncology demo data when no modern persisted state exists.
- Legacy migration path converts old diary/SOAP keys into current model.

## Tech Stack

- Flutter + Dart
- `flutter_riverpod` for state management
- `shared_preferences` for local persistence
- `camera` + `google_mlkit_face_detection` for edge metrics
- `record` for audio capture
- `http` for Azure API calls
- `fl_chart` for trend visualization
- `flutter_dotenv` for environment configuration

## Environment Variables

Create `.env` from `.env.example` and configure:

```env
AZURE_SPEECH_ENDPOINT=https://<region>.stt.speech.microsoft.com
AZURE_SPEECH_KEY=your_speech_key
AZURE_TA_ENDPOINT=https://<your-text-analytics-resource>.cognitiveservices.azure.com/
AZURE_TA_KEY=your_text_analytics_key
AZURE_OPENAI_ENDPOINT=https://<your-openai-resource>.cognitiveservices.azure.com/
AZURE_OPENAI_KEY=your_openai_key
AZURE_OPENAI_DEPLOYMENT=your_chat_model_deployment_name
AZURE_OPENAI_API_VERSION=2024-10-21
```

## Run Locally

```bash
flutter pub get
flutter run
```

## Run Tests

```bash
flutter test
```

## Notes

- Android manifest already declares camera, microphone, and internet permissions.
- For iOS, ensure microphone/camera usage descriptions are configured in `Info.plist` for real-device recording/camera use.
