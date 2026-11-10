import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/subtitle_probe/mkv_track_parser.dart';
import 'package:movie_app/services/subtitle_probe/subtitle_probe_verdict.dart';

MkvTrackParseResult tracksOf(List<MkvTrack> list) =>
    MkvTrackParseResult(tracks: list, foundTracksElement: true);

MkvTrack sub({required String lang, String codec = 'S_TEXT/UTF8'}) =>
    MkvTrack(number: 3, type: 17, codecId: codec, language: lang);

void main() {
  group('judgeSubtitle - 外挂字幕文件', () {
    test('带简中 srt → 有中文文本字幕', () {
      final r = judgeSubtitle(
        files: const [
          ProbeFile(path: 'Movie.2019.1080p.mkv', size: 2000000000),
          ProbeFile(path: 'Movie.2019.chs.srt', size: 80000),
        ],
      );
      expect(r.verdict, SubtitleProbeVerdict.chineseText);
      expect(r.isExternal, isTrue);
      expect(r.isSimplified, isTrue);
      expect(r.reason, contains('外挂'));
    });

    test('只有繁中 ass → 繁体', () {
      final r = judgeSubtitle(
        files: const [
          ProbeFile(path: 'Movie.mkv', size: 100),
          ProbeFile(path: 'Movie.cht.ass', size: 100),
        ],
      );
      expect(r.verdict, SubtitleProbeVerdict.chineseText);
      expect(r.isTraditional, isTrue);
    });

    test('只有 sup 图形字幕 → 中文图形字幕', () {
      final r = judgeSubtitle(
        files: const [
          ProbeFile(path: 'Movie.mkv', size: 100),
          ProbeFile(path: 'Movie.cht.sup', size: 100),
        ],
      );
      expect(r.verdict, SubtitleProbeVerdict.chineseImage);
    });

    test('外挂字幕但文件名没标语言 → 未知，不能判成中文', () {
      final r = judgeSubtitle(
        files: const [
          ProbeFile(path: 'Movie.mkv', size: 100),
          ProbeFile(path: 'Movie.srt', size: 100),
        ],
      );
      expect(
        r.verdict,
        SubtitleProbeVerdict.unknown,
        reason: '英文/俄文 srt 也存在，没标记就不能断言是中文',
      );
      expect(r.isExternal, isTrue);
      expect(r.reason, contains('语言未标注'));
    });

    test('片名里的 sc/tc 不会被误当成简繁标记', () {
      final r = judgeSubtitle(
        files: const [
          ProbeFile(path: 'The.Wandering.Earth.2019.mkv', size: 100),
          ProbeFile(path: 'The.Wandering.Earth.2019.srt', size: 100),
        ],
      );
      expect(r.verdict, SubtitleProbeVerdict.unknown);
    });
  });

  group('judgeSubtitle - 内封轨', () {
    test('有中文文本轨 → 有中文文本字幕', () {
      final r = judgeSubtitle(
        files: const [ProbeFile(path: 'Movie.mkv', size: 2000000000)],
        mkvTracks: tracksOf([sub(lang: 'zh-Hans')]),
      );
      expect(r.verdict, SubtitleProbeVerdict.chineseText);
      expect(r.isSimplified, isTrue);
    });

    test('只有英文字幕轨 → 无中文字幕', () {
      final r = judgeSubtitle(
        files: const [ProbeFile(path: 'Movie.mkv', size: 2000000000)],
        mkvTracks: tracksOf([sub(lang: 'eng')]),
      );
      expect(r.verdict, SubtitleProbeVerdict.noChinese);
      expect(r.reason, contains('eng'));
    });

    test('一条字幕轨都没有 → 无中文字幕', () {
      final r = judgeSubtitle(
        files: const [ProbeFile(path: 'Movie.mkv', size: 2000000000)],
        mkvTracks: tracksOf(const []),
      );
      expect(r.verdict, SubtitleProbeVerdict.noChinese);
      expect(r.reason, contains('无字幕轨'));
    });

    test('中文 PGS 轨 → 中文图形字幕，不是文本', () {
      final r = judgeSubtitle(
        files: const [ProbeFile(path: 'Movie.mkv', size: 2000000000)],
        mkvTracks: tracksOf([sub(lang: 'chi', codec: 'S_HDMV/PGS')]),
      );
      expect(r.verdict, SubtitleProbeVerdict.chineseImage);
    });
  });

  group('judgeSubtitle - 未知情形不能瞎猜', () {
    test('文件列表为空 → 未知', () {
      expect(
        judgeSubtitle(files: const []).verdict,
        SubtitleProbeVerdict.unknown,
      );
    });

    test('单视频但没读到文件头 → 未知（不判无字幕）', () {
      final r = judgeSubtitle(
        files: const [ProbeFile(path: 'Movie.mkv', size: 100)],
      );
      expect(r.verdict, SubtitleProbeVerdict.unknown);
      expect(r.reason, contains('未读到文件头'));
    });

    test('多视频文件不做内封判定 → 未知', () {
      final r = judgeSubtitle(
        files: const [
          ProbeFile(path: 'E01.mkv', size: 100),
          ProbeFile(path: 'E02.mkv', size: 100),
        ],
      );
      expect(r.verdict, SubtitleProbeVerdict.unknown);
    });

    test('非视频文件 → 未知', () {
      final r = judgeSubtitle(
        files: const [ProbeFile(path: 'package.zip', size: 100)],
      );
      expect(r.verdict, SubtitleProbeVerdict.unknown);
    });
  });

  group('P0 - 简繁判定漏洞修复', () {
    test('chs / cht 语言码能定简繁（旧版只认 hans/hant）', () {
      expect(classifyChineseScript('chs'), ChineseScript.simplified);
      expect(classifyChineseScript('cht'), ChineseScript.traditional);
      expect(classifyChineseScript('zh-Hans'), ChineseScript.simplified);
      expect(classifyChineseScript('zh-Hant'), ChineseScript.traditional);
    });

    test('TrackName 参与简繁判定', () {
      expect(classifyChineseScript('und 简体中文'), ChineseScript.simplified);
      expect(
        classifyChineseScript('Chinese (Traditional)'),
        ChineseScript.traditional,
      );
      expect(classifyChineseScript('GB 中文'), ChineseScript.simplified);
    });

    test('简繁同时出现 → both', () {
      expect(classifyChineseScript('简繁双语'), ChineseScript.both);
      expect(classifyChineseScript('chs_cht'), ChineseScript.both);
    });

    test('zho / chi / und 不猜简繁', () {
      expect(classifyChineseScript('zho'), ChineseScript.unspecified);
      expect(classifyChineseScript('chi'), ChineseScript.unspecified);
      expect(classifyChineseScript('und'), ChineseScript.unspecified);
    });

    test('sc/tc 必须独立成词才认', () {
      expect(
        classifyChineseScript('The.Wandering.Earth.2019.srt'),
        ChineseScript.unspecified,
      );
      expect(classifyChineseScript('movie.sc.srt'), ChineseScript.simplified);
    });

    test('语言 und 但轨道名写「简体中文」→ 认成中文轨且判简中', () {
      final r = judgeSubtitle(
        files: const [ProbeFile(path: 'Movie.mkv', size: 100)],
        mkvTracks: tracksOf([
          const MkvTrack(
            number: 3,
            type: 17,
            codecId: 'S_TEXT/UTF8',
            language: 'und',
            name: '简体中文',
          ),
        ]),
      );
      expect(r.verdict, SubtitleProbeVerdict.chineseText);
      expect(r.isSimplified, isTrue);
      expect(subtitleVerdictLabel(r), '内封简中');
    });

    test('chs 内封轨 → 内封简中（旧版会降级成「内封中字」）', () {
      final r = judgeSubtitle(
        files: const [ProbeFile(path: 'Movie.mkv', size: 100)],
        mkvTracks: tracksOf([sub(lang: 'chs')]),
      );
      expect(r.verdict, SubtitleProbeVerdict.chineseText);
      expect(r.isSimplified, isTrue);
      expect(subtitleVerdictLabel(r), '内封简中');
    });

    test('PGS 图形字幕也判简繁', () {
      final r = judgeSubtitle(
        files: const [ProbeFile(path: 'Movie.mkv', size: 100)],
        mkvTracks: tracksOf([sub(lang: 'zh-Hant', codec: 'S_HDMV/PGS')]),
      );
      expect(r.verdict, SubtitleProbeVerdict.chineseImage);
      expect(r.isTraditional, isTrue);
      expect(r.reason, contains('PGS'));
    });
  });

  group('P1 - 外挂字幕正文 CJK 实证', () {
    const files = [
      ProbeFile(path: 'Movie.mkv', size: 100),
      ProbeFile(path: 'Movie.srt', size: 100),
    ];

    test('文件名无标记但正文含中文 → 外挂中字（简繁未分）', () {
      final r = judgeSubtitle(files: files, externalTextIsChinese: true);
      expect(r.verdict, SubtitleProbeVerdict.chineseText);
      expect(r.source, SubtitleProbeSource.subtitleText);
      expect(r.isSimplified, isFalse);
      expect(subtitleVerdictLabel(r), '外挂中字');
    });

    test('正文不含中文 → 无中文字幕', () {
      final r = judgeSubtitle(files: files, externalTextIsChinese: false);
      expect(r.verdict, SubtitleProbeVerdict.noChinese);
      expect(r.source, SubtitleProbeSource.subtitleText);
    });

    test('没读到正文 → 保持未知，绝不写成无', () {
      final r = judgeSubtitle(files: files);
      expect(r.verdict, SubtitleProbeVerdict.unknown);
      expect(r.isExternal, isTrue);
    });
  });

  group('tooltip 依据', () {
    test('结论带上「凭什么这么说」', () {
      const r = SubtitleProbeResult(
        verdict: SubtitleProbeVerdict.chineseText,
        reason: '内封 1 条中文字幕轨',
        source: SubtitleProbeSource.mkvTracks,
      );
      expect(subtitleVerdictTooltip(r), contains('依据 MKV 内封轨道'));
      expect(subtitleVerdictTooltip(r), contains('内封 1 条中文字幕轨'));
    });
  });

  group('文案', () {
    test('内封简中', () {
      expect(
        subtitleVerdictLabel(
          const SubtitleProbeResult(
            verdict: SubtitleProbeVerdict.chineseText,
            reason: '',
            isSimplified: true,
          ),
        ),
        '内封简中',
      );
    });

    test('外挂繁中', () {
      expect(
        subtitleVerdictLabel(
          const SubtitleProbeResult(
            verdict: SubtitleProbeVerdict.chineseText,
            reason: '',
            isExternal: true,
            isTraditional: true,
          ),
        ),
        '外挂繁中',
      );
    });

    test('简繁都有要写明', () {
      expect(
        subtitleVerdictLabel(
          const SubtitleProbeResult(
            verdict: SubtitleProbeVerdict.chineseText,
            reason: '',
            isExternal: true,
            isSimplified: true,
            isTraditional: true,
          ),
        ),
        '外挂简繁中',
      );
    });

    test('没判出简繁只能说中字', () {
      expect(
        subtitleVerdictLabel(
          const SubtitleProbeResult(
            verdict: SubtitleProbeVerdict.chineseText,
            reason: '',
          ),
        ),
        '内封中字',
      );
    });

    test('图形字幕要标出来（取不到文本、字号不可调）', () {
      expect(
        subtitleVerdictLabel(
          const SubtitleProbeResult(
            verdict: SubtitleProbeVerdict.chineseImage,
            reason: '',
          ),
        ),
        '内封图形中字',
      );
    });

    test('无字幕必须明确写无', () {
      expect(
        subtitleVerdictLabel(
          const SubtitleProbeResult(
            verdict: SubtitleProbeVerdict.noChinese,
            reason: '',
          ),
        ),
        '无中文字幕',
      );
    });

    test('未知不写成无', () {
      expect(subtitleVerdictLabel(SubtitleProbeResult.unknown), '字幕未知');
    });
  });

  // 🔴 2026-11-08 真机：列表自动探测只读元数据 + 文件清单，
  // 读 MKV 文件头 / 字幕正文是用户点徽标才做的深度层。
  group('快速层 / 深度层', () {
    test('快速层没读头，理由不能写「未读到文件头」', () {
      final r = judgeSubtitle(
        files: const [ProbeFile(path: 'movie.mkv', size: 1000)],
        fileListOnly: true,
      );
      expect(r.verdict, SubtitleProbeVerdict.unknown);
      expect(r.reason, contains('可能有内封轨'));
      expect(r.reason, isNot(contains('未读到文件头')));
    });

    test('快速层多文件种子的理由也只说未确认', () {
      final r = judgeSubtitle(
        files: const [
          ProbeFile(path: 'cd1.mkv', size: 1000),
          ProbeFile(path: 'cd2.mkv', size: 1000),
        ],
        fileListOnly: true,
      );
      expect(r.verdict, SubtitleProbeVerdict.unknown);
      expect(r.reason, contains('未确认内封轨'));
      expect(r.reason, isNot(contains('未读到文件头')));
    });

    test('快速层仍能从文件名直接判出外挂简中', () {
      final r = judgeSubtitle(
        files: const [
          ProbeFile(path: 'movie.mkv', size: 1000),
          ProbeFile(path: 'movie.chs.srt', size: 100),
        ],
        fileListOnly: true,
      );
      expect(r.verdict, SubtitleProbeVerdict.chineseText);
      expect(r.isExternal, isTrue);
      expect(subtitleVerdictLabel(r), '外挂简中');
    });

    test('fast + unknown 才允许深挖', () {
      const r = SubtitleProbeResult(
        verdict: SubtitleProbeVerdict.unknown,
        reason: '',
        depth: SubtitleProbeDepth.fast,
      );
      expect(r.canDeepProbe, isTrue);
    });

    test('明确结论不提供深挖入口', () {
      const r = SubtitleProbeResult(
        verdict: SubtitleProbeVerdict.noChinese,
        reason: '',
        depth: SubtitleProbeDepth.fast,
      );
      expect(r.canDeepProbe, isFalse);
    });

    test('深挖过的结论不再重复提供入口', () {
      const r = SubtitleProbeResult(
        verdict: SubtitleProbeVerdict.unknown,
        reason: '',
        depth: SubtitleProbeDepth.deep,
      );
      expect(r.canDeepProbe, isFalse);
    });

    test('copyWith 只改深度，不改判定', () {
      const r = SubtitleProbeResult(
        verdict: SubtitleProbeVerdict.unknown,
        reason: '种子内未见独立字幕文件',
        isExternal: true,
        source: SubtitleProbeSource.fileList,
      );
      final fast = r.copyWith(depth: SubtitleProbeDepth.fast);
      expect(fast.verdict, r.verdict);
      expect(fast.reason, r.reason);
      expect(fast.isExternal, isTrue);
      expect(fast.source, SubtitleProbeSource.fileList);
      expect(fast.depth, SubtitleProbeDepth.fast);
      expect(fast.canDeepProbe, isTrue);
      expect(r.depth, SubtitleProbeDepth.deep);
    });
  });

  group('探测准入', () {
    test('播放中一律不放行，用户主动也一样', () {
      expect(
        admitProbe(
          playbackActive: true,
          userInitiated: true,
          pending: 0,
          maxPending: 12,
        ),
        ProbeAdmission.skipPlayback,
      );
    });

    test('自动探测排队满额被挡', () {
      expect(
        admitProbe(
          playbackActive: false,
          userInitiated: false,
          pending: 12,
          maxPending: 12,
        ),
        ProbeAdmission.skipQuota,
      );
    });

    test('用户主动请求不受配额限制', () {
      expect(
        admitProbe(
          playbackActive: false,
          userInitiated: true,
          pending: 12,
          maxPending: 12,
        ),
        ProbeAdmission.run,
      );
    });

    test('空闲且未满配额放行', () {
      expect(
        admitProbe(
          playbackActive: false,
          userInitiated: false,
          pending: 3,
          maxPending: 12,
        ),
        ProbeAdmission.run,
      );
    });
  });
}
