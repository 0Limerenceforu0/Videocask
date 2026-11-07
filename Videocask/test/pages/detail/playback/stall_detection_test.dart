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

    test('正在播放且位置在推进 → 不是停滞（哪怕缓存贴近播放头）', () {
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

    test('playing=true 但位置不推进 → 仍是停滞（mpv 僵死 34 分钟的现场）', () {
      expect(
        isBufferExhaustedStall(
          duration: const Duration(hours: 2),
          position: s(135),
          bufferedPosition: s(135),
          isPlaying: true,
          isBuffering: false,
          advancing: false,
        ),
        isTrue,
      );
    });

    test('playing=true、不推进、但缓存还有富余 → 不是停滞（还在下载）', () {
      expect(
        isBufferExhaustedStall(
          duration: const Duration(hours: 2),
          position: s(135),
          bufferedPosition: s(900),
          isPlaying: true,
          isBuffering: false,
          advancing: false,
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

    test('🔴 seek 到未缓冲点后用户主动暂停 → 不是停滞（摘修复即红）', () {
      // 2026-11-07 现场：点进度条后立刻暂停，缓冲前沿恰好贴合播放头，
      // 旧判据（靠「暂停时缓存还有富余」区分）失效 → 被当成缓冲耗尽停滞，
      // 点播放就走软重载，画面回来时位置已经被拽回 seek 之前。
      expect(
        isBufferExhaustedStall(
          duration: const Duration(hours: 2),
          position: s(3000),
          bufferedPosition: s(3000),
          isPlaying: false,
          isBuffering: false,
          userPaused: true,
        ),
        isFalse,
      );
    });

    test('用户暂停豁免不影响「mpv 僵死但 playing=true」的判定', () {
      expect(
        isBufferExhaustedStall(
          duration: const Duration(hours: 2),
          position: s(135),
          bufferedPosition: s(135),
          isPlaying: true,
          isBuffering: false,
          advancing: false,
          userPaused: true,
        ),
        isTrue,
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

    test('🔴 刚显式 seek 过 → 软重载优先用用户选的位置（摘修复即红）', () {
      // 用户从 2:00 拖到 50:00，mpv 迟到的旧上报仍是 2:00。
      // 旧实现按「偏差>30s 以实际上报为准」会把重载起点定成 2:00，
      // 于是「过一会恢复画面，但是播放位置完全不对」。
      expect(
        resolveReloadStartAt(
          authoritative: s(3000),
          reported: s(120),
          preferAuthoritative: true,
        ),
        s(3000),
      );
    });

    test('未处于显式 seek 保护窗口 → 仍按脱节规则用实际上报', () {
      expect(
        resolveReloadStartAt(
          authoritative: s(3000),
          reported: s(120),
          preferAuthoritative: false,
        ),
        s(120),
      );
    });
  });
}