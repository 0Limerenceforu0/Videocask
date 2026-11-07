import 'playback_lifecycle.dart';
import 'detail_playback_session.dart';
import 'playhead_authority.dart';
import 'route_fallback_policy.dart';

/// 打开媒体前的计划（唯一合法 open 入口产出）。
class MediaOpenPlan {
  const MediaOpenPlan({
    required this.generation,
    required this.startAt,
    required this.preservePlayhead,
  });

  final int generation;
  final Duration? startAt;

  /// 非空表示本次 open 必须 seek 到此位置（seek 失败则视为 open 失败）。
  final Duration? preservePlayhead;
}

/// 详情页播放协调器：**所有** open / 进度 / 换线策略的唯一入口。
///
/// 新增功能（DLNA、缓存、预加载等）不得直接调用 `player.open()` 或读写
/// 裸 `position`；应通过本类查询 [authoritativePosition] 与 [prepareOpen]。
class DetailPlaybackCoordinator {
  DetailPlaybackCoordinator({DetailPlaybackSession? session})
      : session = session ?? DetailPlaybackSession();

  final DetailPlaybackSession session;

  Duration get authoritativePosition => session.playhead.authoritative;

  Duration get lastPlayerReport => session.playhead.lastPlayerReport;

  PlaybackLifecycle get lifecycle => session.lifecycle;

  int get openGeneration => session.openGeneration;

  /// 规划一次 open；调用方必须用返回的 [MediaOpenPlan.generation] 校验 async 结果。
  MediaOpenPlan prepareOpen({
    required bool isNewEpisode,
    Duration? explicitPreserve,
    Duration? pendingResume,
    bool resumeTargetMatches = false,
    Duration? knownDuration,
  }) {
    final preserve =
        explicitPreserve ?? (resumeTargetMatches ? pendingResume : null);

    final generation = session.prepareOpen(
      preservePlayhead: preserve,
      resetPlayhead: isNewEpisode && preserve == null,
    );

    final startAt = preserve ??
        (isNewEpisode
            ? null
            : session.playhead.preserveForMediaSwitch(duration: knownDuration));

    return MediaOpenPlan(
      generation: generation,
      startAt: startAt,
      preservePlayhead: startAt,
    );
  }

  /// 处理 mpv position 上报；返回 discontinuity 时调用方应 seek 回 [authoritativePosition]。
  PlayheadTickAction ingestPlayerPosition(
    Duration reported, {
    Duration? duration,
  }) {
    return session.playhead.ingest(reported, duration: duration);
  }

  void confirmExplicitPosition(Duration position, {Duration? duration}) {
    session.playhead.setExplicit(position, durationCap: duration);
  }

  /// 采纳播放器实际上报位置作为权威进度（承认现实）。
  ///
  /// 场景：历史续播点在新片源上失效 → open 的 seek 抛错 → 改从头播，播放器
  /// 从 0 正常推进，但权威进度仍钉在失效的旧续播点上（实测 2944s vs 实际
  /// 167s），进度条长时间显示错误位置，续播记录也会被污染。
  ///
  /// 偏差在 [tolerance] 内视为抖动不做处理；[reported] 为 0（尚未上报）时忽略。
  bool adoptPlayerPosition(
    Duration reported, {
    Duration tolerance = const Duration(seconds: 5),
  }) {
    if (reported <= Duration.zero) return false;
    final current = session.playhead.authoritative;
    if ((current - reported).abs() <= tolerance) return false;
    session.playhead.setExplicit(reported);
    return true;
  }

  void onOpenSucceeded() {
    session.markPlaying();
  }

  /// 状态机停在 error，但播放器位置仍在推进 → 承认「其实在播」。
  ///
  /// 触发场景：`Could not open codec.` 之后 mpv 回退到可用解码器继续出画面，
  /// 但 lifecycle 已被 [PlaybackSession.markError] 钉在 error。若不拉回来，
  /// 心跳（只认 playing/paused）、停滞看门狗、续播记录全部失效。
  void noteProgressWhileErrored() {
    if (session.lifecycle != PlaybackLifecycle.error) return;
    session.markPlaying();
  }

  void onSeekStarted() {
    session.markSeeking();
  }

  /// 结束 seek。暂停态下 seek（用户点进度条后暂停）不能把 lifecycle 强行
  /// 标回 playing，否则停滞判定 / 心跳会把「已暂停」误当成「在播却不动」。
  void onSeekFinished({bool playing = true}) {
    if (playing) {
      session.markPlaying();
    } else {
      session.markPaused();
    }
  }

  void onPlaybackEnded({Duration? duration}) {
    if (duration != null && duration > Duration.zero) {
      session.playhead.setExplicit(duration, durationCap: duration);
    }
    session.markEnded();
  }

  void onPlaybackError() {
    session.markError();
  }

  void resetSession() {
    session.markIdle();
  }

  bool shouldAllowRouteFallback({
    required bool isMagnet,
    required bool isApplyingResume,
    required bool hasPendingResume,
  }) {
    return RouteFallbackPolicy.allow(
      lifecycle: session.lifecycle,
      authoritativePosition: session.playhead.authoritative,
      isMagnet: isMagnet,
      isApplyingResume: isApplyingResume,
      hasPendingResume: hasPendingResume,
    );
  }

  bool isPrematureComplete(Duration duration) {
    return session.playhead.isPrematureComplete(duration);
  }

  Duration? preserveForRouteSwitch({Duration? duration}) {
    return session.playhead.preserveForMediaSwitch(duration: duration);
  }

  /// 释放协调器持有的会话资源（幂等）。
  void dispose() {
    session.dispose();
  }
}
