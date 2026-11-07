/// 采集站分类族解析与本地筛选判定（纯函数，便于单测）。
///
/// 背景（2026-09-29 实测）：
/// 苹果 CMS 采集站的 `ac=detail` 列表接口只认 `t`（单个 type_id），
/// **不认 `class` / `area` 参数**（实测 ffzy / lzi / hongniu 返回结果完全一致）。
/// 更关键的是：主流采集站把影片挂在**子类**（动作片 / 喜剧片 / 剧情片 …），
/// 父类（「电影片」/「电影」）往往是空壳：
///
/// | 源 | t=电影片(1) | t=动作片(6) |
/// | --- | --- | --- |
/// | ffzy | 0 条 | 229 页 |
/// | lzi | 1 条 | 248 页 |
/// | hongniu | 2 条 | 266 页 |
///
/// 因此「电影」必须展开为「父类 + 其全部子类」并发取页再合并，
/// 否则就会出现「影视数量太少」「筛选没反应」的现象。
library;

/// 采集站分类节点。
class CmsCategoryNode {
  const CmsCategoryNode({
    required this.id,
    required this.name,
    this.parentId = 0,
  });

  /// 苹果 CMS `type_id`
  final int id;

  /// 苹果 CMS `type_name`（如「动作片」）
  final String name;

  /// 苹果 CMS `type_pid`，0 表示顶级分类；
  /// 部分站点（hongniu / bdzy）不返回该字段，统一记为 0。
  final int parentId;

  bool get isTop => parentId == 0;

  @override
  String toString() => 'CmsCategoryNode($id, $name, pid=$parentId)';
}

/// 分类名 → 子类名后缀归一（「动作片」→「动作」），用于把 UI 上的类型项映射到站点真实分类。
abstract final class CmsCategoryResolver {
  /// 单个分类展开后的 type_id 上限，避免子类过多时请求爆炸。
  static const int maxTypeIdsPerCategory = 12;

  /// App 侧分类别名（与 `_resolveCategoryTypeIdForMap` 历史行为一致）。
  static const Map<String, List<String>> categoryAliases = {
    '剧集': ['电视剧', '剧集', '连续剧', '国产剧', '韩剧'],
    '电影': ['电影', '影片', '电影片'],
    '动漫': ['动漫', '动漫片', '动画', '动画片'],
    '综艺': ['综艺', '综艺片'],
    '纪录片': ['纪录片', '记录片', '纪录'],
    '短剧': ['短剧', '短剧大全', '爽文短剧', 'AI漫剧'],
  };

  /// 短剧题材类名（部分站点不返回 type_pid，只能靠命名识别）。
  static const Set<String> shortDramaNames = {
    '古装仙侠',
    '现代都市',
    '现代言情',
    '穿越年代',
    '言情总裁',
    '女恋总裁',
    '重生民国',
    '反转爽文',
    '爽文短剧',
    '闪婚离婚',
    '都市脑洞',
    '豪门恩怨',
    '赘婿逆袭',
    '战神归来',
  };

  /// 地区筛选关键词：UI 文案 → 影片 `vod_area` 里可能出现的写法。
  static const Map<String, List<String>> regionKeywords = {
    '中国大陆': ['大陆', '中国'],
    '中国香港': ['香港', '港'],
    '中国台湾': ['台湾', '台'],
    '美国': ['美国', '美'],
    '韩国': ['韩国', '韩'],
    '日本': ['日本', '日'],
    '英国': ['英国', '英'],
    '法国': ['法国', '法'],
    '德国': ['德国', '德'],
    '泰国': ['泰国', '泰'],
    '印度': ['印度', '印'],
  };

  /// 去掉「片 / 剧 / 动漫 / 综艺」等后缀，得到可比较的类型主干。
  static String normalizeGenreName(String raw) {
    var s = raw.trim();
    for (final suffix in const ['动漫', '综艺', '片', '剧']) {
      if (s.length > 2 && s.endsWith(suffix)) {
        s = s.substring(0, s.length - suffix.length);
        break;
      }
    }
    return s;
  }

