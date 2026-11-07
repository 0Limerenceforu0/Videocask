/// HLS 媒体播放列表广告分片过滤器。
///
/// 采集站（苹果CMS）片源的 m3u8 常被 CDN 注入广告分片，典型形态：
/// - 片头/片尾广告：列表首尾插入若干广告分片，与正片之间以
///   `#EXT-X-DISCONTINUITY` 分隔；
/// - 中插广告：正片中插入来自另一 CDN 域名的广告块（同样有分隔标记）。
///
/// 识别规则（保守，避免误删正片）：
/// 0. **路径特征**：分片 URL 的某个路径段命中已知广告目录名（`adjump`、
///    `preroll` 等，见 [AdBlockRules.builtinPathSegments]）→ 直接判广告。
///    这条不依赖时长/块结构，是「已知注入源」最可靠的判据；
/// 1. 仅处理 VOD 列表（含 `#EXT-X-ENDLIST`）；
/// 2. 按 `#EXT-X-DISCONTINUITY` 把分片切分成块，统计「多数域名」；
///    块内全部分片域名都不同于多数域名、**且块够短**（≤ 时长上限）→ 判定为
///    广告块。长的异域块可能是多 CDN 分发正片，误删就是跳剧情，不冒险；
/// 3. 首块/尾块总时长很短、且它是**时长离群块**（典型块时长的中位数 ≥ 其
///    [HlsAdFilter.adOutlierDominance] 倍）→ 判定为广告块（片头/片尾贴片）。
///    同域首尾块阈值收紧到 [HlsAdFilter.sameHostEdgeAdMaxSeconds]（30s）：
///    30~45s 的片头曲/序幕更可能是正片；
/// 4. **中插同域广告**：被 DISCONTINUITY 前后包夹的中间块，总时长很短
///    （≤ [HlsAdFilter.midRollAdMaxSeconds]），是时长离群块，且左右相邻的正片块
///    都远长于它（≥ [HlsAdFilter.neighborMinSeconds] 且
///    ≥ [HlsAdFilter.neighborDominance] 倍）→ 判定为广告块；
///    或（局部对比，2026-10-18 收紧）整集只切成很少几块、两侧正片够长
///    （各 ≥ [HlsAdFilter.neighborMinSeconds] 且之和 ≥
///    [HlsAdFilter.localContrastMinNeighborSum]）、本块 ≤
///    [HlsAdFilter.localContrastMaxSeconds] 且不到两侧的
///    `localContrastRatio` → 判定为广告块。
///
/// 「离群」必须拿**块时长中位数**比，不能拿最长的块比：有些源会把整集用
/// DISCONTINUITY 切成上百个等长短块（实测某源 146 块 × 约 20s），此时首尾块
/// 相对「最长的块」也显得短，会被规则 3 当成片头/片尾贴片删掉正片
/// （回归样本 `test/fixtures/hls/real_ffzy_plays_146blocks_no_ad.m3u8`）。
/// 等长切分里没有离群块，改用中位数后一处都不会删。
///
/// 规则 4 是采集站目前的主流形态：广告分片与正片**同一域名、同一命名风格**
/// （都是 32 位 hex 的 `.ts`），只有「前后各一条 DISCONTINUITY + 时长异常短」
/// 这一个可判据。实测 ffzy / feifei 等源每集都在正片中段插 5 片 / 19.6s 广告，
/// 仅靠规则 2、3 拦不住。
///
/// fMP4（`#EXT-X-MAP`）若出现**多个不同 init 段**，重建播放列表只会保留第一个，
/// 后续分片会拿到错误的 init → 直接放弃过滤回退直连。
///
/// 剔除广告后各保留分片的「原始序号」会保留在 [HlsAdFilterResult.keptIndices]，
/// AES-128 隐式 IV 依赖该序号，消费方解密时必须使用原始序号。
library;

import 'dart:math' as math;

