import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/magnet_seek_visual_policy.dart';

/// 磁力 seek「等画面回来」的判定（2026-11-11 用户反馈：点进度条后加载
/// 提示先消失，画面还要再等几秒才出来）。
///
/// 「摘修复即红」用例 = `位置停在目标 + mpv 还在 seek + 缓存为 0` 必须继续
/// 显示加载：旧实现只等 `_pendingSeekTarget`，2.5s 兜底超时一到就撤掉了。
void main() {
  Duration s(num v) => Duration(milliseconds: (v * 1000).round());
  Duration ms(int v) => Duration(milliseconds: v);

  bool finish({
    Duration target = const Duration(seconds: 3046),
    Duration reported = const Duration(seconds: 3046),
    bool? seeking = true,
    Duration? cache = Duration.zero,
    bool playing = true,
    Duration elapsed = const Duration(seconds: 1),
  }) {
    return shouldFinishMagnetSeekVisualWait(
      target: target,
      reportedPosition: reported,
      mpvSeeking: seeking,
      cacheDuration: cache,
      playing: playing,
      elapsed: elapsed,
    );
  }

  group('继续等待（不能撤加载提示）', () {
    test('🔴 mpv 仍卡在 seek、位置钉在目标、缓存为 0 → 继续等（摘修复即红）', () {
      // 真机 14:50:05 seek 到 3046s：2.5s 超时后 pending 被清，但 mpv 直到
      // 4.9s 才推进位置。这段时间必须继续显示加载。
      expect(finish(elapsed: const Duration(milliseconds: 2900)), isFalse);
      expect(finish(elapsed: const Duration(seconds: 4)), isFalse);
    });

    test('mpv 已结束 seek 但缓存还没铺开 → 继续等', () {
      expect(
        finish(seeking: false, cache: ms(50), elapsed: s(2)),
        isFalse,
      );
    });

    test('缓存读不到（null）且位置没推进 → 不早撤', () {
      expect(
        finish(seeking: null, cache: null, elapsed: s(5)),
        isFalse,
      );
    });

    test('位置只比目标多 200ms → 还不算在放', () {
      expect(
        finish(reported: const Duration(seconds: 3046, milliseconds: 200)),
        isFalse,
      );
    });

    test('反向 seek 时 mpv 还报着旧位置 → 不能误判出画', () {
      // 用户从 1000s 拖到 100s，seek 刚发出时 time-pos 可能仍是 1000s。
      expect(
        finish(
          target: const Duration(seconds: 100),
          reported: const Duration(seconds: 1000),
          seeking: true,
          cache: Duration.zero,
          elapsed: s(1),
        ),
        isFalse,
      );
    });

    test('最小展示时长内一律不撤（避免快 seek 闪一下）', () {
      expect(
        finish(
          reported: const Duration(seconds: 3100),
          seeking: false,
          cache: s(5),
          elapsed: ms(120),
        ),
        isFalse,
      );
    });

    test('🔴 慢磁力 seek 20s 才出画 → 20s 时仍不能撤（实测 8121 兜底 15s 提前撤）', () {
      // 2026-11-11 17:09:48 seek → 6893s，日志实测：
      //   17:10:03.7 耗时=15002ms 命中 15s 兜底（此时 seeking=yes cache=0）
      //   17:10:08.6 才 seeking=no cache-duration=4.13  ← 真出画
      expect(finish(elapsed: s(15)), isFalse);
      expect(finish(elapsed: s(20)), isFalse);
      expect(finish(elapsed: s(30)), isFalse);
    });
  });

  group('可以结束（画面已回来）', () {
    test('位置真的越过目标 0.4s 以上 → 出画', () {
      expect(
        finish(
          reported: const Duration(seconds: 3046, milliseconds: 500),
          elapsed: s(1),
        ),
        isTrue,
      );
    });

    test('mpv 结束 seek 且目标附近有可播缓存 → 出画', () {
      expect(
        finish(seeking: false, cache: s(1), elapsed: s(1)),
        isTrue,
      );
    });

    test('暂停态：mpv 结束 seek 后过宽限期即撤（时钟不会走）', () {
      expect(
        finish(playing: false, seeking: false, cache: Duration.zero, elapsed: s(1)),
        isFalse,
      );
      expect(
        finish(playing: false, seeking: false, cache: Duration.zero, elapsed: s(2)),
        isTrue,
      );
    });

    test('🔴 超时也不静默撤加载（0 peer 死区实测 45s 仍未出画）', () {
      // 2026-11-11 17:24:55 反向 seek 到 4791s，日志：供数停滞 20s、peers=0，
      // 45s 时仍 seeking=yes cache=0。此时撤掉加载提示 = 画面还冻在旧帧却
      // 没有任何提示，正是用户反馈的现象。改为：超时只升级文案，不撤。
      expect(finish(elapsed: kMagnetSeekVisualSoftTimeout), isFalse);
      expect(finish(elapsed: s(60)), isFalse);
      expect(finish(elapsed: s(120)), isFalse);
    });
  });

  group('mpv 属性解析', () {
    test('秒数', () {
      expect(parseMpvSeconds('3046.421000'), s(3046.421));
      expect(parseMpvSeconds('  1.5 '), ms(1500));
      expect(parseMpvSeconds('0'), Duration.zero);
    });

    test('读不到 / 脏值一律 null（按无证据处理）', () {
      expect(parseMpvSeconds(null), isNull);
      expect(parseMpvSeconds(''), isNull);
      expect(parseMpvSeconds('nan'), isNull);
      expect(parseMpvSeconds('inf'), isNull);
      expect(parseMpvSeconds('-3'), isNull);
    });

    test('布尔属性', () {
      expect(parseMpvFlag('yes'), isTrue);
      expect(parseMpvFlag('no'), isFalse);
      expect(parseMpvFlag('YES'), isTrue);
      expect(parseMpvFlag(null), isNull);
      expect(parseMpvFlag(''), isNull);
    });
  });

  group('常量约束', () {
    test('超时提示要明显长于进度权威的 2.5s 落位超时', () {
      expect(
        kMagnetSeekVisualSoftTimeout,
        greaterThan(const Duration(seconds: 5)),
      );
    });

    test('最小展示短于超时提示，避免互相打架', () {
      expect(
        kMagnetSeekVisualMinShow,
        lessThan(kMagnetSeekVisualSoftTimeout),
      );
    });

    test('超时提示要覆盖实测 20s 的慢磁力出画', () {
      expect(
        kMagnetSeekVisualSoftTimeout,
        greaterThanOrEqualTo(const Duration(seconds: 30)),
      );
    });

    test('慢缓冲提示早于超时提示触发', () {
      expect(
        kMagnetSeekVisualSlowHint,
        lessThan(kMagnetSeekVisualSoftTimeout),
      );
    });
  });
}
