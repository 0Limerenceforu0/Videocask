/// 磁力准备进度条的取值规则（纯函数，可单测）。
///
/// 背景（2026-11-03 真机实测）：进度条原本按「第 N/6 步」线性映射，于是
/// 卡在「第 5/6 步 · 缓冲首段数据」时会一直停在 5/7 ≈ 71% 不动 —— 看着像
/// 「马上就好」，实际可能还要等 30s+，甚至整轮失败后从头再来。阶段号根本
/// 不代表完成度，线性映射必然撒谎。
///
/// 规则（按优先级）：
/// * 已交给播放器（阶段 6，等首帧）：时长无法预估 → 不确定态；
/// * 阶段 5 起：有真实缓冲百分比就用真实数据，不再用阶段号糊弄；
/// * 其余阶段：卡在同一阶段超过 [stallThreshold] → 不确定态（来回扫动），
///   不再假装还在推进；
/// * 完全没有阶段信息（Web 云端代理 / 早期版本）→ 回退到 [torrentStep] 映射。
abstract final class MagnetPrepProgressPolicy {
  /// 同一阶段停留多久算「无法预估」。
  ///
  /// 阶段 2/3（解析元数据、连节点）正常几秒内就过，12s 还不动基本就是
  /// 卡在打洞或 tracker 上，再画一条缓慢推进的进度条只会误导。
  static const Duration stallThreshold = Duration(seconds: 12);

  /// 从这个阶段起，进度以真实缓冲百分比为准（5 = 缓冲首段数据）。
  static const int bufferDrivenFromStage = 5;

  /// 交接给播放器、等首帧的阶段（6 = 交给播放器起播）。
  static const int handoffStage = 6;

  /// 是否走「第 N/M 步」模式：阶段信息齐全且尚未判定连不上节点。
  ///
  /// 抽出来是因为文案（显示哪一步）和进度条（画到哪）必须用同一个判据，
  /// 否则会出现「写着第 5 步、进度条按另一套规则画」的错位。
  static bool showStages({
    required int stageTotal,
    required int torrentStage,
    required String stageProgressLabel,
    required bool deadSwarm,
  }) {
    // 已判定「连不上任何节点」时结论优先：不再让步骤假装在推进。
    return stageTotal > 0 &&
        torrentStage > 0 &&
        stageProgressLabel.trim().isNotEmpty &&
        !deadSwarm;
  }

  /// 进度条取值（0.0~1.0）；返回 **null 表示不确定态**（来回扫动）。
  static double? progressValue({
    required int torrentStep,
    required int torrentStage,
    required int stageTotal,
    required int bufferPct,
    required Duration stageElapsed,
    required bool showStages,
  }) {
    if (showStages) {
      // 已交给播放器：等首帧多久完全取决于封装/解码，画 100% 是撒谎。
      if (torrentStage >= handoffStage) return null;
      // 缓冲阶段有真实百分比 —— 用真实数据，别用阶段号糊弄。
      if (torrentStage >= bufferDrivenFromStage && bufferPct > 0) {
        return (bufferPct / 100).clamp(0.02, 1.0);
      }
      if (stageElapsed >= stallThreshold) return null;
      return (torrentStage / (stageTotal + 1)).clamp(0.05, 1.0);
    }
    if (bufferPct > 0) return (bufferPct / 100).clamp(0.02, 1.0);
    if (torrentStep <= 0) return 0.05;
    return (torrentStep / 4).clamp(0.05, 1.0);
  }
}
