import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/subtitle_decision_policy.dart';
import 'package:movie_app/pages/detail/playback/subtitle_language_policy.dart';
import 'package:movie_app/services/subtitle/subtitle_contract.dart';
import 'package:movie_app/services/subtitle/subtitle_track_parser.dart';

void main() {
  group('mpv track-list 解析（防御性）', () {
    test('只取 sub 轨，过滤 id=0 与视频/音轨', () {
      const raw =
          '[{"type":"video","id":1},{"type":"sub","id":2,"lang":"chi","codec":"ass"},'
          '{"type":"sub","id":3,"lang":"eng"},{"type":"sub","id":0}]';
      final tracks = parseMpvSubtitleTracks(raw);
      expect(tracks.length, 2);
      expect(tracks.first.id, 2);
      expect(tracks.first.lang, 'chi');
      expect(tracks.first.codec, 'ass');
      expect(tracks.last.id, 3);
    });

    test('空 / 非 JSON / 结构畸形一律返回空列表，不抛异常', () {
      expect(parseMpvSubtitleTracks(null), isEmpty);
      expect(parseMpvSubtitleTracks(''), isEmpty);
      expect(parseMpvSubtitleTracks('not json'), isEmpty);
      expect(parseMpvSubtitleTracks('{"type":"sub"}'), isEmpty);
      expect(parseMpvSubtitleTracks('[null, 3, "x"]'), isEmpty);
    });

    test('external 轨标记为本地来源，内封轨为 embedded', () {
      final tracks = parseMpvSubtitleTracks(
        '[{"type":"sub","id":1,"external":false},'
        '{"type":"sub","id":2,"external":true}]',
      );
      expect(tracks.first.source, SubtitleTrackSource.embedded);
      expect(tracks.last.source, SubtitleTrackSource.local);
      expect(tracks.last.isExternal, isTrue);
    });
  });

  group('语言判定（压制组写法不规范的兜底）', () {
    test('常见中文码都识别为中文', () {
      for (final code in ['zh', 'zh-CN', 'zho', 'chi', 'CHS', 'zh-tw']) {
        expect(classifySubtitleLanguage(code), SubtitleLanguage.chinese,
            reason: '$code 应判为中文');
      }
    });

    test('lang 缺失时靠轨标题识别中文 / 双语', () {
      expect(
        classifySubtitleLanguage(null, title: '简体中文'),
        SubtitleLanguage.chinese,
      );
      expect(classifySubtitleLanguage('', title: 'Chs & Eng 双语'),
          SubtitleLanguage.chinese);
      expect(classifySubtitleLanguage(null, title: 'English SDH'),
          SubtitleLanguage.english);
    });

    test('全空为 unknown，无法识别的非空码为 other', () {
      expect(classifySubtitleLanguage(null), SubtitleLanguage.unknown);
      expect(classifySubtitleLanguage('ja'), SubtitleLanguage.other);
    });
  });

  group('默认中文优先决策（摘掉策略即红）', () {
    const zhInternal = SubtitleTrackInfo(id: 2, lang: 'chi', codec: 'ass');
    const zhOnline = SubtitleTrackInfo(
      id: 9,
      lang: 'zh-cn',
      source: SubtitleTrackSource.online,
      isExternal: true,
    );
    const enTrack = SubtitleTrackInfo(id: 3, lang: 'eng');

    test('中英双轨 → 只挂中文，不自动开双语', () {
      final d = decideSubtitleTracks(tracks: [enTrack, zhInternal]);
      expect(d.mode, SubtitleDisplayMode.chineseOnly);
      expect(d.primaryId, 2);
      expect(d.secondaryId, isNull);
      expect(d.needOnlineChinese, isFalse);
    });

    test('内封中文优先于在线中文（来源排序生效）', () {
      final d = decideSubtitleTracks(tracks: [zhOnline, zhInternal]);
      expect(d.primaryId, 2);
    });

    test('本地只有英文、Web 必须双语 → bilingual 且继续找中文', () {
      final d = decideSubtitleTracks(
        tracks: [enTrack],
        webBilingualRequired: true,
      );
      expect(d.mode, SubtitleDisplayMode.bilingual);
      expect(d.primaryId, 3);
      expect(d.needOnlineChinese, isTrue);
    });

    test('Native 默认：只有英文时先挂英文，不自动双语', () {
      final d = decideSubtitleTracks(tracks: [enTrack]);
      expect(d.mode, SubtitleDisplayMode.englishOnly);
      expect(d.needOnlineChinese, isTrue);
    });

    test('在线中文挂载成功后覆盖英文轨', () {
      final d = decideSubtitleTracks(
        tracks: [enTrack],
        onlineChineseTrackId: 9,
      );
      expect(d.mode, SubtitleDisplayMode.chineseOnly);
      expect(d.primaryId, 9);
      expect(d.needOnlineChinese, isFalse);
    });

    test('没有任何轨 → none 且提示继续在线匹配', () {
      final d = decideSubtitleTracks(tracks: const []);
      expect(d.mode, SubtitleDisplayMode.none);
      expect(d.primaryId, isNull);
      expect(d.needOnlineChinese, isTrue);
      expect(d.reason, isNotEmpty);
    });
  });
}
