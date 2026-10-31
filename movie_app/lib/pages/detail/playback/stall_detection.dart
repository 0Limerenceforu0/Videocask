import 'playback_lifecycle.dart';

/// 缓冲前沿与播放头的最大容差（毫秒）：小于该值即视为「缓存已用尽」。
const int kStallBufferGapToleranceMs = 1500;

/// 判断播放器是否处于「缓冲耗尽停滞」：
///
/// 1. 时长未知（还没打开媒体）→ 非停滞；
/// 2. 正在播放或在缓冲中 → 非停滞；
/// 3. 缓存前沿与播放头几乎贴合（容差 [kStallBufferGapToleranceMs]）→ 停滞。
///
/// 典型场景：断网后缓存播完，mpv 放弃读流并停在原地（`playing=false`、位置不动、
/// 不触发 error 事件）。此时 `player.play()` 唤不醒，必须按进度重新 open 媒体。
///
/// [position] 必须传 **mpv 上报的原始位置**（`playback.lastPlayerReport`）
/// 而不是权威进度：续播点失效 + 纠偏场景下权威值可能停在 2944s 而实际在 167s，
/// 用权威值会让缓存差值失真、停滞判定失效。
///
/// 刻意与「用户主动暂停」区分：暂停时一般还有未播完的缓存（差值远大于容差），
/// 不会误判成停滞而擅自恢复播放。
bool isBufferExhaustedStall({
  required Duration duration,
  required Duration position,
  required Duration bufferedPosition,
  required bool isPlaying,
  required bool isBuffering,
}) {
  if (duration <= Duration.zero) return false;
  if (isPlaying) return false;
  if (isBuffering) return false;
  final gapMs = bufferedPosition.inMilliseconds - position.inMilliseconds;
  return gapMs.abs() <= kStallBufferGapToleranceMs;
}

/// 权威进度与 mpv 实际上报的最大容差（超出即认为权威值脱节）。
const Duration kAuthoritativeDriftTolerance = Duration(seconds: 30);

/// 软重载的拉流起点：优先用权威进度；权威值与播放器实际上报脱节时以实际为准。
///
/// 场景：历史续播点在新片源上失效 → mpv 从头播，而权威进度仍停在旧续播点，
/// 此时按权威值 seek 会失败回退成从 0 重开；按实际上报位置才能续上。
Duration resolveReloadStartAt({
  required Duration authoritative,
  required Duration reported,
  Duration driftTolerance = kAuthoritativeDriftTolerance,
}) {
  if (reported > Duration.zero &&
      (authoritative - reported).abs() > driftTolerance) {
    return reported;
  }
  return authoritative;
}

/// 停滞态下是否应把「继续播放」当作软重载处理（而不是普通 resume）。
bool shouldReloadInsteadOfResume({
  required bool stalled,
  required PlaybackLifecycle lifecycle,
}) {
  // 生命周期已 error/ended 时不重试拉流——那是源本身的问题，走重开路径。
  if (lifecycle == PlaybackLifecycle.error) return false;
  if (lifecycle == PlaybackLifecycle.ended) return false;
  return stalled;
}