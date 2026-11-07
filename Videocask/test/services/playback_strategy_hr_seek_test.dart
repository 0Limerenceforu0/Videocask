import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/playback_strategy.dart';

void main() {
  const mb = 1024 * 1024;

  group('拖动精度从三档里拆出来', () {
    test('不传 hrSeek 时保留原策略的 hr-seek', () {
      expect(PlaybackStrategyConfig.fromKey('smooth').hrSeek, 'no');
      expect(PlaybackStrategyConfig.fromKey('quality').hrSeek, 'yes');
      expect(PlaybackStrategyConfig.fromKey('balanced').hrSeek, 'default');
    });

    test('传 yes / no 会覆盖，传空串或 default 等于跟随默认', () {
      expect(
        PlaybackStrategyConfig.fromKey('balanced', hrSeek: 'yes').hrSeek,
        'yes',
      );
      expect(
        PlaybackStrategyConfig.fromKey('quality', hrSeek: 'no').hrSeek,
        'no',
      );
      expect(
        PlaybackStrategyConfig.fromKey('smooth', hrSeek: '').hrSeek,
        'no',
      );
      expect(
        PlaybackStrategyConfig.fromKey('smooth', hrSeek: 'default').hrSeek,
        'no',
      );
    });

    test('hrSeek 覆盖不能把自动缓冲的字节/秒数一起弄丢', () {
      final c = PlaybackStrategyConfig.fromKey(
        'balanced',
        bufferBytes: 128 * mb,
        hrSeek: 'yes',
      );
      expect(c.hrSeek, 'yes');
      expect(c.demuxerMaxBytes, 128 * mb);
      expect(c.demuxerReadaheadBytes, 128 * mb);
      expect(c.demuxerReadaheadSecs, 300);
      expect(c.cacheSecs, 300);
    });

    test('512MB 档仍是 1800 秒，字节与秒同步', () {
      final c = PlaybackStrategyConfig.fromKey(
        'balanced',
        bufferBytes: 512 * mb,
        hrSeek: 'no',
      );
      expect(c.demuxerMaxBytes, 512 * mb);
      expect(c.demuxerReadaheadSecs, 1800);
      expect(c.hrSeek, 'no');
    });
  });
}
