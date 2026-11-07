/// 搜索页「磁力资源」中文名解析。
///
/// ## 为什么需要
///
/// 磁力源（1337x / BT4G / YTS / Torrentio…）返回的**资源名几乎全是英文发布名**：
/// `The.Godfather.1972.1080p.BluRay.x264-GROUP`。用户在搜索页看到的磁力卡片
/// 也全是这种英文串，认不出是哪部片子。
///
/// 详情页已经有中文名兜底（磁力详情页顶部「对应本片」标签 + CMS 补全），
/// 但**搜索页没有** —— 搜索页的磁力卡片是独立的渲染路径（`_buildMagnetSearchTile`），
/// 详情页那套补全根本走不到这里。
///
/// ## 数据来源与算法
///
/// 中文名有两个可用来源，**都不需要额外网络请求**：
///
/// 1. **本次搜索已经加载的影视结果**（`_searchResults`，来自 CMS 采集站）。
///    CMS 的 `vod_name` 就是中文片名（实测 `教父` / `肖申克的救赎`），
///    且 `vod_year` 给出年份。磁力资源名里通常也带年份
///    （`The.Godfather.1972...`），**用年份对齐**就能把英文发布名钉到中文片名上。
/// 2. **用户搜索词本身**。用户搜「教父」时，搜索词就是中文名；
///    这条路径对「中文搜英文资源」这种最常见场景是零成本的。
///
/// 两条来源都不命中时返回 null（**宁可不显示，也不要显示错的中文名**）。
///
/// 本文件只放纯函数，方便单测（不依赖网络 / Dio / Provider）。
library;

import '../models/movie.dart';

final RegExp _cjkPattern = RegExp(r'[\u4e00-\u9fff]');

/// 从资源名里抽年份（如 `The.Godfather.1972.1080p` → `1972`）。
///
/// 只取 19xx / 20xx 四位年份，且排除 `1080` / `2160` 这类**画质数字**
/// （它们也是四位，但首两位是 10 / 21，不在 19/20 段内，天然被排除）。
String? extractYearFromTorrentName(String raw) {
  final m = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(raw);
  return m?.group(1);
}

/// 资源名是否含中文（`[国语中字]`、`教父.The.Godfather...` 这类）。
bool torrentNameHasChinese(String raw) => _cjkPattern.hasMatch(raw);

