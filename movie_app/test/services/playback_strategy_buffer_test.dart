import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/playback_strategy.dart';

void main() {
  const int mb = 1024 * 1024;

  group('PlaybackStrategyConfig 缓冲挡位注入', () {
    test('不传 bufferBytes 保持原有 512MB（向后兼容）', () {
      final cfg = PlaybackStrategyConfig.fromKey('balanced');
      expect(cfg.demuxerMaxBytes, 512 * mb);
      expect(cfg.demuxerReadaheadSecs, 1800);
      expect(cfg.cacheSecs, 1800);
    });

    test('128MB 挡位：三个字节上限与时间上限一起降下来', () {
      final cfg =
          PlaybackStrategyConfig.fromKey('balanced', bufferBytes: 128 * mb);
      // 只降字节不降秒数是无效的：低码率流 1800 秒都攒不到 128MB，
      // 于是照样无限往后预读（这就是 A2 要修的病根）。
      expect(cfg.demuxerBufferBytes, 128 * mb);
      expect(cfg.demuxerMaxBytes, 128 * mb);
      expect(cfg.demuxerReadaheadBytes, 128 * mb);
      expect(cfg.demuxerReadaheadSecs, 300);
      expect(cfg.cacheSecs, 300);
    });

    test('512MB 挡位保持 1800 秒', () {
      final cfg =
          PlaybackStrategyConfig.fromKey('quality', bufferBytes: 512 * mb);
      expect(cfg.demuxerMaxBytes, 512 * mb);
      expect(cfg.demuxerReadaheadSecs, 1800);
    });

    test('低于 128MB 被夹到下限（不能退回 mpv 浅窗口）', () {
      final cfg =
          PlaybackStrategyConfig.fromKey('balanced', bufferBytes: 32 * mb);
      expect(cfg.demuxerMaxBytes, 128 * mb);
      expect(cfg.demuxerReadaheadSecs, 300);
    });

    test('高于 512MB 被夹到上限（不能给 lmkd 递刀）', () {
      final cfg =
          PlaybackStrategyConfig.fromKey('balanced', bufferBytes: 2048 * mb);
      expect(cfg.demuxerMaxBytes, 512 * mb);
    });

    test('挡位只改缓冲，不动 hr-seek / 超时等策略字段', () {
      final base = PlaybackStrategyConfig.fromKey('smooth');
      final tuned =
          PlaybackStrategyConfig.fromKey('smooth', bufferBytes: 192 * mb);
      expect(tuned.hrSeek, base.hrSeek);
      expect(tuned.networkTimeoutSecs, base.networkTimeoutSecs);
      expect(tuned.routeFallbackSec, base.routeFallbackSec);
      expect(tuned.scrubSeekThrottleMs, base.scrubSeekThrottleMs);
    });

    test('secsForBytes 单调递增且封顶 1800', () {
      expect(PlaybackStrategyConfig.secsForBytes(128 * mb), 300);
      expect(PlaybackStrategyConfig.secsForBytes(192 * mb), 600);
      expect(PlaybackStrategyConfig.secsForBytes(256 * mb), 900);
      expect(PlaybackStrategyConfig.secsForBytes(384 * mb), 1200);
      expect(PlaybackStrategyConfig.secsForBytes(512 * mb), 1800);
      expect(PlaybackStrategyConfig.secsForBytes(4096 * mb), 1800);
    });
  });
}
