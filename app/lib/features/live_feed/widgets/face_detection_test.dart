import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'package:flutter/material.dart';

/// Quick test: prove face-api can detect faces on the live MJPEG stream
/// Tests: 1) load face-api, 2) find img element, 3) detect faces, 4) read pixels (no taint)
class FaceDetectionTest extends StatefulWidget {
  final String mjpegUrl;

  const FaceDetectionTest({Key? key, required this.mjpegUrl}) : super(key: key);

  @override
  State<FaceDetectionTest> createState() => _FaceDetectionTestState();
}

class _FaceDetectionTestState extends State<FaceDetectionTest> {
  String log = 'Starting test...\n';
  bool testsRunning = false;

  @override
  void initState() {
    super.initState();
    _runTest();
  }

  void _addLog(String msg) {
    print('[FaceDetectionTest] $msg');
    setState(() => log += '$msg\n');
  }

  Future<void> _runTest() async {
    setState(() => testsRunning = true);

    try {
      // Step 1: Load face-api.js
      _addLog('Step 1: Loading face-api.js from CDN...');
      await _loadFaceApiScript();
      _addLog('✅ face-api.js loaded');

      // Step 2: Initialize face-api models
      _addLog('Step 2: Loading face detection models...');
      await _initializeFaceApiModels();
      _addLog('✅ Models ready');

      // Step 3: Find the MJPEG img element
      _addLog('Step 3: Finding MJPEG img element...');
      final img = _findMjpegImage();
      if (img == null) {
        _addLog('❌ MJPEG img not found');
        return;
      }
      _addLog('✅ Found img element (${img.width}x${img.height})');

      // Step 4: Test canvas pixel reading + detection
      _addLog('Step 4: Testing canvas pixel-read + face detection...');
      final detections = await _detectFacesOnImage(img);
      _addLog('✅ Detection completed (${detections.length} faces found)');

      if (detections.length > 0) {
        _addLog('✅✅✅ MILESTONE A PROOF: face-api detected ${detections.length} real face(s)');
        _addLog('Canvas is NOT tainted — pixels are readable');
      } else {
        _addLog('⚠️  No faces detected in current frame (check lighting/positioning)');
      }
    } catch (e) {
      _addLog('❌ Error: $e');
    }

    setState(() => testsRunning = false);
  }

  Future<void> _loadFaceApiScript() async {
    final completer = Completer<void>();

    final script = html.ScriptElement()
      ..src =
          'https://cdn.jsdelivr.net/npm/@vladmandic/face-api@latest/dist/face-api.min.js'
      ..async = true
      ..onLoad.listen((_) => completer.complete())
      ..onError.listen((_) => completer.completeError('Failed to load face-api'));

    html.document.head!.append(script);
    return completer.future;
  }

  Future<void> _initializeFaceApiModels() async {
    try {
      final modelUrl = 'https://cdn.jsdelivr.net/npm/@vladmandic/face-api@latest/model/';

      // Load models via JS interop
      final jsCode = '''
        (async function() {
          const MODEL_URL = '$modelUrl';
          await faceapi.nets.tinyFaceDetector.loadFromUri(MODEL_URL);
          await faceapi.nets.faceLandmark68Net.loadFromUri(MODEL_URL);
          await faceapi.nets.faceRecognitionNet.loadFromUri(MODEL_URL);
          return true;
        })()
      ''';

      final jsFunc = js.context.callMethod('eval', [jsCode]);
      final completer = Completer<bool>();

      jsFunc.callMethod('then', [
        (result) => completer.complete(result == true),
      ]).callMethod('catch', [
        (error) => completer.completeError('Model load failed: $error'),
      ]);

      await completer.future;
    } catch (e) {
      throw Exception('Failed to initialize models: $e');
    }
  }

  html.ImageElement? _findMjpegImage() {
    try {
      final imgs = html.document.querySelectorAll('img');
      for (final img in imgs) {
        if (img is html.ImageElement && (img.src?.contains(widget.mjpegUrl) ?? false)) {
          return img;
        }
      }
      return null;
    } catch (e) {
      _addLog('Error finding img: $e');
      return null;
    }
  }

  Future<List<dynamic>> _detectFacesOnImage(html.ImageElement img) async {
    try {
      // Use JS to run detection (face-api is globally available)
      final jsCode = '''
        (function() {
          try {
            // Create canvas and draw image to it (tests pixel-reading)
            const canvas = document.createElement('canvas');
            canvas.width = arguments[0].width;
            canvas.height = arguments[0].height;
            const ctx = canvas.getContext('2d');
            ctx.drawImage(arguments[0], 0, 0);

            // Test pixel read (will throw if canvas is tainted)
            const imgData = ctx.getImageData(0, 0, 1, 1);
            console.log('[FaceDetectionTest] Canvas pixel-read OK');

            // Return async detection wrapped in Promise
            return faceapi.detectAllFaces(
              arguments[0],
              new faceapi.TinyFaceDetectorOptions()
            ).then(detections => {
              console.log('[FaceDetectionTest] Detected ' + detections.length + ' faces');
              return detections.map(d => ({
                x: d.detection.box.x,
                y: d.detection.box.y,
                width: d.detection.box.width,
                height: d.detection.box.height,
                score: d.detection.score
              }));
            });
          } catch(err) {
            console.error('[FaceDetectionTest] Detection failed:', err.message);
            return Promise.reject(err);
          }
        })
      ''';

      // Call via JS interop, passing the img element
      final jsFunc = js.context.callMethod('eval', [jsCode]);
      final promise = jsFunc.apply([img]) as js.JsObject;

      // Convert JS Promise to Dart Future
      final completer = Completer<List<dynamic>>();
      promise.callMethod('then', [
        (result) {
          if (result is List) {
            completer.complete(result);
          } else {
            completer.complete(js.JsArray.from(result as List).toList());
          }
        }
      ]).callMethod('catch', [
        (error) {
          completer.completeError('JS Error: $error');
        }
      ]);

      return completer.future;
    } catch (e) {
      _addLog('Detection error: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Face Detection Test (Milestone A)',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: Text(
                  log,
                  style: const TextStyle(
                    color: Color(0xFF00FF00),
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (testsRunning)
            const CircularProgressIndicator()
          else
            ElevatedButton(
              onPressed: _runTest,
              child: const Text('Run Test Again'),
            ),
        ],
      ),
    );
  }
}
