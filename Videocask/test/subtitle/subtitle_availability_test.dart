import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/subtitle_availability_policy.dart';
import 'package:movie_app/pages/detail/playback/subtitle_simplified_policy.dart';
import 'package:movie_app/services/subtitle/subtitle_contract.dart';

void main() {
  group('磁力标题字幕形态判定', () {
    test('简体内封能识别', () {
      final v = detectMagnetSubtitle(
        '[DBD-Raws][流浪地球][1080P][BDRip][简体内封][FLAC][MKV]',
      );
      expect(v, MagnetSubtitleAvailability.simplifiedEmbedded);
      expect(subtitleAvailabilityLabel(v), '简中内封');
      expect(hasUsableSimplifiedSubtitle(v), isTrue);
    });

    test('简繁英双语外挂按简体优先归到简中外挂', () {
      final v = detectMagnetSubtitle(
        '[DBD-Raws][流浪地球2][国英双语][简繁英双语外挂][FLAC][MKV]',
      );
      expect(v, MagnetSubtitleAvailability.simplifiedExternal);
    });

    test('繁体内封与 BIG5 不冒充简体', () {
      expect(
        detectMagnetSubtitle('[xxx][繁日内封][BIG5][MKV]'),
        MagnetSubtitleAvailability.traditionalEmbedded,
      );
      expect(
        hasUsableSimplifiedSubtitle(
          detectMagnetSubtitle('[J.X&WiKi][BIG5][720p][MP4]'),
        ),
        isFalse,
      );
    });

    test('Multiple Subtitle 归为双语', () {
      expect(
        detectMagnetSubtitle(
          '[NC-Raws] LOST GIRLS [Multiple Subtitle][MKV]',
        ),
        MagnetSubtitleAvailability.bilingual,
      );
    });

    test('国语中字是硬字幕，不是可挂载轨', () {
      final v = detectMagnetSubtitle('流浪地球 2019 电影 国语中字 高清');
      expect(v, MagnetSubtitleAvailability.hardcoded);
      expect(hasUsableSimplifiedSubtitle(v), isFalse);
      expect(hasChineseSubtitleMark(v), isTrue);
    });

    test('无标记返回「未标注字幕」而不是「无字幕」', () {
      final v = detectMagnetSubtitle('The.Godfather.1972.1080p.BluRay.x264');
      expect(v, MagnetSubtitleAvailability.notMarked);
      expect(subtitleAvailabilityLabel(v), '未标注字幕');
      expect(hasChineseSubtitleMark(v), isFalse);
    });

    test('标题写 Zho/Chi 语言码 → 有中文字幕（不指定简繁）', () {
      // Torrentio 上真实存在的发布名。
      const title = 'Блуждающая Земля / The Wandering Earth [2019 BDRip 1080p] '
          'MVO + DVO + Sub Rus Zho Eng + Original Zho';
      final v = detectMagnetSubtitle(title);
      expect(v, MagnetSubtitleAvailability.chineseUnspecified);
      expect(subtitleAvailabilityLabel(v), '有中文字幕');
      expect(hasChineseSubtitleMark(v), isTrue);
    });

    test('chill/zhone 之类不会被误当成 zho/chi', () {
      expect(
        detectMagnetSubtitle('Chill.Out.2020.1080p.WEB-DL'),
        MagnetSubtitleAvailability.notMarked,
      );
      expect(
        detectMagnetSubtitle('Zhone.Test.2019.1080p'),
        MagnetSubtitleAvailability.notMarked,
      );
    });

    test('空标题不抛异常', () {
      expect(detectMagnetSubtitle(null), MagnetSubtitleAvailability.notMarked);
      expect(detectMagnetSubtitle('  '), MagnetSubtitleAvailability.notMarked);
    });
  });

  group('简体中文优先', () {
    test('语言码与文件名能区分简繁', () {
      expect(
        classifyChineseVariant(lang: 'zh-cn', title: ''),
        ChineseVariant.simplified,
      );
      expect(
        classifyChineseVariant(lang: 'zht', title: ''),
        ChineseVariant.traditional,
      );
      expect(
        classifyChineseVariant(lang: 'chi', fileName: 'movie.sc.ass'),
        ChineseVariant.simplified,
      );
      expect(
        classifyChineseVariant(lang: 'chi', fileName: 'movie.tc.ass'),
        ChineseVariant.traditional,
      );
      expect(
        classifyChineseVariant(lang: 'chi'),
        ChineseVariant.neutral,
      );
      expect(
        classifyChineseVariant(lang: 'eng'),
        ChineseVariant.notChinese,
      );
    });

    test('中文轨排序时简体在前、繁体在后', () {
      const traditional = SubtitleTrackInfo(id: 1, lang: 'zht');
      const simplified = SubtitleTrackInfo(id: 2, lang: 'zh-cn');
      const neutral = SubtitleTrackInfo(id: 3, lang: 'chi');
      final sorted = sortChineseTracksSimplifiedFirst(
        const <SubtitleTrackInfo>[traditional, simplified, neutral],
      );
      expect(sorted.map((t) => t.id).toList(), <int>[2, 3, 1]);
    });

    test('排序稳定：同级别保持原顺序', () {
      const a = SubtitleTrackInfo(id: 7, lang: 'zh-cn');
      const b = SubtitleTrackInfo(id: 8, lang: 'chs');
      expect(
        sortChineseTracksSimplifiedFirst(const <SubtitleTrackInfo>[a, b])
            .map((t) => t.id)
            .toList(),
        <int>[7, 8],
      );
    });
  });

  group('繁→简轻量转换', () {
    test('典型繁体字幕句转成简体', () {
      expect(traditionalToSimplified('我父親是個農民'), '我父亲是个农民');
      expect(traditionalToSimplified('那時候的人差不多都是農民'), '那时候的人差不多都是农民');
      expect(traditionalToSimplified('穿越直道？'), '穿越直道？');
      expect(traditionalToSimplified('當然他不是一開始就是'), '当然他不是一开始就是');
    });

    test('不破坏 SRT 时间轴与已是简体的内容', () {
      const cue = '00:01:21,700 --> 00:01:23,190';
      expect(traditionalToSimplified(cue), cue);
      expect(traditionalToSimplified('我能行'), '我能行');
      expect(traditionalToSimplified(''), '');
    });

    test('繁简同形字与表外字保持原样', () {
      expect(traditionalToSimplified('角度太大了'), '角度太大了');
      expect(traditionalToSimplified('関1'), '関1');
    });
  });
}
