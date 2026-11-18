import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/api_client.dart';
import '../../services/web_camera.dart';

class AdultVerifyScreen extends ConsumerStatefulWidget {
  final String orderId;
  final int requiredCount;
  final String merchantId;
  final String tableNumber;
  final String verifyMode; // 'physical' or 'mobile'

  const AdultVerifyScreen({
    super.key,
    required this.orderId,
    required this.requiredCount,
    required this.merchantId,
    required this.tableNumber,
    this.verifyMode = 'mobile',
  });

  @override
  ConsumerState<AdultVerifyScreen> createState() => _AdultVerifyScreenState();
}

class _AdultVerifyScreenState extends ConsumerState<AdultVerifyScreen> {
  // ── 공통 ──
  int _verifiedCount = 0;

  // ── 모바일 모드 ──
  String? _verifyUrl;
  bool _loadingQR = false;
  String? _qrError;
  Timer? _pollTimer;

  // ── 실물 신분증 모드 ──
  bool _scanning = false;
  Map<String, dynamic>? _scanResult;

  @override
  void initState() {
    super.initState();
    if (widget.verifyMode == 'mobile') {
      _requestNewQR();
      _startPolling();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── 모바일: QR 요청 ──
  Future<void> _requestNewQR() async {
    setState(() {
      _loadingQR = true;
      _qrError = null;
      _verifyUrl = null;
    });
    try {
      final data =
          await ref.read(apiClientProvider).requestMobileVerify(widget.orderId);
      if (mounted) {
        setState(() {
          _verifyUrl = data['verify_url'] as String;
          _loadingQR = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _qrError = 'QR 생성 실패'; _loadingQR = false; });
    }
  }

  // ── 모바일: 상태 폴링 ──
  void _startPolling() {
    _pollTimer =
        Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) return;
      try {
        final s = await ref
            .read(apiClientProvider)
            .getMobileVerifyStatus(widget.orderId);
        final count = s['verified_count'] as int;
        final done = s['completed'] as bool;
        if (count != _verifiedCount) {
          setState(() => _verifiedCount = count);
          if (done) {
            _pollTimer?.cancel();
            await Future.delayed(const Duration(milliseconds: 600));
            if (mounted) _goComplete();
          } else {
            await _requestNewQR();
          }
        }
      } catch (_) {}
    });
  }

