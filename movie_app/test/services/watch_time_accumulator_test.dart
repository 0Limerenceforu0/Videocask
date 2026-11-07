import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/watch_time_accumulator.dart';

void main() {
  group('countWatchedAdvanceMs', () {
    test('新记录按当前进度计入（受上限约束）', () {
      expect(
        countWatchedAdvanceMs(
          progressMs: 20000,
          sameEpisode: false,
          previousProgressMs: null,
        ),
        20000,
      );
      expect(
        countWatchedAdvanceMs(
          progressMs: 20 * 60 * 1000,
          sameEpisode: false,
          previousProgressMs: null,
        ),
        kMaxCountedAdvanceMs,
      );
    });

    test('同集正常推进按差值计入', () {
      expect(
        countWatchedAdvanceMs(
          progressMs: 12000,
          sameEpisode: true,
          previousProgressMs: 7000,
        ),
        5000,
      );
    });

    test('位置回退（重看/回跳）不计', () {
      expect(
        countWatchedAdvanceMs(
          progressMs: 9000,
          sameEpisode: true,
          previousProgressMs: 10000,
        ),
        0,
      );
    });

    test('一次跨越 10 分钟（拖进度条）不计，避免时长虚增', () {
      expect(
        countWatchedAdvanceMs(
          progressMs: 15 * 60 * 1000,
          sameEpisode: true,
          previousProgressMs: 5 * 60 * 1000,
        ),
        0,
      );
    });

    test('换集只按新集已播部分计，不把上一集进度差带进来', () {
      expect(
        countWatchedAdvanceMs(
          progressMs: 8000,
          sameEpisode: false,
          previousProgressMs: 25 * 60 * 1000,
        ),
        8000,
      );
    });

    test('进度为 0 / 负数不计', () {
      expect(
        countWatchedAdvanceMs(
          progressMs: 0,
          sameEpisode: true,
          previousProgressMs: 5000,
        ),
        0,
      );
      expect(
        countWatchedAdvanceMs(
          progressMs: -1,
          sameEpisode: false,
          previousProgressMs: null,
        ),
        0,
      );
    });

    test('正好等于上限的增量仍然计入（边界）', () {
      expect(
        countWatchedAdvanceMs(
          progressMs: 30000,
          sameEpisode: true,
          previousProgressMs: 0,
        ),
        kMaxCountedAdvanceMs,
      );
    });
  });
}
