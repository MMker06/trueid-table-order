import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../store/session_store.dart';

enum _IdMode { physical, mobile }

class IDScanScreen extends ConsumerStatefulWidget {
  const IDScanScreen({super.key});

  @override
  ConsumerState<IDScanScreen> createState() => _IDScanScreenState();
}

class _IDScanScreenState extends ConsumerState<IDScanScreen> {
  CameraController? _camCtrl;
  bool _cameraReady = false;
  bool _analyzing = false;
  _IdMode _mode = _IdMode.physical;

  @override
  void initState() {
    super.initState();
    _initCamera();
    // 화면 진입 시 백엔드 세션 생성
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sessionProvider.notifier).startSession();
    });
  }

  Future<void> _initCamera() async {
    // 웹에서는 camera 패키지 CameraPreview 미지원 — image_picker로 대체
    if (kIsWeb) return;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      _camCtrl = CameraController(cameras.first, ResolutionPreset.high, enableAudio: false);
      await _camCtrl!.initialize();
      if (mounted) setState(() => _cameraReady = true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _camCtrl?.dispose();
    super.dispose();
  }

  Future<Uint8List?> _captureImage({bool fromGallery = false}) async {
    // 네이티브 앱: 카메라 컨트롤러로 촬영
    if (!kIsWeb && !fromGallery && _cameraReady && _camCtrl != null) {
      final xfile = await _camCtrl!.takePicture();
      return xfile.readAsBytes();
    }
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: fromGallery ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 92,
    );
    if (xfile == null) return null;
    return xfile.readAsBytes();
  }

  Future<void> _analyze(Uint8List bytes) async {
    if (_analyzing) return;

    // 세션 생성 중이면 최대 5초 대기
    String? sessionId;
    for (int i = 0; i < 10; i++) {
      sessionId = ref.read(sessionProvider).sessionId;
      if (sessionId != null) break;
      final step = ref.read(sessionProvider).step;
      if (step == VerificationStep.error) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (sessionId == null) {
      final errMsg = ref.read(sessionProvider).errorMessage;
      _showErrorDialog(errMsg ?? '세션 생성에 실패했습니다. 로그인 상태를 확인해주세요.');
      return;
    }

    setState(() => _analyzing = true);

    try {
      await ref.read(sessionProvider.notifier).submitIdImage(bytes.toList());
      final session = ref.read(sessionProvider);

      if (!mounted) return;
      if (session.step == VerificationStep.otpSending) {
        context.push('/otp', extra: '');
      } else if (session.step == VerificationStep.idFailed) {
        _showFailDialog();
      } else {
        // error 또는 알 수 없는 상태
        final msg = session.errorMessage ?? '신분증 분석에 실패했습니다.\n이미지를 다시 업로드해주세요.';
        _showErrorDialog(msg);
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _capture() async {
    final bytes = await _captureImage(fromGallery: false);
    if (bytes != null) await _analyze(bytes);
  }

  Future<void> _pickFromGallery() async {
    final bytes = await _captureImage(fromGallery: true);
    if (bytes != null) await _analyze(bytes);
  }

  void _showFailDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          Gap(8),
          Text('신분증 확인 실패', style: TextStyle(fontSize: 16)),
        ]),
        content: const Text('위변조가 의심되는 신분증이 감지되었습니다.\n신분증을 다시 준비해주세요.'),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); context.go('/'); }, child: const Text('처음으로')),
          FilledButton(onPressed: () { Navigator.pop(context); setState(() {}); }, child: const Text('다시 시도')),
        ],
      ),
    );
  }

  void _showErrorDialog(String? msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('오류 발생'),
        content: Text(msg ?? '알 수 없는 오류가 발생했습니다.'),
        actions: [TextButton(onPressed: () { Navigator.pop(context); context.go('/'); }, child: const Text('확인'))],
      ),
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
        title: const Text('신분증 확인', style: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 모드 선택 탭
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                _ModeTab(label: '실물 신분증', icon: Icons.credit_card_rounded,
                    active: _mode == _IdMode.physical,
                    onTap: () => setState(() => _mode = _IdMode.physical)),
                _ModeTab(label: '모바일 신분증', icon: Icons.smartphone_rounded,
                    active: _mode == _IdMode.mobile,
                    onTap: () => setState(() => _mode = _IdMode.mobile)),
              ]),
            ),
          ),

          Expanded(
            child: _mode == _IdMode.physical
                ? _buildPhysicalMode()
                : _buildMobileMode(),
          ),
        ],
      ),
    );
  }

  // ── 실물 신분증 모드 ────────────────────────────────
  Widget _buildPhysicalMode() {
    return Column(
      children: [
        // 카메라 / 미리보기 영역
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _cameraReady && _camCtrl != null
                      ? CameraPreview(_camCtrl!)
                      : _NoCameraPlaceholder(
                          onCamera: _capture,
                          onPickFile: _pickFromGallery,
                        ),
                ),
                // 신분증 가이드 프레임
                if (_cameraReady)
                  Center(child: _IDGuideFrame()),
                // 분석 중 오버레이
                if (_analyzing)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        CircularProgressIndicator(color: Colors.white),
                        Gap(16),
                        Text('AI가 신분증을 분석하는 중...', style: TextStyle(color: Colors.white, fontSize: 15)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // 안내 + 버튼
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // 안내 칩
              _GuideRow(items: const ['밝은 환경', '정면 촬영', '흔들림 없이']),
              const Gap(16),
              // 촬영 버튼
              if (_cameraReady)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _analyzing ? null : _capture,
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('신분증 촬영'),
                  ),
                ),
              const Gap(10),
              // 파일 선택 (웹/갤러리)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _analyzing ? null : _pickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: Text(_cameraReady ? '갤러리에서 선택' : '파일 선택 (이미지 업로드)'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    foregroundColor: const Color(0xFF374151),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 모바일 신분증 모드 ──────────────────────────────
  Widget _buildMobileMode() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Gap(8),
          // 안내 카드
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Icon(Icons.smartphone_rounded, color: Colors.white, size: 48),
                const Gap(12),
                const Text('모바일 신분증 인증',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const Gap(6),
                const Text('모바일 운전면허증 / 모바일 주민등록증',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms),
          const Gap(24),

          // 지원 신분증 종류
          Row(children: [
            _MobileIdCard(
              icon: Icons.directions_car_rounded,
              label: '모바일\n운전면허증',
              color: const Color(0xFF2563EB),
            ),
            const Gap(12),
            _MobileIdCard(
              icon: Icons.badge_rounded,
              label: '모바일\n주민등록증',
              color: const Color(0xFF059669),
            ),
          ]),
          const Gap(24),

          // 사용 방법 안내
          _InstructionCard(
            steps: const [
              _Step(num: '1', text: '정부24 앱 또는 PASS 앱을 실행하세요'),
              _Step(num: '2', text: '모바일 신분증 화면을 준비하세요\n(QR코드 또는 신분증 이미지)'),
              _Step(num: '3', text: '아래 버튼으로 화면을 촬영하거나\n이미지를 업로드하세요'),
            ],
          ),
          const Gap(24),

          // 촬영 버튼
          if (_cameraReady)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _analyzing ? null : _capture,
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text('모바일 신분증 화면 촬영'),
              ),
            ),
          const Gap(10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _analyzing ? null : _pickFromGallery,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text('이미지 파일로 업로드'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                side: const BorderSide(color: Color(0xFF2563EB)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                foregroundColor: const Color(0xFF2563EB),
              ),
            ),
          ),

          if (_analyzing)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Column(children: [
                CircularProgressIndicator(),
                Gap(12),
                Text('AI가 신분증을 분석하는 중...', style: TextStyle(color: Color(0xFF6B7280))),
              ]),
            ),

          const Gap(16),
          // 보안 안내
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.security_rounded, size: 16, color: Color(0xFFF97316)),
                Gap(8),
                Expanded(
                  child: Text(
                    '업로드된 신분증 이미지는 인증 후 즉시 삭제되며 저장되지 않습니다.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF92400E), height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 위젯 컴포넌트 ─────────────────────────────────────

class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ModeTab({required this.label, required this.icon, required this.active, required this.onTap});

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

class _IDGuideFrame extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF2563EB), width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text('신분증을 이 영역에 맞춰주세요',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
        ),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true))
        .shimmer(duration: 2.seconds, color: const Color(0x332563EB));
  }
}

