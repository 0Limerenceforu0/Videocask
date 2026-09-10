import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/hls_ad_filter.dart';

const _mainHost = 'https://main.example.com/vod/s1';

String _mediaPlaylist(
  List<String> segmentUrls, {
  bool vod = true,
  Map<int, bool> discontinuityBefore = const {},
  double duration = 10,
}) {
  final buffer = StringBuffer(
    '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:10\n'
    '#EXT-X-MEDIA-SEQUENCE:0\n',
  );
  for (var i = 0; i < segmentUrls.length; i++) {
    if (discontinuityBefore[i] == true) {
      buffer.writeln('#EXT-X-DISCONTINUITY');
    }
    buffer.writeln('#EXTINF:$duration,');
    buffer.writeln(segmentUrls[i]);
  }
  if (vod) buffer.writeln('#EXT-X-ENDLIST');
  return buffer.toString();
}

void main() {
  group('HlsAdFilter.filterContent', () {
    test('无 discontinuity 的纯净列表：原样保留', () {
      final content = _mediaPlaylist([
        '$_mainHost/0.ts',
        '$_mainHost/1.ts',
        '$_mainHost/2.ts',
      ]);
      final result =
          HlsAdFilter.filterContent(content, '$_mainHost/index.m3u8');

      expect(result.removedAny, isFalse);
      expect(result.keptUrls, hasLength(3));
      expect(result.keptIndices, [0, 1, 2]);
    });

    test('片头广告（不同域名）被剔除，原始序号保留', () {
      final content = _mediaPlaylist(
        [
          'https://ad-cdn.example.com/ads/1.ts',
          'https://ad-cdn.example.com/ads/2.ts',
          '$_mainHost/0.ts',
          '$_mainHost/1.ts',
          '$_mainHost/2.ts',
          '$_mainHost/3.ts',
        ],
        discontinuityBefore: {2: true},
      );
      final result =
          HlsAdFilter.filterContent(content, '$_mainHost/index.m3u8');

      expect(result.removedAny, isTrue);
      expect(result.removedSegments, 2);
      expect(result.keptUrls, hasLength(4));
      // 保留分片的原始序号必须从 2 开始（AES-128 隐式 IV 依赖）。
      expect(result.keptIndices, [2, 3, 4, 5]);
    });

    test('中插广告（不同域名）被剔除', () {
      final content = _mediaPlaylist(
        [
          '$_mainHost/0.ts',
          '$_mainHost/1.ts',
          'https://ad-cdn.example.com/mid/1.ts',
          'https://ad-cdn.example.com/mid/2.ts',
          '$_mainHost/2.ts',
          '$_mainHost/3.ts',
        ],
        discontinuityBefore: {2: true, 4: true},
      );
      final result =
          HlsAdFilter.filterContent(content, '$_mainHost/index.m3u8');

      expect(result.removedSegments, 2);
      expect(result.keptUrls, [
        '$_mainHost/0.ts',
        '$_mainHost/1.ts',
        '$_mainHost/2.ts',
        '$_mainHost/3.ts',
      ]);
      expect(result.keptIndices, [0, 1, 4, 5]);
    });

    test('片尾广告（不同域名）被剔除', () {
      final content = _mediaPlaylist(
        [
          '$_mainHost/0.ts',
          '$_mainHost/1.ts',
          'https://ad-cdn.example.com/tail/1.ts',
        ],
        discontinuityBefore: {2: true},
      );
      final result =
          HlsAdFilter.filterContent(content, '$_mainHost/index.m3u8');

      expect(result.removedSegments, 1);
      expect(result.keptUrls, hasLength(2));
    });

    test('同域首部短块（常见片头广告形态）被剔除', () {
      final content = _mediaPlaylist(
        [
          '$_mainHost/ad0.ts',
          '$_mainHost/ad1.ts',
          '$_mainHost/0.ts',
          '$_mainHost/1.ts',
          '$_mainHost/2.ts',
          '$_mainHost/3.ts',
          '$_mainHost/4.ts',
          '$_mainHost/5.ts',
          '$_mainHost/6.ts',
          '$_mainHost/7.ts',
          '$_mainHost/8.ts',
          '$_mainHost/9.ts',
        ],
        discontinuityBefore: {2: true},
      );
      final result =
          HlsAdFilter.filterContent(content, '$_mainHost/index.m3u8');

      expect(result.removedSegments, 2);
      expect(result.keptIndices, [2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
    });

    test('同域中部短块不剔除（避免误删正片场景切换）', () {
      final content = _mediaPlaylist(
        [
          '$_mainHost/0.ts',
          '$_mainHost/1.ts',
          '$_mainHost/part2-0.ts',
          '$_mainHost/part2-1.ts',
          '$_mainHost/2.ts',
          '$_mainHost/3.ts',
        ],
        discontinuityBefore: {2: true, 4: true},
      );
      final result =
          HlsAdFilter.filterContent(content, '$_mainHost/index.m3u8');

      expect(result.removedAny, isFalse);
    });

    test('同域首部长块不剔除（可能就是正片分段）', () {
      final content = _mediaPlaylist(
        [
          '$_mainHost/a0.ts',
          '$_mainHost/a1.ts',
          '$_mainHost/a2.ts',
          '$_mainHost/a3.ts',
          '$_mainHost/0.ts',
          '$_mainHost/1.ts',
          '$_mainHost/2.ts',
          '$_mainHost/3.ts',
        ],
        discontinuityBefore: {4: true},
      );
      final result =
          HlsAdFilter.filterContent(content, '$_mainHost/index.m3u8');

      expect(result.removedAny, isFalse);
    });

    test('直播列表（无 ENDLIST）不过滤', () {
      final content = _mediaPlaylist(
        [
          'https://ad-cdn.example.com/ads/1.ts',
          '$_mainHost/0.ts',
          '$_mainHost/1.ts',
        ],
        vod: false,
        discontinuityBefore: {1: true},
      );
      final result =
          HlsAdFilter.filterContent(content, '$_mainHost/index.m3u8');

      expect(result.removedAny, isFalse);
    });

    test('相对路径分片被解析为绝对地址', () {
      final content = _mediaPlaylist([
        'seg0.ts',
        'seg1.ts',
      ]);
      final result = HlsAdFilter.filterContent(
        content,
        'https://main.example.com/vod/s1/index.m3u8',
      );

      expect(result.keptUrls, [
        'https://main.example.com/vod/s1/seg0.ts',
        'https://main.example.com/vod/s1/seg1.ts',
      ]);
    });

    test('全部分片都是广告域名时兜底保留（宁缺毋滥）', () {
      // 主体域名统计异常（如全部无法解析 host）时不应清空列表。
      final content = _mediaPlaylist([
        'https://a.example.com/0.ts',
        'https://b.example.com/1.ts',
      ]);
      final result = HlsAdFilter.filterContent(content, 'https://x/y.m3u8');

      expect(result.segments, isNotEmpty);
    });
  });

  group('buildAdFreePlaylistContent', () {
    test('重建的播放列表剔除广告并保留 ENDLIST 与块间切换标记', () {
      final content = _mediaPlaylist(
        [
          'https://ad-cdn.example.com/ads/1.ts',
          '$_mainHost/0.ts',
          '$_mainHost/1.ts',
          'https://ad-cdn.example.com/mid/1.ts',
          '$_mainHost/2.ts',
        ],
        discontinuityBefore: {1: true, 3: true, 4: true},
      );
      final result =
          HlsAdFilter.filterContent(content, '$_mainHost/index.m3u8');
      final rewritten = buildAdFreePlaylistContent(result);

      expect(rewritten, isNotNull);
      expect(rewritten!, contains('#EXT-X-ENDLIST'));
      expect(rewritten, isNot(contains('ad-cdn')));
      // 保留块之间的真实切换（0/1 块与 2 块原本被广告分隔）。
      expect(rewritten, contains('#EXT-X-DISCONTINUITY'));
      expect(rewritten, contains('$_mainHost/0.ts'));
      expect(rewritten, contains('$_mainHost/2.ts'));
      expect(rewritten, contains('#EXT-X-PLAYLIST-TYPE:VOD'));
    });

    test('未剔除广告 / 含 BYTERANGE 时返回 null', () {
      final clean = _mediaPlaylist(['$_mainHost/0.ts']);
      final cleanResult =
          HlsAdFilter.filterContent(clean, '$_mainHost/index.m3u8');
      expect(buildAdFreePlaylistContent(cleanResult), isNull);

      const withByteRange = '#EXTM3U\n'
          '#EXT-X-TARGETDURATION:10\n'
          '#EXTINF:10,\n'
          'https://ad-cdn.example.com/ads/1.ts\n'
          '#EXT-X-BYTERANGE:1000@0\n'
          '#EXT-X-DISCONTINUITY\n'
          '#EXTINF:10,\n'
          '$_mainHost/0.ts\n'
          '#EXT-X-ENDLIST\n';
      final byteRangeResult = HlsAdFilter.filterContent(
        withByteRange,
        '$_mainHost/index.m3u8',
      );
      expect(byteRangeResult.hasByteRange, isTrue);
      expect(buildAdFreePlaylistContent(byteRangeResult), isNull);
    });

    test('EXT-X-MAP 初始化分片行被保留且 URI 解析为绝对地址', () {
      const content = '#EXTM3U\n'
          '#EXT-X-TARGETDURATION:10\n'
          '#EXT-X-MAP:URI="init.mp4"\n'
          '#EXTINF:10,\n'
          'https://ad-cdn.example.com/ads/1.ts\n'
          '#EXT-X-DISCONTINUITY\n'
          '#EXTINF:10,\n'
          '$_mainHost/0.ts\n'
          '#EXT-X-ENDLIST\n';
      final result =
          HlsAdFilter.filterContent(content, '$_mainHost/index.m3u8');
      final rewritten = buildAdFreePlaylistContent(result);

      expect(rewritten, isNotNull);
      expect(
        rewritten!,
        contains('#EXT-X-MAP:URI="https://main.example.com/vod/s1/init.mp4"'),
      );
    });
  });
}
