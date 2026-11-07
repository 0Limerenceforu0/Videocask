/// 搜索词类型识别（纯函数，便于单测）。
///
/// 背景（2026-10-21 实测）：苹果CMS 的 `wd=` 搜索**只匹配片名等文本字段**，
/// 搜「动漫」「动作」这类**类型词**返回 0 条（ffzy `?ac=detail&wd=动漫`
/// total=0）—— 用户视角就是「搜索不能搜索类型」。
///
/// 因此搜索前先把词过一遍本表：
/// - 命中一级分类词（电影/剧集/动漫/综艺/纪录片/短剧，含别名）
///   → 直接按该分类拉列表（走 `ac=detail&t=`，与首页 Tab 同一条数据链）；
/// - 命中细分类型词（动作/喜剧/爱情…）
///   → 作为本地筛选条件过滤搜索结果（源站仍按关键词搜）。
///
/// ⚠️ 只做**整词**匹配：「喜剧之王」不得命中「喜剧」，
/// 「流浪地球」不得命中任何词 —— 含子串即误伤正常片名搜索。
abstract final class SearchTypeWord {
  /// 一级分类别名表：词 → App 内分类名（与首页 Tab 同名）。
  static const Map<String, String> _categoryWords = {
    // 电影
    '电影': '电影',
    '影片': '电影',
    '电影片': '电影',
    // 剧集
    '电视剧': '剧集',
    '剧集': '剧集',
    '连续剧': '剧集',
    '国产剧': '剧集',
    '美剧': '剧集',
    '韩剧': '剧集',
    '日剧': '剧集',
    '港剧': '剧集',
    '台剧': '剧集',
    '欧美剧': '剧集',
    '海外剧': '剧集',
    // 动漫
    '动漫': '动漫',
    '动画': '动漫',
    '动画片': '动漫',
    '番剧': '动漫',
    '国漫': '动漫',
    '日漫': '动漫',
    // 综艺
    '综艺': '综艺',
    '综艺片': '综艺',
    '真人秀': '综艺',
    // 纪录片
    '纪录片': '纪录片',
    '记录片': '纪录片',
    '纪录': '纪录片',
    // 短剧
    '短剧': '短剧',
    '爽文短剧': '短剧',
  };

  /// 细分类型词（作为类型筛选用，不切换分类）。
  static const Set<String> _genreWords = {
    '动作', '喜剧', '爱情', '科幻', '悬疑', '恐怖', '惊悚', '奇幻', '冒险',
    '剧情', '家庭', '儿童', '战争', '历史', '传记', '音乐', '歌舞', '运动',
    '西部', '武侠', '犯罪', '古装', '青春', '校园', '热血', '恋爱', '搞笑',
    '同性', '脱口秀', '游戏', '灾难', '玄幻', '仙侠', '都市', '重生', '穿越',
  };

  /// 整词命中一级分类别名表时返回 App 分类名，否则 null。
  static String? categoryOf(String query) {
    final q = _normalize(query);
    if (q.isEmpty) return null;
    return _categoryWords[q];
  }

  /// 整词命中细分类型词表时返回该类型词，否则 null。
  ///
  /// 优先级低于 [categoryOf]：「动画」是分类词（动漫）而不是类型词。
  static String? genreOf(String query) {
    final q = _normalize(query);
    if (q.isEmpty) return null;
    if (_categoryWords.containsKey(q)) return null;
    return _genreWords.contains(q) ? q : null;
  }

  /// 归一化：去首尾空白 + 去掉常见装饰后缀（「动漫片」「科幻片」→ 主干）。
  ///
  /// 「动作片」「科幻片」这类写法要能命中类型词，否则用户照样搜不到。
  static String _normalize(String raw) {
    var q = raw.trim();
    if (q.isEmpty) return q;
    // 分类别名优先原样命中（「动画片」在表里），不预处理。
    if (_categoryWords.containsKey(q)) return q;
    for (final suffix in const ['片', '剧', '动漫', '综艺', '电视剧']) {
      if (q.length > 2 && q.endsWith(suffix)) {
        final stem = q.substring(0, q.length - suffix.length);
        // 去掉后缀后仍需落在某张表里，否则「红楼梦」不该被削成「红楼」。
        if (_categoryWords.containsKey(stem) || _genreWords.contains(stem)) {
          return stem;
        }
      }
    }
    return q;
  }
}