/// 从磁力资源名里抽出「基础标题」（用于跨资源归并 + 查中文名）。
///
/// 例：
/// - `The.Godfather.1972.1080p.BluRay.x264-GROUP` → `The Godfather`
/// - `The Shawshank Redemption 1994 1080p` → `The Shawshank Redemption`
/// - `教父.The.Godfather.1972.1080p` → `The Godfather`（方括号标签被剥掉）
String baseTitleOf(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';

  // 纯画质 / 纯编码标签（`1080p` / `x264` / `bluray`…）没有查中文名的价值。
  if (_pureTagPattern.hasMatch(s)) return '';

  // 去掉方括号 / 圆括号里的标签。
  s = s.replaceAll(RegExp(r'[\[【（(][^\]】）)]*[\]】）)]'), ' ');

  // 🔴 顺序很重要：**先**截掉画质 / 编码标签，**再**剥结尾年份。
  // 反过来的话 `The.Godfather.1972.1080p` 会先被「年份在结尾」规则跳过
  // （结尾是 1080p 不是年份），再截画质 → 剩 `The.Godfather.1972`，
  // 年份就留在了标题里。
  s = s.replaceAll(
    RegExp(
      r'[.\s_-]+(?:4k|2160p|1080p|720p|480p|blu-?ray|bdrip|brrip|dvdrip|'
      r'dvd|web-?dl|webrip|hdtv|remux|x264|x265|h\.?264|h\.?265|hevc|avc|'
      r'aac|ac3|dts|ddp?|flac|hdr|imax|extended|unrated|remastered|'
      r'国语|粤语|中字|双语|简繁|收藏版).*',
      caseSensitive: false,
      dotAll: true,
    ),
    '',
  );

  // 画质截断后可能露出结尾年份（`The.Godfather.1972`）。
  s = s.replaceAll(RegExp(r'[\s._-]+(?:19|20)\d{2}\s*$'), '');

  // 去掉发布组后缀 `-GROUP`。
  s = s.replaceAll(RegExp(r'[-–]\w{2,}$'), '');

  s = s.replaceAll(RegExp(r'[._]+'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

  // 截断后可能只剩画质词（`1080p`）。
  if (s.isEmpty) return '';
  if (_pureTagPattern.hasMatch(s)) return '';
  if (!RegExp(r'[A-Za-z]').hasMatch(s)) return '';
  return s;
}

/// 纯画质 / 纯编码标签（整串就是标签，没有片名）。
final RegExp _pureTagPattern = RegExp(
  r'^(?:4k|8k|2160p|1080p|720p|480p|blu-?ray|bdrip|brrip|dvdrip|dvd|'
  r'web-?dl|webrip|hdtv|remux|x264|x265|h\.?264|h\.?265|hevc|avc|'
  r'aac|ac3|dts|ddp?|flac|hdr|imax)$',
  caseSensitive: false,
);

/// 影视结果（CMS）的中文名是否「足够可信」——用来避免把不相干的条目贴上去。
///
/// 采集站里混着大量「电影解说」「抢先看」「完整版」等**衍生条目**，
/// 它们的中文名不是正片名。命中这些关键词的一律不用。
bool isCanonicalChineseTitle(String name) {
  final n = name.trim();
  if (n.isEmpty) return false;
  if (!_cjkPattern.hasMatch(n)) return false;
  for (final bad in const [
    '电影解说',
    '影视解说',
    '解说',
    '抢先看',
    '抢先版',
    '完整版',
    '未删减',
    '在线观看',
    '完整版在线',
    'BD高清',
    '蓝光',
    '国语',
    '粤语',
    '中字',
    '高清在线',
  ]) {
    if (n.contains(bad)) return false;
  }
  return true;
}

/// 把 CMS 条目的中文名收拾干净（去掉尾部方括号里的备注）。
///
/// 例：`教父[电影解说]` → `教父`；`教父2[完整版]` → `教父2`。
String cleanChineseMovieName(String raw) {
  var n = raw.trim();
  // 反复剥掉尾部 `[]` / `【】` / `（）` 段，直到剥不动（可能有多层）。
  var changed = true;
  while (changed) {
    changed = false;
    final m = RegExp(r'[\[【（(][^\]】）)]*[\]】）)]\s*$').firstMatch(n);
    if (m != null) {
      n = n.substring(0, m.start).trim();
      changed = true;
    }
  }
  return n;
}

/// 为一条磁力资源找出对应的**中文片名**。
///
/// [torrentName] 磁力源返回的资源名（通常是英文发布名）。
/// [searchResults] 本次搜索已加载的影视结果（CMS 采集站，中文名 + 年份）。
/// [query] 用户搜索词（可能是中文，也可能只是英文关键词）。
///
/// 返回 null 表示**没有可信的中文名**——调用方应保持原样，不要瞎猜。
String? resolveChineseTitleForTorrent({
  required String torrentName,
  required List<Movie> searchResults,
  String? query,
}) {
  final raw = torrentName.trim();
  if (raw.isEmpty) return null;

  // 资源名本身就带中文 → 已经是中文名了，不用再贴标签。
  if (torrentNameHasChinese(raw)) return null;

  final year = extractYearFromTorrentName(raw);

  // ── 来源 1：本次搜索的影视结果（CMS），按年份 + 名称相关性对齐 ──
  final fromMovies = _matchFromSearchResults(
    searchResults,
    year: year,
    query: query,
  );
  if (fromMovies != null) return fromMovies;

  // ── 来源 2：用户搜索词本身就是中文 ──
  // 搜「教父」时，磁力源给回来的全是 `The.Godfather...`；
  // 影视源此时可能还没回来（聚合是流式的），但搜索词已经是可靠的中文名。
  //
  // 🔴 但**只有在没有年份证据时**才允许走这条兜底：
  // 若影视结果里带了年份（说明我们确实知道正片是哪一年），
  // 却没能按年份对上（来源 1 返回 null），那就说明这条资源**不是**搜索词
  // 指的那部片子（例如搜「教父」但结果是 `The.Godfather.Part.III.1990`）。
  // 这时再贴「教父」就是把 Part III 认成第一部了 —— 宁可不显示。
  if (!_hasYearEvidence(searchResults)) {
    final fromQuery = chineseNameFromQuery(query);
    if (fromQuery != null) return fromQuery;
  }

  return null;
}

/// 影视结果里是否有年份信息（说明我们掌握了「正片是哪一年」）。
bool _hasYearEvidence(List<Movie> movies) {
  for (final m in movies) {
    final y = m.year.trim();
    if (y.length == 4 && RegExp(r'^\d{4}$').hasMatch(y)) return true;
  }
  return false;
}

/// 从用户搜索词里提取中文片名。
///
/// 搜「教父」→ `教父`；搜「肖申克的救赎 1080p」→ `肖申克的救赎`；
/// 搜「教父 2」→ `教父`（`2` 不是中文，只留中文词）。
///
/// 搜索词没有中文时返回 null（英文搜索词不是中文名）。
String? chineseNameFromQuery(String? query) {
  final q = (query ?? '').trim();
  if (q.isEmpty || !_cjkPattern.hasMatch(q)) return null;

  // 先剥掉方括号里的备注（`教父[电影解说]` → `教父`）。
  final stripped = q.replaceAll(
    RegExp(r'[\[【（(][^\]】）)]*[\]】）)]'),
    ' ',
  );
  // 再按空白切词，只留含中文且像正片名的词。
  final words = stripped
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty && _cjkPattern.hasMatch(e))
      .map(cleanChineseMovieName)
      .where(isCanonicalChineseTitle)
      .toList();
  if (words.isEmpty) return null;
  // 多个中文词时取最长的那个（`肖申克的救赎` 只有一个；`教父 2` → `教父`）。
  words.sort((a, b) => b.length.compareTo(a.length));
  return words.first;
}

/// 在影视结果里找与该磁力资源对应的中文名。
String? _matchFromSearchResults(
  List<Movie> movies, {
  String? year,
  String? query,
}) {
  if (movies.isEmpty) return null;

  final q = (query ?? '').trim();
  final qHasCjk = q.isNotEmpty && _cjkPattern.hasMatch(q);
  // 查询词里的核心中文片名（剥掉「1080p」「2019」这类噪音）。
  final qCore = qHasCjk ? (chineseNameFromQuery(q) ?? q) : '';

  // 🔴 中文查询 + 资源名里没有年份 → **无法判断这条资源到底是不是这部片**。
  //
  // 中文查询下，磁力名是英文、CMS 名是中文，两边无法直接比对片名，
  // 年份是唯一的交叉证据。没有年份就没有证据，宁可不贴标签
  // （用户看到英文原名，也不会看到错的中文名）。
  if (qHasCjk && year == null) return null;

  Movie? best;
  var bestScore = 0;
  for (final m in movies) {
    // 🔴 canonicality 判定必须用**原始名**（带方括号备注），
    // 先剥备注会把 `教父[电影解说]` 变成 `教父` —— 那样解说视频就被
    // 当成正片名贴上去了，等于贴了个错的名字。
    if (!isCanonicalChineseTitle(m.name)) continue;
    final name = cleanChineseMovieName(m.name);
    if (name.isEmpty) continue;

    final mYear = m.year.trim();
    final yearHit = year != null && mYear == year;

    // 年份冲突（双方都有年份却对不上）→ 直接淘汰。
    // `The.Wandering.Earth.2018` 与 CMS《流浪地球》(2019) 本就对不上。
    if (year != null && mYear.isNotEmpty && mYear != year) continue;

    var score = 0;
    if (qHasCjk) {
      // 🔴 中文查询：**片名相关是必要条件**，年份只是加分。
      //
      // 旧实现给「年份一致」+100、片名相关只 +30，门槛才 10 分 ——
      // 于是任何**同年**的 CMS 条目都能把中文名抢走。2026-10-27 真机实测：
      // 搜「流浪地球」时 `The.Wandering.Earth.2018` 被标成
      // 《环太平洋：雷霆再起》(2018)，因为两者年份都是 2018。
      // 现在片名不相关直接跳过：宁可不显示，也不要显示错的名字。
      if (qCore.isEmpty) continue;
      // 🔴 必须是**片名互相包含**才算命中，不能「共享一两个字」就放行。
      //
      // 2026-10-27 真机实测踩到：搜「流浪地球」时，《流浪兄妹：认个爹爹当守护》
      // 只因为共享「流浪」两个字就被判为相关，再靠年份拿分，把
      // `The.Wandering.Earth.2018` 标成了「流浪兄妹」。共享字的匹配太松 ——
      // 宁可不显示，也不要显示错的名字。
      if (name.contains(qCore) || qCore.contains(name)) {
        score += 60;
      } else {
        continue;
      }
    } else {
      // 英文查询：CMS 结果本身已被查询词限定（搜 Inception 只回相关条目），
      // 中文名无法与英文发布名直接比对，年份是唯一可用证据。
      if (!yearHit) continue;
      score += 60;
    }

    if (yearHit) score += 40;
    // 有中文简介说明这是正经条目，同分时优先。
    if (m.description.trim().length > 40) score += 5;

    if (score > bestScore) {
      bestScore = score;
      best = m;
    }
  }

  if (best == null) return null;
  return cleanChineseMovieName(best.name);
}

/// 两个中文串是否共享「核心字」（去掉「的」「之」「：」等连接字后有交集）。
///
/// ⚠️ **当前未被使用**：2026-10-27 真机实测证明这个判据太松
/// （`流浪地球` 与 `流浪兄妹` 共享「流浪」即被判为相关，导致错贴中文名）。
/// 保留函数仅供后续需要「同系列」判定时参考，不要直接拿它当片名匹配。
// ignore: unused_element
bool _sharesCjkCore(String a, String b) {
  const stop = {'的', '之', '：', ':', '了', '与', '和'};
  final ca = a.split('').where((c) => _cjkPattern.hasMatch(c) && !stop.contains(c)).toSet();
  final cb = b.split('').where((c) => _cjkPattern.hasMatch(c) && !stop.contains(c)).toSet();
  if (ca.isEmpty || cb.isEmpty) return false;
  return ca.intersection(cb).isNotEmpty;
}