/// 单个保留分片的描述。
class HlsAdSegment {
  const HlsAdSegment({
    required this.sourceIndex,
    required this.url,
    required this.duration,
    required this.blockIndex,
  });

  /// 在原始列表中的分片序号（AES-128 隐式 IV 依赖）。
  final int sourceIndex;

  /// 分片绝对地址。
  final String url;

  /// EXTINF 时长（秒）。
  final double duration;

  /// 原始分块序号（用于重建播放列表时恢复 DISCONTINUITY 标记）。
  final int blockIndex;
}

/// 过滤结果。
class HlsAdFilterResult {
  const HlsAdFilterResult({
    required this.segments,
    required this.originalCount,
    required this.removedSegments,
    required this.removedSeconds,
    required this.isVod,
    required this.hasByteRange,
    required this.mapLine,
    this.hasMultipleMaps = false,
  });

  /// 保留的分片（按原始顺序）。
  final List<HlsAdSegment> segments;

  /// 原始分片总数。
  final int originalCount;

  /// 被剔除的广告分片数。
  final int removedSegments;

  /// 被剔除的广告总时长（秒）。
  final double removedSeconds;

  /// 是否 VOD 列表。
  final bool isVod;

  /// 是否包含 `#EXT-X-BYTERANGE`（重建播放列表不支持，调用方应回退直连）。
  final bool hasByteRange;

  /// 原始 `#EXT-X-MAP` 行（URI 已解析为绝对地址），无则为 null。
  final String? mapLine;

  /// 是否包含多个不同的 `#EXT-X-MAP` init 段（fMP4 分片级 init）。
  ///
  /// 重建播放列表只保留第一个 MAP，此场景下必须回退直连。
  final bool hasMultipleMaps;

  /// 保留分片的绝对地址列表。
  List<String> get keptUrls =>
      segments.map((s) => s.url).toList(growable: false);

  /// 保留分片的原始序号列表。
  List<int> get keptIndices =>
      segments.map((s) => s.sourceIndex).toList(growable: false);

  /// 保留分片的时长列表。
  List<double> get keptDurations =>
      segments.map((s) => s.duration).toList(growable: false);

  /// 是否剔除了广告。
  bool get removedAny => removedSegments > 0;
}

/// 用户可维护的广告拦截规则（"一劳永逸"开关）。
///
/// 启发式检测对「同域名、等长切块、无 DISCONTINUITY」的片源无能为力——
/// 这类源的广告与正片在播放列表层面长得一模一样。规则清单让用户把**已知**
/// 的广告特征（域名 / URL 子串）写进 [assets/ad_block_rules.json]，一次配好、
/// 永久生效，不依赖代码改动。
///
/// 三层判据，命中即判广告，优先级高于一切启发式：
/// 1. [blockedHosts] —— 广告 CDN 域名（子串匹配）；
/// 2. [blockedUrlSubstrings] —— URL 子串（用户自担误伤风险）；
/// 3. [blockedPathSegments] —— **URL 路径段精确匹配**（默认启用内置清单，
///    见 [AdBlockRules.builtinPathSegments]）。
///
/// 纯 Dart（不依赖 Flutter），便于单测。
class AdBlockRules {
  const AdBlockRules({
    this.blockedHosts = const [],
    this.blockedUrlSubstrings = const [],
    this.blockedPathSegments = const [],
    this.localContrastRatio = 0.6,
    this.maxAdBlockSeconds = 60,
  });

  /// 命中即判定为广告的域名（子串匹配，如 `ad-cdn.example.com`）。
  final List<String> blockedHosts;

  /// 命中即判定为广告的 URL 子串（如 `/preroll/`、`/adzone/`）。
  final List<String> blockedUrlSubstrings;

  /// 命中即判定为广告的 URL **路径段**（整段精确匹配，如 `adjump`）。
  final List<String> blockedPathSegments;

