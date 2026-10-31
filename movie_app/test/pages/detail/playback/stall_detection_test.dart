import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/playback_lifecycle.dart';
import 'package:movie_app/pages/detail/playback/stall_detection.dart';

/// 缓冲耗尽停滞判定（2026-10-21 模拟器实测：断网播放到缓存用尽后 mpv 停在原地，
/// 恢复网络既不自动续播、点播放键也唤不醒，必须按进度重新 open 媒体）。
void main() {
  Duration s(int v) => Duration(seconds: v);

  group('isBufferExhaustedStall', () {
    test('缓冲用尽且未推进 → 判定为停滞', () {
      expect(
        isBufferExhaustedStall(
          duration: const Duration(hours: 2),
          position: s(135),
          bufferedPosition: s(135),
          isPlaying: false,
          isBuffering: false,
        ),
        isTrue,
      );
    });

    test('容差内（前后 1.5s 内）同样算停滞', () {
      expect(
        isBufferExhaustedStall(
          duration: const Duration(hours: 2),
          position: s(135),
          bufferedPosition: s(135) + const Duration(milliseconds: 1400),
          isPlaying: false,
          isBuffering: false,
        ),
        isTrue,
      );
    });

    test('正在播放 → 不是停滞（哪怕缓存贴近播放头）', () {
      expect(
        isBufferExhaustedStall(
          duration: const Duration(hours: 2),
          position: s(135),
          bufferedPosition: s(135),
          isPlaying: true,
          isBuffering: false,
        ),
        isFalse,
      );
    });

    test('正在缓冲 → 不是停滞（下载中即将恢复）', () {
      expect(
        isBufferExhaustedStall(
          duration: const Duration(hours: 2),
          position: s(135),
          bufferedPosition: s(135),
          isPlaying: false,
          isBuffering: true,
        ),
        isFalse,
      );
    });

    test('用户主动暂停且仍有富余缓存 → 不是停滞', () {
      expect(
        isBufferExhaustedStall(
          duration: const Duration(hours: 2),
          position: s(300),
          bufferedPosition: s(900),
          isPlaying: false,
          isBuffering: false,
        ),
        isFalse,
      );
    });

    test('时长未知（未打开媒体）→ 不是停滞', () {
      expect(
        isBufferExhaustedStall(
          duration: Duration.zero,
          position: Duration.zero,
          bufferedPosition: Duration.zero,
          isPlaying: false,
          isBuffering: false,
        ),
        isFalse,
      );
    });
  });

  group('shouldReloadInsteadOfResume', () {
    test('停滞中 → 走软重载', () {
      expect(
        shouldReloadInsteadOfResume(
          stalled: true,
          lifecycle: PlaybackLifecycle.paused,
        ),
        isTrue,
      );
    });

    test('未停滞 → 普通 resume', () {
      expect(
        shouldReloadInsteadOfResume(
          stalled: false,
          lifecycle: PlaybackLifecycle.playing,
        ),
        isFalse,
      );
    });

    test('生命周期已 error → 不软重载（源本身的问题交给重开路径）', () {
      expect(
        shouldReloadInsteadOfResume(
          stalled: true,
          lifecycle: PlaybackLifecycle.error,
        ),
        isFalse,
      );
    });

    test('生命周期已 ended → 不软重载', () {
      expect(
        shouldReloadInsteadOfResume(
          stalled: true,
          lifecycle: PlaybackLifecycle.ended,
        ),
        isFalse,
      );
    });
  });

  group('resolveReloadStartAt', () {
    test('权威进度与上报一致 → 用权威进度', () {
      expect(
        resolveReloadStartAt(
          authoritative: s(600),
          reported: s(604),
        ),
        s(600),
      );
    });

    test('权威进度明显脱节（续播点失效）→ 用实际上报位置', () {
      // 实测场景：权威值钉在 2944s，mpv 实际从 167s 处播。
      expect(
        resolveReloadStartAt(
          authoritative: s(2944),
          reported: s(167),
        ),
        s(167),
      );
    });

    test('偏差在容差内 → 仍以权威进度为准', () {
      expect(
        resolveReloadStartAt(
          authoritative: s(600),
          reported: s(590),
        ),
        s(600),
      );
    });

    test('偏差刚好超出容差 → 以实际上报为准（边界）', () {
      expect(
        resolveReloadStartAt(
          authoritative: s(600),
          reported: s(540),
        ),
        s(540),
      );
    });

    test('mpv 尚无上报（reported=0）→ 用权威进度', () {
      expect(
        resolveReloadStartAt(
          authoritative: s(120),
          reported: Duration.zero,
        ),
        s(120),
      );
    });
  });
}