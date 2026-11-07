/// 断点纠偏（discontinuity 恢复 seek）失败计数策略。
///
/// 断网时 mpv 会把读不到的 HLS 流报成「提前播完」，触发纠偏；而纠偏 seek 在
/// 死流上必然落空，形成每 30s 一次的无效循环（2026-10-21 模拟器实测）。因此连续
/// 失败达到 [maxAttempts] 后必须放弃纠偏，并把权威进度对齐到播放器实际上报。
class DiscontinuityRecoveryPolicy {
  DiscontinuityRecoveryPolicy({this.maxAttempts = 3});

  /// 连续失败多少次后放弃纠偏。
  final int maxAttempts;

  int _failures = 0;
  bool _disabled = false;

  /// 当前 open 代次；换集/重开媒体后自动复位（新流值得重新尝试纠偏）。
  int _generation = -1;

  int get failures => _failures;

  bool get disabled => _disabled;

  /// 当前 open 代次。
  int get generation => _generation;

  /// 换 open 代次时复位；返回是否发生了复位。
  bool syncGeneration(int generation) {
    if (_generation == generation) return false;
    _generation = generation;
    _failures = 0;
    _disabled = false;
    return true;
  }

  /// 记一次失败；返回 true 表示达到上限、应放弃纠偏。
  bool recordFailure() {
    if (_disabled) return true;
    _failures++;
    if (_failures < maxAttempts) return false;
    _disabled = true;
    return true;
  }

  /// 落位成功即清零失败计数（纠偏重新变得可信）。
  void recordSuccess() {
    _failures = 0;
  }
}