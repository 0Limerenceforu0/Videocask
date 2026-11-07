import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/seek_landing_policy.dart';

/// 在途 seek 的位置上报裁决（2026-11-07 用户反馈：点进度条再点暂停，
/// 进度被拽回旧位置）。
///
/// 「摘修复即红」用例 = 「seek 前的旧上报必须整条丢弃」：旧实现在 mpv
/// `seek` 命令返回时就结束 seeking，这条旧上报会被 PlayheadAuthority
/// 判成回跳 → discontinuity → 纠偏 / 采纳旧值，播放位置全错。
void main() {
  Duration s(int v) => Duration(seconds: v);

  group('classifySeekPosition', () {
    test('没有在途 seek → 走常规 ingest', () {
      expect(
        classifySeekPosition(pendingTarget: null, reported: s(120)),
        SeekPositionVerdict.noPendingSeek,
      );
    });

    test('落位：正好落在目标', () {
      expect(
        classifySeekPosition(pendingTarget: s(3000), reported: s(3000)),
        SeekPositionVerdict.landed,
      );
    });

    test('落位：关键帧级别的小偏差仍算落位', () {
      expect(
        classifySeekPosition(
          pendingTarget: s(3000),
          reported: s(3002),
          tolerance: const Duration(seconds: 3),
        ),
        SeekPositionVerdict.landed,
      );
      expect(
        classifySeekPosition(
          pendingTarget: s(3000),
          reported: s(2998),
          tolerance: const Duration(seconds: 3),
        ),
        SeekPositionVerdict.landed,
      );
    });

    test('🔴 seek 前的旧上报必须整条丢弃（摘修复即红）', () {
      // 用户从 2:00 拖到 50:00，mpv 在 seek 真正落位前仍上报 2:00。
      expect(
        classifySeekPosition(pendingTarget: s(3000), reported: s(120)),
        SeekPositionVerdict.ignoreStale,
      );
      // 归零型流重连上报同样不能污染权威进度。
      expect(
        classifySeekPosition(pendingTarget: s(3000), reported: Duration.zero),
        SeekPositionVerdict.ignoreStale,
      );
    });

    test('超出容差但尚未超时 → 继续等待，不结束 seeking', () {
      expect(
        classifySeekPosition(pendingTarget: s(3000), reported: s(2990)),
        SeekPositionVerdict.ignoreStale,
      );
    });

    test('seek 到片头（目标 0）时 0 上报算落位', () {
      expect(
        classifySeekPosition(
            pendingTarget: Duration.zero, reported: Duration.zero),
        SeekPositionVerdict.landed,
      );
    });

    test('自定义容差生效', () {
      expect(
        classifySeekPosition(
          pendingTarget: s(3000),
          reported: s(3005),
          tolerance: const Duration(seconds: 10),
        ),
        SeekPositionVerdict.landed,
      );
    });
  });

  group('常量约束', () {
    test('兜底超时必须有限且短于控制栏隐藏时间之外', () {
      expect(kSeekLandingTimeout.inMilliseconds, greaterThan(0));
      expect(kSeekLandingTimeout.inMilliseconds, lessThanOrEqualTo(5000));
    });
  });
}
