/// 从「种子文件清单 + MKV 轨道信息」得出「这个资源有没有中文字幕」的结论。
///
/// 纯函数，可单测。设计原则：**宁可说未知，也不猜**。
/// 之前那版只看标题关键词，标题没写就输出「未标注字幕」，用户拿它做决策会被误导。
library;

import 'mkv_track_parser.dart';

/// 探测结论。
enum SubtitleProbeVerdict {
  /// 有中文文本字幕（外挂 srt/ass，或内封 S_TEXT 轨）。最理想。
  chineseText,

  /// 只有中文图形字幕（PGS/VobSub）：能显示，但取不到文本、字号不可调。
  chineseImage,

  /// 有字幕轨，但没有一条是中文（含「无字幕轨」）。
  noChinese,

  /// 信息不足（元数据没拿到 / 不是 MKV / 解析失败）。
  unknown,
}

/// 结论是「凭什么」得出的。tooltip 会展示，便于用户判断可信度。
enum SubtitleProbeSource {
  /// 标题关键词。
  title,

  /// 种子文件清单（外挂字幕文件名）。
  fileList,

  /// MKV 内封轨道的 Language / TrackName / CodecID。
  mkvTracks,

  /// 外挂字幕正文 CJK 实证。
  subtitleText,

  /// 信息不足。
  none,
}

/// 中文的简繁形态。
enum ChineseScript {
  simplified,
  traditional,
  both,
  unspecified,
}

/// 结论的探测深度。
///
/// 🔴 2026-11-08 真机定案：搜索列表里自动跑的探测**只能到 fast**。
/// 真机日志 `serve_range: piece=0 not ready ... lt_have=0 done=0MB`、
/// 5/10/15s 后 ABORT —— 刚 add 的种子在超时窗口内根本下不到文件头那 2MB，
/// 于是每条自动探测都白挂 18s 种子，几十条一起还会把正在播的磁力拖卡。
/// 读 MKV 文件头 / 外挂字幕正文属于 deep，只由用户主动点徽标时触发。
enum SubtitleProbeDepth {
  /// 元数据 + 文件清单，绝不 startStream、绝不读任何字节的视频数据。
  fast,

  /// 在 fast 之上再读文件头 / 字幕正文（低频、播放中拒绝）。
  deep,
}

/// 探测结果，带来源说明，方便 UI 解释「凭什么这么说」。
class SubtitleProbeResult {
  const SubtitleProbeResult({
    required this.verdict,
    required this.reason,
    this.isExternal = false,
    this.isSimplified = false,
    this.isTraditional = false,
    this.source = SubtitleProbeSource.none,
    this.depth = SubtitleProbeDepth.deep,
  });

  final SubtitleProbeVerdict verdict;

  /// 一句话依据，例如「外挂 2 个简中字幕文件」「内封 1 条 zh 文本字幕轨」。
  final String reason;

  /// 来自种子内独立字幕文件（相对于内封轨）。
  final bool isExternal;

  final bool isSimplified;
  final bool isTraditional;

  final SubtitleProbeSource source;

  final SubtitleProbeDepth depth;

  static const unknown = SubtitleProbeResult(
    verdict: SubtitleProbeVerdict.unknown,
    reason: '未取到可判定的信息',
  );

  bool get hasChinese =>
      verdict == SubtitleProbeVerdict.chineseText ||
      verdict == SubtitleProbeVerdict.chineseImage;

  /// 快速层没能定论时，才值得让用户主动点一下去读内封轨。
  /// 明确结论（有/无中文字幕）和深挖过的结论都不再提供入口。
  bool get canDeepProbe =>
      depth == SubtitleProbeDepth.fast &&
      verdict == SubtitleProbeVerdict.unknown;

  SubtitleProbeResult copyWith({SubtitleProbeDepth? depth}) =>
      SubtitleProbeResult(
        verdict: verdict,
        reason: reason,
        isExternal: isExternal,
        isSimplified: isSimplified,
        isTraditional: isTraditional,
        source: source,
        depth: depth ?? this.depth,
      );
}

/// 一个种子文件（只需路径和大小）。
class ProbeFile {
  const ProbeFile({required this.path, required this.size});

