part of 'api_service.dart';

/// category 业务域实现。
///
/// 通过 `extension on ApiService` 直接访问主类的私有成员；
/// 引用主类的 static 成员必须写 `ApiService.xxx`（见 detail_page 同款约定）。
extension CategoryApiExt on ApiService {
  /// 分类节点表（含 `type_pid` 父子关系，部分站点缺该字段）。
  Future<Map<int, CmsCategoryNode>> categoryTreeForSourceUrl(
    String sourceUrl,
  ) async {
    final hit = _categoryTreeCache[sourceUrl];
    if (hit != null &&
        DateTime.now().difference(hit.fetchedAt) <
            ApiService._categoryTreeTtl) {
      return hit.nodes;
    }
    final nodes = await _fetchCategoryTreeForSourceUrl(sourceUrl);
    if (nodes.isNotEmpty) {
      _categoryTreeCache[sourceUrl] = _CategoryTreeCacheEntry(nodes);
      _evictCategoryTreeCache();
    }
    return nodes;
  }

  /// 淘汰超量的分类树缓存（保留最新的 N 个源）。
  void _evictCategoryTreeCache() {
    while (
        _categoryTreeCache.length > ApiService._maxCategoryTreeCacheEntries) {
      _categoryTreeCache.remove(_categoryTreeCache.keys.first);
    }
  }

  /// 任意源的分类表（不修改当前源缓存，用于多源聚合）
  Future<Map<int, CmsCategoryNode>> _fetchCategoryTreeForSourceUrl(
    String sourceUrl,
  ) async {
    try {
      final url =
          sourceUrl.contains('?') ? '$sourceUrl&ac=list' : '$sourceUrl?ac=list';
      final rawData = await _httpGet(url);
      if (rawData == null) return {};

      final data = _parseResponseData(rawData);
      if (data == null) return {};

      final classRaw = data['class'];
      if (classRaw is! List) return {};

      final out = <int, CmsCategoryNode>{};
      for (final item in classRaw) {
        if (item is! Map<String, dynamic>) continue;
        final typeId = int.tryParse(item['type_id']?.toString() ?? '') ?? 0;
        final typeName = item['type_name']?.toString() ?? '';
        if (typeId <= 0 || typeName.isEmpty) continue;
        out[typeId] = CmsCategoryNode(
          id: typeId,
          name: typeName,
          parentId: int.tryParse(item['type_pid']?.toString() ?? '') ?? 0,
        );
      }
      debugPrint('📊 分类树: ${out.length} 个节点');
      return out;
    } catch (e) {
      debugPrint('获取外部分类列表失败: $e');
      return {};
    }
  }

  /// 把分类名展开为本次要请求的 type_id 列表。
  ///
  /// 类型筛选命中站点同族子类（「动作」→「动作片」）时收窄到该子类。
  ///
  /// [subClassId] 非空（用户在首页点了「小分类」chip）时只请求该子类 ——
  /// 这是「最小代价」浏览的核心：按需传参，不再一次展开全部子类。
  /// [limit] 非空时只取前 [limit] 个子类（首屏默认量，见
  /// [defaultSubClassCount]）；续页必须用与首屏相同的集合，否则翻页会混入
  /// 别的子类内容。
  List<int> _expandTypeIds(
    Map<int, CmsCategoryNode> tree,
    String category,
    String genre, {
    int? subClassId,
    int? limit,
  }) {
    if (subClassId != null) return <int>[subClassId];
    final all = CmsCategoryResolver.resolveTypeIds(tree, category);
    if (all.isEmpty) return const [];
    final narrowed = CmsCategoryResolver.matchGenreTypeId(tree, all, genre);
    final ids = narrowed != null ? <int>[narrowed] : all;
    return limit != null && ids.length > limit ? ids.sublist(0, limit) : ids;
  }

