import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/playback_strategy.dart';

void main() {
  group('PlaybackStrategyConfig', () {
    test('smooth favors larger buffer and faster fallback', () {
      final smooth = PlaybackStrategyConfig.fromKey('smooth');
      final balanced = PlaybackStrategyConfig.fromKey('balanced');
      expect(
        smooth.demuxerBufferBytes,
        greaterThan(balanced.demuxerBufferBytes),
      );
      expect(smooth.routeFallbackSec, lessThan(balanced.routeFallbackSec));
      expect(smooth.hrSeek, 'no');
    });

    test('quality favors precise seek', () {
      final quality = PlaybackStrategyConfig.fromKey('quality');
      final balanced = PlaybackStrategyConfig.fromKey('balanced');
      expect(quality.hrSeek, 'yes');
      expect(quality.demuxerBufferBytes, lessThan(balanced.demuxerBufferBytes));
      // 精细 seek 意味着更长的缓冲等待 → 换线阈值更宽松
      expect(quality.routeFallbackSec, greaterThan(balanced.routeFallbackSec));
    });

    test('unknown key falls back to balanced', () {
      final cfg = PlaybackStrategyConfig.fromKey('unknown');
      final balanced = PlaybackStrategyConfig.fromKey('balanced');
      // 断言「契约」而非硬编码数值：策略参数会随调优调整（例如 demuxer 读缓存
      // 为降低内存占用从 96MB 调整为 24MB），写死数值会让用例在参数调优后变成
      // 陈旧断言而误报失败。
      expect(cfg.demuxerBufferBytes, balanced.demuxerBufferBytes);
      expect(cfg.demuxerMaxBytes, balanced.demuxerMaxBytes);
      expect(cfg.routeFallbackSec, balanced.routeFallbackSec);
      expect(cfg.routeProbeTimeoutMs, balanced.routeProbeTimeoutMs);
      expect(cfg.prefetchBytes, balanced.prefetchBytes);
      expect(cfg.scrubSeekThrottleMs, balanced.scrubSeekThrottleMs);
      expect(cfg.hrSeek, balanced.hrSeek);
      expect(cfg.cacheSecs, balanced.cacheSecs);
      expect(cfg.networkTimeoutSecs, balanced.networkTimeoutSecs);
      expect(cfg.demuxerSeekableCache, balanced.demuxerSeekableCache);
    });

    test('策略档位齐全且字段合法', () {
      for (final key in ['smooth', 'balanced', 'quality', 'unknown']) {
        final cfg = PlaybackStrategyConfig.fromKey(key);
        expect(cfg.demuxerBufferBytes, greaterThan(0));
        // demuxer 硬上限不应小于读缓存，否则缓冲策略形同虚设
        expect(
          cfg.demuxerMaxBytes,
          greaterThanOrEqualTo(cfg.demuxerBufferBytes),
        );
        expect(cfg.routeFallbackSec, greaterThan(0));
        expect(cfg.routeProbeTimeoutMs, greaterThan(0));
        expect(cfg.networkTimeoutSecs, greaterThan(0));
        expect(['yes', 'no', 'default'], contains(cfg.hrSeek));
      }
    });
  });
}
