import '../../../services/subtitle/subtitle_contract.dart';

/// 「简体中文优先」的判定与轻量繁→简转换。
///
/// 2026-11-06 抽检：免费在线字幕源里中文条目大多是 `zht`（繁体），
/// 只按「中文」挑会拿到繁体，不满足用户「需要简体中文」的要求。
/// 因此：① 挑选字幕时简体优先；② 只有繁体时做**无歧义单字**繁→简转换，
/// 转换范围保守（避开「乾/幹」「瞭/了」等多对一字），错了也不造词。

const Set<String> _simplifiedCodes = <String>{
  'zh-cn', 'zh-sg', 'zh-hans', 'hans', 'chs', 'sc', 'zho-cn',
  '简体', '简中', '简体中文', 'simplified', 'simp',
};

const Set<String> _traditionalCodes = <String>{
  'zh-tw', 'zh-hk', 'zh-hant', 'hant', 'cht', 'tc', 'zht',
  '繁体', '繁中', '繁體', '繁體中文', 'traditional', 'big5',
};

/// 中性中文码（压制组常只写 zh / zho / chi / chinese），无法据此判简繁。
const Set<String> _neutralChineseCodes = <String>{
  'zh', 'zho', 'chi', 'chinese', '中文', 'cn',
};

enum ChineseVariant { simplified, traditional, neutral, notChinese }

/// 判定一条字幕是简体 / 繁体 / 中文未分简繁 / 非中文。
/// lang 优先，title 与 fileName 兜底；`sc.ass` / `tc.ass` 这类文件名很常见。
ChineseVariant classifyChineseVariant({
  String? lang,
  String? title,
  String? fileName,
}) {
  final parts = <String>[
    (lang ?? '').trim().toLowerCase(),
    (title ?? '').trim().toLowerCase(),
    (fileName ?? '').trim().toLowerCase(),
  ];

  // lang 明确写简/繁时直接采信，标题里的剧名可能含「繁」等字造成误判。
  final l = parts.first;
  if (_traditionalCodes.contains(l)) return ChineseVariant.traditional;
  if (_simplifiedCodes.contains(l)) return ChineseVariant.simplified;

  for (final p in parts.skip(1)) {
    if (_traditionalCodes.any((t) => p.contains(t))) {
      return ChineseVariant.traditional;
    }
    if (_simplifiedCodes.any((t) => p.contains(t))) {
      return ChineseVariant.simplified;
    }
  }
  if (_neutralChineseCodes.contains(l) || l.startsWith('zh')) {
    return ChineseVariant.neutral;
  }
  for (final p in parts.skip(1)) {
    if (p.contains('chinese') || p.contains('中文') || p.contains('中字')) {
      return ChineseVariant.neutral;
    }
  }
  return ChineseVariant.notChinese;
}

/// 排序权重：简体 0 < 中文未分 1 < 繁体 2 < 非中文 3。
int simplifiedRankOf(SubtitleTrackInfo track) {
  switch (classifyChineseVariant(lang: track.lang, title: track.title)) {
    case ChineseVariant.simplified:
      return 0;
    case ChineseVariant.neutral:
      return 1;
    case ChineseVariant.traditional:
      return 2;
    case ChineseVariant.notChinese:
      return 3;
  }
}

/// 中文轨按「简体优先」稳定排序，非中文轨保持原顺序排在后面。
List<SubtitleTrackInfo> sortChineseTracksSimplifiedFirst(
  List<SubtitleTrackInfo> tracks,
) {
  final indexed = <({int i, SubtitleTrackInfo t, int rank})>[
    for (var i = 0; i < tracks.length; i++)
      (i: i, t: tracks[i], rank: simplifiedRankOf(tracks[i])),
  ];
  indexed.sort((a, b) {
    final byRank = a.rank.compareTo(b.rank);
    return byRank != 0 ? byRank : a.i.compareTo(b.i);
  });
  return indexed.map((e) => e.t).toList();
}

/// 无歧义的繁→简**单字对**（每两个字符一组：繁、简）。
///
/// 只收一对一且不会改变词义的常用字，避开「乾/幹」「瞭/了」「髮/發」
/// 这类一对多字。用字符串对而不是 Map 字面量，避免重复键触发 lint。
const String _t2sPairs =
    '們们這这個个時时為为會会說说對对樣样裡里後后來来過过還还進进沒没點点無无與与於于嗎吗麼么種种隻只'
    '條条張张開开關关門门問问間间聞闻學学覺觉應应該该當当實实際际現现發发見见觀观讓让給给從从將将卻却'
    '離离東东車车馬马鳥鸟魚鱼書书畫画買买賣卖錢钱銀银鐵铁長长陽阳陰阴雲云電电腦脑話话語语讀读寫写聽听'
    '聲声樂乐歡欢愛爱親亲節节歲岁數数萬万億亿擔担據据準准備备複复雜杂單单雙双變变邊边達达運运動动靜静'
    '態态質质產产業业務务員员團团隊队戰战爭争勝胜敗败記记憶忆錯错誤误題题義义氣气壓压幫帮護护衛卫導导'
    '師师醫医藥药療疗檢检驗验測测試试結结論论證证顯显標标確确認认識识選选擇择決决議议報报紙纸聯联絡络'
    '繫系統统組组織织構构製制創创舊旧壞坏亂乱穩稳續续斷断連连絕绝難难簡简體体國国內内嚴严緊紧鬆松軟软'
    '歷历傳传習习慣惯風风險险驚惊訝讶異异農农誰谁雖虽經经剛刚夠够須须辦办別别圖图場场處处幾几兩两規规'
    '訪访評评譯译頭头寶宝盡尽層层屬属廳厅廣广廠厂環环顏颜麗丽華华夢梦樓楼橋桥鄉乡鎮镇縣县區区灣湾島岛'
    '遠远寬宽闊阔淺浅強强壽寿靈灵願愿貢贡獻献讚赞揚扬舉举參参減减價价費费帳账戶户簽签維维細细紅红綠绿'
    '藍蓝黃黄';

final Map<String, String> _t2s = () {
  final m = <String, String>{};
  for (var i = 0; i + 1 < _t2sPairs.length; i += 2) {
    m[_t2sPairs[i]] = _t2sPairs[i + 1];
  }
  return m;
}();

/// 轻量繁→简转换。只替换表内单字，不做词级转换，也不改 SRT 时间轴。
/// 传入简体内容时保持原样（表里没有简体键）。
String traditionalToSimplified(String text) {
  if (text.isEmpty) return text;
  final buf = StringBuffer();
  for (final ch in text.split('')) {
    buf.write(_t2s[ch] ?? ch);
  }
  return buf.toString();
}
