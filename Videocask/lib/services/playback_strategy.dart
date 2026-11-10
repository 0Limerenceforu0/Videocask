/// 播放策略与 mpv 调优参数（smooth / balanced / quality）。
class PlaybackStrategyConfig {
  const PlaybackStrategyConfig({
    required this.demuxerBufferBytes,
    required this.demuxerMaxBytes,
    required this.hrSeek,
    required this.demuxerSeekableCache,
    required this.cacheSecs,
    required this.networkTimeoutSecs,
    required this.routeFallbackSec,
    required this.routeProbeTimeoutMs,
    required this.prefetchBytes,
    required this.demuxerReadaheadBytes,
    required this.demuxerReadaheadSecs,
    required this.scrubSeekThrottleMs,
    required this.cachePause,
  });

  /// demuxer 读缓存字节数（[PlayerConfiguration.bufferSize] → mpv cache-size）
  final int demuxerBufferBytes;

  /// mpv `demuxer-max-bytes`：demuxer 缓存字节硬上限，防止长时间播放内存堆积被 LMK 杀。
  final int demuxerMaxBytes;

  /// mpv `demuxer-readahead-bytes`：demuxer 向前预读字节目标。
  /// 默认未设（≈1~2s 浅窗口）是「缓冲贴着播放位置跑、几秒卡一下」的根因；拉满 512MB 才会真正把缓冲攒到字节上限。
  final int demuxerReadaheadBytes;

  /// mpv `demuxer-readahead-secs`：demuxer 向前预读秒数目标（时间维度）。
  /// 必须足够大，否则会先于字节上限把缓冲截断；7200s 保证 512MB 字节上限在所有常见码率下先触顶。
  final int demuxerReadaheadSecs;

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

  /// mpv `cache-pause`：缓存低于低水位时是否自动暂停。
  ///
  /// ⚠️ 2026-11-08 真机（4079）定案——磁力 P2P 流「卡在首帧」的根因：
  /// 默认 `yes` 时，缓存一旦低于低水位 mpv 就 `pause=yes`，**同时停止向底层
  /// 本地 HTTP 流服务器发读请求** → libtorrent 不再拉取该 piece → 下载速率
  /// 塌缩到 ~0 → 缓存永远补不上 → 暂停永远清不掉（死锁）。
  /// 表现为「点播放键也救不回来、位置停在几秒不动」。
  /// 磁力流必须 `no`：让 mpv 持续发读请求，下载才能持续供数，播放才能推进；
  /// 真·供数不足由 90s 停滞看门狗兜底（磁力分支已短路为等待供数，不重开流）。
  /// 普通 HTTP 流保留 `yes`（避免偶发卡顿），故按线路区分。
  final String cachePause;

  static PlaybackStrategyConfig fromKey(
    String strategy, {
    int? bufferBytes,
    String? hrSeek,
    String? cachePause,
  }) {
    final base = _baseFromKey(strategy);
    // 拖动精度已从「播放偏好三档」里拆出来单独设置，这里按新设置覆盖。
    final tuned = hrSeek == null || hrSeek.isEmpty || hrSeek == 'default'
        ? base
        : base.copyWith(hrSeek: hrSeek);
    if (cachePause != null && cachePause.isNotEmpty) {
      return tuned.copyWith(cachePause: cachePause);
    }
    if (bufferBytes == null || bufferBytes <= 0) return tuned;
    // 夹到 128~512MB：低于 128 等于退回 mpv 默认的浅窗口（几秒一卡），
    // 高于 512 在手机上就是给 lmkd 递刀。
    const minBytes = 128 * 1024 * 1024;
    const maxBytes = 512 * 1024 * 1024;
    final bytes = bufferBytes < minBytes
        ? minBytes
        : (bufferBytes > maxBytes ? maxBytes : bufferBytes);
    final secs = secsForBytes(bytes);
    return tuned.copyWith(
      demuxerBufferBytes: bytes,
      demuxerMaxBytes: bytes,
      demuxerReadaheadBytes: bytes,
      demuxerReadaheadSecs: secs,
      cacheSecs: secs,
    );
  }

