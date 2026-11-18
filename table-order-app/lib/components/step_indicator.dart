import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

class StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  const StepIndicator({super.key, required this.currentStep, required this.totalSteps});

  static const _labels = ['신분증 스캔', 'OTP 인증', '생체 인증'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSteps, (i) {
        final stepNum = i + 1;
        final done = stepNum < currentStep;
        final active = stepNum == currentStep;
        return Expanded(
          child: Row(
            children: [
              Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: done ? const Color(0xFF2EA84A) : active ? const Color(0xFF1A73E8) : const Color(0xFF30363D),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: done
                          ? const Icon(Icons.check, size: 16, color: Colors.white)
                          : Text('$stepNum', style: TextStyle(color: active ? Colors.white : Colors.white38, fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const Gap(4),
                  Text(
                    _labels[i],
                    style: TextStyle(
                      color: active ? Colors.white : Colors.white38,
                      fontSize: 10,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
              if (stepNum < totalSteps)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 16),
                    color: done ? const Color(0xFF2EA84A) : const Color(0xFF30363D),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}