  /// 中插局部对比阈值：广告块时长 < 两侧正片该比例即判广告。
  final double localContrastRatio;

  /// 中插 / 片头片尾广告块时长上限（秒）；超过则不再按"短块"规则判广告。
  ///
  /// 调大可以拦更长的贴片（如 90s），代价是正片分段被误删的风险上升。
  final double maxAdBlockSeconds;

  /// 内置广告路径特征（路径段小写精确匹配，默认启用）。
  ///
  /// 用**路径段**而不是子串，是为了避免 `downloads/` 命中 `ads/` 这类误伤
  /// （切出来的段是 `downloads`，不等于 `ads`）。这些名字来自实测注入样本与
  /// 常见贴片广告目录命名，正片几乎不可能拿它们当目录名。
  static const List<String> builtinPathSegments = <String>[
    'adjump', // 实测：/video/adjump/time/<ts>.ts（风暴CDN 注入）
    'advert',
    'advertisement',
    'advertising',
    'preroll',
    'postroll',
    'midroll',
    'adtime',
    'adpush',
    'adinsert',
    'adservice',
    'adserver',
    'adsrc',
    'advideo',
    'adzone',
    'ggad',
  ];

  /// 什么规则都没有（仅供测试与"彻底关闭过滤"用）。
  static const AdBlockRules empty = AdBlockRules();

  /// 仅内置路径特征，不含任何用户配置。
  static const AdBlockRules builtin = AdBlockRules(
    blockedPathSegments: builtinPathSegments,
  );

  AdBlockRules copyWith({
    List<String>? blockedHosts,
    List<String>? blockedUrlSubstrings,
    List<String>? blockedPathSegments,
    double? localContrastRatio,
    double? maxAdBlockSeconds,
  }) {
    return AdBlockRules(
      blockedHosts: blockedHosts ?? this.blockedHosts,
      blockedUrlSubstrings: blockedUrlSubstrings ?? this.blockedUrlSubstrings,
      blockedPathSegments: blockedPathSegments ?? this.blockedPathSegments,
      localContrastRatio: localContrastRatio ?? this.localContrastRatio,
      maxAdBlockSeconds: maxAdBlockSeconds ?? this.maxAdBlockSeconds,
    );
  }

  /// 从 `assets/ad_block_rules.json` 解析，并默认并入内置路径特征。
  ///
  /// 内置特征可用 `"disableBuiltinPathSegments": true` 关闭（排查误删时用）。
  factory AdBlockRules.fromJson(Map<String, dynamic> json) {
    final hosts = (json['blockedHosts'] as List?)
        ?.whereType<String>()
        .toList(growable: false);
    final subs = (json['blockedUrlSubstrings'] as List?)
        ?.whereType<String>()
        .toList(growable: false);
    final userSegments = (json['blockedPathSegments'] as List?)
            ?.whereType<String>()
            .map((s) => s.toLowerCase())
            .toList(growable: false) ??
        const <String>[];
    final ratio = (json['localContrastRatio'] as num?)?.toDouble();
    final maxSec = (json['maxAdBlockSeconds'] as num?)?.toDouble();

    final segments = <String>{
      if (json['disableBuiltinPathSegments'] != true) ...builtinPathSegments,
      ...userSegments,
    }.toList(growable: false);

    return AdBlockRules(
      blockedHosts: hosts ?? const [],
      blockedUrlSubstrings: subs ?? const [],
      blockedPathSegments: segments,
      localContrastRatio: ratio ?? 0.6,
      maxAdBlockSeconds: maxSec ?? 60,
    );
  }

  bool get isEmpty =>
      blockedHosts.isEmpty &&
      blockedUrlSubstrings.isEmpty &&
      blockedPathSegments.isEmpty;

