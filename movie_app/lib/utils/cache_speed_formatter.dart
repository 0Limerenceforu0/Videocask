/// 缓存速度格式化工具
class CacheSpeedFormatter {
  /// 按量级自动选择 B/s、KB/s、MB/s（[speed] 为字节/秒）
  static String format(int speed) {
    if (speed < 1024) {
      return '$speed B/s';
    }
    if (speed < 1024 * 1024) {
      final kb = speed / 1024;
      return '${kb >= 100 ? kb.toStringAsFixed(0) : kb.toStringAsFixed(1)} KB/s';
    }
    final mb = speed / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 10 ? 1 : 2)} MB/s';
  }

  /// 从播放速度（倍速）格式化为缓存速度
  ///
  /// [speed] - 播放速度（倍速）
  ///
  /// 返回格式化后的字符串，例如 "3.5 MB/s"
  static String formatFromPlaybackSpeed(double speed) {
    // 这里只是一个示例，实际应用中需要根据实际情况计算
    // 假设1倍速对应1MB/s的缓存速度
    final mbSpeed = speed;
    return '${mbSpeed.toStringAsFixed(1)} MB/s';
  }
}
