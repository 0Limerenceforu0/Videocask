part of 'detail_page.dart';

// 由 detail_page.dart 拆分而来：方法体逐字搬运，
// 通过 extension on _DetailPageState 直接访问原类的私有成员。

extension _DetailPageMiscExt on _DetailPageState {
  void _handleVerticalGesture(DragUpdateDetails details) {
    // 🔴 位移必须无条件累计：节流只控制「多久应用一次」。在窗口外直接 return 会把
    // 这段时间的 delta 一并丢掉 —— 真实手指事件 60–120Hz，50ms 窗口只放行 1/3，
    // 等效满程距离从 110px 变成 ~330px，这正是「亮度/音量不灵敏」的主因。
    _playerModule.pendingGestureDy += details.delta.dy;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _playerModule.lastGestureUpdateMs <
        DetailPlayer.gestureThrottleMs) {
      return;
    }
    _playerModule.lastGestureUpdateMs = now;
    _flushVerticalGesture();
  }

  /// 把累积的竖向位移一次性应用（节流窗口到期 / 手势结束时调用）。
  void _flushVerticalGesture() {
    final dy = _playerModule.pendingGestureDy;
    _playerModule.pendingGestureDy = 0;
    if (dy == 0) return;

    final left = _playerModule.verticalGestureIsLeftSide;
    // 灵敏度：拖 110px 走完全程（原 220px），亮度和音量同时更跟手。
    final delta = -dy / DetailPlayer.gesturePixelsFullRange;

    _setState(() {
      if (left) {
        _playerModule.brightness =
            (_playerModule.brightness + delta).clamp(0.0, 1.0);
        _playerModule.gestureHintValue = _playerModule.brightness;
        _playerModule.gestureProgress = _playerModule.brightness;
        if (!kIsWeb) {
          unawaited(
            ScreenBrightness().setApplicationScreenBrightness(
              _playerModule.brightness,
            ),
          );
        }
      } else {
        // 音量统一走系统音量（0.0–1.0），mpv 保持 100% 直通。
        _playerModule.volume =
            (_playerModule.volume + delta).clamp(0.0, DetailPlayer.maxVolumeUi);
        unawaited(_playerModule.setVolume(_playerModule.volume));
        _playerModule.gestureHintValue = _playerModule.volume;
        _playerModule.gestureProgress = _playerModule.volume;
      }
    });
  }
}