  final String path;
  final int size;

  String get lowerPath => path.toLowerCase();
}

const Set<String> _subtitleExts = {
  '.srt',
  '.ass',
  '.ssa',
  '.vtt',
  '.sub',
  '.idx',
  '.sup',
};

const Set<String> _imageSubtitleExts = {'.sup', '.idx', '.sub'};

const Set<String> _videoExts = {
  '.mkv',
  '.mp4',
  '.avi',
  '.ts',
  '.m2ts',
  '.mov',
  '.wmv',
  '.flv',
  '.webm',
};

/// 从「语言码 + 轨道名 + 文件名」综合判简繁。
///
/// 🔴 2026-11-08 修复三个真实漏洞：
/// 1. 旧版只认 `hans`/`hant`，`chs`/`cht` 明明 `isChinese` 认，简繁却不认；
/// 2. MKV 的 TrackName（「简体中文」「Simplified」「GB」）解析出来了却没参与判定；
/// 3. PGS 图形字幕分支根本不判简繁。
///
/// `sc`/`tc` 这类两字母标记必须**独立成词**才算，否则
/// `The.Wandering.Earth.srt` 里的字母组合会被误命中。
final RegExp _simplifiedWordRe = RegExp(
  r'(^|[^a-z])(chs|sc|gb|gbk|hans|zh-cn|zh_cn|zh-sg|zh_sg|zh-hans|simplified)([^a-z]|$)',
);

final RegExp _traditionalWordRe = RegExp(
  r'(^|[^a-z])(cht|tc|big5|hant|zh-tw|zh_tw|zh-hk|zh_hk|zh-hant|traditional)([^a-z]|$)',
);

bool _hasSimplifiedMark(String s) {
  if (s.contains('简体') ||
      s.contains('简中') ||
      s.contains('简日') ||
      s.contains('国标')) {
    return true;
  }
  return _simplifiedWordRe.hasMatch(s);
}

bool _hasTraditionalMark(String s) {
  if (s.contains('繁体') ||
      s.contains('繁中') ||
      s.contains('繁日') ||
      s.contains('正体')) {
    return true;
  }
  return _traditionalWordRe.hasMatch(s);
}

/// 判简繁。输入可以是文件名、语言码，或「语言码 + 轨道名」拼起来的串。
/// 「简繁」「CHS+CHT」这类同时命中时返回 [ChineseScript.both]。
ChineseScript classifyChineseScript(String raw) {
  final s = raw.toLowerCase();
  if (s.contains('简繁') ||
      s.contains('chs_cht') ||
      s.contains('chs.cht') ||
      s.contains('chs+cht') ||
      s.contains('sc_tc') ||
      s.contains('sc+tc')) {
    return ChineseScript.both;
  }
  final simplified = _hasSimplifiedMark(s);
  final traditional = _hasTraditionalMark(s);
  if (simplified && traditional) return ChineseScript.both;
  if (simplified) return ChineseScript.simplified;
  if (traditional) return ChineseScript.traditional;
  return ChineseScript.unspecified;
}

/// 一组候选（多个字幕文件 / 多条轨道）合并后的简繁结论。
ChineseScript mergeScript(Iterable<ChineseScript> values) {
  var simplified = false;
  var traditional = false;
  for (final v in values) {
    if (v == ChineseScript.simplified || v == ChineseScript.both) {
      simplified = true;
    }
    if (v == ChineseScript.traditional || v == ChineseScript.both) {
      traditional = true;
    }
  }
  if (simplified && traditional) return ChineseScript.both;
  if (simplified) return ChineseScript.simplified;
  if (traditional) return ChineseScript.traditional;
  return ChineseScript.unspecified;
}

bool _flag(ChineseScript script, bool simplified) => script == ChineseScript.both ||
    (simplified
        ? script == ChineseScript.simplified
        : script == ChineseScript.traditional);

