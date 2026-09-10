/// 播放策略与 mpv 调优参数（smooth / balanced / quality）。
class PlaybackStrategyConfig {
  const PlaybackStrategyConfig({
    required this.demuxerBufferBytes,
    required this.hrSeek,
    required this.demuxerSeekableCache,
    required this.cacheSecs,
    required this.networkTimeoutSecs,
    required this.routeFallbackSec,
    required this.routeProbeTimeoutMs,
    required this.prefetchBytes,
    required this.scrubSeekThrottleMs,
  });

  /// demuxer 读缓存字节数（[PlayerConfiguration.bufferSize]）
  final int demuxerBufferBytes;

  /// mpv `hr-seek`：拖动时是否精确到非关键帧
  final String hrSeek;

  /// mpv `demuxer-seekable-cache`
  final String demuxerSeekableCache;

  /// mpv `cache-secs`：向前缓存秒数
  final int cacheSecs;

  /// mpv `network-timeout`（秒）
  final int networkTimeoutSecs;

  /// 长时间缓冲后自动换线阈值（秒）
  final int routeFallbackSec;

  /// 线路探针单次超时（毫秒）
  final int routeProbeTimeoutMs;

  /// Wi‑Fi 下预拉流字节数（0 = 关闭）
  final int prefetchBytes;

  /// 进度条拖动时节流 fast seek 间隔（毫秒）
  final int scrubSeekThrottleMs;

  static PlaybackStrategyConfig fromKey(String strategy) {
    switch (strategy) {
      case 'smooth':
        return const PlaybackStrategyConfig(
          demuxerBufferBytes: 128 * 1024 * 1024,
          hrSeek: 'no',
          demuxerSeekableCache: 'yes',
          cacheSecs: 120,
          networkTimeoutSecs: 15,
          routeFallbackSec: 6,
          routeProbeTimeoutMs: 3500,
          prefetchBytes: 2 * 1024 * 1024,
          scrubSeekThrottleMs: 180,
        );
      case 'quality':
        return const PlaybackStrategyConfig(
          demuxerBufferBytes: 64 * 1024 * 1024,
          hrSeek: 'yes',
          demuxerSeekableCache: 'yes',
          cacheSecs: 60,
          networkTimeoutSecs: 25,
          routeFallbackSec: 12,
          routeProbeTimeoutMs: 5000,
          prefetchBytes: 512 * 1024,
          scrubSeekThrottleMs: 280,
        );
      default:
        return const PlaybackStrategyConfig(
          demuxerBufferBytes: 96 * 1024 * 1024,
          hrSeek: 'default',
          demuxerSeekableCache: 'yes',
          cacheSecs: 90,
          networkTimeoutSecs: 20,
          routeFallbackSec: 8,
          routeProbeTimeoutMs: 4000,
          prefetchBytes: 1024 * 1024,
          scrubSeekThrottleMs: 220,
        );
    }
  }
}
