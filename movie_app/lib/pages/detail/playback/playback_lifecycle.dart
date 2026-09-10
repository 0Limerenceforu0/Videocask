/// 详情页播放器生命周期（所有功能必须通过此状态判断是否可换线 / open）。
enum PlaybackLifecycle {
  idle,
  opening,
  playing,
  seeking,
  paused,
  ended,
  error,
}

extension PlaybackLifecycleX on PlaybackLifecycle {
  bool get blocksAutoRouteFallback =>
      this == PlaybackLifecycle.opening || this == PlaybackLifecycle.seeking;

  bool get isActive =>
      this == PlaybackLifecycle.opening ||
      this == PlaybackLifecycle.playing ||
      this == PlaybackLifecycle.seeking ||
      this == PlaybackLifecycle.paused;
}
