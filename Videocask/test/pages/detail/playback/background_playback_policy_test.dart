import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/background_playback_policy.dart';

void main() {
  group('切后台（paused）', () {
    test('开启后台播放 + 正在播 → 不动，继续播', () {
      expect(
        decideBackgroundPlaybackAction(
          state: AppLifecycleState.paused,
          backgroundPlaybackAllowed: true,
          isPlaying: true,
          pausedByBackground: false,
        ),
        BackgroundPlaybackAction.none,
      );
    });

    test('关闭后台播放 + 正在播 → 暂停', () {
      expect(
        decideBackgroundPlaybackAction(
          state: AppLifecycleState.paused,
          backgroundPlaybackAllowed: false,
          isPlaying: true,
          pausedByBackground: false,
        ),
        BackgroundPlaybackAction.pause,
      );
    });

    test('关闭后台播放但本来就没在播 → 不重复暂停', () {
      expect(
        decideBackgroundPlaybackAction(
          state: AppLifecycleState.paused,
          backgroundPlaybackAllowed: false,
          isPlaying: false,
          pausedByBackground: false,
        ),
        BackgroundPlaybackAction.none,
      );
    });
  });

  group('回前台（resumed）', () {
    test('之前是本页暂停的 → 恢复', () {
      expect(
        decideBackgroundPlaybackAction(
          state: AppLifecycleState.resumed,
          backgroundPlaybackAllowed: false,
          isPlaying: false,
          pausedByBackground: true,
        ),
        BackgroundPlaybackAction.resume,
      );
    });

    test('用户自己按的暂停 → 绝不抢着播', () {
      expect(
        decideBackgroundPlaybackAction(
          state: AppLifecycleState.resumed,
          backgroundPlaybackAllowed: true,
          isPlaying: false,
          pausedByBackground: false,
        ),
        BackgroundPlaybackAction.none,
      );
    });

    test('暂停标记优先于开关：中途关掉后台播放也要把暂停还回去', () {
      expect(
        decideBackgroundPlaybackAction(
          state: AppLifecycleState.resumed,
          backgroundPlaybackAllowed: true,
          isPlaying: false,
          pausedByBackground: true,
        ),
        BackgroundPlaybackAction.resume,
      );
    });
  });

  group('过渡态不能误伤', () {
    test('inactive（下拉通知栏/来电横幅）不暂停', () {
      expect(
        decideBackgroundPlaybackAction(
          state: AppLifecycleState.inactive,
          backgroundPlaybackAllowed: false,
          isPlaying: true,
          pausedByBackground: false,
        ),
        BackgroundPlaybackAction.none,
      );
    });

    test('hidden 不暂停（paused 的前置过渡）', () {
      expect(
        decideBackgroundPlaybackAction(
          state: AppLifecycleState.hidden,
          backgroundPlaybackAllowed: false,
          isPlaying: true,
          pausedByBackground: false,
        ),
        BackgroundPlaybackAction.none,
      );
    });

    test('detached 不暂停（进程要走了，暂停也没意义）', () {
      expect(
        decideBackgroundPlaybackAction(
          state: AppLifecycleState.detached,
          backgroundPlaybackAllowed: false,
          isPlaying: true,
          pausedByBackground: false,
        ),
        BackgroundPlaybackAction.none,
      );
    });
  });

  group('前台服务保活条件', () {
    test('只有「进后台 + 允许后台播放 + 在播」才拉起服务', () {
      expect(
        shouldHoldForegroundService(
          state: AppLifecycleState.paused,
          backgroundPlaybackAllowed: true,
          isPlaying: true,
        ),
        isTrue,
      );
    });

    test('关掉后台播放时不该拉起服务', () {
      expect(
        shouldHoldForegroundService(
          state: AppLifecycleState.paused,
          backgroundPlaybackAllowed: false,
          isPlaying: true,
        ),
        isFalse,
      );
    });

    test('没在播也不拉（避免空通知）', () {
      expect(
        shouldHoldForegroundService(
          state: AppLifecycleState.paused,
          backgroundPlaybackAllowed: true,
          isPlaying: false,
        ),
        isFalse,
      );
    });

    test('前台时不需要服务', () {
      expect(
        shouldHoldForegroundService(
          state: AppLifecycleState.resumed,
          backgroundPlaybackAllowed: true,
          isPlaying: true,
        ),
        isFalse,
      );
    });
  });
}