  /// 单个分片 URL 是否命中规则（命中即判广告）。
  bool segmentBlocked(String url) {
    if (blockedHosts.isNotEmpty) {
      final h = _hostOfStatic(url);
      if (h != null && blockedHosts.any((b) => h.contains(b))) return true;
    }
    if (blockedUrlSubstrings.isNotEmpty) {
      if (blockedUrlSubstrings.any((s) => url.contains(s))) return true;
    }
    if (blockedPathSegments.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        for (final seg in uri.pathSegments) {
          if (blockedPathSegments.contains(seg.toLowerCase())) return true;
        }
      }
    }
    return false;
  }

  static String? _hostOfStatic(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    return uri.host;
  }
}

/// 过滤器入口（纯函数，便于单测）。
class HlsAdFilter {
  HlsAdFilter._();

  /// 首尾块判定为广告的最长总时长（秒）——仅用于**跨域名**首尾块。
  ///
  /// 异域 + 短 + 离群，三重证据才删。同域首尾块用更严的
  /// [sameHostEdgeAdMaxSeconds]。
  static const double edgeAdMaxSeconds = 45;

  /// 同域首尾块判定为广告的最长总时长（秒）。
  ///
  /// 比跨域阈值严一半：同域短块也可能是片头曲/序幕（正片），
  /// 误删就是用户看到的「跳剧情」。注入式贴片通常 15~30s，够用。
  static const double sameHostEdgeAdMaxSeconds = 30;

  /// 判定为广告时，典型块时长（非空块时长中位数）至少是本块时长的倍数。
  ///
  /// 用中位数而非最大值：见库注释里「整集被切成上百个等长短块」的说明。
  static const double adOutlierDominance = 5;

  /// 中间块判定为广告的最长总时长（秒）。
  ///
  /// 覆盖常见的 15s / 20s / 30s / 45s 中插贴片；再长就可能是正片分段，不冒险。
  static const double midRollAdMaxSeconds = 60;

  /// 中间块判定为广告时，左右相邻正片块的最短时长（秒）。
  static const double neighborMinSeconds = 120;

  /// 中间块判定为广告时，左右相邻正片块时长至少是其的倍数。
  static const double neighborDominance = 6;

  /// 允许启用「局部对比」判据的最大非空块数。
  ///
  /// 超过这个块数说明整集被等长切成很多段（DISCONTINUITY 是切分标记而非
  /// 广告注入标记），相邻块时长本就有波动，局部对比会误删正片小段。
  static const int localContrastMaxBlocks = 8;

  /// 局部对比判据下，候选广告块自身的最长时长（秒）。
  ///
  /// 2026-10-18 收紧：超过 45s 的中间块更像正片分段（场景切换），不删。
  static const double localContrastMaxSeconds = 45;

  /// 局部对比判据下，左右两侧正片时长之和的下限（秒）。
  ///
  /// 短视频 / 花絮（几分钟）里的短分段很可能是正片内容，宁可放过；
  /// 中插贴片只存在于长片源。
  static const double localContrastMinNeighborSum = 400;

  /// 剔除总时长占原列表的比例上限（超出说明判定可疑，整体放弃过滤）。
  static const double maxRemovedRatio = 0.5;

