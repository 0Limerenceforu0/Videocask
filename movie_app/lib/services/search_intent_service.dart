import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'search_type_word.dart';

/// 搜索词的**语义角色**。
///
/// 为什么需要它（2026-10-28 用户反馈「怎么跟二极管一样」）：
/// 为了修「搜《死侍》却出来《战狼》」，搜索结果加了一道「片名相关性过滤」，
/// 关键词与片名对不上就丢弃。这条规则对**片名**是对的，但同一个搜索框还要
/// 承担另外两种完全不同的查询：
///
/// * 「周星驰」——关键词是人名，结果片名里当然不含「周星驰」；
/// * 「科幻」  ——关键词是类型，结果片名里当然也不含「科幻」。
///
/// 一刀切下去，修复了错配，同时把这两种能力也砍掉了。真正的解法不是
/// 「严格 / 宽松」二选一，而是**先判断这次查询是哪种语义，再选对应的
/// 检索通道和过滤字段**：
///
/// | 语义     | 检索通道                       | 过滤字段        |
/// |----------|--------------------------------|-----------------|
/// | category | `ac=detail&t=<分类>`（已有）    | 无需过滤        |
/// | genre    | `ac=detail&t=<类型子类>`        | 无需过滤        |
/// | person   | 人名 → 代表作 → 逐部按片名搜    | 按作品名，非关键词 |
/// | title    | `wd=<关键词>`                   | 片名相关性（严格）|
enum SearchIntentKind {
  /// 一级分类词（「电影」「动漫」）。
  category,

  /// 细分类型词（「科幻」「动作」）。
  genre,

  /// 人名（演员 / 导演）。
  person,

  /// 片名 / 其它自由文本（默认）。
  title,
}

/// 一条「人物代表作」——名字拿去源站按片名搜索。
class PersonWork {
  final String title;
  final String year;
  final String posterUrl;

  /// 豆瓣里的 `work.type == 'tv'`（电视剧 / 综艺 / 纪录片剧集）。
  ///
  /// 2026-10-28 用户要求「电视剧、综艺等都要」，同时要求「电影先出」：
  /// 作品全集一次请求就能拿到两类，但**检索要分两阶段**——先把电影跑完
  /// 投递出去，剧集在后台补进来，用户不用等 130 部串行查完才看到东西。
  final bool isTv;

  const PersonWork({
    required this.title,
    this.year = '',
    this.posterUrl = '',
    this.isTv = false,
  });
}

/// 人名识别结果。
class PersonHit {
  final String name;

  /// 豆瓣人物 id（仅用于日志/去重，不参与检索）。
  final String doubanId;

  /// 英文名（如 Stephen Chow），用于查英文名发布资源。
  final String englishName;

  /// 豆瓣在同一响应里给出的代表作（按豆瓣返回顺序）。
  final List<PersonWork> works;

  const PersonHit({
    required this.name,
    this.doubanId = '',
    this.englishName = '',
    this.works = const [],
  });

  bool get hasWorks => works.isNotEmpty;
}

/// 人名探测的三态结果（2026-10-28）。
///
/// 为什么需要这个：`detectPerson` 返回 null 有两种完全不同的含义 ——
/// 「豆瓣明确说这个词不是人物」和「网络失败 / 熔断，我不知道」。
/// 搜索页对两者的处理必须不同：
/// * 明确不是人物 → 按片名处理（严格相关性过滤 + 照常搜磁力）；
/// * 不知道 → 按人名放宽（不过滤，否则会把演员结果杀光）。
class PersonProbe {
  const PersonProbe.person(PersonHit this.hit) : failed = false;
  const PersonProbe.notPerson()
      : hit = null,
        failed = false;
  const PersonProbe.unknown()
      : hit = null,
        failed = true;

  final PersonHit? hit;

  /// true = 探测失败（网络 / 结构异常 / 熔断），结果不可信。
  final bool failed;

  bool get isPerson => hit != null;
}

/// 一次查询的语义解析结果。
class SearchIntent {
  final SearchIntentKind kind;

