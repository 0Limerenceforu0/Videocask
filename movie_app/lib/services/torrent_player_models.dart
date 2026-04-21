/// 磁力链接播放状态
enum TorrentPlayState {
  idle,
  fetchingMeta,
  ready,
  buffering,
  playing,
  error,
}

/// 磁力链接中的文件信息
class TorrentFileItem {
  final int index;
  final String name;
  final int size;
  final bool isStreamable;

  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  const TorrentFileItem({
    required this.index,
    required this.name,
    required this.size,
    required this.isStreamable,
  });
}
