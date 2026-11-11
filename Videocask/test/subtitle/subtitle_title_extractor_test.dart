import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/subtitle/subtitle_title_extractor.dart';
import 'package:movie_app/services/subtitle/subtitle_track_parser.dart';

void main() {
  group('extractSubtitleTitleQuery', () {
    test('真机 release 名：方括号中英并列组剥出干净片名', () {
      final q = extractSubtitleTitleQuery(
        primary: '[DBD-Raws][流浪地球/The.Wandering.Earth.][1080P][BDRip]'
            '[HEVC-10bit][简体内封][FLAC][MKV]',
      );
      expect(q.local, '流浪地球');
      expect(q.english, 'The Wandering Earth');
      expect(q.isEmpty, isFalse);
    });

    test('常规 release 名：点号分隔 + 年份 + 规格噪声', () {
      final q = extractSubtitleTitleQuery(
        primary: 'The.Wandering.Earth.2019.1080p.BluRay.x264-CHD.mkv',
      );
      expect(q.english, 'The Wandering Earth');
      expect(q.year, '2019');
    });

    test('干净中文片名不被改动', () {
      final q = extractSubtitleTitleQuery(primary: '流浪地球');
      expect(q.local, '流浪地球');
    });

    test('中文片名带年份与括号标签', () {
      final q = extractSubtitleTitleQuery(primary: '流浪地球 (2019) 简体内封');
      expect(q.local, '流浪地球');
      expect(q.year, '2019');
    });

    test('规格标签组不会被当成片名', () {
      final q = extractSubtitleTitleQuery(
        primary: '[1080P][HEVC-10bit][FLAC][MKV]',
      );
      expect(q.local, isEmpty);
      expect(q.english, isEmpty);
    });

    test('种子文件名兜底：主片名只有标签时从 releaseName 取', () {
      final q = extractSubtitleTitleQuery(
        primary: '[简体内封][1080P]',
        releaseName: 'The.Wandering.Earth.2019.1080p.mkv',
      );
      expect(q.english, 'The Wandering Earth');
      expect(q.year, '2019');
    });

    test('分辨率四位数不会被当成上映年份', () {
      final q = extractSubtitleTitleQuery(
        primary: 'Alien.1979.1920x1080.1080p.BluRay.mkv',
      );
      expect(q.year, '1979');
    });

    test('磁力 btih 哈希当片名时忽略，改用 releaseName（2026-11-08 真机）', () {
      // 真机日志：中文=mkv 英文=9a384d... 年份=1911 原始=9a384d...
      // → IMDb tt0230911 → 「在线源无中文字幕」，磁力字幕整条链路断电。
      final q = extractSubtitleTitleQuery(
        primary: '9a384d74548884dc4ae9c4ebe1911c402251135a',
        releaseName: '[DBD-Raws][流浪地球/The.Wandering.Earth.]'
            '[1080P][BDRip][HEVC-10bit][简体内封][FLAC][MKV]',
      );
      expect(q.local, '流浪地球');
      expect(q.english, 'The Wandering Earth');
      expect(q.year, isNull); // 不能从哈希里抽出 1911
    });

    test('纯拉丁残渣不会被当成中文片名', () {
      final q = extractSubtitleTitleQuery(
        primary: '[1080P][MKV][简体内封]',
        releaseName: 'The.Wandering.Earth.2019.1080p.mkv',
      );
      expect(q.local, isEmpty);
      expect(q.english, 'The Wandering Earth');
    });

    test('纯英文 release 名剥掉压制组噪声（2026-11-11 真机 IMDb 三路全 null）',
        () {
      // 修复前清洗成 `Hi Mom Chinese HDRip HC BONE`，IMDb 查不到。
      final q = extractSubtitleTitleQuery(
        primary: 'Hi Mom 2021 720p Chinese HDRip HC H264 BONE',
      );
      expect(q.english, 'Hi Mom');
      expect(q.local, isEmpty);
      expect(q.year, '2021');
    });

    test('第一个技术标签之后整段截断，压制组名不会混进片名', () {
      final q = extractSubtitleTitleQuery(
        primary: 'Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1.Atmos.DV.HDR.mkv',
      );
      expect(q.english, 'Dune Part Two');
      expect(q.year, '2024');
    });

    test('方括号中英并列组不受截断规则影响', () {
      final q = extractSubtitleTitleQuery(
        primary: '[DBD-Raws][流浪地球/The.Wandering.Earth.]'
            '[1080P][BDRip][HEVC-10bit][简体内封][FLAC][MKV]',
        releaseName: 'The.Wandering.Earth.2019.1080p.BluRay.x264.mkv',
      );
      expect(q.local, '流浪地球');
      expect(q.english, 'The Wandering Earth');
    });
  });

  group('externalSubtitleTrackIds', () {
    test('只返回 external=true 的 sub 轨，内封轨与 id=0 一律排除', () {
      const raw = '[{"id":1,"type":"video","selected":true},'
          '{"id":1,"type":"sub","external":false,"selected":true},'
          '{"id":3,"type":"sub","external":true,"selected":true},'
          '{"id":4,"type":"sub","external":true,"selected":false},'
          '{"id":0,"type":"sub","external":true}]';
      expect(externalSubtitleTrackIds(raw), <int>[3, 4]);
    });

    test('空 / 非法输入返回空列表', () {
      expect(externalSubtitleTrackIds(null), isEmpty);
      expect(externalSubtitleTrackIds('not json'), isEmpty);
      expect(externalSubtitleTrackIds('[]'), isEmpty);
    });
  });

  group('describeMpvTracks', () {
    test('逐条输出轨道摘要，字幕轨不会被截断掉', () {
      const raw = '[{"id":1,"type":"video","selected":true},'
          '{"id":1,"type":"audio","lang":"zho"},'
          '{"id":1,"type":"sub","lang":"zh","codec":"subrip",'
          '"selected":false,"external":false}]';
      final lines = describeMpvTracks(raw);
      expect(lines.length, 3);
      expect(lines[2], contains('type=sub'));
      expect(lines[2], contains('lang=zh'));
      expect(lines[2], contains('codec=subrip'));
    });

    test('非法输入不抛异常', () {
      expect(describeMpvTracks(null), const <String>['<empty>']);
      expect(describeMpvTracks('not json'), const <String>['<非 JSON>']);
      expect(describeMpvTracks('{}'), const <String>['<非数组>']);
      expect(describeMpvTracks('[]'), const <String>['<无轨道>']);
    });
  });
}