  /// 归一化后的检索词。
  ///
  /// * category / genre：类型词本身（「动漫」「科幻」）；
  /// * person：人名；
  /// * title：用户原词。
  final String term;

  final PersonHit? person;

  const SearchIntent({
    required this.kind,
    required this.term,
    this.person,
  });

  bool get isPerson => kind == SearchIntentKind.person && person != null;
}

/// 判断搜索词属于「片名 / 类型 / 分类 / 人名」中的哪一种。
///
/// 分类词和类型词查本地词表（同步、零成本）；人名必须问一次豆瓣联想
/// （它会把 `type=celebrity` 的条目和该人的作品一起返回），因此只在
/// 「看起来像人名」时才发请求，避免每敲一个字都打一次豆瓣。
class SearchIntentService {
  SearchIntentService._();
  static final SearchIntentService instance = SearchIntentService._();

  static final RegExp _cjkPattern = RegExp(r'[\u4e00-\u9fff]');

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 8),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://movie.douban.com/',
        'Accept': 'application/json,*/*;q=0.8',
      },
    ),
  );

  /// 解析查询语义。
  ///
  /// [probePerson] 为 false 时跳过人名探测（调用方已知不需要，如详情页磁力搜索）。
  Future<SearchIntent> resolve(
    String query, {
    bool probePerson = true,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return const SearchIntent(kind: SearchIntentKind.title, term: '');
    }

    // 1) 一级分类词（「动漫」「纪录片」）——本地词表，零成本。
    final category = SearchTypeWord.categoryOf(q);
    if (category != null) {
      return SearchIntent(kind: SearchIntentKind.category, term: category);
    }

    // 2) 细分类型词（「科幻」「动作」）——同样本地词表。
    final genre = SearchTypeWord.genreOf(q);
    if (genre != null) {
      return SearchIntent(kind: SearchIntentKind.genre, term: genre);
    }

    // 3) 人名：只在「可能是人名」时问豆瓣。
    if (probePerson && looksLikePersonName(q)) {
      final hit = await detectPerson(q);
      if (hit != null) {
        return SearchIntent(
          kind: SearchIntentKind.person,
          term: hit.name,
          person: hit,
        );
      }
    }

    // 4) 其余一律按片名处理（最严格的一条路）。
    return SearchIntent(kind: SearchIntentKind.title, term: q);
  }

  /// 去掉用户输入里的**装饰性标点**，得到真正拿去检索的词。
  ///
  /// 实测（2026-10-28 真机 + 源站）：`wd=《权力的游戏》` 在 ffzy 上
  /// `total=0`，而 `wd=权力的游戏` 有 9 条 —— 采集站的 `wd=` 是逐字匹配，
  /// 书名号/引号/括号会被当成片名的一部分。用户习惯把片名写成《…》，
  /// 不清理就等于「搜不到」。
  ///
  /// 只删「包裹片名」的成对标点，不删片名内部的符号（`蜘蛛侠：英雄归来`
  /// 的冒号在很多源里是片名的一部分，删了反而搜不到）。
  static String stripDecorations(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    for (final ch in _decorationChars) {
      if (s.contains(ch)) s = s.replaceAll(ch, ' ');
    }
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.isEmpty ? raw.trim() : s;
  }

  /// 包裹片名用的成对标点。
  ///
  /// 故意**不用字符类正则**：这一组里同时含半角 `'`/`"`/`[`/`]`/`(`/`)`，
  /// 写成 `r'[...]'` 时 `''` 会把 raw string 截断，后半段退化成普通字符串、
  /// 把 `\[` 的反斜杠吃掉，字符类随即失效（书名号根本匹配不上）。
  static const List<String> _decorationChars = <String>[
    '《', '》', '〈', '〉', '「', '」', '『', '』', //
    '“', '”', '‘', '’', '"', "'", //
    '【', '】', '[', ']', '（', '）', '(', ')',
  ];

  /// 该词是否**值得**问一次豆瓣人名接口。
  ///
  /// 中文 2~6 字、不含四位年份、不含空格/标点。英文人名（Nolan）不走这条路：
  /// 源站本身收录英文片名，按片名搜已能工作，多一次探测反而拖慢首屏。
  static bool looksLikePersonName(String q) {
    final s = q.trim();
    if (s.length < 2 || s.length > 6) return false;
    if (!_cjkPattern.hasMatch(s)) return false;
    if (RegExp(r'\b(19|20)\d{2}\b').hasMatch(s)) return false;
    if (RegExp(r'[\s·,，.。:：!！?？]').hasMatch(s)) return false;
    return true;
  }

  /// 人名探测的硬超时。
  ///
  /// 豆瓣在国内通常 100~300ms，2s 已经足够宽松。设上限是因为这条探测挡在
  /// 「普通片名搜索」前面——它慢一秒，所有搜索都慢一秒。
  static const Duration _probeTimeout = Duration(seconds: 2);

  /// 人物**作品全集**接口的单页超时（2026-10-28）。
  ///
  /// 这个接口比联想接口重得多（一次 50 条、要翻 3 页），真机首字节实测
  /// 1.2s，Dio 冷启动握手后经常贴着 2s。沿用 [_probeTimeout] 的结果是
  /// 每次都超时 → 回退成「4 部代表作」，用户侧看到的是「搜周星驰只有
  /// 105 条、一半是关键词噪声、导演作品一部都没有」。
  static const Duration _worksTimeout = Duration(seconds: 10);

  /// 连续失败多少次后熔断（豆瓣被墙/反爬时不要每次都白等 2s）。
  static const int _failureLimit = 3;

  /// 熔断持续时间。
  static const Duration _circuitCooldown = Duration(seconds: 60);

  int _consecutiveFailures = 0;
  DateTime? _circuitOpenedAt;

  bool get _circuitOpen {
    final at = _circuitOpenedAt;
    if (at == null) return false;
    if (DateTime.now().difference(at) > _circuitCooldown) {
      // 冷却结束，放行一次试探。
      _circuitOpenedAt = null;
      _consecutiveFailures = 0;
      return false;
    }
    return true;
  }

  /// 问一次豆瓣联想，判断这个词是不是人名，并顺带拿到代表作。
  ///
  /// 实测（2026-10-28）：`q=周星驰` 返回
  /// `[{type:celebrity,title:周星驰,id:1048026},
  ///   {type:movie,title:功夫女足}, {type:movie,title:少林足球}, …]`
  /// —— 人物条目排第一，后面就是这个人的作品，一次请求两件事都办了。
  Future<PersonHit?> detectPerson(String query) async =>
      (await probePerson(query)).hit;

  /// 人名探测的**三态**结果（2026-10-28）。
  ///
  /// [detectPerson] 把「豆瓣明确说这不是人物」和「网络失败 / 熔断」
  /// 求值成同一个 null，调用方分不清两者，只能一律按片名处理 ——
  /// 于是探测一超时，搜索页就会对「周星驰」做严格片名相关性过滤，
  /// 把源站已经命中的演员结果全部杀掉（实测 `wd=周星驰` 在量子资源
  /// 能出 20 部）。这里把失败单独暴露出来，让调用方能「按人名放宽」。
  Future<PersonProbe> probePerson(String query) async {
    final q = query.trim();
    // 空词/熔断期都不算「明确不是人名」——属于「不知道」。
    if (q.isEmpty || _circuitOpen) return const PersonProbe.unknown();
    try {
      final resp = await _dio
          .get<dynamic>(
            'https://movie.douban.com/j/subject_suggest'
            '?q=${Uri.encodeComponent(q)}',
          )
          .timeout(_probeTimeout);
      _consecutiveFailures = 0;
      final data = resp.data;
      // 返回结构不对，同样是「不知道」而不是「没有人」。
      if (data is! List) return const PersonProbe.unknown();
      final hit = parsePersonHit(data, q);
      return hit == null ? const PersonProbe.notPerson() : PersonProbe.person(hit);
    } catch (e) {
      _consecutiveFailures++;
      if (_consecutiveFailures >= _failureLimit) {
        _circuitOpenedAt = DateTime.now();
        debugPrint('人名探测连续失败 $_consecutiveFailures 次，熔断 '
            '${_circuitCooldown.inSeconds}s');
      }
      debugPrint('人名探测失败 ($q): $e');
      return const PersonProbe.unknown();
    }
  }

  /// 从豆瓣联想响应里判定人名（纯函数，供单测直接驱动）。
  ///
  /// 判定条件（宁可漏判也不能误判）：
  /// 1. 存在 `type == celebrity` 且**标题与查询词归一化后完全相等**的条目；
  /// 2. 该条目必须排在**前两位**——「功夫」这类词豆瓣首条是电影，
  ///    若某人的别名恰好同名，排在后面的 celebrity 不该抢走这次搜索。
  @visibleForTesting
  static PersonHit? parsePersonHit(List<dynamic> raw, String query) {
    final qn = _norm(query);
    if (qn.isEmpty) return null;

    int? personIndex;
    Map<dynamic, dynamic>? personRaw;
    for (var i = 0; i < raw.length && i < 2; i++) {
      final item = raw[i];
      if (item is! Map) continue;
      if (item['type']?.toString() != 'celebrity') continue;
      if (_norm(item['title']?.toString() ?? '') != qn) continue;
      personIndex = i;
      personRaw = item;
      break;
    }
    if (personIndex == null || personRaw == null) return null;

    final works = <PersonWork>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final type = item['type']?.toString() ?? '';
      if (type != 'movie' && type != 'tv') continue;
      final title = item['title']?.toString().trim() ?? '';
      if (title.isEmpty) continue;
      if (!seen.add(title)) continue;
      works.add(
        PersonWork(
          title: title,
          year: item['year']?.toString().trim() ?? '',
          posterUrl: item['img']?.toString() ?? '',
        ),
      );
      if (works.length >= 8) break;
    }

    return PersonHit(
      name: personRaw['title']?.toString().trim() ?? query.trim(),
      doubanId: personRaw['id']?.toString() ?? '',
      englishName: personRaw['sub_title']?.toString().trim() ?? '',
      works: works,
    );
  }

  /// 豆瓣人物**作品全集**（2026-10-28）。
  ///
  /// 为什么需要它：联想接口 `subject_suggest` 只回 4 部代表作（实测
  /// 「周星驰」= 功夫女足 / 少林足球 / 喜剧之王 / 功夫），拿这个当作品
  /// 列表等于只捞 4 部 —— 真机搜「周星驰」只有 30 条结果，瓶颈就在这里。
  /// 而 rexxar 的作品接口一次 50 条、`total=133`，筛出**电影**有 71 部
  /// （其中 16 部是导演/编剧身份、自己没演）—— 只算「他参演」是 58 部，
  /// 对得上「45 部主演片 + 客串」的口径。
  ///
  /// 只取**电影**（`type == movie`），身份不限（参演 / 客串 / 导演 /
  /// 编剧 / 监制都要，见 [parseWorkEntry]）。[includeTv] 为 true 时连电视剧 /
  /// 综艺一起收（2026-10-28 用户要求「电视剧、综艺等都要」），条目上用
  /// [PersonWork.isTv] 区分，调用方按此分阶段检索（电影先出）。
  ///
  /// 失败一律返回空列表：这条是**增强**通道，不能影响关键词结果。
  Future<List<PersonWork>> fetchPersonWorks(
    String doubanId, {
    int maxWorks = 240,
    bool includeTv = false,
  }) async {
    if (doubanId.isEmpty || _circuitOpen) return const [];
    const pageSize = 50;
    // 豆瓣这个接口最多翻到 150 条左右，再多也没有实际作品。
    const maxStart = 150;
    final out = <PersonWork>[];
    final seen = <String>{};
    try {
      for (var start = 0; start < maxStart && out.length < maxWorks; start += pageSize) {
        final resp = await _dio
            .get<dynamic>(
              'https://m.douban.com/rexxar/api/v2/celebrity/$doubanId/works'
              '?start=$start&count=$pageSize&sortby=vote&mode=grid',
              options: Options(
                headers: {
                  // rexxar 接口对 Referer 敏感，缺了会被判成爬虫。
                  'Referer':
                      'https://m.douban.com/movie/celebrity/$doubanId/',
                },
              ),
            )
            // 不能用 `_probeTimeout`（2s）：那是给联想接口的轻量探测。
            // 真机实测这个接口首字节 1.2s，Dio 首次 TLS 握手后经常贴着 2s，
            // 一超时就整条通道回退成「4 部代表作」—— 真机上表现成
            // 「搜周星驰只有 105 条、全是关键词噪声、导演作品一部都不在」。
            .timeout(_worksTimeout);
        final data = resp.data;
        if (data is! Map) break;
        final works = data['works'];
        if (works is! List || works.isEmpty) break;
        for (final raw in works) {
          if (raw is! Map) continue;
          final work = parseWorkEntry(raw, includeTv: includeTv);
          if (work == null) continue;
          // 按「片名 + 年份」去重：不同年份的同名片（重拍版）是两部作品。
          if (!seen.add('${work.title}|${work.year}')) continue;
          out.add(work);
          if (out.length >= maxWorks) break;
        }
        // 拿满了 / 已经到底（返回条数不足一页）。
        if (works.length < pageSize) break;
      }
      _consecutiveFailures = 0;
      return out;
    } catch (e) {
      debugPrint('人物作品全集获取失败 ($doubanId): $e');
      return out;
    }
  }

  /// 从作品接口的单个条目里解析出一部「他的电影作品」（纯函数，供单测）。
  ///
  /// 返回 null 表示这条不算作品：纯本色出镜、未上映、或不是电影
  /// （除非 [includeTv]）。
  ///
  /// 2026-10-28 用户明确要求：**参演、客串、导演的都要**。所以身份判定
  /// 从「必须有演员身份」放宽成「只要有任何一条非本色身份就留」——
  /// 豆瓣 works 里的身份串是「导演 / 编剧 / 制片人 - 监制 /
  /// 演员 (饰 阿星) / 动作特技 - 动作导演」这类，全收。
  /// 只剔除「纯自己/嘉宾」：那是综艺里以本人身份露面（《锵锵三人行》
  /// 《看见》），不是作品。
  @visibleForTesting
  static PersonWork? parseWorkEntry(
    Map<dynamic, dynamic> raw, {
    bool includeTv = false,
  }) {
    final work = raw['work'];
    if (work is! Map) return null;
    final type = work['type']?.toString() ?? '';
    // 豆瓣 `work.type` 实测只有 movie / tv；综艺归在 tv 下，个别条目给
    // `show`，一并当剧集处理（用户要求「电视剧、综艺等都要」）。
    final isMovieType = type == 'movie';
    final isTvType = const <String>{'tv', 'show', 'variety'}.contains(type);
    if (includeTv ? !(isMovieType || isTvType) : !isMovieType) {
      return null;
    }
    final title = work['title']?.toString().trim() ?? '';
    if (title.isEmpty) return null;

    final roles = (raw['roles'] as List?)
            ?.map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    // 只要不是「纯本色出镜」就留：roles 为空时也保留（个别老片豆瓣
    // 没标身份，直接丢掉会漏片，而这是用户最不能接受的）。
    final onlySelfAppearance = roles.isNotEmpty &&
        roles.every((r) => r.contains('自己') || r.contains('嘉宾'));
    if (onlySelfAppearance) return null;

    final year = work['year']?.toString().trim() ?? '';
    if (year.length == 4) {
      final y = int.tryParse(year);
      // 未上映的（豆瓣挂着 2030 / 2040 这种占位年份）不算作品。
      if (y == null || y > DateTime.now().year) return null;
    }

    return PersonWork(
      title: title,
      year: year.length == 4 ? year : '',
      posterUrl: '',
      isTv: type == 'tv',
    );
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s·《》()（）]'), '');
}
