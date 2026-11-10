/// 磁力资源「是否自带字幕」的标题级判定。
///
/// 纯函数，可单测。2026-11-06 抽检实证：Nyaa/字幕组种子的标题里会明写
/// 「简体内封」「简繁英双语外挂」「Multiple Subtitle」「BIG5」「国语中字」等，
/// 这是详情页/搜索页能在**不下载种子**的前提下显示字幕状态的唯一低成本依据。
///
/// 诚实边界：标题没写标记 ≠ 一定没有字幕（可能内封但没标），所以无标记时
/// 文案用「未标注字幕」，不能写「无字幕」。
enum MagnetSubtitleAvailability {
  /// 简体内封轨（MKV 内封，mpv track-list 能直接读到）。
  simplifiedEmbedded,

  /// 繁体内封轨。
  traditionalEmbedded,

  /// 种子内独立 .ass/.srt 简体字幕。
  simplifiedExternal,

  /// 种子内独立 .ass/.srt 繁体字幕。
  traditionalExternal,

  /// 双语但未指明简繁（如 Multiple Subtitle / 双语字幕）。
  bilingual,

  /// 烧进画面的硬字幕或「国语中字」，没有可挂载的文本轨。
  hardcoded,

  /// 标题用 `Zho` / `Chi` 这类 ISO 语言码写了「有中文字幕」，但没指明简繁。
  ///
  /// Torrentio/Knaben 的发布名常见 `Sub Rus Zho Eng` 这种写法。
  /// 只写语言码不写简繁时，只能说「有中文字幕」，不能说「简中」。
  chineseUnspecified,

  /// 标题里没有任何字幕线索。
  notMarked,
}

const Set<String> _simplifiedTokens = <String>{
  '简体', '简中', '简繁', '简日', 'chs', 'sc', 'gb', 'gbk',
  'simplified', 'jp_sc', 'sc.ass', 'sc.srt', 'zh-cn', 'zh-sg',
};

const Set<String> _traditionalTokens = <String>{
  '繁体', '繁中', '繁日', 'cht', 'tc', 'big5', 'traditional',
  'jp_tc', 'tc.ass', 'tc.srt', 'zh-tw', 'zh-hk',
};

const Set<String> _externalTokens = <String>{
  '外挂', 'external', 'subs', 'subtitle', 'subtitles',
  '.srt', '.ass', '.ssa', '.sub', '.sup',
};

const Set<String> _embeddedTokens = <String>{
  '内封', '内嵌', 'embedded', 'internal', 'softsub',
};

const Set<String> _bilingualTokens = <String>{
  '双语', 'bilingual', 'dualsub', 'dual_sub', 'multiple subtitle',
  'multi subs', 'chs_eng', 'chi_eng',
};

const Set<String> _hardcodedTokens = <String>{
  '硬字幕', '中字', '硬字', 'hardsub', 'hardcoded', '内置字幕',
};

bool _containsAny(String lower, Set<String> tokens) {
  for (final t in tokens) {
    if (lower.contains(t)) return true;
  }
  return false;
}

/// `zho` / `chi` 必须独立成词才算中文标记。
///
/// 直接 `contains` 会误命中：`chill`、`zhone` 这类无关词在发布名里并不罕见。
bool _hasChineseLanguageCode(String lower) {
  return RegExp(r'(^|[^a-z])(zho|chi)([^a-z]|$)').hasMatch(lower);
}

/// 从种子标题判定字幕形态。大小写不敏感，空标题返回 [notMarked]。
///
/// 判定顺序刻意把「简体」放在「繁体」前面：像 `[简繁英双语外挂]` 同时含
/// 简/繁线索时，按用户「简体中文优先」的要求归到简体。
MagnetSubtitleAvailability detectMagnetSubtitle(String? title) {
  final lower = (title ?? '').trim().toLowerCase();
  if (lower.isEmpty) return MagnetSubtitleAvailability.notMarked;

  final simplified = _containsAny(lower, _simplifiedTokens);
  final traditional = _containsAny(lower, _traditionalTokens);
  final external = _containsAny(lower, _externalTokens);
  final embedded = _containsAny(lower, _embeddedTokens);
  final hardcoded = _containsAny(lower, _hardcodedTokens);
  final bilingual = _containsAny(lower, _bilingualTokens);

  // 「国语中字」这类是烧进画面的硬字幕，标题里没有可挂载的轨/文件，
  // 优先级低于明确写了「内封 / 外挂」的资源。
  if (hardcoded && !embedded && !external) {
    return MagnetSubtitleAvailability.hardcoded;
  }

  if (simplified) {
    if (external) return MagnetSubtitleAvailability.simplifiedExternal;
    if (embedded) return MagnetSubtitleAvailability.simplifiedEmbedded;
    // 只写了「简体」没写形态：字幕组资源通常是内封，按内封展示但文案不含形态。
    return MagnetSubtitleAvailability.simplifiedEmbedded;
  }
  if (traditional) {
    if (external) return MagnetSubtitleAvailability.traditionalExternal;
    if (embedded) return MagnetSubtitleAvailability.traditionalEmbedded;
    return MagnetSubtitleAvailability.traditionalEmbedded;
  }
  if (bilingual) return MagnetSubtitleAvailability.bilingual;
  if (embedded || external) return MagnetSubtitleAvailability.bilingual;

  // 只写了 `Zho`/`Chi` 语言码：确实是中文字幕，但简繁未知。
  if (_hasChineseLanguageCode(lower)) {
    return MagnetSubtitleAvailability.chineseUnspecified;
  }

  return MagnetSubtitleAvailability.notMarked;
}

/// 列表/详情页徽标文案（中文）。纯函数，方便单测锁住文案。
String subtitleAvailabilityLabel(MagnetSubtitleAvailability value) {
  switch (value) {
    case MagnetSubtitleAvailability.simplifiedEmbedded:
      return '简中内封';
    case MagnetSubtitleAvailability.traditionalEmbedded:
      return '繁中内封';
    case MagnetSubtitleAvailability.simplifiedExternal:
      return '简中外挂';
    case MagnetSubtitleAvailability.traditionalExternal:
      return '繁中外挂';
    case MagnetSubtitleAvailability.bilingual:
      return '自带双语字幕';
    case MagnetSubtitleAvailability.hardcoded:
      return '中字硬字幕';
    case MagnetSubtitleAvailability.chineseUnspecified:
      return '有中文字幕';
    case MagnetSubtitleAvailability.notMarked:
      return '未标注字幕';
  }
}

/// 是否明确带中文字幕（含硬字幕）。用于配色与「有字幕」筛选。
bool hasChineseSubtitleMark(MagnetSubtitleAvailability value) =>
    value != MagnetSubtitleAvailability.notMarked;

/// 是否是可直接挂载的简体文本轨/文件（「能直接拿到就直接用」的判定）。
bool hasUsableSimplifiedSubtitle(MagnetSubtitleAvailability value) =>
    value == MagnetSubtitleAvailability.simplifiedEmbedded ||
    value == MagnetSubtitleAvailability.simplifiedExternal;