/// 主判定。
///
/// [files] 是种子里全部文件；[mkvTracks] 只在「只有一个视频文件」时才有值
/// （多文件种子里的内封字幕不做解析，成本高且少见）。
/// [externalTextIsChinese] 由调用方在「外挂字幕文件名没有语言标记」时读正文
/// CJK 实证得到；为 null 表示没有做过正文校验。
/// [fileListOnly] = 快速层：只看文件清单，绝不下「读不到文件头」这种结论
/// （快速层压根没去读），而是诚实写「可能有内封轨」。
SubtitleProbeResult judgeSubtitle({
  required List<ProbeFile> files,
  MkvTrackParseResult? mkvTracks,
  bool? externalTextIsChinese,
  bool fileListOnly = false,
}) {
  if (files.isEmpty) return SubtitleProbeResult.unknown;

  // ---- 1. 种子内独立字幕文件 ----
  final subs = files
      .where((f) => _subtitleExts.any((e) => f.lowerPath.endsWith(e)))
      .toList(growable: false);

  if (subs.isNotEmpty) {
    final imageOnly = subs.every(
      (f) => _imageSubtitleExts.any((e) => f.lowerPath.endsWith(e)),
    );
    final fileScript = mergeScript(
      subs.map((f) => classifyChineseScript(f.lowerPath)),
    );
    final names = subs.map((f) => f.path.split('/').last).take(2).join('、');
    final more = subs.length > 2 ? ' 等 ${subs.length} 个' : '';

    // 🔴 有字幕文件 ≠ 有中文字幕。种子里的 `.srt` 完全可能是英文/俄文，
    // 文件名没有任何中文标记时**不能**判成「有中文字幕」——那是在猜。
    // 但如果有正文 CJK 实证，就可以给「中文（简繁未分）」的诚实结论。
    if (fileScript == ChineseScript.unspecified) {
      if (externalTextIsChinese == true) {
        return SubtitleProbeResult(
          verdict: imageOnly
              ? SubtitleProbeVerdict.chineseImage
              : SubtitleProbeVerdict.chineseText,
          reason: '外挂字幕正文含中文：$names$more',
          isExternal: true,
          source: SubtitleProbeSource.subtitleText,
        );
      }
      if (externalTextIsChinese == false) {
        return const SubtitleProbeResult(
          verdict: SubtitleProbeVerdict.noChinese,
          reason: '外挂字幕正文不含中文',
          isExternal: true,
          source: SubtitleProbeSource.subtitleText,
        );
      }
      return SubtitleProbeResult(
        verdict: SubtitleProbeVerdict.unknown,
        reason: '有外挂字幕但语言未标注：$names$more',
        isExternal: true,
        source: SubtitleProbeSource.fileList,
      );
    }

    return SubtitleProbeResult(
      verdict: imageOnly
          ? SubtitleProbeVerdict.chineseImage
          : SubtitleProbeVerdict.chineseText,
      reason: '外挂字幕：$names$more',
      isExternal: true,
      isSimplified: _flag(fileScript, true),
      isTraditional: _flag(fileScript, false),
      source: SubtitleProbeSource.fileList,
    );
  }

  // ---- 2. 内封字幕轨（只对单视频文件解析）----
  final videos =
      files.where((f) => _videoExts.any((e) => f.lowerPath.endsWith(e))).toList();
  if (videos.isEmpty) {
    return const SubtitleProbeResult(
      verdict: SubtitleProbeVerdict.unknown,
      reason: '种子里没有识别到视频文件',
      source: SubtitleProbeSource.fileList,
    );
  }

  if (fileListOnly || mkvTracks == null || !mkvTracks.foundTracksElement) {
    final multi = videos.length > 1;
    String reason;
    if (fileListOnly) {
      reason = multi
          ? '多文件种子，未确认内封轨'
          : '种子内未见独立字幕文件，可能有内封轨';
    } else {
      reason = multi ? '多文件种子，未解析内封轨' : '未读到文件头';
    }
    return SubtitleProbeResult(
      verdict: SubtitleProbeVerdict.unknown,
      reason: reason,
      source: SubtitleProbeSource.fileList,
    );
  }

  final subtitleTracks = mkvTracks.subtitleTracks;
  if (subtitleTracks.isEmpty) {
    return const SubtitleProbeResult(
      verdict: SubtitleProbeVerdict.noChinese,
      reason: '内封无字幕轨',
      source: SubtitleProbeSource.mkvTracks,
    );
  }

  final chineseTracks = subtitleTracks.where((t) => t.isChinese).toList();
  if (chineseTracks.isEmpty) {
    final langs = subtitleTracks
        .map((t) => t.language.isEmpty ? '未标注' : t.language)
        .toSet()
        .join('/');
    return SubtitleProbeResult(
      verdict: SubtitleProbeVerdict.noChinese,
      reason: '内封字幕轨语言：$langs',
      source: SubtitleProbeSource.mkvTracks,
    );
  }

  // 语言码 + 轨道名一起判简繁。只写 `zho`/`chi`/`zh` 时保持 unspecified，
  // 不把「不知道」说成「简中」。
  final script = mergeScript(
    chineseTracks.map(
      (t) => classifyChineseScript(
        '${t.language} ${t.name ?? ''}'.toLowerCase(),
      ),
    ),
  );
  final hasText = chineseTracks.any((t) => t.isTextSubtitle);
  return SubtitleProbeResult(
    verdict:
        hasText ? SubtitleProbeVerdict.chineseText : SubtitleProbeVerdict.chineseImage,
    reason: '内封 ${chineseTracks.length} 条中文字幕轨（${chineseTracks.first.codecId}）',
    isSimplified: _flag(script, true),
    isTraditional: _flag(script, false),
    source: SubtitleProbeSource.mkvTracks,
  );
}

