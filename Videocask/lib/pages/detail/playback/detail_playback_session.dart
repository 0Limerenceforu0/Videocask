import 'package:flutter/foundation.dart';

import 'playback_lifecycle.dart';
import 'playhead_authority.dart';

/// 单次详情页播放会话：生命周期 + open 代次 + 进度权威。
class DetailPlaybackSession {
  DetailPlaybackSession({PlayheadAuthority? playhead})
      : playhead = playhead ?? PlayheadAuthority();

  final PlayheadAuthority playhead;

  final ValueNotifier<PlaybackLifecycle> lifecycleNotifier =
      ValueNotifier(PlaybackLifecycle.idle);

  bool _disposed = false;

  /// 会话是否已释放。
  bool get isDisposed => _disposed;

  /// 释放会话持有的通知器。
  ///
  /// 幂等；释放后对 [lifecycle] 的写入会被**忽略**（而不是抛
  /// "A ValueNotifier was used after being disposed"）—— 详情页退出时可能有
  /// 在途的异步 open/seek 回调落到这里，忽略比崩溃更合理。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    lifecycleNotifier.dispose();
  }

  PlaybackLifecycle get lifecycle => lifecycleNotifier.value;
  set lifecycle(PlaybackLifecycle v) {
    if (_disposed) return;
    if (lifecycleNotifier.value == v) return;
    lifecycleNotifier.value = v;
  }

  /// 每次 [prepareOpen] 递增；用于丢弃过期的 async open。
  int openGeneration = 0;

  /// 最近一次 [prepareOpen] 的墙钟时间。开播后一段 settle 窗口内，播放器位置从 0
  /// 爬到续播点是正常的，不应被当成「跳回开头」去纠偏 seek（否则开播落位期间补发的
  /// 精确 seek 会让 mpv 在代理 HLS 上原生崩溃）。详见 detail_player._scheduleDiscontinuityRecovery。
  DateTime? openedAt;

  /// 准备打开新媒体（**禁止**在外部直接 reset playhead）。
  ///
  /// [preservePlayhead] 非空：换线 / 续播 / 重试，保留或设定进度。
  /// 为空且 [resetPlayhead]：新集起播，清零进度。
  int prepareOpen({
    Duration? preservePlayhead,
    bool resetPlayhead = false,
  }) {
    openGeneration += 1;
    openedAt = DateTime.now();
    lifecycle = PlaybackLifecycle.opening;
    if (preservePlayhead != null && preservePlayhead > Duration.zero) {
      playhead.setExplicit(preservePlayhead);
    } else if (resetPlayhead) {
      playhead.reset();
    }
    return openGeneration;
  }

  void markPlaying() {
    // error 也要能回来：`Could not open codec.` 这类提示出现后 mpv 往往
    // 已经回退到可用解码器继续播，画面与位置都在走。若把 error 视作终态，
    // markPlaying 永远不生效 → 心跳/看门狗/续播记录全部失明（实测整段 0 条心跳）。
    if (lifecycle == PlaybackLifecycle.opening ||
        lifecycle == PlaybackLifecycle.seeking ||
        lifecycle == PlaybackLifecycle.error) {
      lifecycle = PlaybackLifecycle.playing;
    }
  }

  void markSeeking() {
    if (lifecycle.isActive) {
      lifecycle = PlaybackLifecycle.seeking;
    }
  }

  void markPaused() {
    if (lifecycle.isActive) {
      lifecycle = PlaybackLifecycle.paused;
    }
  }

  void markEnded() {
    lifecycle = PlaybackLifecycle.ended;
  }

  void markError() {
    lifecycle = PlaybackLifecycle.error;
  }

  void markIdle() {
    lifecycle = PlaybackLifecycle.idle;
    playhead.reset();
    openGeneration = 0;
  }
}