  /// 从指定播放源拉取分类列表的一页（多源首页用）。
  ///
  /// 分类先展开为「父类 + 全部子类」的 type_id 集合（见 [CmsCategoryResolver]），
  /// 每个 type_id 取同一页后合并去重；否则只能拿到父类空壳里的个位数条目。
  /// 站点没有该分类时返回 [CmsListPage.unsupported]，**不回退全站请求**。
  ///
  /// [subClassId] 非空 = 用户点了小分类 chip，只拉该子类；
  /// [allSubClasses] = true = 用户明确要「全部」，展开全部子类；
  /// 否则按 [defaultSubClassCount] 取前 N 个子类（首屏最小代价）。
  /// [limit] 仅测试用：显式覆盖默认量子类数。
  Future<CmsListPage> fetchCategoryPageForSource(
    PlaySource source,
    String category, {
    String region = '',
    String genre = '',
    String year = '',
    int page = 1,
    int? subClassId,
    bool allSubClasses = false,
    int? limit,
  }) async {
    final tree = await categoryTreeForSourceUrl(source.url);
    final typeIds = _expandTypeIds(
      tree,
      category,
      genre,
      subClassId: subClassId,
      limit: allSubClasses ? null : (limit ?? ApiService.defaultSubClassCount),
    );
    if (typeIds.isEmpty) {
      debugPrint('⚠️ 源 ${source.name} 无分类「$category」，跳过该源');
      return const CmsListPage(movies: [], hasMore: false, unsupported: true);
    }
    final pages = await ApiService._mapInBatches<int, CmsListPage>(
      typeIds,
      ApiService._categoryFetchConcurrency,
      (tid) => _fetchCmsListPageForSource(
        source,
        page: page,
        typeId: tid,
        area: region,
        year: year,
      ),
    );
    return ApiService._mergeCategoryPages(pages);
  }

  /// 分类首屏/续页：并发拉取各已启用源的第 [page] 页并去重合并；
  /// [hasMore] 取当前主源对应条目的翻页标志
  ///
  /// [subClassId] / [allSubClasses] 语义同 [fetchCategoryPageForSource]：
  /// 首页默认只拉前 [defaultSubClassCount] 个子类，点「小分类」chip 才按需拉全。
  ///
  /// ⚠️ **不要把它当翻页主轴**（2026-10-21 重构）：源多时（几十上百个）
  /// 全源并发 × 3 子类的请求量与数据量不可接受。翻页主轴是「使用中」的
  /// 主源（见 `MovieProvider.loadCategoryMovies`），本方法只用于「首屏补充源」
  /// 这类**受限数量**的并发取数（调用方必须先限量）。
  Future<CmsListPage> aggregateCategoryFirstPage({
    required List<PlaySource> sources,
    required String category,
    String region = '',
    String genre = '',
    int page = 1,
    int? subClassId,
    bool allSubClasses = false,
  }) async {
    if (sources.isEmpty) {
      return const CmsListPage(movies: [], hasMore: false);
    }
    final results = await Future.wait(
      sources.map(
        (s) => fetchCategoryPageForSource(
          s,
          category,
          region: region,
          genre: genre,
          page: page,
          subClassId: subClassId,
          allSubClasses: allSubClasses,
        ),
      ),
    );

    final supported = <int>[];
    for (var i = 0; i < results.length; i++) {
      if (!results[i].unsupported) supported.add(i);
    }
    if (supported.isEmpty) {
      // 所有已启用源都没有该分类：宁可为空，也不要回退成全站数据。
      debugPrint('⚠️ 已启用源均无分类「$category」');
      return const CmsListPage(movies: [], hasMore: false, unsupported: true);
    }

    // 各源逐条交替合并：保持每页顺序稳定，避免翻页时条目在列表中来回跳动。
    final seen = <String>{};
    final merged = <Movie>[];
    final maxLen = supported
        .map((i) => results[i].movies.length)
        .fold<int>(0, (a, b) => a > b ? a : b);
    for (var k = 0; k < maxLen; k++) {
      for (final i in supported) {
        final list = results[i].movies;
        if (k >= list.length) continue;
        final m = list[k];
        if (seen.add(ApiService._dedupeKeyForMovie(m))) merged.add(m);
      }
    }

    var primaryHasMore = results[supported.first].hasMore;
    final curId = _currentSource?.id;
    if (curId != null && curId.isNotEmpty) {
      for (final i in supported) {
        if (sources[i].id == curId) {
          primaryHasMore = results[i].hasMore;
          break;
        }
      }
    }

    return CmsListPage(movies: merged, hasMore: primaryHasMore);
  }

