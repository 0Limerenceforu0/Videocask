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
      expect(quality.hrSeek, 'yes');
      expect(quality.demuxerBufferBytes, lessThan(96 * 1024 * 1024));
    });

    test('unknown key falls back to balanced', () {
      final cfg = PlaybackStrategyConfig.fromKey('unknown');
      expect(cfg.demuxerBufferBytes, 96 * 1024 * 1024);
      expect(cfg.routeFallbackSec, 8);
    });
  });
}
