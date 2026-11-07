import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/subtitle_file_policy.dart';
import 'package:movie_app/pages/detail/playback/subtitle_simplified_policy.dart'
    show ChineseVariant;

void main() {
  TorrentSubtitleCandidate file(
    int index,
    String name, [
    int size = 340 * 1024,
  ]) =>
      TorrentSubtitleCandidate(index: index, name: name, size: size);

  group('种子内字幕文件识别', () {
    test('sc.ass 判简体且是字幕文件', () {
      expect(isSubtitleFileName('[SUB] Movie.sc.ass'), isTrue);
      expect(
        subtitleFileVariant('[SUB] Movie.sc.ass'),
        ChineseVariant.simplified,
      );
    });

    test('tc.ass 判繁体，不冒充简体', () {
      expect(
        subtitleFileVariant('[SUB] Movie.tc.ass'),
        ChineseVariant.traditional,
      );
      expect(
        subtitleFileVariant('[SUB] Movie.tc.ass'),
        isNot(ChineseVariant.simplified),
      );
    });

    test('BIG5 与 cht 都判繁体', () {
      expect(subtitleFileVariant('Movie.BIG5.srt'), ChineseVariant.traditional);
      expect(subtitleFileVariant('Movie.cht.srt'), ChineseVariant.traditional);
    });

    test('screen.srt 不因含 sc 被误判成简体', () {
      expect(subtitleFileVariant('screen.srt'), ChineseVariant.notChinese);
    });

    test('简繁英双语按简体优先', () {
      expect(
        subtitleFileVariant('[简繁英双语外挂] Movie.ass'),
        ChineseVariant.simplified,
      );
    });

    test('zh / chinese 归中文未分简繁', () {
      expect(subtitleFileVariant('Movie.zh.srt'), ChineseVariant.neutral);
      expect(subtitleFileVariant('Movie.chinese.srt'), ChineseVariant.neutral);
    });

    test('真实扩展名保留 ASS，不退化成 SRT', () {
      expect(subtitleFileExtension('[SUB] Movie.sc.ass'), '.ass');
      expect(subtitleFileExtension('Movie.ssa'), '.ssa');
      expect(subtitleFileExtension('Movie.vtt'), '.vtt');
      expect(subtitleFileExtension('Movie.unknown'), '.srt');
    });
  });

  group('挑选要挂载的中文字幕', () {
    test('只有简繁外挂时挑简体那条', () {
      final pick = pickChineseSubtitleFile(<TorrentSubtitleCandidate>[
        file(3, '[SUB] Movie.tc.ass'),
        file(4, '[SUB] Movie.sc.ass'),
      ]);
      expect(pick, isNotNull);
      expect(pick!.index, 4);
      expect(pick.name, contains('.sc.ass'));
    });

    test('简体 > 中文未分 > 繁体', () {
      final pick = pickChineseSubtitleFile(<TorrentSubtitleCandidate>[
        file(1, 'Movie.tc.ass'),
        file(2, 'Movie.zh.srt'),
        file(3, 'Movie.sc.ass'),
      ]);
      expect(pick!.index, 3);
    });

    test('同权重挑体积小的，减少起播后带宽占用', () {
      final pick = pickChineseSubtitleFile(<TorrentSubtitleCandidate>[
        file(1, 'A.sc.ass', 900 * 1024),
        file(2, 'B.sc.ass', 120 * 1024),
      ]);
      expect(pick!.index, 2);
    });

    test('只有英文字幕时不建流', () {
      expect(
        pickChineseSubtitleFile(<TorrentSubtitleCandidate>[
          file(1, 'Movie.en.srt'),
          file(2, 'Movie.eng.ass'),
        ]),
        isNull,
      );
      expect(
        hasChineseSubtitleFile(<TorrentSubtitleCandidate>[file(1, 'Movie.en.srt')]),
        isFalse,
      );
    });

    test('纯视频种子返回 null，不额外建第二个种子', () {
      expect(
        pickChineseSubtitleFile(<TorrentSubtitleCandidate>[
          file(0, 'Movie.mkv', 3 * 1024 * 1024 * 1024),
          file(1, 'Movie.nfo', 2048),
        ]),
        isNull,
      );
    });

    test('超过 16MB 的候选被排除', () {
      expect(
        pickChineseSubtitleFile(<TorrentSubtitleCandidate>[
          file(1, 'Movie.sc.ass', maxTorrentSubtitleBytes + 1),
        ]),
        isNull,
      );
    });

    test('零字节 / 负体积候选被排除', () {
      expect(
        pickChineseSubtitleFile(<TorrentSubtitleCandidate>[
          file(1, 'Movie.sc.ass', 0),
          file(2, 'Movie.sc.ass', -1),
        ]),
        isNull,
      );
    });

    test('空列表返回 null', () {
      expect(pickChineseSubtitleFile(const <TorrentSubtitleCandidate>[]), isNull);
      expect(hasChineseSubtitleFile(const <TorrentSubtitleCandidate>[]), isFalse);
    });

    test('[SUB] 目录前缀不影响判定', () {
      final pick = pickChineseSubtitleFile(<TorrentSubtitleCandidate>[
        file(7, '[SUB]/DBD-Raws/Movie.sc.ass'),
      ]);
      expect(pick!.index, 7);
    });
  });
}