class _NoCameraPlaceholder extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onPickFile;
  const _NoCameraPlaceholder({required this.onCamera, required this.onPickFile});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF3F4F6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.camera_alt_outlined, size: 36, color: Color(0xFF9CA3AF)),
          ),
          const Gap(16),
          const Text('신분증 이미지를 제출하세요',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
          const Gap(6),
          const Text('카메라 촬영 또는 파일 업로드 중 선택',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          const Gap(20),
          ElevatedButton.icon(
            onPressed: onCamera,
            icon: const Icon(Icons.camera_alt_rounded, size: 18),
            label: const Text('카메라로 촬영'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              minimumSize: const Size(200, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const Gap(10),
          OutlinedButton.icon(
            onPressed: onPickFile,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('파일 선택'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(200, 44),
              side: const BorderSide(color: Color(0xFFD1D5DB)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              foregroundColor: const Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  final List<String> items;
  const _GuideRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: items.map((item) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(item, style: const TextStyle(fontSize: 12, color: Color(0xFF2563EB), fontWeight: FontWeight.w500)),
        ),
      )).toList(),
    );
  }
}

class _MobileIdCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MobileIdCard({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 28),
          const Gap(8),
          Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color, height: 1.4)),
        ]),
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  final List<_Step> steps;
  const _InstructionCard({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: steps.map((step) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22, height: 22,
                decoration: const BoxDecoration(color: Color(0xFF2563EB), shape: BoxShape.circle),
                child: Center(child: Text(step.num,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
              ),
              const Gap(10),
              Expanded(child: Text(step.text,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5))),
            ],
          ),
        )).toList(),
      ),
    );
  }
}

class _Step {
  final String num;
  final String text;
  const _Step({required this.num, required this.text});
}
