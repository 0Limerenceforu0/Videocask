/// 磁力搜索结果模型
class TorrentInfo {
  /// 资源名称
  final String name;

  /// 文件大小（字节）
  final int size;

  /// 做种数
  final int seeders;

  /// 下载数
  final int leechers;

  /// 磁力链接
  final String magnetUri;

  /// 来源（如 PirateBay、YTS）
  final String source;

  /// 索引方标注的 IMDb ID（若有，用于与 `tt` 精准对齐）
  final String? imdbId;

  TorrentInfo({
    required this.name,
    required this.size,
    required this.seeders,
    required this.leechers,
    required this.magnetUri,
    required this.source,
    this.imdbId,
  });

  /// 格式化文件大小
  String get sizeFormatted => _formatSize(size);

  /// 格式化做种数（超过1000显示为 x.xk；-1 表示未知，显示「?」而非「0」）
  String get seedersFormatted {
    if (seeders < 0) return '?';
    return seeders > 1000
        ? '${(seeders / 1000).toStringAsFixed(1)}k'
        : '$seeders';
  }

  /// 格式化文件大小（静态方法）
  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
