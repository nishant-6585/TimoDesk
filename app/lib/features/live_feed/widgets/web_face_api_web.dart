import 'dart:async';
import 'dart:js' as js;

/// Web implementation of the face-api enrollment seam. The dart:js `eval` logic
/// moved here verbatim from live_feed_screen so the screen no longer imports
/// dart:js. Each function wraps a browser face-api.js call as a Dart Future.

/// Load face-api.js + the tiny detector / landmark / recognition models from
/// [modelBaseUrl]. Resolves true on success, false on failure.
Future<bool> faceApiLoadModels(String modelBaseUrl) {
  final jsCode = '''(async function() {
    const script = document.createElement('script');
    script.src = 'https://cdn.jsdelivr.net/npm/@vladmandic/face-api@latest/dist/face-api.min.js';
    document.head.appendChild(script);

    return new Promise(resolve => {
      script.onload = async () => {
        await faceapi.nets.tinyFaceDetector.loadFromUri('$modelBaseUrl');
        await faceapi.nets.faceLandmark68Net.loadFromUri('$modelBaseUrl');
        await faceapi.nets.faceRecognitionNet.loadFromUri('$modelBaseUrl');
        resolve(true);
      };
    });
  })()''';

  final result = js.context.callMethod('eval', [jsCode]);
  final completer = Completer<bool>();
  result.callMethod('then', [(val) => completer.complete(true)]).callMethod('catch', [
    (err) => completer.complete(false),
  ]);
  return completer.future;
}

/// Detect exactly one face in the element matched by [elementSelector] and return
/// geometry: {faces, faceHeight, centerX, centerY, yaw, noseRel}. Returns
/// {faces: 0|n} when not exactly one face. Never throws (resolves a map).
Future<Map<String, dynamic>> faceApiDetect(String elementSelector) {
  final jsDetectionCode = '''(async function() {
    const el = document.querySelector('$elementSelector');
    const elW = el ? (el.naturalWidth || el.videoWidth || 0) : 0;
    const elH = el ? (el.naturalHeight || el.videoHeight || 0) : 0;
    if (!el || elW === 0) return {faces: 0};
    try {
      const dets = await faceapi
        .detectAllFaces(el, new faceapi.TinyFaceDetectorOptions())
        .withFaceLandmarks();
      if (dets.length !== 1) return {faces: dets.length};

      const d = dets[0];
      const box = d.detection.box;
      const imgW = elW, imgH = elH;

      const lm = d.landmarks;
      const avg = (pts) => { let x=0,y=0; for (const p of pts){x+=p.x;y+=p.y;} return {x:x/pts.length, y:y/pts.length}; };
      const leC = avg(lm.getLeftEye());
      const reC = avg(lm.getRightEye());
      const mC  = avg(lm.getMouth());
      const nose = lm.getNose();
      const noseTip = nose[3] || nose[nose.length-1];
      const eyeMid = { x:(leC.x+reC.x)/2, y:(leC.y+reC.y)/2 };
      const interEye = Math.hypot(reC.x-leC.x, reC.y-leC.y) || 1;
      const faceVert = (mC.y - eyeMid.y) || 1;

      return {
        faces: 1,
        faceHeight: box.height / imgH,
        centerX: (box.x + box.width/2) / imgW,
        centerY: (box.y + box.height/2) / imgH,
        yaw: (noseTip.x - eyeMid.x) / interEye,
        noseRel: (noseTip.y - eyeMid.y) / faceVert
      };
    } catch(e) { return {faces: 0}; }
  })()''';

  final jsFunc = js.context.callMethod('eval', [jsDetectionCode]);
  final completer = Completer<Map<String, dynamic>>();

  jsFunc.callMethod('then', [
    (result) {
      double toD(dynamic v) => (v is num) ? v.toDouble() : 0.0;
      try {
        completer.complete({
          'faces': (result['faces'] is num) ? (result['faces'] as num).toInt() : 0,
          'faceHeight': toD(result['faceHeight']),
          'centerX': toD(result['centerX']),
          'centerY': toD(result['centerY']),
          'yaw': toD(result['yaw']),
          'noseRel': toD(result['noseRel']),
        });
      } catch (e) {
        completer.complete({'faces': 0});
      }
    }
  ]).callMethod('catch', [(err) => completer.complete({'faces': 0})]);
  return completer.future;
}

/// Grab the current frame of the element matched by [elementSelector] as a JPEG
/// data URL (or null on failure).
Future<String?> faceApiCapture(String elementSelector) {
  final captureCode = '''(async function() {
    const el = document.querySelector('$elementSelector');
    if (!el) return null;
    const w = el.naturalWidth || el.videoWidth || 0;
    const h = el.naturalHeight || el.videoHeight || 0;
    if (w === 0) return null;

    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d');
    ctx.drawImage(el, 0, 0);

    return canvas.toDataURL('image/jpeg', 0.9);
  })()''';

  final jsFunc = js.context.callMethod('eval', [captureCode]);
  final completer = Completer<String?>();
  jsFunc.callMethod('then', [(dataUrl) => completer.complete(dataUrl as String?)]).callMethod(
    'catch',
    [(err) => completer.complete(null)],
  );
  return completer.future;
}