  // ── 실물 신분증: 카메라 촬영 + OCR ──
  Future<void> _scanPhysicalId() async {
    setState(() { _scanning = true; _scanResult = null; });
    try {
      final cam = WebCamera(label: '신분증을 카메라에 비춰주세요');
      final bytes = await cam.captureOnce();
      if (!mounted) return;

      final result = await ref
          .read(apiClientProvider)
          .verifyIdOcr(widget.orderId, bytes)
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;
      setState(() {
        _scanning = false;
        _scanResult = result;
        _verifiedCount = result['verified_count'] as int? ?? 0;
      });

      if (result['completed'] == true) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) _goComplete();
      }
    } catch (e) {
      if (!mounted) return;
      final err = e.toString();
      String msg;
      if (err.contains('Permission') || err.contains('NotAllowed')) {
        msg = '카메라 권한을 허용해주세요';
      } else if (err.contains('Timeout') || err.contains('timeout')) {
        msg = '시간 초과 — 다시 시도해주세요';
      } else {
        msg = err.length > 80 ? err.substring(0, 80) : err;
      }
      setState(() {
        _scanning = false;
        _scanResult = {'completed': false, 'message': msg};
      });
    }
  }

  void _goComplete() {
    context.go('/order-complete', extra: {
      'orderId': widget.orderId,
      'merchantId': widget.merchantId,
      'tableNumber': widget.tableNumber,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A1A),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('성인 인증',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
      ),
      body: widget.verifyMode == 'physical'
          ? _buildPhysicalBody()
          : _buildMobileBody(),
    );
  }

  // ──────────────── 실물 신분증 화면 ────────────────────────────
  Widget _buildPhysicalBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(children: [
        // 안내 카드
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E40AF), Color(0xFF1D4ED8)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(children: [
            const Icon(Icons.credit_card_rounded, color: Colors.white, size: 44),
            const Gap(10),
            const Text('신분증 촬영으로 인증',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const Gap(6),
            const Text('주민등록증 · 운전면허증 · 여권',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ),
        const Gap(24),

        // 결과 카드
        if (_scanResult != null) ...[
          _buildScanResultCard(),
          const Gap(20),
        ],

        // 촬영 버튼
        if (_scanResult == null || _scanResult!['completed'] != true) ...[
          // 안내
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(children: [
              _GuideRow(items: ['밝은 환경', '정면으로 펼치기', '흔들림 없이']),
              Gap(10),
              Text(
                '신분증 전체가 화면에 들어오도록\n카메라를 정면에서 비춰주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
              ),
            ]),
          ),
          const Gap(20),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _scanning ? null : _scanPhysicalId,
              icon: _scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Icon(Icons.camera_alt_rounded),
              label: Text(_scanning ? '분석 중...' : '신분증 촬영하기',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],

        const Gap(16),
        const Text('인증 정보는 확인 후 즉시 삭제됩니다',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
      ]),
    );
  }

  Widget _buildScanResultCard() {
    final completed = _scanResult!['completed'] == true;
    final message = _scanResult!['message'] as String? ?? '';

    if (completed) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF6EE7B7)),
        ),
        child: Row(children: [
          const Icon(Icons.check_circle_rounded,
              color: Color(0xFF10B981), size: 32),
          const Gap(12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            const Text('인증 완료',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF065F46))),
            if (message.isNotEmpty)
              Text(message,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF059669))),
          ])),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFD97706), size: 20),
          const Gap(8),
          const Text('인증 실패',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFD97706))),
        ]),
        if (message.isNotEmpty) ...[
          const Gap(6),
          Text(message,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF92400E), height: 1.4)),
        ],
      ]),
    );
  }

  // ──────────────── 모바일 QR 화면 (기존) ──────────────────────
  Widget _buildMobileBody() {
    final remaining = widget.requiredCount - _verifiedCount;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(children: [
        _buildProgressDots(),
        const Gap(16),
        Text(
          remaining > 0 ? '$remaining명이 스마트폰으로 인증하세요' : '인증 완료!',
          style: const TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
        ),
        const Gap(28),

        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8))
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0064D2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.verified_user_rounded,
                    color: Colors.white, size: 14),
                Gap(6),
                Text('카카오 성인인증',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
            const Gap(16),

            if (_loadingQR)
              const SizedBox(
                width: 220,
                height: 220,
                child: Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF0064D2))),
              )
            else if (_qrError != null)
              SizedBox(
                width: 220,
                height: 220,
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Colors.red, size: 48),
                      const Gap(12),
                      Text(_qrError!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 13)),
                      const Gap(12),
                      TextButton.icon(
                        onPressed: _requestNewQR,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('다시 시도'),
                      ),
                    ]),
              )
            else if (_verifyUrl != null)
              QrImageView(
                data: _verifyUrl!,
                version: QrVersions.auto,
                size: 220,
                eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF0064D2)),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF1A1A1A)),
              ),

            const Gap(12),
            const Text('스마트폰 카메라 앱으로 QR을 스캔하세요',
                style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
            const Gap(4),
            const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.smartphone_rounded,
                      size: 13, color: Color(0xFF999999)),
                  Gap(4),
                  Text('카카오로 성인 인증',
                      style: TextStyle(
                          fontSize: 11, color: Color(0xFF999999))),
                ]),
          ]),
        ),

        const Gap(20),
        TextButton.icon(
          onPressed: _loadingQR ? null : _requestNewQR,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('QR 새로 생성'),
          style:
              TextButton.styleFrom(foregroundColor: Colors.white60),
        ),
        const Gap(8),
        const Text('QR은 10분간 유효 · 1회용',
            style:
                TextStyle(color: Colors.white38, fontSize: 11)),
      ]),
    );
  }

  Widget _buildProgressDots() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      ...List.generate(
          widget.requiredCount,
          (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _verifiedCount
                      ? Colors.green[500]
                      : Colors.white.withOpacity(0.12),
                  border: Border.all(
                    color: i < _verifiedCount
                        ? Colors.green[400]!
                        : Colors.white30,
                    width: 2,
                  ),
                ),
                child: Center(
                    child: i < _verifiedCount
                        ? const Icon(Icons.check_rounded,
                            size: 20, color: Colors.white)
                        : Text('${i + 1}',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w600))),
              )),
    ]);
  }
}

class _GuideRow extends StatelessWidget {
  final List<String> items;
  const _GuideRow({required this.items});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: items
            .map((item) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(item,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70)),
                  ),
                ))
            .toList(),
      );
}
