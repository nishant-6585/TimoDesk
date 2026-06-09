import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class CameraCaptureScreen extends StatefulWidget {
  final String fullName;
  final String role;
  final String notifyChannel;
  final Function(List<Uint8List> frames) onFramesCapture;

  const CameraCaptureScreen({
    Key? key,
    required this.fullName,
    required this.role,
    required this.notifyChannel,
    required this.onFramesCapture,
  }) : super(key: key);

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  late CameraController _cameraController;
  late FaceDetector _faceDetector;
  bool _isCameraReady = false;
  Face? _detectedFace;
  String _hint = 'Loading camera...';
  bool _isFaceStable = false;
  int _stableFrameCount = 0;
  bool _isCapturing = false;
  int _capturedFrames = 0;
  final List<Uint8List> _capturedImages = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _faceDetector = FaceDetector(options: FaceDetectorOptions());
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _hint = 'No camera found');
        return;
      }

      // Use front camera for selfie
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController.initialize();

      // Start analyzing frames
      _startFrameAnalysis();

      setState(() {
        _isCameraReady = true;
        _hint = 'Center your face';
      });
    } catch (e) {
      setState(() => _hint = 'Camera error: $e');
    }
  }

  void _startFrameAnalysis() {
    _cameraController.startImageStream((image) async {
      if (_isCapturing) return;

      try {
        final inputImage = _convertToInputImage(image);
        final faces = await _faceDetector.processImage(inputImage);

        setState(() {
          if (faces.isEmpty) {
            _detectedFace = null;
            _stableFrameCount = 0;
            _isFaceStable = false;
            _hint = 'No face detected';
          } else if (faces.length > 1) {
            _detectedFace = null;
            _stableFrameCount = 0;
            _isFaceStable = false;
            _hint = 'Only one face allowed';
          } else {
            final face = faces.first;
            _detectedFace = face;

            // Check if face is large enough (≥25% of frame height)
            final frameHeight = image.height.toDouble();
            final faceSize = face.boundingBox.height;
            final sizeFraction = faceSize / frameHeight;

            if (sizeFraction < 0.25) {
              _stableFrameCount = 0;
              _isFaceStable = false;
              _hint = 'Move closer';
            } else {
              // Check if roughly centered
              final centerX = face.boundingBox.center.dx;
              final centerY = face.boundingBox.center.dy;
              final frameWidth = image.width.toDouble();
              final frameHalfHeight = frameHeight / 2;

              final offCenterX = (centerX - frameWidth / 2).abs();
              const centerTolerance = 100.0;

              if (offCenterX > centerTolerance || centerY < frameHalfHeight * 0.7) {
                _stableFrameCount = 0;
                _isFaceStable = false;
                _hint = 'Center your face';
              } else {
                // Face is in good position, count stable frames (~0.5s at 30fps = 15 frames)
                _stableFrameCount++;
                if (_stableFrameCount >= 15) {
                  _isFaceStable = true;
                  _hint = 'Hold still... 3, 2, 1';
                  _autoCapture();
                } else {
                  _hint = 'Hold still (${(_stableFrameCount * 33 / 1000).toStringAsFixed(1)}s)';
                }
              }
            }
          }
        });
      } catch (e) {
        print('[CameraCapture] Frame analysis error: $e');
      }
    });
  }

  InputImage _convertToInputImage(CameraImage image) {
    final planes = image.planes;
    final WriteBuffer buffer = WriteBuffer();

    for (final plane in planes) {
      buffer.putUint8List(plane.bytes);
    }

    final bytes = buffer.done().buffer.asUint8List();

    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw);

    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: imageSize,
        rotation: InputImageRotation.rotation0deg,
        format: inputImageFormat ?? InputImageFormat.yuv420,
        bytesPerRow: planes[0].bytesPerRow,
      ),
    );

    return inputImage;
  }

  Future<void> _autoCapture() async {
    if (_isCapturing || !_isFaceStable) return;

    setState(() {
      _isCapturing = true;
      _capturedFrames = 0;
      _capturedImages.clear();
      _hint = 'Capturing... slight head turn please';
    });

    // Capture 3-5 frames over 2-3 seconds
    for (int i = 0; i < 4; i++) {
      try {
        final image = await _cameraController.takePicture();
        final bytes = await image.readAsBytes();
        _capturedImages.add(bytes);

        setState(() => _capturedFrames = i + 1);

        if (i < 3) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
      } catch (e) {
        print('[CameraCapture] Capture error: $e');
      }
    }

    setState(() => _hint = 'Captured $_capturedFrames photos');

    // Return frames to enrollment screen
    widget.onFramesCapture(_capturedImages);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _manualCapture() async {
    if (_isCapturing || !_isCameraReady) return;

    setState(() {
      _isCapturing = true;
      _hint = 'Capturing...';
    });

    try {
      final image = await _cameraController.takePicture();
      final bytes = await image.readAsBytes();

      // Just capture 1 frame on manual tap
      widget.onFramesCapture([bytes]);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _hint = 'Capture error: $e');
      setState(() => _isCapturing = false);
    }
  }

  @override
  void dispose() {
    _cameraController.stopImageStream();
    _cameraController.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('Capture Photo')),
        body: Center(child: Text(_hint)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture Photo'),
        backgroundColor: const Color(0xFF0F0F0F),
      ),
      backgroundColor: const Color(0xFF0F0F0F),
      body: Stack(
        children: [
          // Camera preview
          CameraPreview(_cameraController),

          // Face bounding box + hints overlay
          if (_detectedFace != null)
            CustomPaint(
              painter: FaceBoxPainter(
                face: _detectedFace!,
                screenSize: Size(
                  MediaQuery.of(context).size.width,
                  MediaQuery.of(context).size.height,
                ),
                isStable: _isFaceStable,
              ),
              size: Size.infinite,
            ),

          // Hint text + capture status
          Positioned(
            bottom: 80,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_capturedFrames > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Captured: $_capturedFrames/4',
                      style: const TextStyle(
                        color: Color(0xFFFF6B35),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Manual capture button
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                onPressed: _isCapturing ? null : _manualCapture,
                icon: const Icon(Icons.camera),
                label: const Text('Manual Capture'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  disabledBackgroundColor: Colors.grey,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FaceBoxPainter extends CustomPainter {
  final Face face;
  final Size screenSize;
  final bool isStable;

  FaceBoxPainter({
    required this.face,
    required this.screenSize,
    required this.isStable,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isStable ? const Color(0xFF00FF00) : const Color(0xFFFF6B35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final rect = face.boundingBox;
    canvas.drawRect(rect, paint);

    // Draw corner brackets
    const cornerLength = 20.0;
    const cornerPadding = 5.0;

    final corners = [
      Rect.fromLTWH(rect.left, rect.top, cornerLength, cornerLength), // TL
      Rect.fromLTWH(rect.right - cornerLength, rect.top, cornerLength, cornerLength), // TR
      Rect.fromLTWH(rect.left, rect.bottom - cornerLength, cornerLength, cornerLength), // BL
      Rect.fromLTWH(rect.right - cornerLength, rect.bottom - cornerLength, cornerLength, cornerLength), // BR
    ];

    final cornerPaint = Paint()
      ..color = isStable ? const Color(0xFF00FF00) : const Color(0xFFFF6B35)
      ..strokeWidth = 4;

    for (final corner in corners) {
      canvas.drawLine(Offset(corner.left, corner.top), Offset(corner.left + cornerLength, corner.top), cornerPaint);
      canvas.drawLine(Offset(corner.left, corner.top), Offset(corner.left, corner.top + cornerLength), cornerPaint);
    }
  }

  @override
  bool shouldRepaint(FaceBoxPainter oldDelegate) => true;
}
