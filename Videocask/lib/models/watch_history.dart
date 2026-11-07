/// 观看历史模型
class WatchHistory {
  /// 唯一标识
  final String id;

  /// 影片ID
  final String movieId;

  /// 所属源ID
  final String sourceId;

  /// 影片名称
  final String movieName;

  /// 影片封面
  final String movieCover;

  /// 当前集数索引
  final int episodeIndex;

  /// 当前集数名称
  final String episodeName;

  /// 播放进度（毫秒，精确到毫秒）
  final int progress;

  /// 总时长（毫秒，精确到毫秒）
  final int duration;

  /// 当前线路索引
  final int routeIndex;

  /// 最后观看时间
  final DateTime lastWatchTime;

  /// 观看次数
  final int watchCount;

  /// 累计实际观看时长（毫秒）。
  ///
  /// 由 [HistoryProvider.saveOrUpdateHistory] 按「播放位置增量」累加，只统计
  /// 正常推进的部分：拖动进度条跨越的区间不计入，所以这个值不会因 seek 虚增。
  /// 老存档没有该字段 → 0（解析时兜底）。
  final int watchedMs;

  /// 磁力详情专用：完整 magnet 链接，用于从历史恢复播放与列表展示
  final String magnetUri;

  WatchHistory({
    required this.id,
    required this.movieId,
    this.sourceId = '',
    required this.movieName,
    this.movieCover = '',
    this.episodeIndex = 0,
    this.episodeName = '',
    this.progress = 0,
    this.duration = 0,
    this.routeIndex = 0,
    DateTime? lastWatchTime,
    this.watchCount = 1,
    this.watchedMs = 0,
    this.magnetUri = '',
  }) : lastWatchTime = lastWatchTime ?? DateTime.now();

  /// 从JSON创建
  factory WatchHistory.fromJson(Map<String, dynamic> json) {
    return WatchHistory(
      id: json['id']?.toString() ?? '',
      movieId: json['movieId']?.toString() ?? '',
      sourceId: json['sourceId']?.toString() ?? '',
      movieName: json['movieName']?.toString() ?? '',
      movieCover: json['movieCover']?.toString() ?? '',
      episodeIndex: json['episodeIndex'] as int? ?? 0,
      episodeName: json['episodeName']?.toString() ?? '',
      progress: json['progress'] as int? ?? 0,
      duration: json['duration'] as int? ?? 0,
      routeIndex: json['routeIndex'] as int? ?? 0,
      lastWatchTime: json['lastWatchTime'] != null
          ? DateTime.tryParse(json['lastWatchTime'].toString()) ??
              DateTime.now()
          : DateTime.now(),
      watchCount: json['watchCount'] as int? ?? 1,
      watchedMs: json['watchedMs'] as int? ?? 0,
      magnetUri: json['magnetUri']?.toString() ?? '',
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'movieId': movieId,
      'sourceId': sourceId,
      'movieName': movieName,
      'movieCover': movieCover,
      'episodeIndex': episodeIndex,
      'episodeName': episodeName,
      'progress': progress,
      'duration': duration,
      'routeIndex': routeIndex,
      'lastWatchTime': lastWatchTime.toIso8601String(),
      'watchCount': watchCount,
      'watchedMs': watchedMs,
      'magnetUri': magnetUri,
    };
  }

  /// 复制并修改部分字段
  WatchHistory copyWith({
    String? id,
    String? movieId,
    String? sourceId,
    String? movieName,
    String? movieCover,
    int? episodeIndex,
    String? episodeName,
    int? progress,
    int? duration,
    int? routeIndex,
    DateTime? lastWatchTime,
    int? watchCount,
    int? watchedMs,
    String? magnetUri,
  }) {
    return WatchHistory(
      id: id ?? this.id,
      movieId: movieId ?? this.movieId,
      sourceId: sourceId ?? this.sourceId,
      movieName: movieName ?? this.movieName,
      movieCover: movieCover ?? this.movieCover,
      episodeIndex: episodeIndex ?? this.episodeIndex,
      episodeName: episodeName ?? this.episodeName,
      progress: progress ?? this.progress,
      duration: duration ?? this.duration,
      routeIndex: routeIndex ?? this.routeIndex,
      lastWatchTime: lastWatchTime ?? this.lastWatchTime,
      watchCount: watchCount ?? this.watchCount,
      watchedMs: watchedMs ?? this.watchedMs,
      magnetUri: magnetUri ?? this.magnetUri,
    );
  }

  /// 播放进度百分比
  double get progressPercent {
    if (duration <= 0) return 0.0;
    return (progress / duration).clamp(0.0, 1.0);
  }

  /// 是否已看完（进度超过90%）
  bool get isFinished => progressPercent >= 0.9;

  /// 剩余时间（秒）
  int get remaining => (duration - progress).clamp(0, duration);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WatchHistory && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'WatchHistory(movieId: $movieId, progress: $progress/$duration)';
}