  /// 类型词（「科幻」「动作」）搜索：按站点**类型子类**检索，而不是 `wd=`。
  ///
  /// ## 为什么不能用 `wd=科幻`（2026-10-28 六源实测）
  ///
  /// 采集站 `wd=` 只匹配**片名字段**：`wd=科幻` / `wd=周星驰` 在 ffzy 上
  /// `total=0`。所以用户搜类型，源站根本没东西可给 —— 这不是过滤问题，
  /// 是请求参数用错了。
  ///
  /// 正确通道是 `ac=detail&t=<type_id>`：把「科幻」映射到站点分类树里的
  /// 「科幻片」子类（[CmsCategoryResolver.matchGenreTypeId]），直接拉该类目。
  /// ffzy 实测 `class=科幻` 有 4211 条，走 `t=` 同样能翻页拿全。
  ///
  /// 逐源逐分类先查树：**找不到该类型子类就不发请求**（否则会退化成
  /// 「不带 t 的全站请求」，把不相关的内容灌进结果）。
  Future<CmsListPage> aggregateGenreFirstPage({
    required List<PlaySource> sources,
    required String genre,
    List<String> categories = const ['电影', '剧集', '动漫', '综艺', '纪录片'],
    int page = 1,
  }) async {
    final g = genre.trim();
    if (g.isEmpty || sources.isEmpty) {
      return const CmsListPage(movies: [], hasMore: false);
    }
    final perSource = await Future.wait(
      sources.map((s) => _fetchGenrePagesForSource(s, g, categories, page)),
    );

    final seen = <String>{};
    final merged = <Movie>[];
    var hasMore = false;
    var anySupported = false;
    for (final p in perSource) {
      if (!p.unsupported) anySupported = true;
      if (p.hasMore) hasMore = true;
      for (final m in p.movies) {
        if (seen.add(ApiService._dedupeKeyForMovie(m))) merged.add(m);
      }
    }
    return CmsListPage(
      movies: merged,
      hasMore: hasMore && merged.isNotEmpty,
      unsupported: !anySupported,
    );
  }

  Future<CmsListPage> _fetchGenrePagesForSource(
    PlaySource source,
    String genre,
    List<String> categories,
    int page,
  ) async {
    try {
      final tree = await categoryTreeForSourceUrl(source.url);
      final typeIds = <int>[];
      for (final category in categories) {
        final all = CmsCategoryResolver.resolveTypeIds(tree, category);
        if (all.isEmpty) continue;
        final id = CmsCategoryResolver.matchGenreTypeId(tree, all, genre);
        if (id != null && !typeIds.contains(id)) typeIds.add(id);
      }
      if (typeIds.isEmpty) {
        return const CmsListPage(movies: [], hasMore: false, unsupported: true);
      }
      final pages = await ApiService._mapInBatches<int, CmsListPage>(
        typeIds,
        2,
        (tid) => _fetchCmsListPageForSource(
          source,
          page: page,
          typeId: tid,
        ),
      );
      return ApiService._mergeCategoryPages(pages);
    } catch (e) {
      debugPrint('类型检索失败（${source.name} / $genre）: $e');
      return const CmsListPage(movies: [], hasMore: false, unsupported: true);
    }
  }

  /// （见 `MovieProvider` 的 `categoryMovies`），不再指望服务端。
  ///
  /// [subClassId] / [allSubClasses] 必须与首屏（[aggregateCategoryFirstPage]）
  /// 保持一致，否则续页会从另一批子类取数，列表内容前后对不上。
  Future<CmsListPage> getMoviesByCategory({
    required String category,
    String region = '',
    String year = '',
    String sort = '',
    String genre = '',
    int page = 1,
    int? subClassId,
    bool allSubClasses = false,
  }) async {
    final source = _currentSource;
    if (source == null) {
      return const CmsListPage(movies: [], hasMore: false);
    }

    try {
      return await fetchCategoryPageForSource(
        source,
        category,
        region: region,
        genre: genre,
        year: year,
        page: page,
        subClassId: subClassId,
        allSubClasses: allSubClasses,
      );
    } catch (e) {
      debugPrint('获取分类影片失败: $e');
      return const CmsListPage(movies: [], hasMore: false);
    }
  }

