import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DetectStatus { idle, initializing, previewing, detecting, done, failed }

class PeopleCountState {
  final int total;
  final int adults;
  final bool allClearlyAdult;
  final DetectStatus status;
  final String? error;
  final String? stage; // 현재 진행 단계 메시지

  const PeopleCountState({
    this.total = 0,
    this.adults = 0,
    this.allClearlyAdult = false,
    this.status = DetectStatus.idle,
    this.error,
    this.stage,
  });

  PeopleCountState copyWith({
    int? total, int? adults, bool? allClearlyAdult,
    DetectStatus? status, String? error, String? stage,
  }) => PeopleCountState(
    total: total ?? this.total,
    adults: adults ?? this.adults,
    allClearlyAdult: allClearlyAdult ?? this.allClearlyAdult,
    status: status ?? this.status,
    error: error ?? this.error,
    stage: stage ?? this.stage,
  );

  bool get isDone => status == DetectStatus.done;
  bool get isFailed => status == DetectStatus.failed;
  bool get isActive => status == DetectStatus.previewing || status == DetectStatus.detecting || status == DetectStatus.initializing;
}

class PeopleCountNotifier extends StateNotifier<PeopleCountState> {
  PeopleCountNotifier() : super(const PeopleCountState());

  void setStatus(DetectStatus s) => state = state.copyWith(status: s, stage: null);
  void setStage(String msg) => state = state.copyWith(stage: msg);

  void setResult(int total, int adults, {bool allClearlyAdult = false}) =>
      state = state.copyWith(
        total: total, adults: adults,
        allClearlyAdult: allClearlyAdult,
        status: DetectStatus.done,
      );

  void setError(String err) => state = state.copyWith(
    status: DetectStatus.failed, error: err,
  );

  void reset() => state = const PeopleCountState();
}

final peopleCountProvider = StateNotifierProvider<PeopleCountNotifier, PeopleCountState>(
  (ref) => PeopleCountNotifier(),
);
