/// 高保真宽屏稿中的「电影 / 连续剧 / …」频道占位路由。
///
/// 路径与 [docs/hifi_flutter_migration.md](hifi_flutter_migration.md) 第五步一致。
enum ChannelPortalKind {
  movies,
  tv,
  variety,
  anime,
  short;

  String get path => switch (this) {
        ChannelPortalKind.movies => '/movies',
        ChannelPortalKind.tv => '/tv',
        ChannelPortalKind.variety => '/variety',
        ChannelPortalKind.anime => '/anime',
        ChannelPortalKind.short => '/short',
      };

  /// 与首页分类 Tab、`MovieProvider.loadCategoryMovies` 使用的 CMS 分类名对齐。
  String get categoryApiValue => switch (this) {
        ChannelPortalKind.movies => '电影',
        ChannelPortalKind.tv => '剧集',
        ChannelPortalKind.variety => '综艺',
        ChannelPortalKind.anime => '动漫',
        ChannelPortalKind.short => '短剧',
      };

  /// 首页分类 Tab（与 `AppConstants.categories` 对齐）；无对应 Tab（如短剧）时为 `null`。
  String? get homeBrowseCategoryName => switch (this) {
        ChannelPortalKind.movies => '电影',
        ChannelPortalKind.tv => '剧集',
        ChannelPortalKind.variety => '综艺',
        ChannelPortalKind.anime => '动漫',
        ChannelPortalKind.short => null,
      };
}
