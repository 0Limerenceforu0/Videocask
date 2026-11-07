import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/config/magnet_source_catalog.dart';
import 'package:movie_app/services/torrent_search_service.dart';

/// Torrentio URL 构造回归（2026-10-22）。
///
/// 背景：内置模板曾写成 `stream/{query}.json`（缺 `movie/` 媒体类型前缀），
/// Torrentio 对该路径恒返 404 —— 国内唯一稳定可达的磁力源静默失效，
/// 表现为「磁力资源播放不了 / 搜不到任何磁力」。
/// 本组测试钉住两条契约：URL 必须带 `/movie/` 前缀；非 IMDb id 查询不得
/// 产生请求（`stream/search/{片名}.json` 实测返回空 streams）。
void main() {
  // 内置默认模板（与 MagnetSourceCatalog 保持一致的钉法：直接取目录里的真值）。
  const template = 'https://torrentio.strem.fun/stream/movie/{query}.json';

  group('内置目录契约', () {
    test('Torrentio 模板必须带 movie/ 前缀（防回归到 404 旧模板）', () {
      final torrentio = MagnetSourceCatalog.builtInDefaults
          .where((c) => c.id == 'torrentio')
          .toList();
      expect(torrentio, hasLength(1));
      expect(torrentio.single.driver.name, 'torrentioJson');
      expect(
        torrentio.single.urlTemplate,
        contains('/stream/movie/{query}.json'),
      );
      expect(torrentio.single.enabled, isTrue);
    });
  });

  group('TorrentSearchService.torrentioUrlCandidates', () {
    test('tt id → movie 前缀为主候选 + series 前缀兜底', () {
      final urls = TorrentSearchService.torrentioUrlCandidates(
        template,
        'tt0111161',
      );
      expect(urls, [
        'https://torrentio.strem.fun/stream/movie/tt0111161.json',
        'https://torrentio.strem.fun/stream/series/tt0111161.json',
      ]);
    });

    test('movie 候选必须排在 series 之前（先按电影查）', () {
      final urls = TorrentSearchService.torrentioUrlCandidates(
        template,
        'tt0903747',
      );
      expect(urls.first, contains('/stream/movie/tt0903747.json'));
      expect(urls.last, contains('/stream/series/tt0903747.json'));
    });

    test('大写 TT 与空白 trim 后同样构造 URL', () {
      final urls =
          TorrentSearchService.torrentioUrlCandidates(template, '  TT0111161 ');
      expect(urls, [
        'https://torrentio.strem.fun/stream/movie/TT0111161.json',
        'https://torrentio.strem.fun/stream/series/TT0111161.json',
      ]);
    });

    test('片名查询不产生 URL（search 端点实测返回空 streams）', () {
      expect(
        TorrentSearchService.torrentioUrlCandidates(template, '肖申克的救赎'),
        isEmpty,
      );
      expect(
        TorrentSearchService.torrentioUrlCandidates(template, 'shawshank 1994'),
        isEmpty,
      );
    });

    test('8-9 位数字的 tt id 同样构造 URL（IMDb 新片 id 已到 8-9 位）', () {
      expect(
        TorrentSearchService.torrentioUrlCandidates(template, 'tt01111611'),
        [
          'https://torrentio.strem.fun/stream/movie/tt01111611.json',
          'https://torrentio.strem.fun/stream/series/tt01111611.json',
        ],
      );
    });

    test('非 tt id 形态不产生 URL', () {
      for (final bad in const [
        '',
        '   ',
        'tt',
        'ttabc',
        'tt011116', // 只有 6 位数字，短于合法 IMDb id
        '0111161',
      ]) {
        expect(
          TorrentSearchService.torrentioUrlCandidates(template, bad),
          isEmpty,
          reason: 'query="$bad" 不应构造 Torrentio URL',
        );
      }
    });

    test('模板无 /movie/ 路径段时只发一次请求（用户自定义模板）', () {
      const custom = 'https://example.com/api/{query}.json';
      final urls =
          TorrentSearchService.torrentioUrlCandidates(custom, 'tt0111161');
      expect(urls, ['https://example.com/api/tt0111161.json']);
    });
  });
}
