/// 磁力资源「音轨/配音是什么语言」的标题级判定。
///
/// 纯函数，可单测。与 `detectMagnetSubtitle` 并列但**互不代替**：字幕徽标回答
/// 「有没有中文字幕、什么字幕」，本策略回答「这条资源说的是哪种语言」。
///
/// 🔴 为什么必须先把字幕段剥掉：2026-11-08 真机抽检的 Torrentio 发布名大量是
/// `Sub Rus Zho Eng + Original Zho` 这种写法——`Sub ...` 列的是**字幕**语言，
/// `Original ...` 才是**原声音轨**。不剥离的话，「有中文字幕」会被误当成
/// 「中文音轨」，把 `2_English.srt` 误当成「英语发音」。
///
/// 🔴 诚实边界：上游磁力索引（Torrentio / Knaben / Nyaa / YTS）不返回音轨语言
/// 字段，magnet 链接本身也只有 info-hash / 文件名 / tracker。快速探测只看元数据
/// 与文件清单，深度探测读 MKV 头在慢种上大概率超时，所以**标题标记是列表页唯一
/// 能在点进来之前给出答案的依据**。没标记一律 [MagnetAudioLanguage.unknown]，
/// 不把「不知道」写成「非中文」或「英语」。
enum MagnetAudioLanguage {
  /// 国语 / 普通话配音。
  mandarin,

  /// 粤语。
  cantonese,

  /// 国粤双语（两个音轨都在）。
  chineseBilingual,

  /// 中文原声 / 未指明国语还是粤语的中文音轨。
  chinese,

  english,
  japanese,
  korean,
  russian,

  /// 标题写了多语 / 双语，或同时标了两种以上语言。
  multilingual,

  /// 标题和文件名都没写语言。
  unknown,
}

/// 结论依据，用于 tooltip 说明「这个判断从哪来的」。
enum AudioLanguageEvidence { titleMark, fileName, none }

class MagnetAudioLanguageResult {
  const MagnetAudioLanguageResult({
    required this.language,
    required this.evidence,
    required this.hits,
  });

  final MagnetAudioLanguage language;
  final AudioLanguageEvidence evidence;

  /// 命中的标题/文件名标记，原样留给用户核对，避免「黑箱结论」。
  final List<String> hits;

  bool get isKnown => language != MagnetAudioLanguage.unknown;
}

/// `Sub Rus Zho Eng` 这类字幕语言段。`[a-z]{2,4}` 只吃 iso 语言码，
/// `Original` 有 8 个字母不会被吃掉，所以不会误删后面的原声标记。
/// 语言码后面必须紧跟分隔符/词尾，否则 `Original` 会被切成 `orig`+`inal`
/// 两个「语言码」一起吃掉，把真正的原声标记也删没了（单测已锁住这个坑）。
final RegExp _subtitleLanguageSegment = RegExp(
  r'\bsubs?\s+(?:(?:[a-z]{2,4}|chs|cht|sc|tc)'
  r'(?=[/\s+&,\-]|$)[/\s+&,\-]*)+',
  caseSensitive: false,
);

/// 只描述字幕、与音轨无关的标记。
///
/// 注意：这里**不包含**「双语」——`国粤双语` 说的是音轨，`双语字幕` 才是字幕。
/// 顺序刻意「先长后短」：`chs_eng` 这类双语字幕组合必须先整体删掉，
/// 否则先删 `chs` 会残留 `_eng`，被当成英语音轨误判。
const List<String> _subtitleOnlyWords = <String>[
  '简繁英双语外挂', '双语字幕', '双语外挂', 'chs_eng', 'chi_eng',
  'chts_eng', 'cht_eng', 'chs&eng', 'chs eng', 'sc.ass', 'sc.srt',
  'tc.ass', 'tc.srt', 'sc_ass', 'tc_ass',
  '简体内封', '繁体内封', '中字', '硬字幕', '硬字', '内封', '内嵌', '外挂',
  '简繁', '简体', '繁体', '字幕', 'chs', 'cht', 'big5',
  'subtitles', 'subtitle', 'softsub', 'hardsub', 'hardcoded',
  'embedded', 'internal', 'dualsub', 'dual_sub', 'multi subs',
  'multiple subtitle', 'subrip',
];

