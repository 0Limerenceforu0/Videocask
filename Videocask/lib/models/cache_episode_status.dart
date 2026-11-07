/// 详情页当前集离线缓存状态。
enum CacheEpisodeStatus {
  none,
  waiting,
  downloading,
  paused,
  completed,
}

extension CacheEpisodeStatusX on CacheEpisodeStatus {
  bool get isActive =>
      this == CacheEpisodeStatus.waiting ||
      this == CacheEpisodeStatus.downloading ||
      this == CacheEpisodeStatus.paused;

  bool get isCompleted => this == CacheEpisodeStatus.completed;
}
