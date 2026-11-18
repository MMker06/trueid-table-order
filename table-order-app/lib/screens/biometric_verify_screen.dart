import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import '../store/session_store.dart';

enum _AuthMethod { face, fingerprint }

class BiometricVerifyScreen extends ConsumerStatefulWidget {
  const BiometricVerifyScreen({super.key});

  @override
  ConsumerState<BiometricVerifyScreen> createState() => _BiometricVerifyScreenState();
}

class _BiometricVerifyScreenState extends ConsumerState<BiometricVerifyScreen> {
  CameraController? _camCtrl;
  bool _cameraReady = false;
  _AuthMethod _method = _AuthMethod.face;
  bool _verifying = false;
  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _camCtrl = CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await _camCtrl!.initialize();
      if (mounted) setState(() => _cameraReady = true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _camCtrl?.dispose();
    super.dispose();
  }

  Future<void> _verifyFace({bool fromGallery = false}) async {
    if (_verifying) return;
    setState(() => _verifying = true);

    try {
      Uint8List? bytes;

      if (!fromGallery && _cameraReady && _camCtrl != null) {
        final xfile = await _camCtrl!.takePicture();
        bytes = await xfile.readAsBytes(); // dart:io File 미사용 — 웹 호환
      } else {
        final picker = ImagePicker();
        final xfile = await picker.pickImage(
          source: fromGallery ? ImageSource.gallery : ImageSource.camera,
          imageQuality: 90,
        );
        if (xfile == null) {
          setState(() => _verifying = false);
          return;
        }
        bytes = await xfile.readAsBytes();
      }

      if (bytes == null) {
        _showError('얼굴 이미지를 가져올 수 없습니다.');
        setState(() => _verifying = false);
        return;
      }

      await ref.read(sessionProvider.notifier).verifyFace(bytes.toList());
      _handleResult();
    } catch (e) {
      _showError('얼굴 인증 중 오류가 발생했습니다.');
      setState(() => _verifying = false);
    }
  }

  Future<void> _verifyFingerprint() async {
    if (_verifying) return;

    // 기기 생체인증 (보조 레이어)
    try {
      final canAuth = await _localAuth.canCheckBiometrics;
      if (canAuth) {
        final authenticated = await _localAuth.authenticate(
          localizedReason: '지문을 인식해주세요',
          options: const AuthenticationOptions(biometricOnly: true),
        );
        if (!authenticated) return;
      }
    } catch (_) {
      // local_auth 미지원 환경은 그냥 통과
    }

    setState(() => _verifying = true);
    await ref.read(sessionProvider.notifier).verifyFingerprint(sdkScore: null);
    _handleResult();
  }

  void _handleResult() {
    if (!mounted) return;
    final step = ref.read(sessionProvider).step;
    setState(() => _verifying = false);
    if (step == VerificationStep.completed) {
      context.pushReplacement('/result', extra: true);
    } else {
      context.pushReplacement('/result', extra: false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red[600]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF111827)),
          onPressed: () => context.go('/'),
        ),
        title: const Text('생체 인증', style: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 방식 선택 탭
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                _ModeTab(
                  icon: Icons.face_retouching_natural_rounded,
                  label: '얼굴 인식',
                  active: _method == _AuthMethod.face,
                  onTap: () => setState(() => _method = _AuthMethod.face),
                ),
                _ModeTab(
                  icon: Icons.fingerprint_rounded,
                  label: '지문 인식',
                  active: _method == _AuthMethod.fingerprint,
                  onTap: () => setState(() => _method = _AuthMethod.fingerprint),
                ),
              ]),
            ),
          ),

          Expanded(
            child: _method == _AuthMethod.face
                ? _buildFaceMode()
                : _buildFingerprintMode(),
          ),
        ],
      ),
    );
  }

  // ── 얼굴 인식 ─────────────────────────────────────
  Widget _buildFaceMode() {
    return Column(
      children: [
        // 카메라 영역
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _cameraReady && _camCtrl != null
                      ? CameraPreview(_camCtrl!)
                      : _NoCameraBox(),
                ),
                // 얼굴 가이드 원
                if (_cameraReady)
                  Center(
                    child: Container(
                      width: 200, height: 240,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF2563EB), width: 2.5),
                        borderRadius: BorderRadius.circular(120),
                      ),
                    ).animate(onPlay: (c) => c.repeat(reverse: true))
                        .shimmer(duration: 2.seconds, color: const Color(0x332563EB)),
                  ),
                // 인증 중 오버레이
                if (_verifying)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        CircularProgressIndicator(color: Colors.white),
                        Gap(16),
                        Text('얼굴을 인식하는 중...', style: TextStyle(color: Colors.white, fontSize: 15)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const Text('카메라 정면을 바라봐주세요',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
            const Gap(16),
            if (_cameraReady)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _verifying ? null : () => _verifyFace(),
                  icon: const Icon(Icons.camera_front_rounded),
                  label: const Text('얼굴 인증하기'),
                ),
              ),
            const Gap(10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _verifying ? null : () => _verifyFace(fromGallery: true),
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(_cameraReady ? '갤러리에서 선택' : '얼굴 사진 업로드'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  foregroundColor: const Color(0xFF374151),
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  // ── 지문 인식 ─────────────────────────────────────
  Widget _buildFingerprintMode() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fingerprint_rounded, size: 120, color: const Color(0xFF2563EB))
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scaleXY(begin: 0.94, end: 1.06, duration: 1200.ms, curve: Curves.easeInOut),
                const Gap(24),
                const Text('지문 인식 센서에\n손가락을 올려주세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF374151), height: 1.5)),
                const Gap(12),
                const Text('등록된 지문으로 본인 확인을 진행합니다',
                    style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _verifying ? null : _verifyFingerprint,
                icon: _verifying
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Icon(Icons.fingerprint_rounded),
                label: Text(_verifying ? '인증 중...' : '지문 인증하기'),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

class _ModeTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ModeTab({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4)] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: active ? const Color(0xFF2563EB) : const Color(0xFF9CA3AF)),
              const Gap(6),
              Text(label, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: active ? const Color(0xFF2563EB) : const Color(0xFF9CA3AF),
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoCameraBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3F4F6),
      child: const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.no_photography_outlined, size: 48, color: Color(0xFF9CA3AF)),
          Gap(12),
          Text('카메라를 사용할 수 없습니다', style: TextStyle(color: Color(0xFF6B7280))),
          Gap(4),
          Text('아래에서 얼굴 사진을 업로드하세요', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
        ]),
      ),
    );
  }
}
