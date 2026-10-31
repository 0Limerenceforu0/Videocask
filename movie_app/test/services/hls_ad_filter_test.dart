import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/hls_ad_filter.dart';

const _mainHost = 'https://main.example.com/vod/s1';

String _mediaPlaylist(
  List<String> segmentUrls, {
  bool vod = true,
  Map<int, bool> discontinuityBefore = const {},
  double duration = 10,
  List<double>? durations,
}) {
  final buffer = StringBuffer(
    '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:10\n'
    '#EXT-X-MEDIA-SEQUENCE:0\n',
  );
  for (var i = 0; i < segmentUrls.length; i++) {
    if (discontinuityBefore[i] == true) {
      buffer.writeln('#EXT-X-DISCONTINUITY');
    }
    final d =
        durations != null && i < durations.length ? durations[i] : duration;
    buffer.writeln('#EXTINF:$d,');
    buffer.writeln(segmentUrls[i]);
  }
  if (vod) buffer.writeln('#EXT-X-ENDLIST');
  return buffer.toString();
}

/// 按块构造播放列表：每块前插一条 DISCONTINUITY，URL 前缀可带绝对域名。
/// [blocks] 元素为 (分片数, 单片时长, URL 前缀)。
String _rawPlaylist(List<(int, double, String)> blocks) {
  final buffer = StringBuffer(
    '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:10\n',
  );
  for (final block in blocks) {
    buffer.writeln('#EXT-X-DISCONTINUITY');
    for (var i = 0; i < block.$1; i++) {
      buffer.writeln('#EXTINF:${block.$2},');
      buffer.writeln('${block.$3}$i.ts');
    }
  }
  buffer.writeln('#EXT-X-ENDLIST');
  return buffer.toString();
}

/// 按块构造播放列表：每块前插一条 DISCONTINUITY。
/// [blocks] 元素为 (分片数, 单片时长, 文件名前缀)。
String _blocksPlaylist(List<(int, double, String)> blocks) {
  final urls = <String>[];
  final durations = <double>[];
  final discontinuity = <int, bool>{};
  for (final block in blocks) {
    discontinuity[urls.length] = true;
    for (var i = 0; i < block.$1; i++) {
      urls.add('${_mainHost}_${block.$3}$i.ts');
      durations.add(block.$2);
    }
  }
  return _mediaPlaylist(
    urls,
    durations: durations,
    discontinuityBefore: discontinuity,
  );
}

