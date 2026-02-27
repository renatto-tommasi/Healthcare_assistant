import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/app_models.dart';

class MentalHealthEdgeTracker {
  MentalHealthEdgeTracker()
      : _faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            enableClassification: true,
            performanceMode: FaceDetectorMode.fast,
          ),
        );

  CameraController? _cameraController;
  final FaceDetector _faceDetector;
  bool _processingFrame = false;
  bool _lastEyesClosed = false;
  int _blinkCount = 0;
  DateTime? _sessionStartedAt;
  int _totalProcessedFrames = 0;
  int _validFaceFrames = 0;
  int _closedEyeFrames = 0;
  double _runningDriftDegrees = 0;
  double _runningInstabilityDegrees = 0;
  double? _baselineYaw;
  double? _baselinePitch;
  double? _lastYaw;
  double? _lastPitch;
  DateTime? _lastFrameAt;
  final List<double> _sampleIntervalsMs = <double>[];
  int _framesSinceNotify = 0;

  CameraController? get controller => _cameraController;

  Future<void> initializeFrontCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => throw StateError('No front-facing camera available.'),
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await _cameraController!.initialize();
    beginLogSession();
  }

  void beginLogSession() {
    _processingFrame = false;
    _lastEyesClosed = false;
    _blinkCount = 0;
    _totalProcessedFrames = 0;
    _validFaceFrames = 0;
    _closedEyeFrames = 0;
    _runningDriftDegrees = 0;
    _runningInstabilityDegrees = 0;
    _baselineYaw = null;
    _baselinePitch = null;
    _lastYaw = null;
    _lastPitch = null;
    _lastFrameAt = null;
    _sampleIntervalsMs.clear();
    _framesSinceNotify = 0;
    _sessionStartedAt = DateTime.now();
  }

  EdgeMetrics endLogSession() {
    return getAnonymizedMetrics();
  }

  Future<void> startFaceTrackingStream(VoidCallback onMetricsUpdated) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('Camera not initialized.');
    }
    if (controller.value.isStreamingImages) {
      return;
    }

    await controller.startImageStream((cameraImage) async {
      if (_processingFrame) return;
      _processingFrame = true;
      try {
        final now = DateTime.now();
        _totalProcessedFrames += 1;
        if (_lastFrameAt != null) {
          _sampleIntervalsMs
              .add(now.difference(_lastFrameAt!).inMilliseconds.toDouble());
          if (_sampleIntervalsMs.length > 120) {
            _sampleIntervalsMs.removeAt(0);
          }
        }
        _lastFrameAt = now;

        final inputImage = _cameraImageToInputImage(cameraImage, controller);
        if (inputImage == null) {
          return;
        }
        final faces = await _faceDetector.processImage(inputImage);
        if (faces.isEmpty) return;
        _validFaceFrames += 1;
        _framesSinceNotify += 1;

        final face = faces.first;
        final left = face.leftEyeOpenProbability ?? 1;
        final right = face.rightEyeOpenProbability ?? 1;
        final eyesClosed = left < 0.35 && right < 0.35;
        if (eyesClosed) {
          _closedEyeFrames += 1;
        }

        final yaw = face.headEulerAngleY ?? 0;
        final pitch = face.headEulerAngleX ?? 0;
        _baselineYaw ??= yaw;
        _baselinePitch ??= pitch;
        final drift =
            ((yaw - _baselineYaw!).abs() + (pitch - _baselinePitch!).abs()) / 2;
        _runningDriftDegrees =
            ((_runningDriftDegrees * (_validFaceFrames - 1)) + drift) /
                _validFaceFrames;

        if (_lastYaw != null && _lastPitch != null) {
          final instability =
              ((yaw - _lastYaw!).abs() + (pitch - _lastPitch!).abs()) / 2;
          _runningInstabilityDegrees =
              ((_runningInstabilityDegrees * (_validFaceFrames - 1)) +
                      instability) /
                  _validFaceFrames;
        }
        _lastYaw = yaw;
        _lastPitch = pitch;

        if (!eyesClosed && _lastEyesClosed) {
          _blinkCount += 1;
          _framesSinceNotify = 0;
          onMetricsUpdated();
        }
        _lastEyesClosed = eyesClosed;
        if (_framesSinceNotify >= 15) {
          _framesSinceNotify = 0;
          onMetricsUpdated();
        }
      } on PlatformException {
        // Skip malformed or unsupported frames instead of crashing stream processing.
      } on ArgumentError {
        // Frame conversion can fail transiently during camera warmup on some devices.
      } finally {
        _processingFrame = false;
      }
    });
  }

  InputImage? _cameraImageToInputImage(
    CameraImage image,
    CameraController controller,
  ) {
    if (image.planes.isEmpty) {
      return null;
    }
    final writeBuffer = WriteBuffer();
    for (final plane in image.planes) {
      writeBuffer.putUint8List(plane.bytes);
    }
    final bytes = writeBuffer.done().buffer.asUint8List();
    final size = Size(image.width.toDouble(), image.height.toDouble());

    final rotation = InputImageRotationValue.fromRawValue(
          controller.description.sensorOrientation,
        ) ??
        InputImageRotation.rotation0deg;
    final parsedFormat = InputImageFormatValue.fromRawValue(image.format.raw);
    if (parsedFormat == null ||
        (parsedFormat != InputImageFormat.nv21 &&
            parsedFormat != InputImageFormat.bgra8888 &&
            parsedFormat != InputImageFormat.yuv_420_888)) {
      return null;
    }

    final metadata = InputImageMetadata(
      size: size,
      rotation: rotation,
      format: parsedFormat,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(
      bytes: Uint8List.fromList(bytes),
      metadata: metadata,
    );
  }

  EdgeMetrics getAnonymizedMetrics() {
    final startedAt = _sessionStartedAt;
    if (startedAt == null) return EdgeMetrics.empty;

    final elapsedMinutes =
        DateTime.now().difference(startedAt).inSeconds.clamp(1, 36000) / 60;
    final bpm = _blinkCount / elapsedMinutes;
    final fatigueScore = (bpm < 8 ? (8 - bpm) / 8 : 0).clamp(0, 1).toDouble();
    final anxietyScore =
        (bpm > 30 ? (bpm - 30) / 30 : 0).clamp(0, 1).toDouble();
    final uptime = _totalProcessedFrames == 0
        ? 0.0
        : (_validFaceFrames / _totalProcessedFrames) * 100;
    final eyeClosureRate = _validFaceFrames == 0
        ? 0.0
        : (_closedEyeFrames / _validFaceFrames) * 100;
    final sampleRateHz = _sampleIntervalsMs.isEmpty
        ? 0.0
        : 1000 /
            (_sampleIntervalsMs.reduce((a, b) => a + b) /
                _sampleIntervalsMs.length);
    final normalizedDrift = (_runningDriftDegrees / 20).clamp(0, 1).toDouble();
    final normalizedInstability =
        (_runningInstabilityDegrees / 10).clamp(0, 1).toDouble();
    final quality = (0.5 * (uptime / 100) +
            0.3 * (1 - normalizedDrift) +
            0.2 * (1 - normalizedInstability))
        .clamp(0, 1)
        .toDouble();

    return EdgeMetrics(
      blinksPerMinute: bpm,
      fatigueScore: fatigueScore,
      anxietyScore: anxietyScore,
      totalBlinks: _blinkCount,
      trackingUptimePercent: uptime,
      sampleRateHz: sampleRateHz,
      eyeClosureRatePercent: eyeClosureRate,
      gazeDriftDegrees: _runningDriftDegrees,
      fixationInstabilityDegrees: _runningInstabilityDegrees,
      trackingQualityScore: quality,
    );
  }

  Future<void> dispose() async {
    if (_cameraController?.value.isStreamingImages == true) {
      await _cameraController?.stopImageStream();
    }
    await _cameraController?.dispose();
    await _faceDetector.close();
  }
}