  /// 解析并过滤媒体播放列表内容。
  ///
  /// [rules] 为用户可维护的广告拦截规则（详见 [AdBlockRules]）；传 [AdBlockRules.empty]
  /// 时仅用启发式，行为与旧版一致。
  ///
  /// [heuristicsEnabled] 为 false 时整体关闭过滤（用户开关，见设置 → 播放设置），
  /// 仅当 [rules] 非空时仍应用规则清单——调用方关开关时应传空规则。
  static HlsAdFilterResult filterContent(
    String content,
    String baseUrl, {
    AdBlockRules rules = AdBlockRules.empty,
    bool heuristicsEnabled = true,
  }) {
    final lines = content.split('\n');

    var isVod = false;
    var hasByteRange = false;
    var currentDuration = 10.0;
    String? mapLine;
    final mapUris = <String>{};
    final segments = <HlsAdSegment>[];
    final blocks = <List<HlsAdSegment>>[<HlsAdSegment>[]];

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#')) {
        if (line.startsWith('#EXT-X-ENDLIST')) {
          isVod = true;
        } else if (line.startsWith('#EXT-X-BYTERANGE')) {
          hasByteRange = true;
        } else if (line.startsWith('#EXT-X-MAP')) {
          mapLine = _resolveMapLine(line, baseUrl);
          final m = RegExp(r'URI="([^"]+)"').firstMatch(mapLine ?? '');
          if (m != null) mapUris.add(m.group(1)!);
        } else if (line.startsWith('#EXTINF:')) {
          final payload = line.substring('#EXTINF:'.length);
          final value = payload.split(',').first.trim();
          currentDuration = double.tryParse(value) ?? 10.0;
        } else if (line.startsWith('#EXT-X-DISCONTINUITY')) {
          blocks.add(<HlsAdSegment>[]);
        }
        continue;
      }

