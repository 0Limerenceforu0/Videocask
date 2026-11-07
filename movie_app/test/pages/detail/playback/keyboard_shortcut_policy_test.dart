import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/keyboard_shortcut_policy.dart';

/// 快捷键解析的守卫（2026-11-07 用户反馈：ESC 退不出全屏、空格不暂停）。
///
/// 「摘修复即红」用例：焦点在输入框 / 弹窗在上层 / 长按重复事件时，
/// 旧实现（挂在播放器子树里的 KeyboardListener）没有这些守卫，会把空格
/// 当暂停、把弹窗里的按键也抢走；改成页面级全局监听后必须由策略层拦住。
void main() {
  PlayerShortcut resolve(
    LogicalKeyboardKey key, {
    bool isShiftPressed = false,
    bool isRepeat = false,
    bool helpVisible = false,
    bool textInputFocused = false,
    bool routeIsCurrent = true,
    bool playerActive = true,
    bool supportsScreenLock = true,
  }) {
    return resolvePlayerShortcut(
      key: key,
      isShiftPressed: isShiftPressed,
      isRepeat: isRepeat,
      helpVisible: helpVisible,
      textInputFocused: textInputFocused,
      routeIsCurrent: routeIsCurrent,
      playerActive: playerActive,
      supportsScreenLock: supportsScreenLock,
    );
  }

  group('ESC / 空格', () {
    test('ESC 一律交给退出全屏链路，哪怕还没起播', () {
      expect(resolve(LogicalKeyboardKey.escape).action,
          PlayerShortcutAction.escape);
      expect(
        resolve(LogicalKeyboardKey.escape, playerActive: false).action,
        PlayerShortcutAction.escape,
      );
    });

    test('空格 → 播放/暂停', () {
      expect(resolve(LogicalKeyboardKey.space).action,
          PlayerShortcutAction.togglePlayPause);
    });

    test('帮助面板打开时空格不生效，但 ESC / H 仍能关面板', () {
      expect(
        resolve(LogicalKeyboardKey.space, helpVisible: true).isNone,
        isTrue,
      );
      expect(
        resolve(LogicalKeyboardKey.escape, helpVisible: true).action,
        PlayerShortcutAction.escape,
      );
      expect(
        resolve(LogicalKeyboardKey.keyH, helpVisible: true).action,
        PlayerShortcutAction.toggleHelp,
      );
    });
  });

  group('守卫：摘修复即红', () {
    test('弹窗 / 上层路由打开时不抢按键', () {
      expect(
        resolve(LogicalKeyboardKey.space, routeIsCurrent: false).isNone,
        isTrue,
      );
      expect(
        resolve(LogicalKeyboardKey.escape, routeIsCurrent: false).isNone,
        isTrue,
      );
    });

    test('焦点在输入框时，空格留给文本输入', () {
      expect(
        resolve(LogicalKeyboardKey.space, textInputFocused: true).isNone,
        isTrue,
      );
      expect(
        resolve(LogicalKeyboardKey.arrowRight, textInputFocused: true).isNone,
        isTrue,
      );
    });

    test('长按重复事件只认第一次 KeyDown', () {
      expect(
        resolve(LogicalKeyboardKey.arrowRight, isRepeat: true).isNone,
        isTrue,
      );
      expect(
        resolve(LogicalKeyboardKey.space, isRepeat: true).isNone,
        isTrue,
      );
    });

    test('未起播时其余快捷键放行给页面滚动 / 系统默认', () {
      expect(
        resolve(LogicalKeyboardKey.arrowDown, playerActive: false).isNone,
        isTrue,
      );
      expect(
        resolve(LogicalKeyboardKey.keyF, playerActive: false).isNone,
        isTrue,
      );
    });
  });

  group('键位映射', () {
    test('方向键：Shift 决定 5s / 10s', () {
      expect(resolve(LogicalKeyboardKey.arrowLeft).action,
          PlayerShortcutAction.seekBack5);
      expect(
        resolve(LogicalKeyboardKey.arrowLeft, isShiftPressed: true).action,
        PlayerShortcutAction.seekBack10,
      );
      expect(resolve(LogicalKeyboardKey.arrowRight).action,
          PlayerShortcutAction.seekForward5);
      expect(
        resolve(LogicalKeyboardKey.arrowRight, isShiftPressed: true).action,
        PlayerShortcutAction.seekForward10,
      );
    });

    test('? 需要不带 Shift，带 Shift 不触发帮助', () {
      expect(resolve(LogicalKeyboardKey.slash).action,
          PlayerShortcutAction.toggleHelp);
      expect(
        resolve(LogicalKeyboardKey.slash, isShiftPressed: true).isNone,
        isTrue,
      );
    });

    test('数字键 → 0.0~0.9 的百分比 seek', () {
      expect(resolve(LogicalKeyboardKey.digit0).fraction, 0.0);
      expect(resolve(LogicalKeyboardKey.digit5).fraction, 0.5);
      expect(resolve(LogicalKeyboardKey.digit9).action,
          PlayerShortcutAction.seekToFraction);
    });

    test('锁屏键只在支持的平台生效', () {
      expect(resolve(LogicalKeyboardKey.keyL).action,
          PlayerShortcutAction.toggleLock);
      expect(
        resolve(LogicalKeyboardKey.keyL, supportsScreenLock: false).isNone,
        isTrue,
      );
    });

    test('F/M/C/[/]/N/P/音量键映射完整', () {
      final cases = <LogicalKeyboardKey, PlayerShortcutAction>{
        LogicalKeyboardKey.keyF: PlayerShortcutAction.toggleFullscreen,
        LogicalKeyboardKey.keyM: PlayerShortcutAction.toggleMute,
        LogicalKeyboardKey.keyC: PlayerShortcutAction.toggleSubtitles,
        LogicalKeyboardKey.bracketLeft: PlayerShortcutAction.speedDown,
        LogicalKeyboardKey.bracketRight: PlayerShortcutAction.speedUp,
        LogicalKeyboardKey.keyN: PlayerShortcutAction.nextEpisode,
        LogicalKeyboardKey.keyP: PlayerShortcutAction.prevEpisode,
        LogicalKeyboardKey.arrowUp: PlayerShortcutAction.volumeUp,
        LogicalKeyboardKey.arrowDown: PlayerShortcutAction.volumeDown,
      };
      cases.forEach((key, expected) {
        expect(resolve(key).action, expected, reason: 'key=$key');
      });
    });

    test('未映射的键不接管', () {
      expect(resolve(LogicalKeyboardKey.keyQ).isNone, isTrue);
    });
  });
}
