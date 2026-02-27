import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
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
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _cameraController!.initialize();
    _sessionStartedAt = DateTime.now();
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
        final inputImage = _cameraImageToInputImage(cameraImage, controller);
        final faces = await _faceDetector.processImage(inputImage);
        if (faces.isEmpty) return;

        final face = faces.first;
        final left = face.leftEyeOpenProbability ?? 1;
        final right = face.rightEyeOpenProbability ?? 1;
        final eyesClosed = left < 0.35 && right < 0.35;

        if (!eyesClosed && _lastEyesClosed) {
          _blinkCount += 1;
          onMetricsUpdated();
        }
        _lastEyesClosed = eyesClosed;
      } finally {
        _processingFrame = false;
      }
    });
  }

  InputImage _cameraImageToInputImage(
    CameraImage image,
    CameraController controller,
  ) {
    final bytes = image.planes.map((p) => p.bytes).expand((e) => e).toList();
    final size = Size(image.width.toDouble(), image.height.toDouble());

    final rotation = InputImageRotationValue.fromRawValue(
          controller.description.sensorOrientation,
        ) ??
        InputImageRotation.rotation0deg;
    final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
        InputImageFormat.nv21;

    final metadata = InputImageMetadata(
      size: size,
      rotation: rotation,
      format: format,
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
    final anxietyScore = (bpm > 30 ? (bpm - 30) / 30 : 0).clamp(0, 1).toDouble();

    return EdgeMetrics(
      blinksPerMinute: bpm,
      fatigueScore: fatigueScore,
      anxietyScore: anxietyScore,
      totalBlinks: _blinkCount,
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
