import 'playback_lifecycle.dart';

/// 缓冲自动换线策略（与 UI / 播放器解耦，便于单测）。
class RouteFallbackPolicy {
  RouteFallbackPolicy._();

  /// 已稳定观看超过此时长后，禁止因缓冲自动换线（避免误触 open）。
  static const stableWatchBeforeNoFallback = Duration(minutes: 3);

  static bool allow({
    required PlaybackLifecycle lifecycle,
    required Duration authoritativePosition,
    required bool isMagnet,
    required bool isApplyingResume,
    required bool hasPendingResume,
  }) {
    if (isMagnet || isApplyingResume || hasPendingResume) return false;
    if (lifecycle.blocksAutoRouteFallback) return false;
    if (authoritativePosition > stableWatchBeforeNoFallback) return false;
    return true;
  }
}