  /// 字节上限 → 时间上限。
  ///
  /// 两个上限是「谁先到算谁」，只调小字节没用：`demuxer-readahead-secs: 1800`
  /// 在低码率流里可能 1800 秒都没攒到 128MB，于是照样无限往后读。
  /// 这里按码率量级（1~4 Mbps）给一个大致同时触顶的值。
  static int secsForBytes(int bytes) {
    final mb = bytes ~/ (1024 * 1024);
    if (mb <= 128) return 300;
    if (mb <= 192) return 600;
    if (mb <= 256) return 900;
    if (mb <= 384) return 1200;
    return 1800;
  }

  PlaybackStrategyConfig copyWith({
    int? demuxerBufferBytes,
    int? demuxerMaxBytes,
    String? hrSeek,
    int? demuxerReadaheadBytes,
    int? demuxerReadaheadSecs,
    int? cacheSecs,
    int? networkTimeoutSecs,
    String? cachePause,
  }) {
    return PlaybackStrategyConfig(
      demuxerBufferBytes: demuxerBufferBytes ?? this.demuxerBufferBytes,
      demuxerMaxBytes: demuxerMaxBytes ?? this.demuxerMaxBytes,
      hrSeek: hrSeek ?? this.hrSeek,
      demuxerSeekableCache: demuxerSeekableCache,
      cacheSecs: cacheSecs ?? this.cacheSecs,
      networkTimeoutSecs: networkTimeoutSecs ?? this.networkTimeoutSecs,
      routeFallbackSec: routeFallbackSec,
      routeProbeTimeoutMs: routeProbeTimeoutMs,
      prefetchBytes: prefetchBytes,
      demuxerReadaheadBytes:
          demuxerReadaheadBytes ?? this.demuxerReadaheadBytes,
      demuxerReadaheadSecs: demuxerReadaheadSecs ?? this.demuxerReadaheadSecs,
      scrubSeekThrottleMs: scrubSeekThrottleMs,
      cachePause: cachePause ?? this.cachePause,
    );
  }

  static PlaybackStrategyConfig _baseFromKey(String strategy) {
    switch (strategy) {
      case 'smooth':
        return const PlaybackStrategyConfig(
          demuxerBufferBytes: 512 * 1024 * 1024,
          demuxerMaxBytes: 512 * 1024 * 1024,
          demuxerReadaheadBytes: 512 * 1024 * 1024,
          demuxerReadaheadSecs: 1800,
          hrSeek: 'no',
          demuxerSeekableCache: 'yes',
          cacheSecs: 1800,
          networkTimeoutSecs: 15,
          routeFallbackSec: 6,
          routeProbeTimeoutMs: 3500,
          prefetchBytes: 2 * 1024 * 1024,
          scrubSeekThrottleMs: 180,
          cachePause: 'yes',
        );
      case 'quality':
        return const PlaybackStrategyConfig(
          demuxerBufferBytes: 512 * 1024 * 1024,
          demuxerMaxBytes: 512 * 1024 * 1024,
          demuxerReadaheadBytes: 512 * 1024 * 1024,
          demuxerReadaheadSecs: 1800,
          hrSeek: 'yes',
          demuxerSeekableCache: 'yes',
          cacheSecs: 1800,
          networkTimeoutSecs: 25,
          routeFallbackSec: 12,
          routeProbeTimeoutMs: 5000,
          prefetchBytes: 512 * 1024,
          scrubSeekThrottleMs: 280,
          cachePause: 'yes',
        );
      default:
        return const PlaybackStrategyConfig(
          demuxerBufferBytes: 512 * 1024 * 1024,
          demuxerMaxBytes: 512 * 1024 * 1024,
          demuxerReadaheadBytes: 512 * 1024 * 1024,
          demuxerReadaheadSecs: 1800,
          hrSeek: 'default',
          demuxerSeekableCache: 'yes',
          cacheSecs: 1800,
          networkTimeoutSecs: 20,
          routeFallbackSec: 8,
          routeProbeTimeoutMs: 4000,
          prefetchBytes: 1024 * 1024,
          scrubSeekThrottleMs: 220,
          cachePause: 'yes',
        );
    }
  }
}
