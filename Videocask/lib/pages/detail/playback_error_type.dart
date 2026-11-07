/// 播放错误类型
enum PlaybackErrorType {
  none,
  noPlayableEpisode,
  parseFailed,
  routeFallback,
  sourceFallbackFailed,
  networkOrPlayer,
  magnetFailed,
}
