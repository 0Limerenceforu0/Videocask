import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/hls_ad_filter.dart';

/// 真实片源样本回放测试。
///
/// 与 [hls_ad_filter_test] 里的合成列表互补：那里的列表是手写的理想形态，
/// 这里喂的是**采集站当天真实返回的 m3u8**（已抓包固化到
/// `test/fixtures/hls/`），用来兜住「合成数据过了、真实片源却漏判/误删」的情况。
///
/// 样本来源与抓取方式见 `docs/验证与用例清单.md` 的「HLS 广告形态样本库」。
/// 采集站会改版，样本过期时应按文档里的命令重新抓取并覆盖同名文件。
const _fixtureDir = 'test/fixtures/hls';

String _read(String name) => File('$_fixtureDir/$name').readAsStringSync();

void main() {
  group('真实片源样本回放', () {
    test('非凡源：中插同域广告被剔除，正片一片不少', () {
      final result = HlsAdFilter.filterContent(
        _read('real_ffzy_play9_midroll_ad.m3u8'),
        'https://vip.ffzy-play9.com/20230104/32915_2fb357b7/2000k/hls/'
        'mixed.m3u8',
      );

      // 结构：正片前段 89 片 ─ DISCONTINUITY ─ 广告 5 片 ─ 正片后段 186 片。
      expect(result.originalCount, 280);
      expect(result.removedSegments, 5);
      expect(result.removedSeconds, closeTo(19.63, 0.05));
      expect(result.keptUrls, hasLength(275));
      // 广告块是 5 片一组，剔除后剩下的分片必须连续落回正片两段。
      expect(result.keptIndices.last, 279);
    });

    test('飞飞源：同形态中插广告同样剔除', () {
      final result = HlsAdFilter.filterContent(
        _read('real_feifeikan_midroll_ad.m3u8'),
        'https://vod.feifei-kan.com/20230205/7343_6683e5bb/2000k/hls/'
        'mixed.m3u8',
      );

      expect(result.originalCount, 275);
      expect(result.removedSegments, 5);
      expect(result.removedSeconds, closeTo(19.63, 0.05));
      expect(result.keptUrls, hasLength(270));
    });

    test('整集被 DISCONTINUITY 切碎的片源不得误删（关键反例）', () {
      // 这个源把整集切成了 146 个约 20 秒的块（896 片），块与块之间没有
      // 明显的主次之分 —— 正是「中插短块」规则最容易误伤的形态。
      // 必须一片不删，否则会砍掉正片。
      final result = HlsAdFilter.filterContent(
        _read('real_ffzy_plays_146blocks_no_ad.m3u8'),
        'https://vip.ffzy-plays.com/20250728/43628_f18ca683/3000k/hls/'
        'mixed.m3u8',
      );

      expect(result.originalCount, 896);
      expect(result.removedAny, isFalse);
      expect(result.keptUrls, hasLength(896));
      // 顺序与序号必须原样保留。
      expect(result.keptIndices, List<int>.generate(896, (i) => i));
    });

    test('全部样本过滤后都仍是可播的 VOD 列表', () {
      for (final entry in {
        'real_ffzy_play9_midroll_ad.m3u8':
            'https://vip.ffzy-play9.com/20230104/32915_2fb357b7/2000k/hls/'
                'mixed.m3u8',
        'real_feifeikan_midroll_ad.m3u8':
            'https://vod.feifei-kan.com/20230205/7343_6683e5bb/2000k/hls/'
                'mixed.m3u8',
        'real_ffzy_plays_146blocks_no_ad.m3u8':
            'https://vip.ffzy-plays.com/20250728/43628_f18ca683/3000k/hls/'
                'mixed.m3u8',
      }.entries) {
        final result = HlsAdFilter.filterContent(_read(entry.key), entry.value);
        expect(result.isVod, isTrue, reason: entry.key);
        expect(result.hasByteRange, isFalse, reason: entry.key);
        expect(result.segments, isNotEmpty, reason: entry.key);
      }
    });
  });
}
