import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/magnet_detail_enrichment_service.dart';

void main() {
  group('MagnetDetailEnrichmentService.cleanSearchTitle', () {
    test('中文片名后带年份与分辨率 → 只留片名', () {
      expect(
        MagnetDetailEnrichmentService.cleanSearchTitle('肖申克的救赎.1994.1080p'),
        '肖申克的救赎',
      );
    });

    test('英文点分资源名剥离片源 / 编码标签', () {
      expect(
        MagnetDetailEnrichmentService.cleanSearchTitle(
          'The.Shawshank.Redemption.1994.1080p.BluRay.x264',
        ),
        'The Shawshank Redemption',
      );
    });

    test('片名自带的年份不被误删', () {
      expect(
        MagnetDetailEnrichmentService.cleanSearchTitle(
          'Blade.Runner.2049.2017.1080p',
        ),
        'Blade Runner 2049',
      );
      expect(
        MagnetDetailEnrichmentService.cleanSearchTitle('1917.2019.1080p'),
        '1917',
      );
    });

    test('括号内的语言 / 字幕标签整体去掉', () {
      expect(
        MagnetDetailEnrichmentService.cleanSearchTitle('教父[国语中字].1080p'),
        '教父',
      );
    });

    test('没有发布标签时原样返回', () {
      expect(
        MagnetDetailEnrichmentService.cleanSearchTitle('霸王别姬'),
        '霸王别姬',
      );
      expect(MagnetDetailEnrichmentService.cleanSearchTitle(''), '');
    });
  });

  group('MagnetDetailEnrichmentService.cleanLookupParts', () {
    test('纯英文 release 名剥成干净片名并保留年份', () {
      final p = MagnetDetailEnrichmentService.cleanLookupParts(
        'Hi Mom 2021 720p Chinese HDRip HC H264 BONE',
      );
      expect(p.title, 'Hi Mom');
      expect(p.year, '2021');
    });

    test('中文名后跟英文规格词时一并截掉', () {
      final p = MagnetDetailEnrichmentService.cleanLookupParts(
        '肖申克的救赎.1994.1080p.BluRay.x264',
      );
      expect(p.title, '肖申克的救赎');
      expect(p.year, '1994');
    });

    test('方括号中英并列时优先英文供 IMDb 联想', () {
      final p = MagnetDetailEnrichmentService.cleanLookupParts(
        '[DBD-Raws][流浪地球/The.Wandering.Earth.][1080P][BDRip][简体内封]',
      );
      expect(p.title, 'The Wandering Earth');
    });

    test('干净中文片名原样返回且无年份', () {
      final p = MagnetDetailEnrichmentService.cleanLookupParts('霸王别姬');
      expect(p.title, '霸王别姬');
      expect(p.year, isNull);
    });

    test('btih 哈希不会污染检索片名', () {
      final p = MagnetDetailEnrichmentService.cleanLookupParts(
        '9a384d74548884dc4ae9c4ebe1911c402251135a',
      );
      expect(p.title, isEmpty);
    });
  });
}
