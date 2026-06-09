import 'dart:async';
import 'dart:html' as html;
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:js/js.dart' as js;
import 'mjpeg_view.dart';

/// Face detection overlay for live robot MJPEG feed
/// Loads face-api.js, detects faces in real-time, draws bounding boxes
class FaceDetectionOverlay extends StatefulWidget {
  final String mjpegUrl;
  final BoxFit fit;

  const FaceDetectionOverlay({
    Key? key,
    required this.mjpegUrl,
    this.fit = BoxFit.cover,
  }) : super(key: key);

  @override
  State<FaceDetectionOverlay> createState() => _FaceDetectionOverlayState();
}

class _FaceDetectionOverlayState extends State<FaceDetectionOverlay> {
  late html.CanvasElement overlayCanvas;
  late html.ImageElement imgElement;
  Timer? detectionTimer;
  bool modelsLoaded = false;
  String statusText = 'Loading face-api...';

  @override
  void initState() {
    super.initState();
    _initializeFaceDetection();
  }

  Future<void> _initializeFaceDetection() async {
    try {
      // Load face-api.js from CDN
      await _loadScript(
        'https://cdn.jsdelivr.net/npm/@vladmandic/face-api@latest/dist/face-api.min.js',
      );

      setState(() => statusText = 'Loading models...');

      // Wait for models to load via JS
      await Future.delayed(const Duration(seconds: 2));

      // Initialize face-api models (via JS interop)
      await _initializeFaceApiModels();

      setState(() {
        modelsLoaded = true;
        statusText = 'Detecting faces...';
      });

      // Start detection loop
      _startDetectionLoop();
    } catch (e) {
      setState(() => statusText = 'Error: $e');
      print('[FaceDetection] Init error: $e');
    }
  }

  Future<void> _loadScript(String src) async {
    final script = html.ScriptElement()
      ..src = src
      ..async = true
      ..defer = true;

    return html.document.head!.append(script) as Future<void>;
  }

  Future<void> _initializeFaceApiModels() async {
    // Call window.faceapi.nets.<detector>.loadFromUri
    // This assumes face-api is loaded globally as window.faceapi
    try {
      // Using js.context to access global window.faceapi
      final result = js.context.callMethod('eval', [
        '''
        (async () => {
          const MODEL_URL = 'https://cdn.jsdelivr.net/npm/@vladmandic/face-api@latest/model/';
          await faceapi.nets.tinyFaceDetector.loadFromUri(MODEL_URL);
          await faceapi.nets.faceLandmark68Net.loadFromUri(MODEL_URL);
          await faceapi.nets.faceRecognitionNet.loadFromUri(MODEL_URL);
          return true;
        })()
        '''
      ]);
      return result;
    } catch (e) {
      print('[FaceDetection] Model load error: $e');
      rethrow;
    }
  }

  void _startDetectionLoop() {
    // Get the MJPEG img element from the platform view
    // This is a bit tricky in Flutter web — we'll use a timer to poll for detection

    detectionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      try {
        // Find the img element (it's the only img in the live feed)
        final imgs = html.document.querySelectorAll('img');
        imgElement = imgs.firstWhere(
          (e) => e.src.contains(widget.mjpegUrl),
          orElse: () => null as html.ImageElement,
        );

        if (imgElement == null) return;

        // Create or get overlay canvas
        if (overlayCanvas == null) {
          _createOverlayCanvas();
        }

        // Run detection
        await _detectAndDraw();
      } catch (e) {
        print('[FaceDetection] Loop error: $e');
      }
    });
  }

  void _createOverlayCanvas() {
    // Create canvas overlay positioned absolutely over the img
    overlayCanvas = html.CanvasElement()
      ..width = imgElement.width
      ..height = imgElement.height
      ..style.position = 'absolute'
      ..style.top = '0'
      ..style.left = '0'
      ..style.cursor = 'crosshair';

    // Add to DOM (will be positioned by Flutter)
    html.document.body!.append(overlayCanvas);
  }

  Future<void> _detectAndDraw() async {
    try {
      // Use face-api to detect faces
      final detections = await js.context.callMethod('eval', [
        '''
        (async () => {
          const img = document.querySelector('img[src*="${widget.mjpegUrl}"]');
          if (!img) return [];
          const detections = await faceapi.detectAllFaces(img, new faceapi.TinyFaceDetectorOptions());
          return detections;
        })()
        '''
      ]) as List;

      // Draw bounding boxes
      _drawDetections(detections);
    } catch (e) {
      print('[FaceDetection] Detection error: $e');
    }
  }

  void _drawDetections(List detections) {
    if (overlayCanvas == null) return;

    final ctx = overlayCanvas.context2D;

    // Clear canvas
    ctx.fillStyle = 'rgba(0, 0, 0, 0)';
    ctx.fillRect(0, 0, overlayCanvas.width!, overlayCanvas.height!);

    // Draw boxes for each detection
    for (final detection in detections) {
      _drawBox(ctx, detection);
    }

    // Draw status
    ctx.fillStyle = '#FF6B35';
    ctx.font = '14px Arial';
    ctx.fillText('Detected: ${detections.length} face(s)', 10, 30);
  }

  void _drawBox(html.CanvasRenderingContext2D ctx, dynamic detection) {
    try {
      // Extract bounding box (face-api returns box as {x, y, width, height})
      final box = detection['_box'] ?? detection['box'];
      if (box == null) return;

      final x = box['_x'] ?? box['x'] ?? 0;
      final y = box['_y'] ?? box['y'] ?? 0;
      final width = box['_width'] ?? box['width'] ?? 0;
      final height = box['_height'] ?? box['height'] ?? 0;

      // Draw bounding box (green for now)
      ctx.strokeStyle = '#00FF00';
      ctx.lineWidth = 2;
      ctx.strokeRect(x, y, width, height);

      // Draw corner brackets
      const cornerLen = 20;
      ctx.strokeStyle = '#00FF00';
      ctx.lineWidth = 3;

      // Top-left
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x + cornerLen, y);
      ctx.stroke();

      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x, y + cornerLen);
      ctx.stroke();

      // Top-right
      ctx.beginPath();
      ctx.moveTo(x + width, y);
      ctx.lineTo(x + width - cornerLen, y);
      ctx.stroke();

      ctx.beginPath();
      ctx.moveTo(x + width, y);
      ctx.lineTo(x + width, y + cornerLen);
      ctx.stroke();

      // Bottom-left
      ctx.beginPath();
      ctx.moveTo(x, y + height);
      ctx.lineTo(x + cornerLen, y + height);
      ctx.stroke();

      ctx.beginPath();
      ctx.moveTo(x, y + height);
      ctx.lineTo(x, y + height - cornerLen);
      ctx.stroke();

      // Bottom-right
      ctx.beginPath();
      ctx.moveTo(x + width, y + height);
      ctx.lineTo(x + width - cornerLen, y + height);
      ctx.stroke();

      ctx.beginPath();
      ctx.moveTo(x + width, y + height);
      ctx.lineTo(x + width, y + height - cornerLen);
      ctx.stroke();
    } catch (e) {
      print('[FaceDetection] Draw error: $e');
    }
  }

  @override
  void dispose() {
    detectionTimer?.cancel();
    overlayCanvas.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // MJPEG feed (live robot camera)
        buildMjpegView(context, widget.mjpegUrl, widget.fit),

        // Overlay canvas (rendered by browser, not Flutter)
        // The canvas is added directly to DOM, so we just need a placeholder
        Container(),

        // Status text
        if (!modelsLoaded)
          Positioned(
            top: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusText,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
      ],
    );
  }
}
