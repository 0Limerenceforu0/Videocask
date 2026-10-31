part of 'detail_page.dart';

// 由 detail_page.dart 拆分而来：方法体逐字搬运，
// 通过 extension on _DetailPageState 直接访问原类的私有成员。

extension _DetailPageMiscExt on _DetailPageState {
  void _handleVerticalGesture(DragUpdateDetails details) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _playerModule.lastGestureUpdateMs <
        DetailPlayer.gestureThrottleMs) {
      return;
    }
    _playerModule.lastGestureUpdateMs = now;

    final left = _playerModule.verticalGestureIsLeftSide;
    final delta = -details.delta.dy / 220;

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
        _playerModule.volume = (_playerModule.volume + delta * 200)
            .clamp(0.0, DetailPlayer.maxVolumeUi);
        unawaited(_playerModule.playerService.setVolume(_playerModule.volume));
        _playerModule.gestureHintValue =
            _playerModule.volume / DetailPlayer.maxVolumeUi;
        _playerModule.gestureProgress =
            _playerModule.volume / DetailPlayer.maxVolumeUi;
      }
    });
  }
}