  /// 当前源分类树里 [category] 下的子类节点（供首页「小分类」chip 使用）。
  ///
  /// 顺序即取页顺序（与 [CmsCategoryResolver.resolveTypeIds] 一致），
  /// 首屏默认只拉前 [defaultSubClassCount] 个，其余点 chip 按需拉。
  /// 树尚未缓存（冷启动）时返回空，由调用方等首屏加载完再读。
  List<CmsCategoryNode> subClassesFor(String category) {
    final source = _currentSource;
    if (source == null) return const [];
    final hit = _categoryTreeCache[source.url];
    if (hit == null ||
        DateTime.now().difference(hit.fetchedAt) >=
            ApiService._categoryTreeTtl) {
      return const [];
    }
    final tree = hit.nodes;
    final ids = CmsCategoryResolver.resolveTypeIds(tree, category);
    return ids
        .map((id) => tree[id])
        .whereType<CmsCategoryNode>()
        .toList(growable: false);
  }

  /// 获取指定页的影片列表（公开方法，供 Provider 调用）
  ///
  /// 苹果CMS接口：GET {url}?ac=detail&pg={页码}
  /// 用于首页无限滚动加载更多数据
  Future<CmsListPage> fetchMoviesByPage(int page) async {
    return _fetchCmsListPageForSource(_currentSource, page: page);
  }

  /// 获取CMS列表单页（指定源）及是否还有下一页
  Future<CmsListPage> _fetchCmsListPageForSource(
    PlaySource? source, {
    int page = 1,
    int? typeId,
    String area = '',
    String clazz = '',
    String year = '',
  }) async {
    if (source == null) {
      return const CmsListPage(movies: [], hasMore: false);
    }

    try {
      final queryParameters = <String, String>{
        'ac': 'detail',
        'pg': page.toString(),
      };

      if (typeId != null) {
        queryParameters['t'] = typeId.toString();
      }

      if (area.isNotEmpty && area != '全部') {
        queryParameters['area'] = area;
      }
      if (clazz.isNotEmpty && clazz != '全部') {
        queryParameters['class'] = clazz;
      }
      if (year.isNotEmpty && year != '全部' && year != '更早') {
        queryParameters['year'] = year;
      }

      final uri =
          Uri.parse(source.url).replace(queryParameters: queryParameters);
      final rawData = await _httpGet(uri.toString());
      if (rawData == null) {
        return const CmsListPage(movies: [], hasMore: false);
      }

      final json = _parseResponseData(rawData);
      if (json == null) {
        return const CmsListPage(movies: [], hasMore: false);
      }

      final listRaw = json['list'];
      if (listRaw is! List || listRaw.isEmpty) {
        return const CmsListPage(movies: [], hasMore: false);
      }

      final movies = listRaw
          .whereType<Map<String, dynamic>>()
          .map((e) => Movie.fromCmsJson(e).copyWith(sourceId: source.id))
          .toList();

      final pg = int.tryParse(json['page']?.toString() ?? '1') ?? 1;
      final pagecount = int.tryParse(json['pagecount']?.toString() ?? '0') ?? 0;
      final limit = int.tryParse(
            json['limit']?.toString() ?? '${AppConstants.pageSize}',
          ) ??
          AppConstants.pageSize;

      final bool hasMore;
      if (pagecount > 0) {
        hasMore = pg < pagecount;
      } else {
        hasMore = movies.length >= limit;
      }

      debugPrint('📊 获取列表数据: page=$page, ${movies.length} 条, hasMore=$hasMore');
      return CmsListPage(movies: movies, hasMore: hasMore);
    } catch (e, stackTrace) {
      debugPrint('获取列表数据失败: $e');
      debugPrint('堆栈: $stackTrace');
      return const CmsListPage(movies: [], hasMore: false);
    }
  }

  /// 获取CMS列表数据（指定源，仅影片列表）
  Future<List<Movie>> _fetchCmsListForSource(
    PlaySource? source, {
    int page = 1,
    int? typeId,
    String area = '',
    String clazz = '',
    String year = '',
  }) async {
    final p = await _fetchCmsListPageForSource(
      source,
      page: page,
      typeId: typeId,
      area: area,
      clazz: clazz,
      year: year,
    );
    return p.movies;
  }
}
