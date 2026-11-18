import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

class WebCamera {
  html.VideoElement? _video;
  html.MediaStream? _stream;
  html.DivElement? _overlay;

  final String label;
  void Function(String)? onStage;

  WebCamera({this.label = '신분증을 카메라에 비춰주세요'});

  void _log(String msg) {
    print('[WebCamera] $msg');
    onStage?.call(msg);
  }

  Future<void> startPreview() async {
    _log('카메라 권한 요청 중...');

    // 최대한 유연한 제약 — 어떤 웹캠이든 동작
    try {
      _stream = await html.window.navigator.mediaDevices!
          .getUserMedia({'video': true, 'audio': false});
    } catch (e) {
      _log('카메라 오류: $e');
      rethrow;
    }
    _log('카메라 연결 완료');

    _video = html.VideoElement()
      ..srcObject = _stream
      ..autoplay = true
      ..muted = true
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.borderRadius = '12px';

    _overlay = html.DivElement()
      ..style.position = 'fixed'
      ..style.top = '0'
      ..style.left = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.background = 'rgba(0,0,0,0.75)'
      ..style.zIndex = '99999'
      ..style.display = 'flex'
      ..style.flexDirection = 'column'
      ..style.alignItems = 'center'
      ..style.justifyContent = 'center'
      ..style.gap = '16px';

    final videoWrap = html.DivElement()
      ..style.width = '90%'
      ..style.maxWidth = '480px'
      ..style.aspectRatio = '4/3'
      ..style.border = '3px solid #10B981'
      ..style.borderRadius = '12px'
      ..style.overflow = 'hidden';

    final labelEl = html.DivElement()
      ..style.color = 'white'
      ..style.fontSize = '17px'
      ..style.fontWeight = '600'
      ..style.fontFamily = 'sans-serif'
      ..innerText = label;

    videoWrap.append(_video!);
    _overlay!.append(videoWrap);
    _overlay!.append(labelEl);
    html.document.body!.append(_overlay!);

    try { await _video!.play(); } catch (_) {}
    _log('카메라 프리뷰 표시됨');
  }

  Future<Uint8List> captureOnce() async {
    return _doCapture().timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _log('30초 타임아웃!');
        dispose();
        throw TimeoutException('카메라 타임아웃');
      },
    );
  }

  Future<Uint8List> _doCapture() async {
    await startPreview();

    _log('영상 준비 대기 중...');
    int waited = 0;
    while ((_video!.readyState as int) < 2 && waited < 5000) {
      await Future.delayed(const Duration(milliseconds: 100));
      waited += 100;
    }
    _log('준비 완료 (${waited}ms), 촬영 시작');

    await Future.delayed(const Duration(milliseconds: 1500));

    _overlay?.style.background = 'rgba(255,255,255,0.85)';
    await Future.delayed(const Duration(milliseconds: 150));
    _overlay?.style.background = 'rgba(0,0,0,0.75)';

    final bytes = await _captureFrame();
    _log('캡처 완료: ${bytes.length} bytes');
    dispose();
    return bytes;
  }

  Future<Uint8List> _captureFrame() async {
    final v = _video!;
    final w = v.videoWidth > 0 ? v.videoWidth : 640;
    final h = v.videoHeight > 0 ? v.videoHeight : 480;
    _log('해상도: ${w}x${h}');
    final canvas = html.CanvasElement(width: w, height: h);
    canvas.context2D.drawImage(v, 0, 0);
    final dataUrl = canvas.toDataUrl('image/jpeg', 0.85);
    final base64 = dataUrl.split(',').last;
    return base64Decode(base64);
  }

  void dispose() {
    _stream?.getTracks().forEach((t) => t.stop());
    try { _overlay?.remove(); } catch (_) {}
    _video = null;
    _stream = null;
    _overlay = null;
  }
}