      final url = _resolveUrl(baseUrl, line);
      final segment = HlsAdSegment(
        sourceIndex: segments.length,
        url: url,
        duration: currentDuration,
        blockIndex: blocks.length - 1,
      );
      segments.add(segment);
      blocks.last.add(segment);
    }

    // fMP4 多个不同 init 段：重建列表只保留第一个 MAP，其余分片会拿到
    // 错误的 init 数据 → 放弃过滤，回退直连（2026-10-18 防闪退/花屏）。
    final hasMultipleMaps = mapUris.length > 1;

    final kept = _detectAds(
      segments,
      blocks,
      isVod: isVod,
      rules: rules,
      heuristicsEnabled: heuristicsEnabled,
      hasMultipleMaps: hasMultipleMaps,
    );
    var removedSeconds = 0.0;
    if (kept.length != segments.length) {
      final keptSet = kept.map((s) => s.sourceIndex).toSet();
      for (final s in segments) {
        if (!keptSet.contains(s.sourceIndex)) {
          removedSeconds += s.duration;
        }
      }
    }

    return HlsAdFilterResult(
      segments: kept,
      originalCount: segments.length,
      removedSegments: segments.length - kept.length,
      removedSeconds: removedSeconds,
      isVod: isVod,
      hasByteRange: hasByteRange,
      mapLine: mapLine,
      hasMultipleMaps: hasMultipleMaps,
    );
  }

  /// 广告块识别（见库注释的规则说明）。
  ///
  /// [rules] 为用户规则清单：命中的分片（按域名 / URL 子串）一律判广告，
  /// 优先级高于启发式，用于覆盖"同域名等长切块无 DISCONTINUITY"这类死区。
  ///
  /// [heuristicsEnabled] 为 false 时跳过全部启发式（用户总开关关闭）。
  /// [hasMultipleMaps] 为 true 时同样放弃启发式（重建播放列表会损坏 fMP4）。
  static List<HlsAdSegment> _detectAds(
    List<HlsAdSegment> segments,
    List<List<HlsAdSegment>> blocks, {
    required bool isVod,
    AdBlockRules rules = AdBlockRules.empty,
    bool heuristicsEnabled = true,
    bool hasMultipleMaps = false,
  }) {
    // 无法识别的形态一律原样保留。
    if (!isVod || segments.isEmpty || !heuristicsEnabled || hasMultipleMaps) {
      return segments;
    }

    // 规则清单命中的分片（片段级），任何形态都先剔除。
    final ruleRemoved = <int>{};
    if (!rules.isEmpty) {
      for (final s in segments) {
        if (rules.segmentBlocked(s.url)) ruleRemoved.add(s.sourceIndex);
      }
    }

    // 只在「非空块」序列上判定首尾 —— 列表开头常有一条多余的
    // DISCONTINUITY，会产生一个空块，直接用原始下标会把真正的首块误判成中间块。
    final nonEmpty = <int>[];
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].isNotEmpty) nonEmpty.add(i);
    }

    // 单块（无 DISCONTINUITY）：启发式无信号，仅规则清单能起作用。
    if (nonEmpty.length <= 1) {
      if (ruleRemoved.isEmpty) return segments;
      final kept =
          segments.where((s) => !ruleRemoved.contains(s.sourceIndex)).toList();
      if (kept.isEmpty) return segments;
      final totalSeconds = segments.fold<double>(0, (a, s) => a + s.duration);
      final removedSeconds =
          ruleRemoved.fold<double>(0, (a, idx) => a + segments[idx].duration);
      if (totalSeconds > 0 && removedSeconds > totalSeconds * maxRemovedRatio) {
        return segments;
      }
      return kept;
    }

    final durations = List<double>.generate(
      blocks.length,
      (i) => _blockDuration(blocks[i]),
      growable: false,
    );

    final majorityHost = _contentHost(segments, blocks, durations, nonEmpty);
    if (majorityHost == null) {
      return segments;
    }

    var totalSeconds = 0.0;
    for (final i in nonEmpty) {
      totalSeconds += durations[i];
    }

    // 典型块时长：非空块时长的中位数（取上中位数，块数为偶数时偏大的那个）。
    final sortedDurations =
        nonEmpty.map((i) => durations[i]).toList(growable: false)..sort();
    final medianBlock = sortedDurations[sortedDurations.length ~/ 2];

    final isAd = List<bool>.filled(blocks.length, false, growable: false);

    /// 占比达到总时长一半的块一定是正片，任何规则都不得判它为广告。
    bool isDominantBlock(int i) =>
        totalSeconds > 0 && durations[i] * 2 > totalSeconds;

    /// 时长离群：比典型块短一个数量级。切分均匀（等长短块）的片源没有离群块。
    bool isOutlierBlock(int i) =>
        durations[i] * adOutlierDominance <= medianBlock;

    // 第一遍：跨域名块 + 首尾短块。
    //
    // 时长上限取「内置阈值」与「用户配置」的较大者：用户调大
    // maxAdBlockSeconds 即可拦更长的贴片（代价是误删风险上升）。
    // 跨域名块也必须「够短」才判广告——多 CDN 分发正片时长的异域块
    // 是正片，删了就是跳剧情（2026-10-18 用户反馈修复）。
    final durationCap = math.max(midRollAdMaxSeconds, rules.maxAdBlockSeconds);
    for (var p = 0; p < nonEmpty.length; p++) {
      final i = nonEmpty[p];
      if (isDominantBlock(i)) continue;
      if (_hostOf(blocks[i].first.url) == null) continue;
      final isEdgeBlock = p == 0 || p == nonEmpty.length - 1;
      final crossHost = blocks[i].every((s) => _hostOf(s.url) != majorityHost);
      if (crossHost) {
        // 异域块：短才可能是贴片；长异域块按多 CDN 正片放过。
        // 首尾异域块用更严的 edgeAdMaxSeconds。
        final cap = isEdgeBlock ? edgeAdMaxSeconds : durationCap;
        if (durations[i] <= cap) {
          isAd[i] = true;
        }
        continue;
      }
      // 同域首尾块：阈值收紧到 sameHostEdgeAdMaxSeconds，
      // 30~45s 的片头曲/序幕更可能是正片，误删就是跳剧情。
      if (isEdgeBlock &&
          durations[i] <= sameHostEdgeAdMaxSeconds &&
          isOutlierBlock(i)) {
        isAd[i] = true;
      }
    }

    // 第二遍：中插同域短块（全局离群）。左右参照取「最近的未被判为广告的块」，
    // 这样连续两个广告块（正片 → 广告A → 广告B → 正片）也能各自命中。
    for (var p = 0; p < nonEmpty.length; p++) {
      final i = nonEmpty[p];
      if (isAd[i] || p == 0 || p == nonEmpty.length - 1) continue;
      if (isDominantBlock(i)) continue;

      double? prevDuration;
      for (var q = p - 1; q >= 0; q--) {
        final j = nonEmpty[q];
        if (!isAd[j]) {
          prevDuration = durations[j];
          break;
        }
      }
      double? nextDuration;
      for (var q = p + 1; q < nonEmpty.length; q++) {
        final j = nonEmpty[q];
        if (!isAd[j]) {
          nextDuration = durations[j];
          break;
        }
      }
      if (prevDuration == null || nextDuration == null) continue;
      if (durations[i] > durationCap) continue;

      // 判据一（全局离群）：块时长比典型块短一个数量级，且左右邻居都够长。
      final threshold = math.max(
        neighborMinSeconds,
        durations[i] * neighborDominance,
      );
      final byGlobalOutlier = isOutlierBlock(i) &&
          prevDuration >= threshold &&
          nextDuration >= threshold;

      // 判据二（局部对比）：整集只被切成很少几块时，DISCONTINUITY 基本就是
      // 「广告注入标记」，此时直接拿左右邻居比——广告块必然远短于两侧正片。
      //
      // 闸门（缺一不可，2026-10-18 收紧）：
      // - 块数必须很少。块多（等长切分）的源相邻块时长本就有波动，实测会把
      //   5.8s 的正片小段误判成广告（146 块样本），那里只能靠全局中位数；
      // - 两侧正片必须够长、且加起来够长。短视频 / 花絮里的短分段很可能
      //   是正片的场景切换，不是广告，宁可放过；
      // - 本块必须够短（≤ localContrastMaxSeconds）。更长的中间块更像正片分段。
      final byLocalContrast = nonEmpty.length <= localContrastMaxBlocks &&
          durations[i] <= localContrastMaxSeconds &&
          prevDuration >= neighborMinSeconds &&
          nextDuration >= neighborMinSeconds &&
          prevDuration + nextDuration >= localContrastMinNeighborSum &&
          durations[i] < prevDuration * rules.localContrastRatio &&
          durations[i] < nextDuration * rules.localContrastRatio;

      if (byGlobalOutlier || byLocalContrast) {
        isAd[i] = true;
      }
    }

    final kept = <HlsAdSegment>[];
    var removedSeconds = 0.0;
    for (final s in segments) {
      if (ruleRemoved.contains(s.sourceIndex)) {
        removedSeconds += s.duration;
        continue;
      }
      if (isAd[s.blockIndex]) {
        removedSeconds += s.duration;
        continue;
      }
      kept.add(s);
    }

    // 兜底：清空 / 剔除比例异常高，说明判定可疑，宁可保留全部分片。
    if (kept.isEmpty) return segments;
    if (totalSeconds > 0 && removedSeconds > totalSeconds * maxRemovedRatio) {
      return segments;
    }
    return kept;
  }

  static double _blockDuration(List<HlsAdSegment> block) {
    var total = 0.0;
    for (final s in block) {
      total += s.duration;
    }
    return total;
  }

  /// 正片域名基准。
  ///
  /// 直接用「全局出现最多的域名」并不可靠：广告常被切成大量极短分片，
  /// 多段广告的时长加起来甚至能超过正片（此时正片反而成了"异域块"）。
  /// 因此优先以**时长最长的那个块**为基准 —— 它几乎必然是正片主体 ——
  /// 只有并列最长或该块域名无法解析时，才退回全局按总时长加权统计。
  static String? _contentHost(
    List<HlsAdSegment> segments,
    List<List<HlsAdSegment>> blocks,
    List<double> durations,
    List<int> nonEmpty,
  ) {
    var maxDuration = -1.0;
    var longest = <int>[];
    for (final i in nonEmpty) {
      if (durations[i] > maxDuration + 1e-9) {
        maxDuration = durations[i];
        longest = <int>[i];
      } else if ((durations[i] - maxDuration).abs() <= 1e-9) {
        longest.add(i);
      }
    }
    if (longest.length == 1) {
      final host = _majorityHost(blocks[longest.first]);
      if (host != null) return host;
    }
    return _majorityHost(segments);
  }

  /// 主体内容域名：按**分片总时长**加权统计，而不是分片个数。
  ///
  /// 广告常被切成大量极短分片，按个数统计会让广告 CDN 反过来成为「主体」，
  /// 进而把正片当成异域块删掉 —— 时长加权可避免这类反向误判。
  static String? _majorityHost(List<HlsAdSegment> segments) {
    final weights = <String, double>{};
    for (final s in segments) {
      final host = _hostOf(s.url);
      if (host == null) continue;
      weights[host] = (weights[host] ?? 0) + s.duration;
    }
    if (weights.isEmpty) return null;
    String? best;
    var bestWeight = -1.0;
    for (final entry in weights.entries) {
      if (entry.value > bestWeight) {
        best = entry.key;
        bestWeight = entry.value;
      }
    }
    return best;
  }

  static String? _hostOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    return uri.host;
  }

  static String? _resolveMapLine(String line, String baseUrl) {
    final match = RegExp(r'URI="([^"]+)"').firstMatch(line);
    if (match == null) return line;
    final uriValue = match.group(1)!;
    final resolved = _resolveUrl(baseUrl, uriValue);
    return line.replaceFirst('"$uriValue"', '"$resolved"');
  }

  static String _resolveUrl(String baseUrl, String ref) {
    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return ref;
    }
    return Uri.parse(baseUrl).resolve(ref).toString();
  }
}

