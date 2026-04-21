/// 缓存项模型
class CacheItem {
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

  /// 集数索引
  final int episodeIndex;

  /// 集数名称
  final String episodeName;

  /// 播放地址
  final String url;

  /// 清晰度
  final String quality;

  /// 本地缓存路径
  final String localPath;

  /// 文件大小（字节）
  final int fileSize;

  /// 已下载大小（字节）
  final int downloadedSize;

  /// 下载状态（waiting, downloading, paused, completed, failed）
  final String status;

  /// 下载速度（字节/秒）
  final int speed;

  /// 创建时间
  final DateTime createdAt;

  /// 完成时间
  final DateTime? completedAt;

  CacheItem({
    required this.id,
    required this.movieId,
    this.sourceId = '',
    required this.movieName,
    this.movieCover = '',
    this.episodeIndex = 0,
    this.episodeName = '',
    required this.url,
    this.quality = '自动',
    this.localPath = '',
    this.fileSize = 0,
    this.downloadedSize = 0,
    this.status = 'waiting',
    this.speed = 0,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 从JSON创建
  factory CacheItem.fromJson(Map<String, dynamic> json) {
    return CacheItem(
      id: json['id']?.toString() ?? '',
      movieId: json['movieId']?.toString() ?? '',
      sourceId: json['sourceId']?.toString() ?? '',
      movieName: json['movieName']?.toString() ?? '',
      movieCover: json['movieCover']?.toString() ?? '',
      episodeIndex: json['episodeIndex'] as int? ?? 0,
      episodeName: json['episodeName']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      quality: json['quality']?.toString() ?? '自动',
      localPath: json['localPath']?.toString() ?? '',
      fileSize: json['fileSize'] as int? ?? 0,
      downloadedSize: json['downloadedSize'] as int? ?? 0,
      status: json['status']?.toString() ?? 'waiting',
      speed: json['speed'] as int? ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'].toString())
          : null,
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
      'url': url,
      'quality': quality,
      'localPath': localPath,
      'fileSize': fileSize,
      'downloadedSize': downloadedSize,
      'status': status,
      'speed': speed,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  /// 复制并修改部分字段
  CacheItem copyWith({
    String? id,
    String? movieId,
    String? sourceId,
    String? movieName,
    String? movieCover,
    int? episodeIndex,
    String? episodeName,
    String? url,
    String? quality,
    String? localPath,
    int? fileSize,
    int? downloadedSize,
    String? status,
    int? speed,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return CacheItem(
      id: id ?? this.id,
      movieId: movieId ?? this.movieId,
      sourceId: sourceId ?? this.sourceId,
      movieName: movieName ?? this.movieName,
      movieCover: movieCover ?? this.movieCover,
      episodeIndex: episodeIndex ?? this.episodeIndex,
      episodeName: episodeName ?? this.episodeName,
      url: url ?? this.url,
      quality: quality ?? this.quality,
      localPath: localPath ?? this.localPath,
      fileSize: fileSize ?? this.fileSize,
      downloadedSize: downloadedSize ?? this.downloadedSize,
      status: status ?? this.status,
      speed: speed ?? this.speed,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  /// 下载进度百分比
  double get progressPercent {
    if (fileSize <= 0) return 0.0;
    return (downloadedSize / fileSize).clamp(0.0, 1.0);
  }

  /// 是否正在下载
  bool get isDownloading => status == 'downloading';

  /// 是否已完成
  bool get isCompleted => status == 'completed';

  /// 是否已暂停
  bool get isPaused => status == 'paused';

  /// 是否失败
  bool get isFailed => status == 'failed';

  /// 是否等待中
  bool get isWaiting => status == 'waiting';

  /// 格式化文件大小
  String get formattedSize => _formatBytes(fileSize);

  /// 格式化已下载大小
  String get formattedDownloadedSize => _formatBytes(downloadedSize);

  /// 格式化速度
  String get formattedSpeed => '${_formatBytes(speed)}/s';

  /// 格式化字节数
  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int unitIndex = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CacheItem && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'CacheItem(movieName: $movieName, episodeName: $episodeName, status: $status)';
}