  /// 判断分类节点是否属于 [category] 族（无 type_pid 时的兜底归类）。
  static bool _belongsTo(String name, String category) {
    final n = name.trim();
    if (n.isEmpty) return false;
    switch (category) {
      case '电影':
        if (n == '电影' || n == '电影片' || n == '影片') return true;
        if (n.contains('动漫') || n.contains('动画')) return false;
        if (n.contains('解说') || n.contains('预告')) return false;
        if (n.contains('纪录') || n.contains('记录')) return false;
        return n.endsWith('片');
      case '剧集':
        if (n == '电视剧' || n == '连续剧' || n == '剧集') return true;
        // 「短剧」「爽文短剧」属于短剧族，不能算剧集。
        if (n.contains('短剧')) return false;
        if (n.contains('解说')) return false;
        return n.endsWith('剧');
      case '综艺':
        return n.contains('综艺');
      case '动漫':
        return n.contains('动漫') || n.contains('动画');
      case '纪录片':
        return n.contains('纪录') || n.contains('记录');
      case '短剧':
        if (n.contains('短剧')) return true;
        return shortDramaNames.contains(n);
      default:
        return n == category;
    }
  }

  /// 在分类表里找出 [category] 的「主类」节点 id。
  static int? _findRootId(
    Map<int, CmsCategoryNode> tree,
    String category,
  ) {
    // 1. 精确同名
    for (final node in tree.values) {
      if (node.name == category) return node.id;
    }
    // 2. 别名（含反向包含，兼容「电影片」这类带后缀写法）
    final names = categoryAliases[category] ?? [category];
    for (final want in names) {
      for (final node in tree.values) {
        if (node.name == want) return node.id;
      }
    }
    for (final want in names) {
      for (final node in tree.values) {
        if (node.name.contains(want) || want.contains(node.name)) {
          return node.id;
        }
      }
    }
    // 3. 命名归类兜底（无别名可依时）
    for (final node in tree.values) {
      if (_belongsTo(node.name, category)) return node.id;
    }
    return null;
  }

  /// 把 App 分类名解析为该源上的一组 type_id。
  ///
  /// 返回顺序即取页顺序：先子类（内容主要在这里），需要时再补主类自身。
  /// 解析不到（该源无此分类）时返回空列表——调用方**不得**退化成「不带 t 的全站请求」，
  /// 否则会把电影塞进短剧频道。
  static List<int> resolveTypeIds(
    Map<int, CmsCategoryNode> tree,
    String category,
  ) {
    if (tree.isEmpty || category.isEmpty) return const [];
    final rootId = _findRootId(tree, category);
    if (rootId == null) return const [];

    // 短剧自成频道：ffzy 把「短剧」挂在「连续剧」子类下，若不排除，
    // 剧集频道会混进短剧（反向同理，短剧频道要保持短剧族完整）。
    bool excluded(CmsCategoryNode n) =>
        category != '短剧' && _belongsTo(n.name, '短剧');

    var children = tree.values
        .where((n) => n.id != rootId && n.parentId == rootId && !excluded(n))
        .map((n) => n.id)
        .toList()
      ..sort();

    // 站点不返回 type_pid 时（整表 pid 都是 0），用命名归类补出同族子类。
    final treeHasPid = tree.values.any((n) => n.parentId != 0);
    if (children.isEmpty && !treeHasPid) {
      children = tree.values
          .where((n) =>
              n.id != rootId && !excluded(n) && _belongsTo(n.name, category))
          .map((n) => n.id)
          .toList()
        ..sort();
    }

    // 短剧数据常散落在题材类名下（古装仙侠 / 现代都市 / 重生民国 …），补进来。
    if (category == '短剧') {
      final extras = tree.values
          .where((n) => n.id != rootId && shortDramaNames.contains(n.name))
          .map((n) => n.id);
      final merged = <int>{...children, ...extras}.toList()..sort();
      children = merged;
    }

    final out = <int>[];
    // 有子类时只用子类：父类若也返回数据，通常与子类重复（实测父类基本为空）。
    if (children.isNotEmpty) {
      out.addAll(children);
    } else {
      out.add(rootId);
    }
    return out.take(maxTypeIdsPerCategory).toList(growable: false);
  }