/// 基于过滤结果重建一份「去广告」的媒体播放列表，供本地静态代理输出。
///
/// 返回 null 表示不适合重建（非 VOD / 含 BYTERANGE / 无广告），调用方应回退直连。
String? buildAdFreePlaylistContent(HlsAdFilterResult result) {
  if (!result.isVod || !result.removedAny || result.segments.isEmpty) {
    return null;
  }
  if (result.hasByteRange) return null;

  var targetDuration = 10;
  for (final s in result.segments) {
    final ceil = s.duration.ceil();
    if (ceil > targetDuration) targetDuration = ceil;
  }

  final buffer = StringBuffer(
    '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:$targetDuration\n'
    '#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PLAYLIST-TYPE:VOD\n',
  );
  final mapLine = result.mapLine;
  if (mapLine != null) {
    buffer.writeln(mapLine);
  }

  // 保留下来的原始分片序号集合，用于判断「某分片的前一个原始分片是否也保留」。
  final keptSet = result.segments.map((s) => s.sourceIndex).toSet();

  var previousBlock = -1;
  for (final s in result.segments) {
    // 仅当「当前分片的前一个原始分片也被保留」时，才保留其前的 DISCONTINUITY。
    // 否则该 DISCONTINUITY 原本是正片→广告的边界；广告剔除后两侧已是连续正片，
    // 留着会让 mpv 越过它时重置解码器，而紧跟的广告后正片分片并非干净关键帧起点
    // → 反复 "Error decoding audio"（实测 1 秒内纠偏 seek 12 次，拖垮原生层 → 闪退）。
    // 该规则只删「人为断层」，源里原本就存在的正片→正片 discontinuity 仍保留。
    final prevOriginalKept =
        s.sourceIndex > 0 && keptSet.contains(s.sourceIndex - 1);
    if (previousBlock >= 0 &&
        s.blockIndex != previousBlock &&
        prevOriginalKept) {
      buffer.writeln('#EXT-X-DISCONTINUITY');
    }
    previousBlock = s.blockIndex;
    buffer.writeln('#EXTINF:${s.duration.toStringAsFixed(3)},');
    buffer.writeln(s.url);
  }
  buffer.writeln('#EXT-X-ENDLIST');
  return buffer.toString();
}
