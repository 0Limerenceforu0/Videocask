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

  PlaybackLifecycle get lifecycle => lifecycleNotifier.value;
  set lifecycle(PlaybackLifecycle v) {
    if (lifecycleNotifier.value == v) return;
    lifecycleNotifier.value = v;
  }

  /// 每次 [prepareOpen] 递增；用于丢弃过期的 async open。
  int openGeneration = 0;

  /// 准备打开新媒体（**禁止**在外部直接 reset playhead）。
  ///
  /// [preservePlayhead] 非空：换线 / 续播 / 重试，保留或设定进度。
  /// 为空且 [resetPlayhead]：新集起播，清零进度。
  int prepareOpen({
    Duration? preservePlayhead,
    bool resetPlayhead = false,
  }) {
    openGeneration += 1;
    lifecycle = PlaybackLifecycle.opening;
    if (preservePlayhead != null && preservePlayhead > Duration.zero) {
      playhead.setExplicit(preservePlayhead);
    } else if (resetPlayhead) {
      playhead.reset();
    }
    return openGeneration;
  }

  void markPlaying() {
    if (lifecycle == PlaybackLifecycle.opening ||
        lifecycle == PlaybackLifecycle.seeking) {
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
