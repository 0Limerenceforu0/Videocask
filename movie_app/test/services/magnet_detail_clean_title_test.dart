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
}
