import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/magnet_audio_language_policy.dart';

void main() {
  group('磁力音轨语言判定：中文标记', () {
    test('国语中字判国语，且不被「中字」字幕标记带偏', () {
      final r = detectMagnetAudioLanguage(
        '[DBD-Raws][流浪地球][1080P][BDRip][国语中字][FLAC]',
      );
      expect(r.language, MagnetAudioLanguage.mandarin);
      expect(audioLanguageLabel(r.language), '国语');
    });

    test('粤语单独判粤语', () {
      expect(
        detectMagnetAudioLanguage('[粤语中字][1080P]').language,
        MagnetAudioLanguage.cantonese,
      );
    });

    test('国粤双语判国粤双语', () {
      final r = detectMagnetAudioLanguage('[国粤双语][内封]');
      expect(r.language, MagnetAudioLanguage.chineseBilingual);
      expect(audioLanguageLabel(r.language), '国粤双语');
    });

    test('CHINESE 标记的英文发布名判中文原声', () {
      expect(
        detectMagnetAudioLanguage(
          'The.Wandering.Earth.2019.CHINESE.1080p.BluRay.x264.DTS-FGT.mkv',
        ).language,
        MagnetAudioLanguage.chinese,
      );
    });

    test('中文配音不会被「中文」通用词重复计成两种语言', () {
      expect(
        detectMagnetAudioLanguage('[中文配音][1080P]').language,
        MagnetAudioLanguage.mandarin,
      );
    });
  });

  group('字幕语言不等于音轨语言', () {
    test('Sub Rus Zho Eng 是字幕，Original Zho 才是中文原声', () {
      final r = detectMagnetAudioLanguage(
        'Sub Rus Zho Eng + Original Zho',
      );
      expect(r.language, MagnetAudioLanguage.chinese);
      expect(audioLanguageTooltip(r), contains('Original 中文原声'));
      expect(audioLanguageTooltip(r), isNot(contains('俄语')));
    });

    test('字幕语言是英语而原声是中文时，不能报英语', () {
      expect(
        detectMagnetAudioLanguage('Sub Eng Chi + Original Zho').language,
        MagnetAudioLanguage.chinese,
      );
    });

    test('只有简体内封时语言未知：不能把字幕当音轨', () {
      final r = detectMagnetAudioLanguage(
        '[DBD-Raws][4K_HDR][流浪地球2][简体内封][FLAC][MKV]',
      );
      expect(r.isKnown, isFalse);
      expect(audioLanguageLabel(r.language), '语言未知');
      expect(audioLanguageTooltip(r), contains('不等于没有中文音轨'));
    });

    test('CHS_ENG 双语字幕先整体剥离，不残留 _eng 误判英语', () {
      // 早期版本先删 chs 会留下 _eng，被当成英语音轨。
      expect(
        detectMagnetAudioLanguage('[CHS_ENG][双语字幕][1080P]').language,
        MagnetAudioLanguage.unknown,
      );
    });

    test('字幕文件名不参与音轨判定', () {
      final r = detectMagnetAudioLanguage(
        '',
        fileNames: const ['2_English.srt', 'chs.ass'],
      );
      expect(r.language, MagnetAudioLanguage.unknown);
    });
  });

  group('外语与多语', () {
    test('eng sub ita eng ac3 判英语', () {
      expect(
        detectMagnetAudioLanguage(
          'The Wandering Earth (2019) 1080p x265 eng sub ita eng ac3',
        ).language,
        MagnetAudioLanguage.english,
      );
    });

    test('Original Eng 判英语', () {
      expect(
        detectMagnetAudioLanguage('Sub Rus Zho + Original Eng').language,
        MagnetAudioLanguage.english,
      );
    });

    test('日语 / 韩语 / 俄语', () {
      expect(
        detectMagnetAudioLanguage('[日语中字]').language,
        MagnetAudioLanguage.japanese,
      );
      expect(
        detectMagnetAudioLanguage('Korean 1080p').language,
        MagnetAudioLanguage.korean,
      );
      expect(
        detectMagnetAudioLanguage('MVO Rus 720p').language,
        MagnetAudioLanguage.russian,
      );
    });

    test('Dual.Audio 判多语音轨', () {
      expect(
        detectMagnetAudioLanguage(
          'The.Wandering.Earth.2019.1080p.Dual.Audio.NF.WEB-DL.x264.mkv',
        ).language,
        MagnetAudioLanguage.multilingual,
      );
    });

    test('真机 Torrentio 标题：原声中文 + 多种配音轨判多语音轨', () {
      final r = detectMagnetAudioLanguage(
        'Блуждающая Земля [2019 BDRip 1080p] '
        'MVO + DVO + AVO + MVO Ukr + Sub Rus Zho Eng + Original Zho',
      );
      expect(r.language, MagnetAudioLanguage.multilingual);
      expect(r.hits.join('、'), contains('Original 中文原声'));
    });

    test('DUBBED 没写语种时仍是未知，不反推语言', () {
      expect(
        detectMagnetAudioLanguage(
          'The.Wandering.Earth.2019.DUBBED.1080p.WEB.x265.6CH-LUMI.mp4',
        ).language,
        MagnetAudioLanguage.unknown,
      );
    });
  });

  group('误命中与兜底', () {
    test('chill / zhone 里的 chi / zho 不算中文语言码', () {
      expect(
        detectMagnetAudioLanguage('The.Chill.Zhone.2019.1080p.mkv').language,
        MagnetAudioLanguage.unknown,
      );
    });

    test('纯英文标题无语言标记时诚实显示未知', () {
      expect(
        detectMagnetAudioLanguage(
          'The.Wandering.Earth.2019.720p.WEBRip.x264-[YTS.AM].mp4',
        ).language,
        MagnetAudioLanguage.unknown,
      );
    });

    test('空标题与空文件名返回未知', () {
      expect(
        detectMagnetAudioLanguage(null).language,
        MagnetAudioLanguage.unknown,
      );
      expect(
        detectMagnetAudioLanguage('   ').language,
        MagnetAudioLanguage.unknown,
      );
    });

    test('标题没线索时可用音轨文件名兜底，并标明依据', () {
      final r = detectMagnetAudioLanguage(
        '',
        fileNames: const ['audio_zho.mka', 'movie.mkv'],
      );
      expect(r.language, MagnetAudioLanguage.chinese);
      expect(r.evidence, AudioLanguageEvidence.fileName);
      expect(audioLanguageTooltip(r), contains('种子内文件名'));
    });

    test('标题优先于文件名', () {
      final r = detectMagnetAudioLanguage(
        '[国语]',
        fileNames: const ['audio_eng.mka'],
      );
      expect(r.language, MagnetAudioLanguage.mandarin);
      expect(r.evidence, AudioLanguageEvidence.titleMark);
    });
  });
}
