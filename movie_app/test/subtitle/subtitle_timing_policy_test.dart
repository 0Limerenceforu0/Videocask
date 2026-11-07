import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/subtitle_timing_policy.dart';

void main() {
  group('帧率归一', () {
    test('23.976023 必须归到 23.976，不能被容差吞成 24', () {
      // 摘掉 0.012 的小容差、改成 0.05 就会误判成 24。
      expect(
        normalizeFrameRate('23.976023'),
        VideoFrameRate.fps23976,
      );
      expect(normalizeFrameRate('23.976'), VideoFrameRate.fps23976);
    });

    test('29.970030 必须归到 29.97，不能被吞成 30', () {
      expect(normalizeFrameRate('29.970030'), VideoFrameRate.fps2997);
      expect(normalizeFrameRate('29.97'), VideoFrameRate.fps2997);
    });

    test('59.94 与 60 能区分', () {
      expect(normalizeFrameRate('59.940060'), VideoFrameRate.fps5994);
      expect(normalizeFrameRate('60.0'), VideoFrameRate.fps60);
    });

    test('整数帧率各自归位', () {
      expect(normalizeFrameRate('24'), VideoFrameRate.fps24);
      expect(normalizeFrameRate('25'), VideoFrameRate.fps25);
      expect(normalizeFrameRate('30'), VideoFrameRate.fps30);
      expect(normalizeFrameRate('50'), VideoFrameRate.fps50);
    });

    test('非法 / 空 / 越界值返回 unknown，不猜', () {
      expect(normalizeFrameRate(null), VideoFrameRate.unknown);
      expect(normalizeFrameRate(''), VideoFrameRate.unknown);
      expect(normalizeFrameRate('abc'), VideoFrameRate.unknown);
      expect(normalizeFrameRate('0'), VideoFrameRate.unknown);
      expect(normalizeFrameRate('-24'), VideoFrameRate.unknown);
      expect(normalizeFrameRate('999'), VideoFrameRate.unknown);
      // 非标称帧率（如 27.5）也不能强行贴到 25 或 30。
      expect(normalizeFrameRate('27.5'), VideoFrameRate.unknown);
    });

    test('resolvePlaybackFrameRate 优先 container-fps', () {
      expect(
        resolvePlaybackFrameRate(
          containerFps: '25.000',
          estimatedVfFps: '60.0',
        ),
        VideoFrameRate.fps25,
      );
    });

    test('container 缺失时用 estimated-vf-fps 兜底；两者都无则 unknown', () {
      expect(
        resolvePlaybackFrameRate(
          containerFps: null,
          estimatedVfFps: '23.976023',
        ),
        VideoFrameRate.fps23976,
      );
      expect(
        resolvePlaybackFrameRate(containerFps: '', estimatedVfFps: 'garbage'),
        VideoFrameRate.unknown,
      );
    });
  });

  group('字幕基准帧率标记识别', () {
    test('明确写出 25fps / PAL 才认 25', () {
      expect(
        detectSubtitleBaseFrameRate('Movie.2019.1080p.25fps.srt'),
        VideoFrameRate.fps25,
      );
      expect(
        detectSubtitleBaseFrameRate('Movie.PAL.DVDRip.ass'),
        VideoFrameRate.fps25,
      );
    });

    test('23.976 / NTSC 归到 23976', () {
      expect(
        detectSubtitleBaseFrameRate('Movie.23.976fps.chs.srt'),
        VideoFrameRate.fps23976,
      );
      expect(
        detectSubtitleBaseFrameRate('Movie.NTSC.ass'),
        VideoFrameRate.fps23976,
      );
    });

    test('孤立数字不能被误读成帧率（S01E25 / 1080p / x264）', () {
      // 若用 contains('25') 就会把剧集号、分辨率当帧率，进而改坏时间轴。
      expect(
        detectSubtitleBaseFrameRate('Show.S01E25.1080p.x264.chs.srt'),
        isNull,
      );
      expect(detectSubtitleBaseFrameRate('Movie.2019.720p.srt'), isNull);
      expect(detectSubtitleBaseFrameRate(null), isNull);
      expect(detectSubtitleBaseFrameRate(''), isNull);
    });
  });

  group('sub-speed 漂移', () {
    test('23.976 视频配 25fps 字幕 → 0.95904', () {
      expect(
        computeSubSpeed(
          video: VideoFrameRate.fps23976,
          subtitleBase: VideoFrameRate.fps25,
        ),
        closeTo(0.95904, 0.00001),
      );
    });

    test('25fps 视频配 23.976 字幕 → 真实比值 1.04271', () {
      // 方案文档 S4 写的是「1.0417 倍」，那其实是 25/24 的值；
      // 25/(24000/1001) = 25025/24000 = 1.042708…，以精确帧率为准。
      expect(
        computeSubSpeed(
          video: VideoFrameRate.fps25,
          subtitleBase: VideoFrameRate.fps23976,
        ),
        closeTo(1.04271, 0.00001),
      );
      // 反向（23.976 视频 + 25fps 字幕）同理是 0.95904，不是 1/1.0417。
      expect(
        computeSubSpeed(
          video: VideoFrameRate.fps23976,
          subtitleBase: VideoFrameRate.fps25,
        ),
        closeTo(0.95904, 0.00001),
      );
    });

    test('24 与 25 也在 PAL 转换对里', () {
      expect(
        computeSubSpeed(
          video: VideoFrameRate.fps25,
          subtitleBase: VideoFrameRate.fps24,
        ),
        closeTo(1.04167, 0.00001),
      );
    });

    test('同帧率返回 1.0（无需设置）', () {
      expect(
        computeSubSpeed(
          video: VideoFrameRate.fps25,
          subtitleBase: VideoFrameRate.fps25,
        ),
        1.0,
      );
    });

    test('证据不足或无关组合一律 null，绝不乱调', () {
      expect(
        computeSubSpeed(video: VideoFrameRate.fps25, subtitleBase: null),
        isNull,
      );
      expect(
        computeSubSpeed(
          video: VideoFrameRate.unknown,
          subtitleBase: VideoFrameRate.fps25,
        ),
        isNull,
      );
      // 30 ↔ 25 不是 PAL/电影帧转换，不能套用 1.0417。
      expect(
        computeSubSpeed(
          video: VideoFrameRate.fps30,
          subtitleBase: VideoFrameRate.fps25,
        ),
        isNull,
      );
    });
  });

  group('cue 解析', () {
    test('SRT 逗号毫秒', () {
      final r = parseSubtitleCueRange(
        '1\n'
        '00:00:02,500 --> 00:00:05,000\n'
        '第一句\n\n'
        '2\n'
        '01:30:10,120 --> 01:30:13,000\n'
        '最后一句\n',
      );
      expect(r.cueCount, 2);
      expect(r.firstCueSeconds, closeTo(2.5, 0.001));
      expect(r.lastCueSeconds, closeTo(5413.0, 0.001));
      expect(r.isValid, isTrue);
    });

    test('VTT 点号毫秒 + WEBVTT 头', () {
      final r = parseSubtitleCueRange(
        'WEBVTT\n\n'
        '00:00:01.000 --> 00:00:03.500\n'
        'hi\n\n'
        '00:01:00.000 --> 00:01:02.000\n'
        'bye\n',
      );
      expect(r.cueCount, 2);
      expect(r.firstCueSeconds, closeTo(1.0, 0.001));
      expect(r.lastCueSeconds, closeTo(62.0, 0.001));
    });

    test('ASS Dialogue 的百分秒', () {
      final r = parseSubtitleCueRange(
        '[Events]\n'
        'Dialogue: 0,0:00:02.50,0:00:05.00,Default,,0,0,0,,第一句\n'
        'Dialogue: 0,1:30:10.12,1:30:13.00,Default,,0,0,0,,末句\n',
      );
      expect(r.cueCount, 2);
      expect(r.firstCueSeconds, closeTo(2.5, 0.001));
      expect(r.lastCueSeconds, closeTo(5413.0, 0.001));
    });

    test('空文本 / 无时间轴 / 单行不产生可用范围', () {
      expect(parseSubtitleCueRange('').cueCount, 0);
      expect(parseSubtitleCueRange('随便一行文字').cueCount, 0);
      final one = parseSubtitleCueRange('00:00:01,000 --> 00:00:02,000\nA');
      expect(one.cueCount, 1);
      expect(one.isValid, isFalse);
    });

    test('时间轴倒序的坏 cue 不参与统计', () {
      final r = parseSubtitleCueRange(
        '1\n00:00:09,000 --> 00:00:02,000\n坏数据\n',
      );
      expect(r.cueCount, 0);
    });
  });

  group('匹配判定', () {
    SubtitleCueRange range(double first, double last) => SubtitleCueRange(
          firstCueSeconds: first,
          lastCueSeconds: last,
          cueCount: 12,
        );

    test('90 分钟片长配 88 分钟字幕 → matched', () {
      expect(
        judgeSubtitleMatch(
          range: range(5, 5285),
          videoDurationSeconds: 5400,
        ),
        SubtitleMatchVerdict.matched,
      );
    });

    test('字幕只有片长的一小截 → mismatched', () {
      // 摘掉 0.7 下界就会把错版本字幕当成匹配。
      expect(
        judgeSubtitleMatch(
          range: range(5, 1205),
          videoDurationSeconds: 5400,
        ),
        SubtitleMatchVerdict.mismatched,
      );
    });

    test('字幕比片长长太多 → mismatched', () {
      expect(
        judgeSubtitleMatch(
          range: range(5, 8000),
          videoDurationSeconds: 5400,
        ),
        SubtitleMatchVerdict.mismatched,
      );
    });

    test('首 cue 晚于片长 1/4 → mismatched', () {
      expect(
        judgeSubtitleMatch(
          range: range(2000, 5300),
          videoDurationSeconds: 5400,
        ),
        SubtitleMatchVerdict.mismatched,
      );
    });

    test('片长未知 / cue 不足 → uncertain，不提示不调整', () {
      expect(
        judgeSubtitleMatch(
          range: range(5, 5285),
          videoDurationSeconds: 0,
        ),
        SubtitleMatchVerdict.uncertain,
      );
      expect(
        judgeSubtitleMatch(
          range: SubtitleCueRange.empty,
          videoDurationSeconds: 5400,
        ),
        SubtitleMatchVerdict.uncertain,
      );
    });

    test('可选音轨活动起点：偏差 > 8s 判不匹配，接近则仍 matched', () {
      expect(
        judgeSubtitleMatch(
          range: range(20, 5285),
          videoDurationSeconds: 5400,
          firstAudioActivitySeconds: 2,
        ),
        SubtitleMatchVerdict.mismatched,
      );
      expect(
        judgeSubtitleMatch(
          range: range(5, 5285),
          videoDurationSeconds: 5400,
          firstAudioActivitySeconds: 6,
        ),
        SubtitleMatchVerdict.matched,
      );
    });
  });

  group('文案与标签', () {
    test('帧率标签用于诊断日志', () {
      expect(VideoFrameRate.fps23976.label, '23.976');
      expect(VideoFrameRate.fps2997.label, '29.97');
      expect(VideoFrameRate.unknown.label, '未知');
      expect(subtitleMismatchHint, contains('换一个字幕'));
    });
  });
}
