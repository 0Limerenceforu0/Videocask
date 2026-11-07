import 'package:flutter/services.dart' show LogicalKeyboardKey;

/// 详情页播放器快捷键的动作。
///
/// 抽成纯函数是为了让「键位 → 动作」与「页面焦点 / 弹窗 / 全屏」彻底解耦：
/// 旧的快捷键挂在播放器子树内的 [KeyboardListener] 上，一旦切全屏整棵子树
/// 换父节点就失焦，ESC / 空格全部失灵（2026-11-07 用户反馈）。
enum PlayerShortcutAction {
  none,
  escape,
  toggleHelp,
  togglePlayPause,
  toggleFullscreen,
  toggleMute,
  toggleLock,
  volumeUp,
  volumeDown,
  seekBack5,
  seekBack10,
  seekForward5,
  seekForward10,
  toggleSubtitles,
  speedDown,
  speedUp,
  seekToFraction,
  nextEpisode,
  prevEpisode,
}

/// 一次按键解析的结果；[fraction] 仅 [PlayerShortcutAction.seekToFraction] 使用。
class PlayerShortcut {
  const PlayerShortcut(this.action, {this.fraction});

  final PlayerShortcutAction action;
  final double? fraction;

  bool get isNone => action == PlayerShortcutAction.none;

  static const PlayerShortcut noneShortcut =
      PlayerShortcut(PlayerShortcutAction.none);
}

// 注意：不能写成 const Map —— LogicalKeyboardKey 重写了 == / hashCode，
// Dart 不允许这类对象作为 const map 的键（const_map_key_not_primitive_equality）。
final Map<LogicalKeyboardKey, double> kDigitSeekFractions =
    <LogicalKeyboardKey, double>{
  LogicalKeyboardKey.digit0: 0.0,
  LogicalKeyboardKey.digit1: 0.1,
  LogicalKeyboardKey.digit2: 0.2,
  LogicalKeyboardKey.digit3: 0.3,
  LogicalKeyboardKey.digit4: 0.4,
  LogicalKeyboardKey.digit5: 0.5,
  LogicalKeyboardKey.digit6: 0.6,
  LogicalKeyboardKey.digit7: 0.7,
  LogicalKeyboardKey.digit8: 0.8,
  LogicalKeyboardKey.digit9: 0.9,
};

/// 把一次按键解析成播放器动作。
///
/// 守卫（缺一不可）：
/// - [routeIsCurrent] = false：弹窗 / 新路由在上层，快捷键不能抢它的按键；
/// - [textInputFocused] = true：正在输入框打字，空格要留给文本输入；
/// - [isRepeat] = true：长按只认第一次 KeyDown，避免连发 seek / 全屏抖动。
///
/// ESC 特意排在 [playerActive] 之前：全屏时哪怕还没起播，也必须能退出去。
PlayerShortcut resolvePlayerShortcut({
  required LogicalKeyboardKey key,
  required bool isShiftPressed,
  required bool isRepeat,
  required bool helpVisible,
  required bool textInputFocused,
  required bool routeIsCurrent,
  required bool playerActive,
  required bool supportsScreenLock,
}) {
  if (!routeIsCurrent || textInputFocused || isRepeat) {
    return PlayerShortcut.noneShortcut;
  }

  // ESC：关帮助 → 关音量弹层 → 退出全屏，由调用方按当前 UI 状态依次处理。
  if (key == LogicalKeyboardKey.escape) {
    return const PlayerShortcut(PlayerShortcutAction.escape);
  }

  // H / ?：快捷键帮助面板。
  if (key == LogicalKeyboardKey.keyH ||
      (key == LogicalKeyboardKey.slash && !isShiftPressed)) {
    return const PlayerShortcut(PlayerShortcutAction.toggleHelp);
  }

  // 帮助面板显示时吞掉其他快捷键（否则按空格会在面板后面悄悄暂停）。
  if (helpVisible) return PlayerShortcut.noneShortcut;

  // 没有正在播放的媒体时放行按键，让页面能正常滚动 / 使用系统默认行为。
  if (!playerActive) return PlayerShortcut.noneShortcut;

  if (key == LogicalKeyboardKey.space) {
    return const PlayerShortcut(PlayerShortcutAction.togglePlayPause);
  }
  if (key == LogicalKeyboardKey.keyF) {
    return const PlayerShortcut(PlayerShortcutAction.toggleFullscreen);
  }
  if (key == LogicalKeyboardKey.keyM) {
    return const PlayerShortcut(PlayerShortcutAction.toggleMute);
  }
  if (supportsScreenLock && key == LogicalKeyboardKey.keyL) {
    return const PlayerShortcut(PlayerShortcutAction.toggleLock);
  }
  if (key == LogicalKeyboardKey.arrowUp) {
    return const PlayerShortcut(PlayerShortcutAction.volumeUp);
  }
  if (key == LogicalKeyboardKey.arrowDown) {
    return const PlayerShortcut(PlayerShortcutAction.volumeDown);
  }
  if (key == LogicalKeyboardKey.arrowLeft) {
    return isShiftPressed
        ? const PlayerShortcut(PlayerShortcutAction.seekBack10)
        : const PlayerShortcut(PlayerShortcutAction.seekBack5);
  }
  if (key == LogicalKeyboardKey.arrowRight) {
    return isShiftPressed
        ? const PlayerShortcut(PlayerShortcutAction.seekForward10)
        : const PlayerShortcut(PlayerShortcutAction.seekForward5);
  }
  if (key == LogicalKeyboardKey.keyC) {
    return const PlayerShortcut(PlayerShortcutAction.toggleSubtitles);
  }
  if (key == LogicalKeyboardKey.bracketLeft) {
    return const PlayerShortcut(PlayerShortcutAction.speedDown);
  }
  if (key == LogicalKeyboardKey.bracketRight) {
    return const PlayerShortcut(PlayerShortcutAction.speedUp);
  }
  final fraction = kDigitSeekFractions[key];
  if (fraction != null) {
    return PlayerShortcut(
      PlayerShortcutAction.seekToFraction,
      fraction: fraction,
    );
  }
  if (key == LogicalKeyboardKey.keyN) {
    return const PlayerShortcut(PlayerShortcutAction.nextEpisode);
  }
  if (key == LogicalKeyboardKey.keyP) {
    return const PlayerShortcut(PlayerShortcutAction.prevEpisode);
  }
  return PlayerShortcut.noneShortcut;
}
