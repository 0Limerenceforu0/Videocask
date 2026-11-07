import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/player_chrome_policy.dart';

/// 「磁力加载中没有任何返回入口」的回归测试（2026-10-28 真机反馈）。
///
/// 现场：磁力资源解析到「解析种子元数据」第 35 秒，控制栏早已自动隐藏，
/// 而 VideoController 要等元数据拿到才创建 → 隐藏态返回按钮不满足
/// `videoController != null`，整个播放器区域没有任何出口。
void main() {
  bool show({
    bool hasVideoController = false,
    bool controlsVisible = false,
    bool fullScreen = false,
    bool screenLocked = false,
    bool magnetBusyOrFailed = false,
  }) {
    return shouldShowPersistentPlayerBackButton(
      hasVideoController: hasVideoController,
      controlsVisible: controlsVisible,
      fullScreen: fullScreen,
      screenLocked: screenLocked,
      magnetBusyOrFailed: magnetBusyOrFailed,
    );
  }

  test('磁力准备中、控制栏已隐藏、控制器尚未创建 → 必须显示返回', () {
    expect(show(magnetBusyOrFailed: true), isTrue);
  });

  test('磁力失败（错误卡片独占画面）→ 必须显示返回', () {
    // 错误卡片只有「再试一次」，退出得靠这个按钮。
    expect(show(magnetBusyOrFailed: true), isTrue);
  });

  test('普通在线播放、控制栏隐藏 → 仍然保留返回', () {
    expect(show(hasVideoController: true), isTrue);
  });

  test('控制栏可见时不重复画一个返回', () {
    // 顶部栏自己带返回；再叠一个会出现两个图标。
    expect(show(hasVideoController: true, controlsVisible: true), isFalse);
    expect(show(magnetBusyOrFailed: true, controlsVisible: true), isFalse);
  });

  test('全屏 / 锁屏交给各自的出口', () {
    expect(show(hasVideoController: true, fullScreen: true), isFalse);
    expect(show(hasVideoController: true, screenLocked: true), isFalse);
    expect(show(magnetBusyOrFailed: true, screenLocked: true), isFalse);
  });

  test('既无控制器也无磁力状态（空播放器）→ 不凭空出现返回', () {
    expect(show(), isFalse);
  });

  // 2026-11-07：点进度条 → mpv 正在向未缓冲位置 seek、没有画面，
  // 控制栏若照常 3 秒隐藏，用户就「既黑屏又丢了进度条」。
  bool startTimer({
    bool controlsVisible = true,
    bool helpVisible = false,
    bool buffering = false,
    bool openingMedia = false,
    bool magnetPreparing = false,
    bool seekLandingPending = false,
  }) {
    return shouldStartControlsHideTimer(
      controlsVisible: controlsVisible,
      helpVisible: helpVisible,
      buffering: buffering,
      openingMedia: openingMedia,
      magnetPreparing: magnetPreparing,
      seekLandingPending: seekLandingPending,
    );
  }

  group('shouldStartControlsHideTimer', () {
    test('稳态播放 → 正常启动 3 秒隐藏计时', () {
      expect(startTimer(), isTrue);
    });

    test('🔴 seek 未落位 → 控制栏常驻（摘修复即红）', () {
      expect(startTimer(seekLandingPending: true), isFalse);
    });

    test('🔴 缓冲中 → 控制栏常驻（摘修复即红）', () {
      expect(startTimer(buffering: true), isFalse);
    });

    test('打开媒体 / 磁力准备中 → 控制栏常驻', () {
      expect(startTimer(openingMedia: true), isFalse);
      expect(startTimer(magnetPreparing: true), isFalse);
    });

    test('控制栏本来隐藏 / 帮助面板打开 → 不需要隐藏计时', () {
      expect(startTimer(controlsVisible: false), isFalse);
      expect(startTimer(helpVisible: true), isFalse);
    });

    test('多个忙碌状态叠加仍常驻', () {
      expect(
        startTimer(buffering: true, seekLandingPending: true),
        isFalse,
      );
    });
  });
}
