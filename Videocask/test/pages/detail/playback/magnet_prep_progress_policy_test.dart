import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/magnet_prep_progress_policy.dart';

/// 磁力准备进度条取值规则（2026-11-03 真机实测后重做）。
///
/// 旧规则的缺陷：一律按「第 N/6 步」线性映射，卡在第 5 步时进度条一直停在
/// 5/7 不动，用户以为「马上就好」。新规则的核心契约是 **该不确定的时候就
/// 返回 null（不确定态），不撒谎**。
void main() {
  const stageTotal = 6;

  double? value({
    required int stage,
    required Duration stageElapsed,
    int bufferPct = 0,
    int torrentStep = 3,
    bool showStages = true,
  }) {
    return MagnetPrepProgressPolicy.progressValue(
      torrentStep: torrentStep,
      torrentStage: stage,
      stageTotal: stageTotal,
      bufferPct: bufferPct,
      stageElapsed: stageElapsed,
      showStages: showStages,
    );
  }

  group('阶段推进正常时按阶段线性映射', () {
    test('阶段 2 刚进入 → 2/7', () {
      expect(
        value(stage: 2, stageElapsed: const Duration(seconds: 1)),
        closeTo(2 / 7, 1e-9),
      );
    });

    test('阶段 4 刚进入 → 4/7', () {
      expect(
        value(stage: 4, stageElapsed: const Duration(seconds: 3)),
        closeTo(4 / 7, 1e-9),
      );
    });
  });

  group('卡在同一阶段超过阈值 → 不确定态', () {
    test('阶段 2 卡 12s（解析元数据打洞失败）不再画推进', () {
      expect(
        value(stage: 2, stageElapsed: const Duration(seconds: 12)),
        isNull,
      );
    });

    test('阶段 3 卡 40s（连不上节点）不确定', () {
      expect(
        value(stage: 3, stageElapsed: const Duration(seconds: 40)),
        isNull,
      );
    });

    test('阈值前（11s）仍按阶段映射', () {
      expect(
        value(stage: 3, stageElapsed: const Duration(seconds: 11)),
        closeTo(3 / 7, 1e-9),
      );
    });
  });

  group('缓冲阶段用真实缓冲百分比', () {
    test('有缓冲数据时不再用阶段号糊弄', () {
      expect(
        value(
          stage: 5,
          stageElapsed: const Duration(seconds: 30),
          bufferPct: 12,
        ),
        closeTo(0.12, 1e-9),
      );
    });

    test('零缓冲且已卡住 → 不确定态（旧版这里一直停在 71%）', () {
      expect(
        value(
          stage: 5,
          stageElapsed: const Duration(seconds: 30),
          bufferPct: 0,
        ),
        isNull,
      );
    });

    test('缓冲满 → 1.0', () {
      expect(
        value(
          stage: 5,
          stageElapsed: const Duration(seconds: 5),
          bufferPct: 100,
        ),
        1.0,
      );
    });
  });

  group('已交给播放器（等首帧）→ 直接不确定态', () {
    test('阶段 6 不画 100%（等首帧多久完全取决于封装/解码）', () {
      expect(
        value(
          stage: 6,
          stageElapsed: const Duration(seconds: 1),
          bufferPct: 100,
        ),
        isNull,
      );
    });
  });

  group('无阶段信息时回退到 torrentStep 映射', () {
    test('有缓冲百分比用缓冲', () {
      expect(
        value(
          stage: 0,
          stageElapsed: Duration.zero,
          bufferPct: 40,
          showStages: false,
        ),
        closeTo(0.4, 1e-9),
      );
    });

    test('无缓冲时按 step/4', () {
      expect(
        value(
          stage: 0,
          stageElapsed: Duration.zero,
          torrentStep: 3,
          showStages: false,
        ),
        closeTo(0.75, 1e-9),
      );
    });

    test('未开始（step<=0）给最小可见值', () {
      expect(
        value(
          stage: 0,
          stageElapsed: Duration.zero,
          torrentStep: 0,
          showStages: false,
        ),
        0.05,
      );
    });
  });

  group('showStages 判据', () {
    bool show({
      required int stage,
      String label = '第 3/6 步 · 连接节点',
      bool deadSwarm = false,
      int total = stageTotal,
    }) {
      return MagnetPrepProgressPolicy.showStages(
        stageTotal: total,
        torrentStage: stage,
        stageProgressLabel: label,
        deadSwarm: deadSwarm,
      );
    }

    test('阶段信息齐全 → true', () {
      expect(show(stage: 3), isTrue);
    });

    test('阶段未开始/失败 → false', () {
      expect(show(stage: 0), isFalse);
      expect(show(stage: -1), isFalse);
    });

    test('无阶段文案 → false', () {
      expect(show(stage: 3, label: '   '), isFalse);
    });

    test('已判定连不上节点 → false（结论优先）', () {
      expect(show(stage: 5, deadSwarm: true), isFalse);
    });
  });
}