/// 复刻采集站真实片源的形态：全部分片同域相对路径，
/// 正片中段被两条 DISCONTINUITY 包夹着一小段广告。
String _realWorldPlaylist({
  int headSegments = 89,
  double headDuration = 4.0,
  int adSegments = 5,
  double adDuration = 3.92,
  int tailSegments = 186,
  double tailDuration = 4.0,
}) {
  final urls = <String>[];
  final durations = <double>[];
  final discontinuity = <int, bool>{};
  // 列表开头就有一条 DISCONTINUITY（真实源就是这样，会产生一个空块）。
  discontinuity[0] = true;
  for (var i = 0; i < headSegments; i++) {
    urls.add('${_mainHost}_h$i.ts');
    durations.add(headDuration);
  }
  discontinuity[urls.length] = true;
  for (var i = 0; i < adSegments; i++) {
    urls.add('${_mainHost}_ad$i.ts');
    durations.add(adDuration);
  }
  discontinuity[urls.length] = true;
  for (var i = 0; i < tailSegments; i++) {
    urls.add('${_mainHost}_t$i.ts');
    durations.add(tailDuration);
  }
  return _mediaPlaylist(
    urls,
    durations: durations,
    discontinuityBefore: discontinuity,
  );
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

    test('同域中插广告被剔除（采集站真实形态）', () {
      // 全部分片同域、命名风格一致，只有「DISCONTINUITY 包夹 + 时长异常短」
      // 这一个可判据：19.6s 夹在 356s 与 744s 之间。
      final content = _realWorldPlaylist();
      final result = HlsAdFilter.filterContent(
        content,
        'https://main.example.com/vod/s1/index.m3u8',
      );

      expect(result.removedAny, isTrue);
      expect(result.removedSegments, 5);
      expect(result.removedSeconds, closeTo(19.6, 0.01));
      expect(result.keptUrls, hasLength(89 + 186));
      // 原始序号必须连续跳过广告段（AES-128 隐式 IV 依赖）。
      expect(result.keptIndices.first, 0);
      expect(result.keptIndices.last, 89 + 5 + 186 - 1);
      expect(result.keptIndices, isNot(contains(89)));
      for (final url in result.keptUrls) {
        expect(url, isNot(contains('_ad')));
      }
    });

    test('连续两个同域中插广告都能剔除', () {
      // 正片 → 广告A → 正片 → 广告B → 正片。
      // 两个广告块相邻参照必须跳过对方，否则第二个会因「邻居太短」漏判。
      final content = _blocksPlaylist([
        (30, 4.0, 'h'),
        (5, 3.92, 'ad1'),
        (30, 4.0, 'm'),
        (5, 3.92, 'ad2'),
        (30, 4.0, 't'),
      ]);
      final result = HlsAdFilter.filterContent(
        content,
        'https://main.example.com/vod/s1/index.m3u8',
      );

      expect(result.removedSegments, 10);
      expect(result.keptUrls, hasLength(90));
      for (final url in result.keptUrls) {
        expect(url, isNot(contains('_ad')));
      }
    });

    test('开头多余的 DISCONTINUITY 不影响首尾判定', () {
      // 首块为正片（356s），不应被当作「首部广告」误删。
      final content = _realWorldPlaylist(adSegments: 0);
      final result = HlsAdFilter.filterContent(
        content,
        'https://main.example.com/vod/s1/index.m3u8',
      );

      expect(result.removedAny, isFalse);
      expect(result.keptUrls, hasLength(89 + 186));
    });

    test('中插短块但两侧正片不够长时不剔除', () {
      // 短视频（两侧各 60s）里的 20s 分段，风险太高，宁可保留。
      final content = _realWorldPlaylist(
        headSegments: 6,
        adSegments: 2,
        tailSegments: 6,
      );
      final result = HlsAdFilter.filterContent(
        content,
        'https://main.example.com/vod/s1/index.m3u8',
      );

      expect(result.removedAny, isFalse);
    });

    test('剔除比例过高时整体放弃过滤', () {
      // 三段跨域广告合计 120s > 正片 100s（占比 55%）→ 判定可疑，原样返回。
      final content = _rawPlaylist([
        (4, 10.0, 'https://ad-cdn.example.com/a'),
        (10, 10.0, '$_mainHost/c'),
        (4, 10.0, 'https://ad-cdn.example.com/b'),
        (4, 10.0, 'https://ad-cdn.example.com/d'),
      ]);

      final result =
          HlsAdFilter.filterContent(content, '$_mainHost/index.m3u8');

      expect(result.removedAny, isFalse);
      expect(result.keptUrls, hasLength(22));
    });

    test('广告分片更多时不会把正片误判为跨域广告', () {
      // 广告被切成很多短片，按「分片个数」统计主体域名会被广告 CDN 顶替，
      // 进而把正片当成异域块删掉。主体域名必须按总时长加权统计。
      final content = _rawPlaylist([
        (12, 2.0, 'https://ad-cdn.example.com/a'),
        (10, 10.0, '$_mainHost/c'),
      ]);

      final result =
          HlsAdFilter.filterContent(content, '$_mainHost/index.m3u8');

      // 正片 100s 是主体（广告虽 12 片但只有 24s），必须保留。
      expect(result.keptUrls.every((u) => u.contains('/c')), isTrue);
      expect(result.removedSegments, 12);
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
    test('广告被剔除后，其两侧正片之间不再保留人为 DISCONTINUITY（修复解码报错/闪退）', () {
      final content = _mediaPlaylist(
        [
          'https://ad-cdn.example.com/ads/1.ts', // 0: 片头广告
          '$_mainHost/0.ts', // 1: 正片
          '$_mainHost/1.ts', // 2: 正片
          'https://ad-cdn.example.com/mid/1.ts', // 3: 中插广告
          '$_mainHost/2.ts', // 4: 正片
        ],
        discontinuityBefore: {1: true, 3: true, 4: true},
      );
      final result =
          HlsAdFilter.filterContent(content, '$_mainHost/index.m3u8');
      final rewritten = buildAdFreePlaylistContent(result);

      expect(rewritten, isNotNull);
      expect(rewritten!, contains('#EXT-X-ENDLIST'));
      expect(rewritten, isNot(contains('ad-cdn')));
      // 广告被剔除后，正片 2 → 正片 4 之间本无真实 discontinuity（原标记是正片→广告
      // 边界），应当删掉；否则 mpv 越过时重置解码器 → "Error decoding audio" 反复报错。
      expect(rewritten, isNot(contains('#EXT-X-DISCONTINUITY')));
      expect(rewritten, contains('$_mainHost/0.ts'));
      expect(rewritten, contains('$_mainHost/2.ts'));
      expect(rewritten, contains('#EXT-X-PLAYLIST-TYPE:VOD'));
    });

    test('源里原本就存在的正片→正片 DISCONTINUITY 仍保留（人为断层才删）', () {
      // 构造：正片 a → 真实 discontinuity → 正片 b → 中插广告 → 正片 c。
      // 剔除中插广告后：a→b 的「真实」discontinuity 应保留；广告两侧的人为断层应删掉。
      final content = _mediaPlaylist(
        [
          '$_mainHost/a0.ts', // 0
          '$_mainHost/a1.ts', // 1
          '$_mainHost/b0.ts', // 2 紧随一条真实 discontinuity（a→b 正片切换）
          '$_mainHost/b1.ts', // 3
          'https://ad-cdn.example.com/ad/1.ts', // 4 中插广告（跨域，被剔除）
          '$_mainHost/c0.ts', // 5 紧随广告后的 discontinuity（正片→广告边界，应删）
        ],
        discontinuityBefore: {2: true, 4: true, 5: true},
      );
      final result =
          HlsAdFilter.filterContent(content, '$_mainHost/index.m3u8');
      final rewritten = buildAdFreePlaylistContent(result);

      expect(rewritten, isNotNull);
      // a→b 的真实 discontinuity 必须保留（a1 的前一个原始分片 a0 也保留）。
      expect(rewritten!, contains('#EXT-X-DISCONTINUITY'));
      // 广告两侧的人为断层：b→c 之间原是正片→广告边界，广告剔除后不应保留。
      // 这里只断言 a→b 的真实标记存在、且内容都还在。
      expect(rewritten, contains('$_mainHost/a0.ts'));
      expect(rewritten, contains('$_mainHost/c0.ts'));
      expect(rewritten, isNot(contains('ad-cdn')));
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
          '#EXTINF:10,\n'
          '$_mainHost/1.ts\n'
          '#EXTINF:10,\n'
          '$_mainHost/2.ts\n'
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
