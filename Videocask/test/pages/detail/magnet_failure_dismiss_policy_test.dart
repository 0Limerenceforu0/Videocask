import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/magnet_failure_dismiss_policy.dart';

/// 磁力失败态「自动撤销」规则回归测试。
///
/// 对应真机反馈（2026-11-07）：「都已经正常播放了，为什么还是有失败弹窗」。
/// 首帧看门狗在窗口末尾判失败，慢种子却在那之后才出画面；失败态本身不会
/// 自己消失，于是卡片一直压在一个正在播的视频上。这里锁住「什么才算真的
/// 在播」——只认连续往前推，seek 跳变和回退都不算。
void main() {
  group('accumulate', () {
    test('正常推进两段各 500ms → 累计 1000ms', () {
      final first = MagnetFailureDismissPolicy.accumulate(
        accumulated: Duration.zero,
        previousPosition: Duration.zero,
        currentPosition: const Duration(milliseconds: 500),
      );
      final second = MagnetFailureDismissPolicy.accumulate(
        accumulated: first,
        previousPosition: const Duration(milliseconds: 500),
        currentPosition: const Duration(milliseconds: 1000),
      );
      expect(second, const Duration(milliseconds: 1000));
    });

    test('位置原地不动 → 清零（画面是死的，不能当在播）', () {
      expect(
        MagnetFailureDismissPolicy.accumulate(
          accumulated: const Duration(milliseconds: 800),
          previousPosition: const Duration(seconds: 10),
          currentPosition: const Duration(seconds: 10),
        ),
        Duration.zero,
      );
    });

    test('位置回退 → 清零', () {
      expect(
        MagnetFailureDismissPolicy.accumulate(
          accumulated: const Duration(milliseconds: 800),
          previousPosition: const Duration(seconds: 10),
          currentPosition: const Duration(seconds: 9),
        ),
        Duration.zero,
      );
    });

    test('拖动进度条造成的大跳变 → 清零（seek 不是播放证据）', () {
      expect(
        MagnetFailureDismissPolicy.accumulate(
          accumulated: const Duration(milliseconds: 900),
          previousPosition: const Duration(seconds: 5),
          currentPosition: const Duration(minutes: 12),
        ),
        Duration.zero,
      );
    });

    test('刚好等于跳变阈值仍算正常推进（不误杀慢机型的粗粒度回调）', () {
      expect(
        MagnetFailureDismissPolicy.accumulate(
          accumulated: Duration.zero,
          previousPosition: Duration.zero,
          currentPosition: const Duration(seconds: 3),
        ),
        const Duration(seconds: 3),
      );
    });

    test('跳变清零后可以重新累计', () {
      final afterJump = MagnetFailureDismissPolicy.accumulate(
        accumulated: const Duration(seconds: 2),
        previousPosition: const Duration(seconds: 1),
        currentPosition: const Duration(minutes: 5),
      );
      expect(afterJump, Duration.zero);
      final resumed = MagnetFailureDismissPolicy.accumulate(
        accumulated: afterJump,
        previousPosition: const Duration(minutes: 5),
        currentPosition: const Duration(minutes: 5, milliseconds: 600),
      );
      expect(resumed, const Duration(milliseconds: 600));
    });
  });

  group('shouldDismiss', () {
    test('磁力失败 + 连续推进满 1s → 撤销', () {
      expect(
        MagnetFailureDismissPolicy.shouldDismiss(
          magnetFailed: true,
          accumulated: const Duration(seconds: 1),
        ),
        isTrue,
      );
    });

    test('磁力失败 + 只推进 999ms → 还不撤销', () {
      expect(
        MagnetFailureDismissPolicy.shouldDismiss(
          magnetFailed: true,
          accumulated: const Duration(milliseconds: 999),
        ),
        isFalse,
      );
    });

    test('不是磁力失败态 → 永不撤销（在线源失败有自己的重试链路）', () {
      expect(
        MagnetFailureDismissPolicy.shouldDismiss(
          magnetFailed: false,
          accumulated: const Duration(seconds: 30),
        ),
        isFalse,
      );
    });
  });
}
