import 'constants.dart';

/// 首页分类 Tab / 频道页：各 CMS 大类对应的「类型」「地区」筛选项。
///
/// 与 [AppConstants.categories] 对齐；对接苹果 CMS `class` / `area` 参数。
abstract final class CategoryFilterCatalog {
  static const List<String> _sharedRegions = [
    '全部',
    '中国大陆',
    '中国香港',
    '中国台湾',
    '美国',
    '韩国',
    '日本',
    '英国',
    '法国',
    '德国',
    '泰国',
    '印度',
    '其他',
  ];

  static const List<String> _movieGenres = AppConstants.filterGenres;

  static const List<String> _tvGenres = [
    '全部',
    '古装',
    '都市',
    '言情',
    '悬疑',
    '谍战',
    '武侠',
    '仙侠',
    '家庭',
    '偶像',
    '青春',
    '犯罪',
    '军旅',
    '喜剧',
    '历史',
    '科幻',
    '奇幻',
    '剧情',
  ];

  static const List<String> _animeGenres = [
    '全部',
    '热血',
    '冒险',
    '搞笑',
    '恋爱',
    '校园',
    '科幻',
    '奇幻',
    '治愈',
    '机战',
    '魔法',
    '运动',
    '推理',
    '悬疑',
    '百合',
    '耽美',
    '泡面',
    '剧场版',
  ];

  static const List<String> _varietyGenres = [
    '全部',
    '真人秀',
    '脱口秀',
    '访谈',
    '选秀',
    '音乐',
    '晚会',
    '美食',
    '旅游',
    '科教',
    '纪实',
    '搞笑',
    '情感',
    '职场',
  ];

  static const List<String> _documentaryGenres = [
    '全部',
    '自然',
    '人文',
    '历史',
    '科技',
    '社会',
    '军事',
    '美食',
    '旅行',
    '传记',
    '探险',
    '动物',
  ];

  static const List<String> _tvRegions = [
    '全部',
    '中国大陆',
    '中国香港',
    '中国台湾',
    '韩国',
    '日本',
    '美国',
    '英国',
    '泰国',
    '其他',
  ];

  static const List<String> _animeRegions = [
    '全部',
    '日本',
    '中国大陆',
    '中国台湾',
    '美国',
    '韩国',
    '法国',
    '其他',
  ];

  static const List<String> _varietyRegions = [
    '全部',
    '中国大陆',
    '中国香港',
    '中国台湾',
    '韩国',
    '日本',
    '美国',
    '英国',
    '其他',
  ];

  static const List<String> _documentaryRegions = [
    '全部',
    '中国大陆',
    '美国',
    '英国',
    '日本',
    '法国',
    '德国',
    '韩国',
    '其他',
  ];

  static List<String> genresFor(String category) => switch (category) {
        '电影' => _movieGenres,
        '剧集' => _tvGenres,
        '动漫' => _animeGenres,
        '综艺' => _varietyGenres,
        '纪录片' => _documentaryGenres,
        _ => _movieGenres,
      };

  static List<String> regionsFor(String category) => switch (category) {
        '电影' => _sharedRegions,
        '剧集' => _tvRegions,
        '动漫' => _animeRegions,
        '综艺' => _varietyRegions,
        '纪录片' => _documentaryRegions,
        _ => _sharedRegions,
      };

  /// 切换分类 Tab 后，若当前选中项不在新列表中则回退为「全部」。
  static String normalizeGenre(String category, String selected) {
    final options = genresFor(category);
    return options.contains(selected) ? selected : '全部';
  }

  static String normalizeRegion(String category, String selected) {
    final options = regionsFor(category);
    return options.contains(selected) ? selected : '全部';
  }
}
