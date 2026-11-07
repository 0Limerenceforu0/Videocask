part of 'api_service.dart';

/// home 业务域实现。
///
/// 通过 `extension on ApiService` 直接访问主类的私有成员；
/// 引用主类的 static 成员必须写 `ApiService.xxx`（见 detail_page 同款约定）。
extension HomeApiExt on ApiService {
  /// 获取首页数据（**推荐 Tab 专用**，全站无分类筛选）。
  ///
  /// ⚠️ 类目 Tab 不要用这个方法：它按「每个子类各拉 5 页」取数
  /// （上限 12 子类 × 5 页 = 60 个请求），与分类列表的数据完全重复。
  /// 类目 Tab 的正确做法是「拉分类列表 → 从中派生轮播与分区」
  /// （`MovieProvider.deriveHomeSectionsFromCategory`），零额外请求。
  ///
  /// 当当前源无数据时，自动切换到其他可用源。
  Future<HomeData> getHomeData() async {
    // 自动化测试模式：不依赖外部接口，直接返回模拟数据，保证 UI 与流程可跑通。
    if (AppEnv.isTestMode) {
      return HomeData.empty();
    }
    if (_currentSource == null) {
      return HomeData.empty();
    }

    try {
      HomeData? result;

      await _requestWithFallback<HomeData>(
        (source) async {
          // 并发请求多页数据（首次加载5页，确保用户滚动时有充足数据）
          final futures = <Future<List<Movie>>>[
            // 最近更新：请求第1页，取全部
            _fetchCmsListForSource(source, page: 1),
            // 热门影视：请求第2页，获取不同的数据
            _fetchCmsListForSource(source, page: 2),
            // 高分推荐：请求第3页
            _fetchCmsListForSource(source, page: 3),
            // 预加载第4页（提前准备，滚动无感）
            _fetchCmsListForSource(source, page: 4),
            // 预加载第5页
            _fetchCmsListForSource(source, page: 5),
          ];

          final results = await Future.wait(futures);

          final page1Movies = results[0]; // 最近更新
          final page2Movies = results[1]; // 热门影视
          final page3Movies = results[2]; // 高分推荐
          final page4Movies = results[3]; // 预加载
          final page5Movies = results[4]; // 预加载

          if (page1Movies.isEmpty &&
              page2Movies.isEmpty &&
              page3Movies.isEmpty) {
            return null; // 触发 fallback
          }

          debugPrint('📊 首页数据加载完成 (${source.name})'
              ': '
              '最近${page1Movies.length}条, 热门${page2Movies.length}条, 高分${page3Movies.length}条, '
              '预加载${page4Movies.length + page5Movies.length}条');

          // 高分推荐：合并所有数据，按评分排序取前30
          final allMovies = [
            ...page1Movies,
            ...page2Movies,
            ...page3Movies,
            ...page4Movies,
            ...page5Movies,
          ];
          final sortedByRating = List<Movie>.from(allMovies)
            ..sort((a, b) {
              final c = b.rating.compareTo(a.rating);
              if (c != 0) return c;
              return a.id.compareTo(b.id);
            });
          final topRatedMovies = sortedByRating.length > 30
              ? sortedByRating.sublist(0, 30)
              : sortedByRating;

          // Banner：取评分最高且有封面的前5条（空封面会让轮播视觉上「都一样」）。
          final bannerList = pickBannerMovies(sortedByRating);

          result = HomeData(
            bannerList: bannerList,
            hotMovies: page2Movies.isNotEmpty ? page2Movies : page1Movies,
            latestMovies: page1Movies,
            topRatedMovies: topRatedMovies,
            classicMovies: page3Movies.isNotEmpty ? page3Movies : page1Movies,
          );
          return result!;
        },
      );

      if (result == null) {
        debugPrint('API未返回数据，使用模拟数据展示');
        return HomeData.empty();
      }

      return result!;
    } catch (e) {
      debugPrint('获取首页数据失败: $e');
      return HomeData.empty();
    }
  }
}
