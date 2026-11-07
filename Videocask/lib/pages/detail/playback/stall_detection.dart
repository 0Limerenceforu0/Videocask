import 'playback_lifecycle.dart';

/// 缓冲前沿与播放头的最大容差（毫秒）：小于该值即视为「缓存已用尽」。
const int kStallBufferGapToleranceMs = 1500;

/// 判断播放器是否处于「缓冲耗尽停滞」：
///
/// 1. 时长未知（还没打开媒体）→ 非停滞；
/// 2. 正在缓冲（`isBuffering`）→ 非停滞（下载中即将恢复）；
/// 3. 缓存前沿与播放头几乎贴合（容差 [kStallBufferGapToleranceMs]）：
///    - `playing=false` → 停滞；
///    - `playing=true` 但 [advancing] 为 false（心跳里位置**没推进**）→ 同样算停滞。
///
/// 第 3 条的后半句是 2026-11-05 补的：mpv 在断流后会把 `playing` 一直报成 true、
/// 位置却定格不动（实测 34 分钟、69 条心跳），首行 `if (isPlaying) return false`
/// 把这种僵死全部排除，用户点「继续播放」也没反应。判「有没有推进」需要跨心跳
/// 的历史，纯函数拿不到，因此由调用方通过 [advancing] 传入（默认 true =
/// 「在推进」，保持原有保守行为，不会因为缺少历史就误判）。
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
///
/// 🔴 [userPaused]（2026-11-07 补）：用户**刚 seek 到未缓冲位置又主动暂停**时，
/// 缓存前沿本来就和播放头贴合（gap ≈ 0），上面这条「靠缓存富余区分暂停」的
/// 经验判据完全失效 → 点播放被误判成缓冲耗尽停滞 → `reloadStalled()` 重新
/// open 媒体，表现就是「过一会恢复画面、播放位置完全不对」。用户主动暂停后
/// 的一段保护窗口内一律不算停滞。
bool isBufferExhaustedStall({
  required Duration duration,
  required Duration position,
  required Duration bufferedPosition,
  required bool isPlaying,
  required bool isBuffering,
  bool advancing = true,
  bool userPaused = false,
}) {
  if (duration <= Duration.zero) return false;
  if (isBuffering) return false;
  if (!isPlaying && userPaused) return false;
  final gapMs = bufferedPosition.inMilliseconds - position.inMilliseconds;
  if (gapMs.abs() > kStallBufferGapToleranceMs) return false;
  if (!isPlaying) return true;
  return !advancing;
}

/// 权威进度与 mpv 实际上报的最大容差（超出即认为权威值脱节）。
const Duration kAuthoritativeDriftTolerance = Duration(seconds: 30);

/// 软重载的拉流起点：优先用权威进度；权威值与播放器实际上报脱节时以实际为准。
///
/// 场景一：历史续播点在新片源上失效 → mpv 从头播，而权威进度仍停在旧续播点，
/// 此时按权威值 seek 会失败回退成从 0 重开；按实际上报位置才能续上。
///
/// 场景二（2026-11-07 补）：用户**刚点了进度条**，此时 `reported` 很可能还是
/// seek 前的旧位置（mpv seek 异步），两条相差远超容差 → 旧实现会选旧位置，
/// 软重载后直接跳回用户拖动之前 = 「播放位置完全不对」。
/// [preferAuthoritative] 由调用方按「距上次显式 seek 是否在保护窗口内」传入。
Duration resolveReloadStartAt({
  required Duration authoritative,
  required Duration reported,
  Duration driftTolerance = kAuthoritativeDriftTolerance,
  bool preferAuthoritative = false,
}) {
  if (preferAuthoritative) return authoritative;
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