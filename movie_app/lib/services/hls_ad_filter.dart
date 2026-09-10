/// HLS 媒体播放列表广告分片过滤器。
///
/// 采集站（苹果CMS）片源的 m3u8 常被 CDN 注入广告分片，典型形态：
/// - 片头/片尾广告：列表首尾插入若干广告分片，与正片之间以
///   `#EXT-X-DISCONTINUITY` 分隔；
/// - 中插广告：正片中插入来自另一 CDN 域名的广告块（同样有分隔标记）。
///
/// 识别规则（保守，避免误删正片）：
/// 1. 仅处理 VOD 列表（含 `#EXT-X-ENDLIST`）；
/// 2. 按 `#EXT-X-DISCONTINUITY` 把分片切分成块，统计「多数域名」；
///    块内全部分片域名都不同于多数域名 → 判定为广告块；
/// 3. 首块/尾块总时长很短（≤ [edgeAdMaxSeconds]）且主体时长远大于它
///    （≥ [mainBlockDominance] 倍）→ 判定为广告块（同域注入的片头广告）；
///    中间的同域短块不删（无法与正片场景切换区分）。
///
/// 剔除广告后各保留分片的「原始序号」会保留在 [HlsAdFilterResult.keptIndices]，
/// AES-128 隐式 IV 依赖该序号，消费方解密时必须使用原始序号。
library;

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

/// 过滤器入口（纯函数，便于单测）。
class HlsAdFilter {
  HlsAdFilter._();

  /// 首尾块判定为广告的最长总时长（秒）。
  static const double edgeAdMaxSeconds = 30;

  /// 首尾块判定为广告时，主体块时长至少是其的倍数。
  static const double mainBlockDominance = 5;

  /// 解析并过滤媒体播放列表内容。
  static HlsAdFilterResult filterContent(String content, String baseUrl) {
    final lines = content.split('\n');

    var isVod = false;
    var hasByteRange = false;
    var currentDuration = 10.0;
    String? mapLine;
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

    final kept = _detectAds(segments, blocks, isVod: isVod);
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
    );
  }

  /// 广告块识别（见库注释的规则说明）。
  static List<HlsAdSegment> _detectAds(
    List<HlsAdSegment> segments,
    List<List<HlsAdSegment>> blocks, {
    required bool isVod,
  }) {
    // 无法识别的形态一律原样保留。
    if (!isVod || segments.isEmpty || blocks.length <= 1) {
      return segments;
    }

    final majorityHost = _majorityHost(segments);
    if (majorityHost == null) {
      return segments;
    }

    var mainBlockDuration = 0.0;
    for (final block in blocks) {
      var total = 0.0;
      for (final s in block) {
        total += s.duration;
      }
      if (total > mainBlockDuration) {
        mainBlockDuration = total;
      }
    }

    final kept = <HlsAdSegment>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (block.isEmpty) continue;

      if (_isAdBlock(
        block,
        majorityHost: majorityHost,
        isEdgeBlock: i == 0 || i == blocks.length - 1,
        mainBlockDuration: mainBlockDuration,
      )) {
        continue;
      }
      kept.addAll(block);
    }

    // 过滤逻辑异常导致清空时，宁可保留全部分片。
    if (kept.isEmpty) {
      return segments;
    }
    return kept;
  }

  static bool _isAdBlock(
    List<HlsAdSegment> block, {
    required String majorityHost,
    required bool isEdgeBlock,
    required double mainBlockDuration,
  }) {
    // 块内全部域名都不同于主体域名 → 广告 CDN 注入。
    final allForeignHost = block.every(
      (s) => _hostOf(s.url) != majorityHost,
    );
    if (allForeignHost) return true;

    if (!isEdgeBlock) return false;

    // 首尾短块（常见同域片头广告）：时长很短且主体远大于它。
    var total = 0.0;
    for (final s in block) {
      total += s.duration;
    }
    return total <= edgeAdMaxSeconds &&
        mainBlockDuration >= total * mainBlockDominance;
  }

  /// 出现次数最多的分片域名（主体内容域名）。
  static String? _majorityHost(List<HlsAdSegment> segments) {
    final counts = <String, int>{};
    for (final s in segments) {
      final host = _hostOf(s.url);
      if (host == null) continue;
      counts[host] = (counts[host] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    String? best;
    var bestCount = 0;
    for (final entry in counts.entries) {
      if (entry.value > bestCount) {
        best = entry.key;
        bestCount = entry.value;
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

  var previousBlock = -1;
  for (final s in result.segments) {
    // 保留块与块之间的真实切换标记（原广告块已被剔除）。
    if (previousBlock >= 0 && s.blockIndex != previousBlock) {
      buffer.writeln('#EXT-X-DISCONTINUITY');
    }
    previousBlock = s.blockIndex;
    buffer.writeln('#EXTINF:${s.duration.toStringAsFixed(3)},');
    buffer.writeln(s.url);
  }
  buffer.writeln('#EXT-X-ENDLIST');
  return buffer.toString();
}
