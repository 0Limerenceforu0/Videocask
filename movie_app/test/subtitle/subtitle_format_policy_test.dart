import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/subtitle_format_policy.dart';

void main() {
  group('字幕真实扩展名', () {
    test('ASS / SSA / VTT / SUB 各自保留，不再一律 .srt', () {
      expect(subtitleExtensionFor(fileName: 'Movie.sc.ass'), '.ass');
      expect(subtitleExtensionFor(fileName: 'Movie.ssa'), '.ssa');
      expect(subtitleExtensionFor(fileName: 'Movie.chs.vtt'), '.vtt');
      expect(subtitleExtensionFor(fileName: 'Movie.idx.sub'), '.sub');
      expect(subtitleExtensionFor(fileName: 'Movie.srt'), '.srt');
    });

    test('下载端点的 .srt.gz 与 query 参数不干扰判定', () {
      expect(
        subtitleExtensionFor(
          url: 'https://subs5.strem.io/sub/abcd.srt.gz?token=xyz',
        ),
        '.srt',
      );
      expect(
        subtitleExtensionFor(
          url: 'https://subs5.strem.io/sub/abcd.ass?token=xyz',
        ),
        '.ass',
      );
    });

    test('没有可识别扩展名时默认 .srt', () {
      expect(subtitleExtensionFor(), '.srt');
      expect(subtitleExtensionFor(fileName: '', url: ''), '.srt');
      expect(subtitleExtensionFor(fileName: 'Movie.2019.chs'), '.srt');
    });
  });

  group('字幕编码探测', () {
    test('纯 UTF-8 文本', () {
      final d = decodeSubtitleBytes(utf8.encode('1\n00:00:01,000 --> 00:00:02,000\n你好'));
      expect(d.encoding, SubtitleEncoding.utf8);
      expect(d.hasBom, isFalse);
      expect(d.text, contains('你好'));
    });

    test('UTF-8 BOM 被剥掉', () {
      final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('字幕')];
      final d = decodeSubtitleBytes(bytes);
      expect(d.encoding, SubtitleEncoding.utf8Bom);
      expect(d.hasBom, isTrue);
      expect(d.text, '字幕');
      expect(d.text, isNot(startsWith('\uFEFF')));
    });

    test('UTF-16LE / BE BOM 都能解出文本', () {
      final le = decodeSubtitleBytes(<int>[
        0xFF, 0xFE, 0x41, 0x00, 0x42, 0x00,
      ]);
      expect(le.encoding, SubtitleEncoding.utf16Le);
      expect(le.text, 'AB');
      final be = decodeSubtitleBytes(<int>[
        0xFE, 0xFF, 0x00, 0x41, 0x00, 0x42,
      ]);
      expect(be.encoding, SubtitleEncoding.utf16Be);
      expect(be.text, 'AB');
    });

    test('无 BOM 的 UTF-16LE 不能被误当成合法 UTF-8', () {
      // 'A',0,'B',0 在 UTF-8 里是合法字节（NUL 也是码点），若先做严格
      // UTF-8 判定就会解成带 NUL 的乱码。
      final d = decodeSubtitleBytes(<int>[0x41, 0x00, 0x42, 0x00]);
      expect(d.encoding, SubtitleEncoding.utf16Le);
      expect(d.text, 'AB');
    });

    test('GBK/BIG5 字节保留原样，不做虚假转码', () {
      // 「中文」的 GBK 字节；项目无 GBK 解码包，硬 latin1 转 utf8 会毁掉汉字。
      final bytes = <int>[
        ...utf8.encode('1\r\n00:00:01,000 --> 00:00:02,000\r\n'),
        0xD6, 0xD0, 0xCE, 0xC4,
      ];
      final d = decodeSubtitleBytes(bytes);
      expect(d.encoding, SubtitleEncoding.nonUtf8);
      expect(d.isText, isFalse);
      expect(d.text, isNull);
      // 原样字节必须完整保留，供 writeAsBytes 落盘。
      expect(d.rawBytes, bytes);
      expect(d.label, contains('GBK'));
    });

    test('空字节返回空文本，不抛异常', () {
      final d = decodeSubtitleBytes(<int>[]);
      expect(d.text, '');
      expect(d.encoding, SubtitleEncoding.utf8);
    });
  });

  group('剧集季集解析', () {
    test('S01E02 / s1e2 / 1x02 都能解析', () {
      expect(
        parseSubtitleSeasonEpisode('Show.S01E02.1080p', null),
        (season: 1, episode: 2),
      );
      expect(
        parseSubtitleSeasonEpisode('Show.s1e2.WEB-DL', null),
        (season: 1, episode: 2),
      );
      expect(
        parseSubtitleSeasonEpisode('Show 1x02 HDTV', null),
        (season: 1, episode: 2),
      );
      expect(
        parseSubtitleSeasonEpisode('Show S1 E2', null),
        (season: 1, episode: 2),
      );
    });

    test('电影名里的年份不算季集，避免走错 series 路径', () {
      expect(
        parseSubtitleSeasonEpisode('The.Wandering.Earth.2019.1080p', '流浪地球'),
        (season: null, episode: null),
      );
      expect(parseSubtitleSeasonEpisode(null, null), (season: null, episode: null));
      expect(parseSubtitleSeasonEpisode('', ''), (season: null, episode: null));
    });
  });
}
