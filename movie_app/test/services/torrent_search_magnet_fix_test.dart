import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/torrent_search_service.dart';

/// 磁力搜索修复回归（2026-10-25）。
///
/// 钉住三类契约，摘修复即红：
/// 1. Torrentio 解析必须把查询的 imdbId 回填到每条结果 —— 否则 `_finalizeResults`
///    的 imdb 硬过滤会把详情页/搜索框的磁力整批删光（旧「磁力一直为空」）。
/// 2. `isMagnetLink` 正确识别磁力链接/裸 btih，且不误判普通搜索词。
/// 3. `torrentInfoFromRawMagnet` 能从原始磁力构造详情页可用的 TorrentInfo。
void main() {
  const torrentioBody = {
    'streams': [
      {
        'title': 'The Godfather 1972 1080p BluRay',
        'infoHash': '0123456789abcdef0123456789abcdef01234567',
        'url':
            'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=The+Godfather',
      },
      {
        'title': 'The Godfather Part II 1974',
        'infoHash': 'abcdef0123456789abcdef0123456789abcdef01',
      },
    ],
  };

  group('TorrentSearchService.parseTorrentioBody', () {
    test('必须回填查询 imdbId，否则会被 imdb 过滤整批删光', () {
      final parsed = TorrentSearchService.parseTorrentioBody(
        torrentioBody,
        'Torrentio',
        imdbId: 'tt0068646',
      );
      expect(parsed, isNotNull);
      expect(parsed!.length, 2);
      for (final t in parsed) {
        expect(
          t.imdbId,
          'tt0068646',
          reason: 'Torrentio 结果必须携带查询的 imdbId',
        );
      }
    });

    test('不传 imdbId 时结果不带 imdbId（默认行为不变）', () {
      final parsed =
          TorrentSearchService.parseTorrentioBody(torrentioBody, 'Torrentio');
      expect(parsed, isNotNull);
      expect(parsed!.every((t) => t.imdbId == null), isTrue);
    });

    test('无 streams 返回 null', () {
      expect(
        TorrentSearchService.parseTorrentioBody(
          {'streams': []},
          'Torrentio',
          imdbId: 'tt0068646',
        ),
        isNull,
      );
    });
  });

  group('TorrentSearchService.isMagnetLink', () {
    test('识别完整 magnet:? 链接（含合法 btih）', () {
      expect(
        TorrentSearchService.isMagnetLink(
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=test',
        ),
        isTrue,
      );
    });

    test('识别裸 40 位 btih 哈希', () {
      expect(
        TorrentSearchService.isMagnetLink(
          '0123456789abcdef0123456789abcdef01234567',
        ),
        isTrue,
      );
    });

    test('拒绝缺少合法 btih 的磁力前缀', () {
      expect(
        TorrentSearchService.isMagnetLink('magnet:?xt=urn:btih:zzz'),
        isFalse,
      );
    });

    test('拒绝普通搜索词（中文/英文片名）', () {
      expect(TorrentSearchService.isMagnetLink('教父'), isFalse);
      expect(TorrentSearchService.isMagnetLink('The Godfather 1972'), isFalse);
      expect(TorrentSearchService.isMagnetLink(''), isFalse);
    });
  });

  group('TorrentSearchService.torrentInfoFromRawMagnet', () {
    test('从磁力链接构造，名称取 dn 参数', () {
      final t = TorrentSearchService.torrentInfoFromRawMagnet(
        'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=The+Godfather+1972',
      );
      expect(
        t.magnetUri,
        contains('btih:0123456789abcdef0123456789abcdef01234567'),
      );
      expect(t.name, 'The Godfather 1972');
      expect(t.source, '本地磁力');
    });

    test('裸 btih 补齐成完整 magnet，名称回退为「磁力链接」', () {
      final t = TorrentSearchService.torrentInfoFromRawMagnet(
        '0123456789abcdef0123456789abcdef01234567',
      );
      expect(
        t.magnetUri,
        'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
      );
      expect(t.name, '磁力链接');
    });
  });
}
