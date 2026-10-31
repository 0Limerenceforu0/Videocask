import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/hls_ad_filter.dart';

/// 增强检测（规则清单 + 既有启发式不退化）的回归测试。
///
/// 与 `hls_ad_filter_real_sample_test.dart`（真实抓包）互补：这里用合成列表
/// 锁定「规则清单能补盲」的新能力，以及「等长切块绝不能误删」的死线。
///
/// 重要：实测真实片源的内容块时长跨度极大（5.8s–120.8s 都存在），裸的「局部
/// 时长对比」会把 legit 的短视频块误判成广告删掉正片。因此局部对比只在**闸门
/// 全部满足**时启用：整集块数很少（≤8，说明 DISCONTINUITY 是注入标记而非等长
/// 切分）、两侧正片都够长（≥120s）且之和 ≥400s、本块 ≤45s。其余死区（同域名
/// 等长切块）交给规则清单。2026-10-18 应用户反馈进一步收紧（同域首尾 30s、
/// 跨域长块放过、局部对比 45s/400s 闸门），见
/// `lib/services/hls_ad_filter.dart` 注释。
class _Blk {
  const _Blk(this.segs, this.dur, this.host,
      [this.path = 'seg', this.dir = '']);
  final int segs;
  final double dur; // 单分片时长（秒）
  final String host;
  final String path;

  /// 分片所在目录（用于构造路径段，如 `adjump`）。
  final String dir;
}

String _build(List<_Blk> blocks) {
  final b = StringBuffer()
    ..writeln('#EXTM3U')
    ..writeln('#EXT-X-VERSION:3')
    ..writeln('#EXT-X-TARGETDURATION:60')
    ..writeln('#EXT-X-MEDIA-SEQUENCE:0')
    ..writeln('#EXT-X-PLAYLIST-TYPE:VOD');
  var first = true;
  for (var bi = 0; bi < blocks.length; bi++) {
    if (!first) b.writeln('#EXT-X-DISCONTINUITY');
    first = false;
    final blk = blocks[bi];
    final prefix = blk.dir.isEmpty ? '' : '${blk.dir}/';
    for (var i = 0; i < blk.segs; i++) {
      b.writeln('#EXTINF:${blk.dur.toStringAsFixed(3)},');
      b.writeln('https://${blk.host}/$prefix${blk.path}_${bi}_$i.ts');
    }
  }
  b.writeln('#EXT-X-ENDLIST');
  return b.toString();
}

const _base = 'https://c.com/m3000k/hls/mixed.m3u8';

