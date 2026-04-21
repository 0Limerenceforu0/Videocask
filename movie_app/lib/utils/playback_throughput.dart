/// 基于 demuxer 缓冲时间轴（[buffer]）相对墙钟增速，结合估算码率换算等效网络吞吐（字节/秒）。
///
/// media_kit 未暴露 demuxer 原始字节增量，此为工程上常用的「码率 × 可播放时长缓冲增速」近似。
class PlaybackThroughputEstimator {
  Duration _lastBuffer = Duration.zero;
  int _lastWallMs = 0;
  double _emaBytesPerSec = 0;

  /// 返回平滑后的字节/秒（非负）。
  int update({
    required Duration buffer,
    required int wallMs,
    required double? audioBitrateBps,
    required int? videoWidth,
    required int? videoHeight,
  }) {
    if (_lastWallMs == 0) {
      _lastBuffer = buffer;
      _lastWallMs = wallMs;
      return 0;
    }

    final dtSec = (wallMs - _lastWallMs) / 1000.0;
    if (dtSec <= 0) {
      return _emaBytesPerSec.round().clamp(0, 1 << 30);
    }

    final dBufSec = (buffer - _lastBuffer).inMicroseconds / 1e6;
    _lastBuffer = buffer;
    _lastWallMs = wallMs;

    if (dBufSec <= 0) {
      _emaBytesPerSec *= 0.88;
      return _emaBytesPerSec.round().clamp(0, 1 << 30);
    }

    if (dtSec < 0.2) {
      return _emaBytesPerSec.round().clamp(0, 1 << 30);
    }

    final totalBps = _estimateTotalBitrateBps(
      audioBitrateBps,
      videoWidth,
      videoHeight,
    );
    final mediaMultiplier = dBufSec / dtSec;
    final bytesPerSec = (totalBps / 8.0) * mediaMultiplier;
    _emaBytesPerSec = _emaBytesPerSec * 0.35 + bytesPerSec * 0.65;

    return _emaBytesPerSec.round().clamp(0, 500 * 1024 * 1024);
  }

  void reset() {
    _lastWallMs = 0;
    _lastBuffer = Duration.zero;
    _emaBytesPerSec = 0;
  }
}

int _estimateTotalBitrateBps(
  double? audioBps,
  int? w,
  int? h,
) {
  final audio =
      (audioBps != null && audioBps > 8000) ? audioBps.round() : 128000;
  if (w != null && h != null && w > 0 && h > 0) {
    final pixels = w * h;
    const refPixels = 1920 * 1080;
    const refVideoBps = 5000000;
    final video =
        (pixels / refPixels * refVideoBps).round().clamp(400000, 80000000);
    return audio + video;
  }
  return audio + 3000000;
}
