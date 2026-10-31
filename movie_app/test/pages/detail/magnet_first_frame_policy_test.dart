import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/magnet_first_frame_policy.dart';

/// 磁力起播「首帧看门狗」规则回归测试。
///
/// 对应真机反馈（2026-10-28）：「磁力资源这个没有时长的黑屏，一直黑屏，
/// 换一个资源能播放」——截图里是 0:00 / 0:00。这里锁住「什么算出画」，
/// 避免以后把「同一部片的残留时长」当成出画而再次出现永久黑屏。
void main() {
  group('frameArrived', () {
    test('位置推进到阈值 → 出画', () {
      expect(
        MagnetFirstFramePolicy.frameArrived(
          beforePosition: Duration.zero,
          beforeDuration: Duration.zero,
          position: const Duration(milliseconds: 400),
          duration: Duration.zero,
        ),
        isTrue,
      );
    });

    test('位置只推进 399ms → 还不算出画', () {
      expect(
        MagnetFirstFramePolicy.frameArrived(
          beforePosition: Duration.zero,
          beforeDuration: Duration.zero,
          position: const Duration(milliseconds: 399),
          duration: Duration.zero,
        ),
        isFalse,
      );
    });

    test('位置推进但时长仍为 0（还没解析容器头）→ 出画', () {
      expect(
        MagnetFirstFramePolicy.frameArrived(
          beforePosition: const Duration(seconds: 3),
          beforeDuration: Duration.zero,
          position: const Duration(seconds: 4),
          duration: Duration.zero,
        ),
        isTrue,
      );
    });

    test('时长从 0 变成非零 → 出画', () {
      expect(
        MagnetFirstFramePolicy.frameArrived(
          beforePosition: Duration.zero,
          beforeDuration: Duration.zero,
          position: Duration.zero,
          duration: const Duration(hours: 2, minutes: 57),
        ),
        isTrue,
      );
    });

    test('时长是上一部片残留的旧值（未变化）→ 不算是新流出画', () {
      expect(
        MagnetFirstFramePolicy.frameArrived(
          beforePosition: Duration.zero,
          beforeDuration: const Duration(minutes: 90),
          position: Duration.zero,
          duration: const Duration(minutes: 90),
        ),
        isFalse,
      );
    });

    test('时长从旧值换成新值 → 出画', () {
      expect(
        MagnetFirstFramePolicy.frameArrived(
          beforePosition: Duration.zero,
          beforeDuration: const Duration(minutes: 90),
          position: Duration.zero,
          duration: const Duration(hours: 2, minutes: 57),
        ),
        isTrue,
      );
    });

    test('位置和时长都纹丝不动 → 黑屏，不冲出画', () {
      expect(
        MagnetFirstFramePolicy.frameArrived(
          beforePosition: Duration.zero,
          beforeDuration: Duration.zero,
          position: Duration.zero,
          duration: Duration.zero,
        ),
        isFalse,
      );
    });
  });

  group('giveUpReason', () {
    test('刚交接（25s 内）一律继续等，哪怕数据没动', () {
      expect(
        MagnetFirstFramePolicy.giveUpReason(
          elapsed: const Duration(seconds: 24),
          stalledFor: const Duration(seconds: 24),
        ),
        isNull,
      );
    });

    test('超过 25s 且连续 8s 没有任何数据流动 → 归因「节点不给数据」', () {
      expect(
        MagnetFirstFramePolicy.giveUpReason(
          elapsed: const Duration(seconds: 26),
          stalledFor: const Duration(seconds: 8),
        ),
        MagnetFirstFrameOutcome.noData,
      );
    });

    test('超过 25s 但数据还在动 → 继续等（慢种子不误杀）', () {
      expect(
        MagnetFirstFramePolicy.giveUpReason(
          elapsed: const Duration(seconds: 30),
          stalledFor: const Duration(seconds: 2),
        ),
        isNull,
      );
    });

    test('数据一直在动也不能无限等：40s 硬上限，归因「解不出画面」', () {
      expect(
        MagnetFirstFramePolicy.giveUpReason(
          elapsed: const Duration(seconds: 40),
          stalledFor: Duration.zero,
        ),
        MagnetFirstFrameOutcome.unsupported,
      );
    });
  });

  group('classifyStall（mpv 报错时）', () {
    test('已经 8s 没有数据 → 归因「节点不给数据」', () {
      expect(
        MagnetFirstFramePolicy.classifyStall(
          stalledFor: const Duration(seconds: 8),
        ),
        MagnetFirstFrameOutcome.noData,
      );
    });

    test('刚才还在流就报错 → 更像解码/封装问题', () {
      expect(
        MagnetFirstFramePolicy.classifyStall(
          stalledFor: const Duration(seconds: 1),
        ),
        MagnetFirstFrameOutcome.unsupported,
      );
    });
  });

  test('看门狗阈值：25s 判卡死、40s 硬上限、连续 2 次读不出画面才放弃', () {
    expect(MagnetFirstFramePolicy.stallTimeout, const Duration(seconds: 25));
    expect(MagnetFirstFramePolicy.hardTimeout, const Duration(seconds: 40));
    expect(MagnetFirstFramePolicy.maxNoFrameStrikes, 2);
    // 轮询间隔必须明显小于超时，否则一次重试都等不到判定。
    expect(
      MagnetFirstFramePolicy.pollInterval.inMilliseconds,
      lessThan(MagnetFirstFramePolicy.stallTimeout.inMilliseconds),
    );
  });
}