void main() {
  group('既有启发式中插（全局离群，factor 5）不退化', () {
    test('中插 19.6s 广告夹在 350s/1322s 正片间，被拦', () {
      // 19.6*5=98 ≤ 350（正片块中位数）→ 全局离群 → 命中。
      final content = _build(const [
        _Blk(89, 3.92, 'c.com'),
        _Blk(5, 3.92, 'c.com'),
        _Blk(330, 3.92, 'c.com'),
      ]);
      final r = HlsAdFilter.filterContent(content, _base);
      expect(r.originalCount, 424);
      expect(r.removedSegments, 5);
      expect(r.keptUrls, hasLength(419));
    });

    test('等长切块（整集均匀 ~20s）：绝不误删', () {
      final blocks = List.generate(6, (_) => const _Blk(5, 4, 'c.com'));
      final content = _build(blocks);
      final r = HlsAdFilter.filterContent(content, _base);
      expect(r.originalCount, 30);
      expect(r.removedAny, isFalse);
      expect(r.keptUrls, hasLength(30));
    });

    test('真实反例样本（146 等长块）零误删', () {
      final file =
          File('test/fixtures/hls/real_ffzy_plays_146blocks_no_ad.m3u8');
      final r = HlsAdFilter.filterContent(
        file.readAsStringSync(),
        'https://vip.ffzy-plays.com/20250728/43628_f18ca683/3000k/hls/'
        'mixed.m3u8',
      );
      expect(r.removedAny, isFalse);
      expect(r.keptIndices, List<int>.generate(r.originalCount, (i) => i));
    });
  });

  group('用户规则清单（AdBlockRules）—— 死区永久解法', () {
    test('单块列表 + URL 子串规则，按片段拦截', () {
      final content = _build(const [
        _Blk(1, 4, 'c.com', 'ok1'),
        _Blk(1, 4, 'c.com', 'ad/ad1'),
        _Blk(1, 4, 'c.com', 'ok2'),
      ]);
      final rules = AdBlockRules.empty.copyWith(blockedUrlSubstrings: ['/ad/']);
      final r = HlsAdFilter.filterContent(content, _base, rules: rules);
      expect(r.originalCount, 3);
      expect(r.removedSegments, 1);
      expect(r.keptUrls, hasLength(2));
    });

    test('单块列表无规则时，启发式不误删', () {
      final content = _build(const [
        _Blk(1, 4, 'c.com', 'ok1'),
        _Blk(1, 4, 'c.com', 'ad/ad1'),
        _Blk(1, 4, 'c.com', 'ok2'),
      ]);
      final r = HlsAdFilter.filterContent(content, _base);
      expect(r.removedAny, isFalse);
      expect(r.keptUrls, hasLength(3));
    });

    test('同域同长广告：启发式无信号，规则按 URL 特征拦截', () {
      // 与正片同域名、同时长 → 跨域/离群/局部对比全失效；靠规则拦。
      final content = _build(const [
        _Blk(10, 4, 'c.com', 'ok'),
        _Blk(10, 4, 'c.com', 'adzone/ad'),
        _Blk(10, 4, 'c.com', 'ok'),
      ]);
      final heuristic = HlsAdFilter.filterContent(content, _base);
      expect(heuristic.removedAny, isFalse, reason: '同域同长广告启发式应漏判，凸显规则必要性');
      final rules =
          AdBlockRules.empty.copyWith(blockedUrlSubstrings: ['/adzone/']);
      final r = HlsAdFilter.filterContent(content, _base, rules: rules);
      expect(r.removedSegments, 10);
      expect(r.keptUrls, hasLength(20));
    });

    test('跨域广告：无需规则，启发式即拦', () {
      final content = _build(const [
        _Blk(10, 4, 'c.com'),
        _Blk(10, 4, 'adcdn.com'),
        _Blk(10, 4, 'c.com'),
      ]);
      final r = HlsAdFilter.filterContent(content, _base);
      expect(r.removedSegments, 10);
      expect(r.keptUrls, hasLength(20));
    });
  });

  group('内置路径特征（AdBlockRules.builtin）—— 已知注入源最可靠判据', () {
    test('真实样本：风暴CDN /video/adjump/ 注入的 9 片广告被剔除', () {
      // 结构：正片 100 片/302.84s ─ 广告 9 片/26.04s ─ 正片 471 片/1408.12s。
      final content =
          File('test/fixtures/hls/real_fengbao_adjump_injected.m3u8')
              .readAsStringSync();
      final r = HlsAdFilter.filterContent(
        content,
        'https://fengbao13.com/video/mamafafengliao/801631e465d1/index.m3u8',
        rules: AdBlockRules.builtin,
      );
      expect(r.originalCount, 580);
      expect(r.removedSegments, 9);
      expect(r.removedSeconds, closeTo(26.04, 0.05));
      expect(r.keptUrls, hasLength(571));
      expect(r.keptUrls.any((u) => u.contains('adjump')), isFalse);
    });

    test('启发式死区一：整集被切成很多块时，路径特征仍能拦住中插广告', () {
      // 21 个 60s 块夹一个 26s 广告块：块时长中位数只有 60s，
      // 26*5=130 > 60 → 全局离群判据失效，且块数 >8 局部对比也不启用。
      final blocks = <_Blk>[
        ...List.generate(10, (_) => const _Blk(10, 6, 'c.com', 'seg', 'v')),
        const _Blk(5, 5.2, 'c.com', 'seg', 'adjump'),
        ...List.generate(10, (_) => const _Blk(10, 6, 'c.com', 'seg', 'v')),
      ];
      final content = _build(blocks);

      // 先确认这确实是启发式死区（无规则时漏判）。
      expect(
        HlsAdFilter.filterContent(content, _base).removedAny,
        isFalse,
        reason: '该形态启发式应漏判，否则说明死区已不存在',
      );

      final r = HlsAdFilter.filterContent(
        content,
        _base,
        rules: AdBlockRules.builtin,
      );
      expect(r.removedSegments, 5);
      expect(r.keptUrls, hasLength(200));
    });

    test('启发式死区二：超过 60s 的长贴片，路径特征仍能拦', () {
      // 90s 广告 > midRollAdMaxSeconds；片头 88.5s > edgeAdMaxSeconds。
      final mid = _build(const [
        _Blk(100, 6, 'c.com', 'seg', 'v'),
        _Blk(18, 5, 'c.com', 'seg', 'adjump'),
        _Blk(100, 6, 'c.com', 'seg', 'v'),
      ]);
      final midResult = HlsAdFilter.filterContent(
        mid,
        _base,
        rules: AdBlockRules.builtin,
      );
      expect(midResult.removedSegments, 18);
      expect(midResult.removedSeconds, closeTo(90, 0.1));

      final head = _build(const [
        _Blk(15, 5.9, 'c.com', 'seg', 'preroll'),
        _Blk(150, 6, 'c.com', 'seg', 'v'),
      ]);
      final headResult = HlsAdFilter.filterContent(
        head,
        _base,
        rules: AdBlockRules.builtin,
      );
      expect(headResult.removedSegments, 15);
      expect(headResult.keptUrls, hasLength(150));
    });

    test('反例：路径段是精确匹配，不误伤含相似子串的正片目录', () {
      // downloads/ 含 "ads" 子串、adventure/ 含 "ad" 前缀，都不是广告。
      final content = _build(const [
        _Blk(10, 6, 'c.com', 'seg', 'downloads'),
        _Blk(10, 6, 'c.com', 'seg', 'adventure'),
        _Blk(10, 6, 'c.com', 'seg', 'videos'),
      ]);
      final r = HlsAdFilter.filterContent(
        content,
        _base,
        rules: AdBlockRules.builtin,
      );
      expect(r.removedAny, isFalse);
      expect(r.keptUrls, hasLength(30));
    });
  });

  group('局部对比启发式（闸门）', () {
    test('长视频中插：两侧正片够长且不全局离群时，靠局部对比拦住', () {
      // 3 块，两侧各 210s，中插 43s。中位数 210，43*5=215 > 210 →
      // 全局离群不成立；43 ≤45s、两侧之和 420 ≥400、43 < 210*0.6=126 →
      // 仅局部对比命中。
      final content = _build(const [
        _Blk(35, 6, 'c.com'),
        _Blk(10, 4.3, 'c.com'),
        _Blk(35, 6, 'c.com'),
      ]);
      final r = HlsAdFilter.filterContent(content, _base);
      expect(r.removedSegments, 10);
      expect(r.keptUrls, hasLength(70));
    });

    test('闸门一：块数多（等长切分）时不启用局部对比', () {
      // 21 个等长 60s 块夹一个 26s 块 —— 局部对比本会命中，但块数 >8 禁用。
      final blocks = <_Blk>[
        ...List.generate(10, (_) => const _Blk(10, 6, 'c.com')),
        const _Blk(5, 5.2, 'c.com'),
        ...List.generate(10, (_) => const _Blk(10, 6, 'c.com')),
      ];
      final r = HlsAdFilter.filterContent(_build(blocks), _base);
      expect(r.removedAny, isFalse);
    });

    test('闸门二：短视频（两侧各 60s）里的短分段不启用局部对比', () {
      // 与 hls_ad_filter_test 的「中插短块但两侧正片不够长时不剔除」同源：
      // 短视频里的 20s 分段很可能是场景切换，不是广告。
      final content = _build(const [
        _Blk(6, 10, 'c.com'),
        _Blk(2, 10, 'c.com'),
        _Blk(6, 10, 'c.com'),
      ]);
      final r = HlsAdFilter.filterContent(content, _base);
      expect(r.removedAny, isFalse);
    });
  });

  group('保守化闸门（2026-10-18 用户反馈：删多了会跳剧情）', () {
    test('同域首尾块超过 30s 不删（可能是片头曲/序幕）', () {
      // 40s 首块 + 600s 正片：离群成立，但超过同域 30s 阈值 → 放过。
      final content = _build(const [
        _Blk(10, 4, 'c.com'),
        _Blk(100, 6, 'c.com'),
      ]);
      final r = HlsAdFilter.filterContent(content, _base);
      expect(r.removedAny, isFalse);
      expect(r.keptUrls, hasLength(110));
    });

    test('同域首尾块 30s 以内仍是广告，照删', () {
      final content = _build(const [
        _Blk(5, 6, 'c.com'),
        _Blk(100, 6, 'c.com'),
      ]);
      final r = HlsAdFilter.filterContent(content, _base);
      expect(r.removedSegments, 5);
    });

    test('局部对比下中插块超过 45s 不删（更像正片分段）', () {
      // 两侧各 180s、中插 50s：50 > 45 → 不删。
      final content = _build(const [
        _Blk(30, 6, 'c.com'),
        _Blk(10, 5, 'c.com'),
        _Blk(30, 6, 'c.com'),
      ]);
      final r = HlsAdFilter.filterContent(content, _base);
      expect(r.removedAny, isFalse);
    });

    test('局部对比下两侧正片之和不足 400s 不删', () {
      // 两侧各 150s、中插 40s：全局离群不成立（40*5=200 > 150 中位数），
      // 局部对比本会命中（40 < 150*0.6=90），但两侧之和 300 < 400 → 不删。
      final content = _build(const [
        _Blk(25, 6, 'c.com'),
        _Blk(10, 4, 'c.com'),
        _Blk(25, 6, 'c.com'),
      ]);
      final r = HlsAdFilter.filterContent(content, _base);
      expect(r.removedAny, isFalse);
    });

    test('跨域长块不删（多 CDN 分发正片）', () {
      // 600s 异域块 + 600s 主域块：长异域块按正片放过。
      final content = _build(const [
        _Blk(100, 6, 'c.com'),
        _Blk(100, 6, 'cdn2.com'),
      ]);
      final r = HlsAdFilter.filterContent(content, _base);
      expect(r.removedAny, isFalse);
      expect(r.keptUrls, hasLength(200));
    });

    test('跨域短块照删（贴片广告主流形态不变）', () {
      final content = _build(const [
        _Blk(5, 4, 'ad.com'),
        _Blk(100, 6, 'c.com'),
      ]);
      final r = HlsAdFilter.filterContent(content, _base);
      expect(r.removedSegments, 5);
    });

    test('fMP4 多个不同 init 段时不过滤（重建列表会损坏）', () {
      final content = '''
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXT-X-MAP:URI="init1.mp4"
#EXTINF:5,
a.ts
#EXT-X-DISCONTINUITY
#EXT-X-MAP:URI="init2.mp4"
#EXTINF:5,
b.ts
#EXT-X-ENDLIST
''';
      final r = HlsAdFilter.filterContent(content, _base);
      expect(r.hasMultipleMaps, isTrue);
      expect(r.removedAny, isFalse);
      expect(r.keptUrls, hasLength(2));
    });

    test('总开关关闭时原样保留', () {
      final content = _build(const [
        _Blk(5, 6, 'c.com'),
        _Blk(100, 6, 'c.com'),
      ]);
      final r = HlsAdFilter.filterContent(
        content,
        _base,
        rules: AdBlockRules.builtin,
        heuristicsEnabled: false,
      );
      expect(r.removedAny, isFalse);
      expect(r.keptUrls, hasLength(105));
    });
  });
}
