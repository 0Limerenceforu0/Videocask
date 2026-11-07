import 'package:flutter/widgets.dart';

/// 前后台切换时对播放器的处理动作。
enum BackgroundPlaybackAction {
  /// 什么都不做（例如切到 inactive/hidden，或后台播放开着继续播）。
  none,

  /// 进入后台且不允许后台播放 → 暂停。
  pause,

  /// 回到前台且之前是我们暂停的 → 恢复。
  resume,
}

/// 前后台播放策略（纯函数，便于单测）。
///
/// 历史背景：`media_kit_video` 的 [Video] 组件默认
/// `pauseUponEnteringBackgroundMode = true` 且
/// `resumeUponEnteringForegroundMode = false`，即「切后台自动暂停、回前台
/// 不恢复」。实测 3/3 复现：切出去 60 秒回来，`pos` 停在 920s、
/// `playing=false`，必须手动点一下。
///
/// 所以这里把这两个开关都关掉，改由本策略统一决定——
/// 这样「后台播放」这个用户开关才有意义。
///
/// 规则：
/// 1. 只有 [AppLifecycleState.paused] 才算「真的进后台」。
///    `inactive` 在 Android 上会因下拉通知栏/来电横幅频繁触发，不能暂停；
///    `hidden` 是 paused 的前置过渡态，同样不动。
/// 2. 允许后台播放 → 进后台不暂停（配合前台服务保活）。
/// 3. 不允许后台播放 → 进后台暂停，并打上 [pausedByBackground] 标记，
///    回前台时无条件恢复（哪怕用户后来把开关关了，也得把暂停还回去）。
BackgroundPlaybackAction decideBackgroundPlaybackAction({
  required AppLifecycleState state,
  required bool backgroundPlaybackAllowed,
  required bool isPlaying,
  required bool pausedByBackground,
}) {
  switch (state) {
    case AppLifecycleState.paused:
      if (!backgroundPlaybackAllowed && isPlaying) {
        return BackgroundPlaybackAction.pause;
      }
      return BackgroundPlaybackAction.none;
    case AppLifecycleState.resumed:
      if (pausedByBackground) return BackgroundPlaybackAction.resume;
      return BackgroundPlaybackAction.none;
    case AppLifecycleState.inactive:
    case AppLifecycleState.hidden:
    case AppLifecycleState.detached:
      return BackgroundPlaybackAction.none;
  }
}

/// 是否需要在前台服务保活（只有「允许后台播放 + 确实在播」才需要）。
bool shouldHoldForegroundService({
  required AppLifecycleState state,
  required bool backgroundPlaybackAllowed,
  required bool isPlaying,
}) {
  return state == AppLifecycleState.paused &&
      backgroundPlaybackAllowed &&
      isPlaying;
}