/// 徽标文案。**必须一眼能判断「有没有中文字幕、是什么字幕」**——
/// 这是用户决定点不点进来的依据。
///
/// 文案结构：`形态 + 简繁`（如「内封简中」「外挂繁中」），四个字以内，
/// 保证在搜索列表的窄徽标里不被截断。
///
/// 🔴 没判出简繁时只能说「中字」，不能默认说「简中」。
String subtitleVerdictLabel(SubtitleProbeResult result) {
  final form = result.isExternal ? '外挂' : '内封';
  switch (result.verdict) {
    case SubtitleProbeVerdict.chineseText:
      if (result.isSimplified && result.isTraditional) return '$form简繁中';
      if (result.isSimplified) return '$form简中';
      if (result.isTraditional) return '$form繁中';
      return '$form中字';
    case SubtitleProbeVerdict.chineseImage:
      // PGS/VobSub：能看，但取不到文本，字号不可调——要让人知道是图形字幕。
      return '$form图形中字';
    case SubtitleProbeVerdict.noChinese:
      return '无中文字幕';
    case SubtitleProbeVerdict.unknown:
      return '字幕未知';
  }
}

String _sourceLabel(SubtitleProbeSource source) {
  switch (source) {
    case SubtitleProbeSource.title:
      return '依据标题';
    case SubtitleProbeSource.fileList:
      return '依据种子文件清单';
    case SubtitleProbeSource.mkvTracks:
      return '依据 MKV 内封轨道';
    case SubtitleProbeSource.subtitleText:
      return '依据字幕正文';
    case SubtitleProbeSource.none:
      return '';
  }
}

/// tooltip 文案：把「凭什么这么说」摆出来，避免又出现零证据断言。
String subtitleVerdictTooltip(SubtitleProbeResult result) {
  final source = _sourceLabel(result.source);
  if (source.isEmpty) return result.reason;
  return '${result.reason}（$source）';
}

/// 一次探测请求能不能真的去连种子。
///
/// 🔴 真机定案：搜索页是 Column 一次性渲染全部条目，56 条同时 add 种子会
/// 把 BT 连接占满，播放首段缓冲直接从几秒拖到几分钟。所以：
/// - **播放中一律不让行**（含用户主动点徽标，避免抢正在播的 peer）；
/// - 自动探测排队数受配额约束；用户主动的请求不受配额限制。
enum ProbeAdmission {
  run,
  skipPlayback,
  skipQuota,
}

ProbeAdmission admitProbe({
  required bool playbackActive,
  required bool userInitiated,
  required int pending,
  required int maxPending,
}) {
  if (playbackActive) return ProbeAdmission.skipPlayback;
  if (!userInitiated && pending >= maxPending) return ProbeAdmission.skipQuota;
  return ProbeAdmission.run;
}
