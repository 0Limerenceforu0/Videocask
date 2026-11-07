import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/torrent_search_service.dart';

/// Torrentio 单条流的「体积 / 做种」解析回归测试。
///
/// 背景（2026-10-27 真机实测）：`parseTorrentioBody` 曾把
/// `size / seeders / leechers` 全部写死成 `0`，于是搜索页与详情页
/// 一边显示标题里的 `6.64 GB`，一边显示「体积 0 B / 做种 0」。
/// 做种数是用户判断「这资源能不能播」的唯一依据，全 0 等于劝退。
void main() {
  group('parseTorrentioStats', () {
    test('两行标题：解析做种与体积', () {
      final stats = TorrentSearchService.parseTorrentioStats(
        'Inception 2010 1080p BluRay x264-YIFY\n👤 208 💾 6.64 GB ⚙️ YTS',
      );
      expect(stats.seeders, 208);
      expect(stats.sizeBytes, (6.64 * 1024 * 1024 * 1024).round());
    });

    test('单行内联也解析得出来', () {
      final stats = TorrentSearchService.parseTorrentioStats(
        'The Wandering Earth 2019 1080p 👤 11 💾 2.15 GB',
      );
      expect(stats.seeders, 11);
      expect(stats.sizeBytes, (2.15 * 1024 * 1024 * 1024).round());
    });

    test('带千分位的做种数', () {
      final stats = TorrentSearchService.parseTorrentioStats(
        'Movie 2020 👤 1,204 💾 900 MB',
      );
      expect(stats.seeders, 1204);
      expect(stats.sizeBytes, 900 * 1024 * 1024);
    });

    test('MB / TB 单位换算', () {
      expect(
        TorrentSearchService.parseTorrentioStats('A 👤 1 💾 700 MB').sizeBytes,
        700 * 1024 * 1024,
      );
      expect(
        TorrentSearchService.parseTorrentioStats('B 👤 1 💾 1.5 TB').sizeBytes,
        (1.5 * 1024 * 1024 * 1024 * 1024).round(),
      );
    });

    test('没有统计信息时返回 0（不虚构数字）', () {
      final stats = TorrentSearchService.parseTorrentioStats(
        'Movie 2020 1080p BluRay',
      );
      expect(stats.seeders, 0);
      expect(stats.sizeBytes, 0);
      expect(stats.isEmpty, isTrue);
    });

    test('空串返回 0', () {
      expect(TorrentSearchService.parseTorrentioStats('').isEmpty, isTrue);
    });
  });

  group('torrentioDisplayName', () {
    test('丢掉统计行，只留发布名', () {
      expect(
        TorrentSearchService.torrentioDisplayName(
          'Inception 2010 1080p BluRay x264-YIFY\n👤 208 💾 6.64 GB ⚙️ YTS',
        ),
        'Inception 2010 1080p BluRay x264-YIFY',
      );
    });

    test('单行时从 👤 处截断', () {
      expect(
        TorrentSearchService.torrentioDisplayName(
          'The Wandering Earth 2019 1080p 👤 11 💾 2.15 GB ⚙️ ThePirateBay',
        ),
        'The Wandering Earth 2019 1080p',
      );
    });

    test('没有统计行时原样返回', () {
      expect(
        TorrentSearchService.torrentioDisplayName('Movie 2020 1080p'),
        'Movie 2020 1080p',
      );
    });
  });

  group('parseTorrentioBody 体积/做种入包', () {
    test('解析结果带真实体积与做种，名字不含 emoji 统计行', () {
      final body = {
        'streams': [
          {
            'title': 'Inception 2010 1080p\n👤 208 💾 6.64 GB ⚙️ YTS',
            'infoHash': '0123456789abcdef0123456789abcdef01234567',
          },
        ],
      };
      final parsed = TorrentSearchService.parseTorrentioBody(
        body,
        'Torrentio',
        imdbId: 'tt1375666',
      );
      expect(parsed, isNotNull);
      expect(parsed!.length, 1);
      expect(parsed.first.seeders, 208);
      expect(parsed.first.size, (6.64 * 1024 * 1024 * 1024).round());
      expect(parsed.first.name, 'Inception 2010 1080p');
      expect(parsed.first.imdbId, 'tt1375666');
    });

    test('生成磁力时 dn 用的是干净片名', () {
      final body = {
        'streams': [
          {
            'title': 'Inception 2010 1080p\n👤 5 💾 1 GB ⚙️ X',
            'infoHash': '0123456789abcdef0123456789abcdef01234567',
          },
        ],
      };
      final parsed = TorrentSearchService.parseTorrentioBody(
        body,
        'Torrentio',
        imdbId: 'tt1375666',
      );
      expect(parsed!.first.magnetUri, contains('dn=Inception'));
      expect(parsed.first.magnetUri, isNot(contains('👤')));
    });
  });
}