  /// 类型筛选：若站点存在同名子类（「动作」→「动作片」），收窄到该子类；
  /// 收窄不到时返回 `null`，由调用方改走客户端本地过滤。
  static int? matchGenreTypeId(
    Map<int, CmsCategoryNode> tree,
    List<int> candidateIds,
    String genre,
  ) {
    final g = genre.trim();
    if (g.isEmpty || g == '全部') return null;
    final candidateSet = candidateIds.toSet();
    int? loose;
    for (final node in tree.values) {
      if (!candidateSet.contains(node.id)) continue;
      if (node.name == g) return node.id;
      if (normalizeGenreName(node.name) == g && loose == null) loose = node.id;
    }
    if (loose != null) return loose;
    for (final node in tree.values) {
      if (!candidateSet.contains(node.id)) continue;
      if (node.name.startsWith(g) || g.startsWith(node.name)) return node.id;
    }
    return null;
  }

  /// 影片类型是否命中筛选词（客户端兜底过滤，读 `vod_class` + `type_name`）。
  ///
  /// ⚠️ **列表接口普遍不返回 `vod_class`**（2026-10-21 实测 lzi / ffzy 的
  /// `ac=list` 只有 8 个字段：无 `vod_class` / `vod_area` / `vod_year`，加 `h` 参数
  /// 也无效），此时 [genres] 只剩 `fromCmsJson` 塞进去的 `type_name`
  /// （如「国产动漫」「欧美综艺」）。若把「查不到」当成「不匹配」，选「热血」
  /// 这类细分词会把整个类目清空 —— 表现就是「筛选结果少到只剩零星几条」。
  ///
  /// [genreTags] 必须传 `Movie.genreTags`（**纯 `vod_class`**，不含分类名），
  /// 不要传 `Movie.genres` —— 后者含 `type_name`，拿「国产动漫」去比「热血」会误杀。
  static bool genreMatches(String filter, Iterable<String> genreTags) {
    final f = filter.trim();
    if (f.isEmpty || f == '全部') return true;
    final list = genreTags
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    // 源未提供类型信息（列表接口无 `vod_class`）：无法判定，放行而不是清空列表。
    if (list.isEmpty) return true;
    for (final g in list) {
      if (g == f) return true;
      if (normalizeGenreName(g) == f) return true;
      if (g.contains(f)) return true;
    }
    return false;
  }

  /// 影片地区是否命中筛选词。
  ///
  /// [knownRegions] 传入 UI 上的完整地区项（含「其他」），用于判定「其他」。
  static bool regionMatches(
    String filter,
    String value, {
    List<String> knownRegions = const [],
  }) {
    final f = filter.trim();
    if (f.isEmpty || f == '全部') return true;
    final v = value.trim();
    if (f == '其他') {
      // 地区未知（`vod_area` 缺失）时既不是「其他」也不该被排除 → 放行。
      if (v.isEmpty) return true;
      final known = knownRegions
          .where((r) => r != '全部' && r != '其他')
          .where((r) => regionMatches(r, v, knownRegions: const []));
      return known.isEmpty;
    }
    final keys = regionKeywords[f];
    if (keys != null) {
      // 列表接口不返回 `vod_area`（见 genreMatches 注释）：未知地区不参与筛选，
      // 否则选任一地区都会把列表清空到只剩「碰巧地区已知」的零星几条。
      if (v.isEmpty) return true;
      return keys.any(v.contains);
    }
    if (v.isEmpty) return true;
    return v.contains(f) || f.contains(v);
  }

  /// 源站分类名（`type_name`）是否属于 [category] 族。
  ///
  /// 用途：轮播等场景要判断「混进该类目的异类条目」。采集站子类里会混进
  /// 异类（实测 lzi「海外动漫」第 1 条是印度真人剧；某源「连续剧」子类里
  /// 有动画电影），合并多源后按评分选轮播，异类会被顶到 banner 上 ——
  /// 用户看到「动漫 Tab 顶部放着剧集简介」就是这么来的。
  ///
  /// 规则与 [_belongsTo] 一致（含短剧排除）；[typeName] 为空（源没给分类名）
  /// 时返回 true —— **未知 ≠ 不属于**，与 [genreMatches] 的放行策略保持一致，
  /// 避免把没有 type_name 的源整个滤掉。
  static bool typeNameBelongsTo(String category, String typeName) {
    final n = typeName.trim();
    if (n.isEmpty) return true;
    if (category != '短剧' && _belongsTo(n, '短剧')) return false;
    return _belongsTo(n, category);
  }
}
