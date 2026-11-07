import '../../../services/subtitle/subtitle_contract.dart';

/// 字幕语言粗分类。只区分「中文 / 英文 / 其它 / 未知」，
/// 不需要完整 BCP-47 解析——压制组写的语言码本来就不规范。
enum SubtitleLanguage { chinese, english, other, unknown }

const Set<String> _chineseCodes = <String>{
  'zh', 'zho', 'chi', 'zh-cn', 'zh-tw', 'zh-hk', 'zh-sg',
  'chs', 'cht', 'cn', 'chinese', '中文', '简体', '繁体', '中字', '国语',
};

const Set<String> _englishCodes = <String>{
  'en', 'eng', 'en-us', 'en-gb', 'en-au', 'english', '英文', '英语',
};

/// 语言判定：lang 码优先，轨标题兜底。
///
/// 很多压制组不写 lang，只把「简体中文 / Chs / 中英双语」写在 title 里，
/// 所以标题里出现中文线索也算中文轨（双语轨含中文，按中文优先不亏）。
SubtitleLanguage classifySubtitleLanguage(String? lang, {String? title}) {
  final l = (lang ?? '').trim().toLowerCase();
  if (l.isNotEmpty) {
    if (_chineseCodes.contains(l)) return SubtitleLanguage.chinese;
    if (_englishCodes.contains(l)) return SubtitleLanguage.english;
    if (l.startsWith('zh') || l.startsWith('chi')) {
      return SubtitleLanguage.chinese;
    }
    if (l.startsWith('en')) return SubtitleLanguage.english;
  }

  final t = (title ?? '').toLowerCase();
  if (t.contains('中') ||
      t.contains('chinese') ||
      t.contains('chs') ||
      t.contains('cht') ||
      t.contains('双语') ||
      t.contains('bilingual')) {
    return SubtitleLanguage.chinese;
  }
  if (t.contains('english') || t.contains('eng')) {
    return SubtitleLanguage.english;
  }
  if (l.isEmpty && t.isEmpty) return SubtitleLanguage.unknown;
  return SubtitleLanguage.other;
}

bool isChineseSubtitle(SubtitleTrackInfo track) =>
    classifySubtitleLanguage(track.lang, title: track.title) ==
    SubtitleLanguage.chinese;

bool isEnglishSubtitle(SubtitleTrackInfo track) =>
    classifySubtitleLanguage(track.lang, title: track.title) ==
    SubtitleLanguage.english;