final RegExp _zhoCode = RegExp(r'(^|[^a-z])(zho|chi|zh|cmn)([^a-z]|$)');
final RegExp _engCode = RegExp(r'(^|[^a-z])(eng|en)([^a-z]|$)');
final RegExp _jpnCode = RegExp(r'(^|[^a-z])(jap|jpn)([^a-z]|$)');
final RegExp _korCode = RegExp(r'(^|[^a-z])kor([^a-z]|$)');
final RegExp _rusCode = RegExp(r'(^|[^a-z])rus([^a-z]|$)');
final RegExp _originalChinese =
    RegExp(r'\boriginal[\s:_-]*(zho|chi|zh|cmn|chinese)\b');
final RegExp _originalEnglish =
    RegExp(r'\boriginal[\s:_-]*(eng|en|english)\b');
final RegExp _dubbingCode =
    RegExp(r'(^|[^a-z])(mvo|dvo|avo|dubbed|dub)([^a-z]|$)');

const List<String> _subtitleExtensions = <String>[
  '.srt', '.ass', '.ssa', '.vtt', '.sub', '.sup', '.idx', '.pgs',
];

bool _hasAny(String s, List<String> words) {
  for (final w in words) {
    if (s.contains(w)) return true;
  }
  return false;
}

String _stripSubtitleMarks(String raw) {
  var s = raw.toLowerCase().replaceAll(_subtitleLanguageSegment, ' ');
  for (final w in _subtitleOnlyWords) {
    s = s.replaceAll(w, ' ');
  }
  return s;
}

bool _isSubtitleFile(String name) {
  final n = name.toLowerCase();
  for (final ext in _subtitleExtensions) {
    if (n.endsWith(ext)) return true;
  }
  return false;
}

/// 从资源标题（可选：种子内文件名清单）判定音轨语言。
///
/// 标题优先：字幕组把 `[国语]` 写在标题里，比文件名里的 `audio_zho.mka` 更可信。
/// 文件名只在标题完全没线索时兜底，且**跳过字幕文件**，避免 `2_English.srt`
/// 被当成英语发音。
MagnetAudioLanguageResult detectMagnetAudioLanguage(
  String? title, {
  List<String> fileNames = const <String>[],
}) {
  final fromTitle = _detectOne(title ?? '');
  if (fromTitle.isKnown) return fromTitle;

  for (final name in fileNames) {
    if (_isSubtitleFile(name)) continue;
    final r = _detectOne(name);
    if (r.isKnown) {
      return MagnetAudioLanguageResult(
        language: r.language,
        evidence: AudioLanguageEvidence.fileName,
        hits: r.hits,
      );
    }
  }
  return fromTitle;
}

