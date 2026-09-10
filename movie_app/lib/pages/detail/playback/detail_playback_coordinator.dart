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

  void onOpenSucceeded() {
    session.markPlaying();
  }

  void onSeekStarted() {
    session.markSeeking();
  }

  void onSeekFinished() {
    session.markPlaying();
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
}
