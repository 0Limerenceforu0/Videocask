/// 带 [startAt] 打开媒体后，seek 未能到达目标位置。
class PlaybackStartSeekException implements Exception {
  PlaybackStartSeekException(this.target, this.actual);

  final Duration target;
  final Duration actual;

  @override
  String toString() =>
      'PlaybackStartSeekException(target=${target.inSeconds}s, actual=${actual.inSeconds}s)';
}