MagnetAudioLanguageResult _detectOne(String raw) {
  final s = _stripSubtitleMarks(raw);
  if (s.trim().isEmpty) {
    return const MagnetAudioLanguageResult(
      language: MagnetAudioLanguage.unknown,
      evidence: AudioLanguageEvidence.none,
      hits: <String>[],
    );
  }

  final langs = <MagnetAudioLanguage>{};
  final hits = <String>[];
  void add(MagnetAudioLanguage language, String mark) {
    langs.add(language);
    hits.add(mark);
  }

  // 「国粤」同时点名两种中文音轨。
  final hasGuoyue = s.contains('国粤');
  final mandarin = hasGuoyue ||
      _hasAny(s, const <String>[
        '国语', '国配', '普通话', '中文配音', '中配', 'mandarin', 'guoyu',
      ]);
  final cantonese = hasGuoyue ||
      _hasAny(s, const <String>['粤语', '粤配', 'cantonese', '广东话']);
  if (mandarin) add(MagnetAudioLanguage.mandarin, hasGuoyue ? '国粤' : '国语');
  if (cantonese) add(MagnetAudioLanguage.cantonese, hasGuoyue ? '国粤' : '粤语');

  // `Original Zho` 是明确的中文原声；与「国语配音」可以并存（多语音轨）。
  final originalChinese = _originalChinese.hasMatch(s);
  final originalEnglish = _originalEnglish.hasMatch(s);
  if (originalChinese) {
    add(MagnetAudioLanguage.chinese, 'Original 中文原声');
  } else if (!mandarin &&
      (_zhoCode.hasMatch(s) ||
          _hasAny(s, const <String>[
            'chinese', '中文', '华语', '汉语', '原声中',
          ]))) {
    add(MagnetAudioLanguage.chinese, '中文标记');
  }

  if (originalEnglish ||
      _engCode.hasMatch(s) ||
      _hasAny(s, const <String>['english', '英语', '英文'])) {
    add(MagnetAudioLanguage.english, '英语标记');
  }
  if (_jpnCode.hasMatch(s) ||
      _hasAny(s, const <String>['japanese', '日语', '日文'])) {
    add(MagnetAudioLanguage.japanese, '日语标记');
  }
  if (_korCode.hasMatch(s) ||
      _hasAny(s, const <String>['korean', '韩语', '韩文'])) {
    add(MagnetAudioLanguage.korean, '韩语标记');
  }
  if (_rusCode.hasMatch(s) ||
      _hasAny(s, const <String>['russian', '俄语', '俄文'])) {
    add(MagnetAudioLanguage.russian, '俄语标记');
  }
  final multiMark = _hasAny(s, const <String>[
    '双语', '双音轨', '多语', '多音轨', 'dual audio', 'dual-audio',
    'dual.audio', 'dual_audio', 'multilang', 'multi audio',
    'multi.audio', 'multi-language',
  ]);
  if (multiMark) add(MagnetAudioLanguage.multilingual, '双语/多语标记');

  // `MVO + DVO + AVO ... Original Zho`：明确标了原声语言 + 额外配音轨，才算多语。
  // 只有 `MVO Rus` 时配音轨和 Rus 说的是同一件事，不能升级成多语；
  // 中文「配音」不在 _dubbingCode 里，所以 `[国语配音]` 也不会被误升级。
  if ((originalChinese || originalEnglish) &&
      _dubbingCode.hasMatch(s) &&
      langs.isNotEmpty) {
    add(MagnetAudioLanguage.multilingual, '配音轨标记');
  }

  MagnetAudioLanguage language;
  if (langs.contains(MagnetAudioLanguage.mandarin) &&
      langs.contains(MagnetAudioLanguage.cantonese)) {
    language = MagnetAudioLanguage.chineseBilingual;
  } else if (multiMark || langs.length >= 2) {
    language = MagnetAudioLanguage.multilingual;
  } else if (langs.length == 1) {
    language = langs.single;
  } else {
    // 有 MVO/DVO/DUBBED 但完全没写语种，也只能是 unknown：不能凭「配音版」
    // 反推是哪国语言。
    language = MagnetAudioLanguage.unknown;
  }

  return MagnetAudioLanguageResult(
    language: language,
    evidence: language == MagnetAudioLanguage.unknown
        ? AudioLanguageEvidence.none
        : AudioLanguageEvidence.titleMark,
    hits: hits,
  );
}

/// 徽标文案（中文）。纯函数，单测锁住文案。
String audioLanguageLabel(MagnetAudioLanguage value) {
  switch (value) {
    case MagnetAudioLanguage.mandarin:
      return '国语';
    case MagnetAudioLanguage.cantonese:
      return '粤语';
    case MagnetAudioLanguage.chineseBilingual:
      return '国粤双语';
    case MagnetAudioLanguage.chinese:
      return '中文原声';
    case MagnetAudioLanguage.english:
      return '英语';
    case MagnetAudioLanguage.japanese:
      return '日语';
    case MagnetAudioLanguage.korean:
      return '韩语';
    case MagnetAudioLanguage.russian:
      return '俄语';
    case MagnetAudioLanguage.multilingual:
      return '多语音轨';
    case MagnetAudioLanguage.unknown:
      return '语言未知';
  }
}

/// tooltip：把依据和边界讲清楚，用户能自己核对，而不是给一个黑箱结论。
String audioLanguageTooltip(MagnetAudioLanguageResult result) {
  if (!result.isKnown) {
    return '标题与文件名都没标注音轨语言，进详情页之前无法确认；'
        '这不等于没有中文音轨。字幕语言请看旁边的字幕徽标。';
  }
  final basis = result.evidence == AudioLanguageEvidence.fileName
      ? '种子内文件名'
      : '资源标题标记';
  return '依据$basis（${result.hits.join('、')}）判断音轨语言为'
      '「${audioLanguageLabel(result.language)}」。'
      '字幕语言另见字幕徽标；标题未写明的语言不代表一定没有。';
}
