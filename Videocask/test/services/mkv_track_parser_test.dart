import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/subtitle_probe/mkv_track_parser.dart';

/// 构造一个最小的 MKV `Tracks` 元素（只含需要的字段）。
///
/// 结构：`Tracks { TrackEntry { TrackType, CodecID, Language } }`
Uint8List buildTracks({
  required int trackType,
  required String codecId,
  required String language,
}) {
  final codec = codecId.codeUnits;
  final lang = language.codeUnits;

  final entry = <int>[
    0x83, 0x81, trackType, // TrackType
    0x86, 0x80 | codec.length, ...codec, // CodecID
    0x22, 0xB5, 0x9C, 0x80 | lang.length, ...lang, // Language
  ];

  final tracksBody = <int>[
    0xAE, 0x80 | entry.length, ...entry, // TrackEntry
  ];

  return Uint8List.fromList([
    0x16, 0x54, 0xAE, 0x6B, // Tracks
    0x80 | tracksBody.length,
    ...tracksBody,
  ]);
}

void main() {
  group('parseMkvTracks', () {
    test('解析中文字幕文本轨', () {
      final result = parseMkvTracks(
        buildTracks(trackType: 17, codecId: 'S_TEXT/UTF8', language: 'chi'),
      );

      expect(result.foundTracksElement, isTrue);
      expect(result.tracks, hasLength(1));
      final track = result.tracks.first;
      expect(track.isSubtitle, isTrue);
      expect(track.isTextSubtitle, isTrue);
      expect(track.isChinese, isTrue);
      expect(result.hasChineseSubtitle, isTrue);
    });

    test('PGS 图形字幕不算文本轨但仍属中文', () {
      final result = parseMkvTracks(
        buildTracks(trackType: 17, codecId: 'S_HDMV/PGS', language: 'zho'),
      );

      final track = result.tracks.first;
      expect(track.isSubtitle, isTrue);
      expect(track.isTextSubtitle, isFalse, reason: 'PGS 取不到文本');
      expect(track.isChinese, isTrue);
    });

    test('英文字幕轨不是中文', () {
      final result = parseMkvTracks(
        buildTracks(trackType: 17, codecId: 'S_TEXT/UTF8', language: 'eng'),
      );

      expect(result.tracks.first.isSubtitle, isTrue);
      expect(result.tracks.first.isChinese, isFalse);
      expect(result.hasChineseSubtitle, isFalse);
    });

    test('IETF 标签 zh-Hans 算中文', () {
      final result = parseMkvTracks(
        buildTracks(trackType: 17, codecId: 'S_TEXT/ASS', language: 'zh-Hans'),
      );
      expect(result.tracks.first.isChinese, isTrue);
    });

    test('视频轨不会被当成字幕', () {
      final result = parseMkvTracks(
        buildTracks(trackType: 1, codecId: 'V_MPEG4/ISO/AVC', language: 'und'),
      );
      expect(result.tracks.first.isSubtitle, isFalse);
      expect(result.subtitleTracks, isEmpty);
    });

    test('没有 Tracks 元素时返回未找到', () {
      final result = parseMkvTracks(Uint8List.fromList(List.filled(64, 0x11)));
      expect(result.foundTracksElement, isFalse);
      expect(result.tracks, isEmpty);
    });

    test('数据被截断时不抛异常', () {
      final full = buildTracks(
        trackType: 17,
        codecId: 'S_TEXT/UTF8',
        language: 'chi',
      );
      final truncated = full.sublist(0, full.length - 4);
      expect(() => parseMkvTracks(truncated), returnsNormally);
    });

    test('空字节不崩', () {
      expect(() => parseMkvTracks(Uint8List(0)), returnsNormally);
    });
  });
}
