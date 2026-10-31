import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../config/app_env.dart';
import '../config/constants.dart';
import '../models/movie.dart';
import '../models/play_source.dart';
import 'cms_category_resolver.dart';
import 'banner_picker.dart';
import 'network/dio_factory.dart';
import '../utils/commentary_content_filter.dart';
import 'error_handler.dart';
import 'detail_source_matcher.dart';
import '../utils/movie_dedupe.dart';

// 条件导入：Web端使用 dart:html 的 HttpRequest，非Web端使用 stub
import '../utils/web_http_stub.dart'
    if (dart.library.html) '../utils/web_http.dart' as web_http;

/// 一条「按片名检索」的请求（人名搜索用：豆瓣代表作 → 逐个片名搜源站）。
class TitleQuery {
  final String title;

  /// 作品年份。用来把「功夫」和「功夫女足 / 功夫星猫 / 功夫小子闯佛山」分开
  /// —— 采集站的 `wd=` 是模糊匹配，只给片名会混进一堆同名衍生内容。
  final String year;

  const TitleQuery(this.title, {this.year = ''});
}

/// 搜索结果的相关性处理方式。
///
/// 「严格」不等于「一刀切」：严格模式在**某源严格命中为 0** 时会自动放宽到
/// [ApiService.isSearchResultLooselyRelevant] 再试一次，避免整个源被清空。
/// 人名 / 类型查询直接走 [off]——它们的检索通道已经保证语义正确，再拿关键词
/// 去比片名只会把结果全部杀掉（2026-10-28 用户反馈的「二极管」）。
enum SearchRelevance {
  /// 按片名相关性过滤（默认，片名搜索用）。
  strict,

  /// 不过滤（人名 / 类型 / 分类等「关键词不是片名」的检索）。
  off,
}

/// CMS 列表单页结果（含是否还有下一页，避免条数 <20 时误停分页）
class CmsListPage {
  final List<Movie> movies;
  final bool hasMore;

  /// 该源根本没有此分类（如站点没有「短剧」）。
  ///
  /// 为 true 时说明**没有发起请求**——绝不能退化成「不带 t 的全站请求」，
  /// 否则电影会被塞进短剧频道（2026-09-29 修复的问题之一）。
  final bool unsupported;

  const CmsListPage({
    required this.movies,
    required this.hasMore,
    this.unsupported = false,
  });
}

/// 分类树缓存条目。
class _CategoryTreeCacheEntry {
  _CategoryTreeCacheEntry(this.nodes);

  final Map<int, CmsCategoryNode> nodes;
  final DateTime fetchedAt = DateTime.now();
}

/// API服务 - 兼容苹果CMS采集接口格式
///
/// 苹果CMS采集接口说明：
/// - 影片列表：GET {url}?ac=detail&t={分类ID}&pg={页码}
/// - 影片详情：GET {url}?ac=detail&ids={影片ID}
/// - 搜索影片：GET {url}?ac=detail&wd={关键词}&pg={页码}
/// - 分类列表：GET {url}?ac=list（返回中包含class字段）
///
/// Web端通过CORS代理转发请求，绕过浏览器跨域限制

/// 单页关键词搜索结果 + 总页数（供翻页聚合使用）。
class _SearchPageResult {
  const _SearchPageResult({
    required this.movies,
    required this.pagecount,
    required this.page,
  });
  final List<Movie> movies;
  final int pagecount;
  final int page;
}

class ApiService {
  ApiService._();
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;

  /// Dio实例（非Web端使用）
  Dio? _dio;

  /// 是否已初始化
  bool _initialized = false;

  /// 当前使用的源
  PlaySource? _currentSource;

  /// 当前源
  PlaySource? get currentSource => _currentSource;

  /// 初始化
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // 自动化测试模式：避免创建真实 HttpClient / Dio，防止测试环境产生 400 噪声与不稳定因素。
    if (AppEnv.isTestMode) {
      debugPrint('测试模式：跳过 Dio 初始化');
      return;
    }

    // Web端不需要初始化 Dio（所有请求通过 dart:html HttpRequest 发送）
    if (kIsWeb) {
      debugPrint('Web 端跳过 Dio 初始化');
      return;
    }

    _dio = await DioFactory.plainText();

    // 添加拦截器
    _dio!.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          debugPrint('API请求: ${options.method} ${options.uri}');
          handler.next(options);
        },
        onResponse: (response, handler) {
          handler.next(response);
        },
        onError: (error, handler) {
          debugPrint('API错误: ${error.message}');
          handler.next(error);
        },
      ),
    );
  }

  /// 设置当前源
  void setCurrentSource(PlaySource source) {
    _currentSource = source;
  }

  /// 获取所有可用源列表（由 SourceProvider 设置）
  /// 用于当当前源请求失败时自动切换到其他源
  List<PlaySource> _availableSources = [];

  /// 设置可用源列表
  void setAvailableSources(List<PlaySource> sources) {
    _availableSources = sources;
  }

  /// 源切换回调（通知 SourceProvider 更新当前源）
  void Function(PlaySource source)? onSourceSwitched;

  /// 源切换提示信息（供 UI 层展示给用户）
  /// 格式：["源A无数据", "切换到源B", "源B成功"]
  List<String> sourceSwitchMessages = [];

  /// 用指定源尝试请求，失败自动切换到下一个可用源
  ///
  /// 会尝试所有启用的源，直到找到返回有效数据的源。
  /// 切换过程记录在 [sourceSwitchMessages] 中，供 UI 展示提示。
  ///
  /// [requestFn] 接收一个 PlaySource 参数，返回请求结果
  /// [isValidResult] 可选的验证函数，用于判断结果是否有效
  Future<T?> _requestWithFallback<T>(
    Future<T?> Function(PlaySource source) requestFn, {
    bool Function(T? result)? isValidResult,
  }) async {
    if (_currentSource == null) return null;

    sourceSwitchMessages.clear();
    // F4：记住用户当前源；回退只是「请求级别的临时探测」，绝不永久改用户全局源。
    final originalSource = _currentSource!;

    Future<T?> _run() async {
      // 收集所有启用的源：原始源优先，然后是其他源
      final enabledSources = _availableSources.where((s) => s.enabled).toList();
      final otherSources =
          enabledSources.where((s) => s.id != originalSource.id).toList();

      final sourcesToTry = <PlaySource>[
        if (originalSource.enabled) originalSource,
        ...otherSources,
      ];

      for (int i = 0; i < sourcesToTry.length; i++) {
        final source = sourcesToTry[i];

        // 不是当前(原始)源时才临时切换；仅请求级别切换，不通知全局改源。
        if (source.id != _currentSource?.id) {
          debugPrint('🔄 临时尝试源 "${source.name}"（不影响用户当前源）');
          sourceSwitchMessages
              .add('源 "${originalSource.name}" 无数据，临时尝试 "${source.name}"');
          _currentSource = source;
          // 注意：不调用 onSourceSwitched，避免悄悄改用户全局源。
        }

        try {
          final result = await requestFn(source);

          bool isValid = false;
          if (isValidResult != null) {
            isValid = isValidResult(result);
          } else if (result is List) {
            isValid = result.isNotEmpty;
          } else if (result is Map) {
            isValid = result.isNotEmpty;
          } else if (result != null) {
            isValid = true;
          }

          if (isValid) {
            if (i > 0) {
              sourceSwitchMessages.add('已临时从 "${source.name}" 加载数据');
            }
            return result;
          }

          // 当前源返回无效数据
          if (i < sourcesToTry.length - 1) {
            debugPrint('⚠️ 源 "${source.name}" 返回无效数据，尝试下一个源...');
            sourceSwitchMessages.add('源 "${source.name}" 无数据');
          }
        } catch (e) {
          debugPrint('⚠️ 源 "${source.name}" 请求异常: $e');
          sourceSwitchMessages.add('源 "${source.name}" 请求失败');
          if (i < sourcesToTry.length - 1) {
            debugPrint('尝试下一个源...');
          }
        }
      }

      // 所有源都失败
      sourceSwitchMessages.add('所有源均无法加载数据');
      return null;
    }

    try {
      return await _run();
    } finally {
      // F4：无论成功与否，还原用户当前源。
      _currentSource = originalSource;
    }
  }

  /// 发起HTTP GET请求
  ///
  /// Web端通过CORS代理转发，非Web端直接使用Dio
  Future<String?> _httpGet(String url) async {
    if (AppEnv.isTestMode) return null;
    if (kIsWeb) {
      try {
        return web_http.webRequestForApi(url);
      } catch (e) {
        debugPrint('Web HTTP请求失败: ${ErrorHandler().handleNetworkError(e)}');
        return null;
      }
    } else {
      try {
        if (_dio == null) {
          await init();
        }
        final response = await _dio!.get(url);
        if (response.data is String) {
          return response.data as String;
        }
        debugPrint('Dio响应数据异常: ${response.data}');
        return null;
      } catch (e) {
        debugPrint('HTTP请求失败: ${ErrorHandler().handleNetworkError(e)}');
        return null;
      }
    }
  }

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

  /// 获取影片详情
  ///
  /// 苹果CMS详情接口：GET {url}?ac=detail&ids={影片ID}
  /// 用指定源按 id 拉取影片详情，并补上该源的 sourceId（F2）。
  Future<Movie?> _fetchDetailByIdFromSource(
      String movieId, PlaySource source) async {
    final url = '${source.url}?ac=detail&ids=$movieId';
    final rawData = await _httpGet(url);
    if (rawData == null) return null;
    final data = _parseResponseData(rawData);
    if (data == null) return null;
    final listRaw = data['list'];
    if (listRaw is! List || listRaw.isEmpty) return null;
    final movie = Movie.fromCmsJson(listRaw[0] as Map<String, dynamic>);
    return movie.sourceId.isEmpty ? movie.copyWith(sourceId: source.id) : movie;
  }

  /// 按 sourceId 从已配置源里取 [PlaySource]（找不到返回 null）。
  PlaySource? _sourceById(String id) {
    if (id.isEmpty) return null;
    try {
      return _availableSources.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 当前源无法播放时，按片名跨源安全匹配出「同一部片」的其它源条目（修订版 F1）。
  ///
  /// 与手动换源面板 [DetailSourceSwitchPane] 共用 [DetailSourceMatcher] 的匹配口径：
  /// 拿片名去其它启用源各搜一遍，挑出名字+年份最像的那条，返回带正确 sourceId
  /// 与**该源自己 id** 的候选。匹配不到可信同名片时返回 null——
  /// 绝不退回「同一个 id 去别的源」这种会打开错片的旧逻辑。
  Future<Movie?> autoFallbackByTitle(
    String title,
    String year, {
    String? excludeSourceId,
    int minScore = 85,
  }) async {
    if (_currentSource == null || title.trim().isEmpty) return null;
    final candidates = _availableSources
        .where((s) => s.enabled && s.id != _currentSource!.id)
        .where((s) => s.id != excludeSourceId)
        .toList();
    Movie? best;
    var bestScore = 0;
    for (final source in candidates) {
      try {
        final list =
            await searchMovies(title, page: 1, maxPages: 2, source: source);
        final picked = DetailSourceMatcher.pickBest(
          list,
          targetName: title,
          targetYear: year,
        );
        if (picked == null) continue;
        final score = DetailSourceMatcher.score(
          candidateName: picked.name,
          targetName: title,
          candidateYear: picked.year,
          targetYear: year,
        );
        if (score > bestScore) {
          bestScore = score;
          best = picked;
        }
      } catch (_) {
        // 单个源搜索失败不阻断其它源。
      }
    }
    if (best == null || bestScore < minScore) return null;
    return best;
  }

  Future<Movie?> getMovieDetail(
    String movieId, {
    bool allowFallback = true,
    String? titleHint,
    String? yearHint,
  }) async {
    // 自动化测试模式：返回一个可渲染的详情对象，避免依赖外部接口。
    if (AppEnv.isTestMode) {
      return Movie(
        id: movieId.isEmpty ? 'mock_detail_1' : movieId,
        name: '示例影片（详情）',
        rating: 8.5,
        genres: const ['动作', '科幻'],
        year: '2024',
        updateStatus: '更新至第1集',
      );
    }
    if (_currentSource == null) return null;

    try {
      // 只用「当前源」按 id 加载；各 CMS 的 vod_id 仅在本站唯一，
      // 禁止用同一个 id 去其它源回退（会打开完全错误的片子）。
      final current =
          await _fetchDetailByIdFromSource(movieId, _currentSource!);
      Movie? result = current;

      // 当前源无有效可播数据时，按片名安全跨源匹配（用目标源自己的 id）。
      if (allowFallback &&
          (result == null || !_hasPlayableEpisode(result)) &&
          titleHint != null &&
          titleHint.trim().isNotEmpty) {
        final alt = await autoFallbackByTitle(titleHint.trim(), yearHint ?? '');
        if (alt != null) {
          final targetSource = _sourceById(alt.sourceId);
          if (targetSource != null) {
            final altDetail =
                await _fetchDetailByIdFromSource(alt.id, targetSource);
            if (altDetail != null && _hasPlayableEpisode(altDetail)) {
              result = altDetail;
            }
          }
        }
      }

      if (result != null) {
        debugPrint('📊 影片详情: id=$movieId, 成功'
            '${result.sourceId != _currentSource!.id ? "（已在其它源找到同名片）" : ""}');
      } else {
        debugPrint('📊 影片详情: id=$movieId, 无可用播放线路（含其它源均未找到同名片）');
      }
      return result;
    } catch (e) {
      debugPrint('获取影片详情失败: $e');
      debugPrint('📊 影片详情: id=$movieId, 失败');
      return null;
    }
  }

  /// 判断详情是否含有至少一个可用播放地址
  bool _hasPlayableEpisode(Movie? movie) {
    if (movie == null) return false;
    for (final route in movie.playRoutes) {
      for (final ep in route.episodes) {
        if (ep.url.trim().isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  /// 搜索影片
  ///
  /// 苹果CMS搜索接口：GET {url}?ac=detail&wd={关键词}&pg={页码}
  /// 单页搜索结果 + 总页数（供翻页聚合使用）。
  static const _SearchPageResult _emptySearchPage = _SearchPageResult(
    movies: [],
    pagecount: 1,
    page: 1,
  );

  Future<List<Movie>> searchMovies(
    String keyword, {
    int page = 1,
    int maxPages = _maxSearchPagesPerSource,
    PlaySource? source,
  }) async {
    // 自动化测试模式：返回稳定的模拟搜索结果，便于验证搜索页面交互与列表渲染。
    if (AppEnv.isTestMode) {
      if (keyword.trim().isEmpty) return [];
      return List<Movie>.generate(
        10,
        (i) => Movie(
          id: 'mock_search_${page}_$i',
          name: '搜索结果 ${i + 1}：$keyword',
          rating: 7.5,
          genres: const ['剧情'],
          year: '2024',
          updateStatus: i.isEven ? '已完结' : '更新中',
        ),
      );
    }
    // 显式指定源（多源并发搜索用）：不经过 [_currentSource] 的保存/恢复，
    // 避免 4 路并发互相踩对方的临时切换，导致搜索后当前源被留错。
    if (_currentSource == null && source == null) return [];
    if (keyword.trim().isEmpty) return [];

    try {
      // 第 1 页：拿到本页结果 + 总页数 pagecount。
      final first = await _fetchSearchPageRaw(keyword, page, source: source);
      // 实际翻到的最后一页（受单源页数上限约束）。
      final upper = first.pagecount > maxPages ? maxPages : first.pagecount;
      final all = <Movie>[...first.movies];

      // 翻页聚合：把后续页并发拉取并合并（同一源内按 id 去重）。
      if (first.pagecount > page) {
        final pages = <int>[];
        for (var p = page + 1; p <= upper; p++) {
          pages.add(p);
        }
        if (pages.isNotEmpty) {
          final rest = await _mapInBatches<int, List<Movie>>(
            pages,
            3,
            (p) => _fetchSearchPageRaw(keyword, p, source: source)
                .then((r) => r.movies),
          );
          final seen = <String>{...all.map((m) => m.id)};
          for (final list in rest) {
            for (final m in list) {
              if (!seen.contains(m.id)) {
                seen.add(m.id);
                all.add(m);
              }
            }
          }
        }
      }

      debugPrint('📊 搜索结果: keyword=$keyword, 获取到 ${all.length} 条'
          '（共 ${first.pagecount} 页，已聚合至第 $upper 页）');
      // F2：统一补上来源 sourceId，避免下游（推荐卡、换源匹配）拿到空源。
      final resolvedSourceId = (source ?? _currentSource)?.id ?? '';
      final withSource = resolvedSourceId.isEmpty
          ? all
          : all
              .map((m) => m.sourceId.isEmpty
                  ? m.copyWith(sourceId: resolvedSourceId)
                  : m)
              .toList();
      return withSource;
    } catch (e) {
      debugPrint('搜索影片失败: $e');
      return [];
    }
  }

  /// 取单页关键词搜索结果，并解析响应里的 `pagecount`（供翻页聚合使用）。
  ///
  /// [source] 显式指定搜索源；为空则用当前源 [_currentSource]。
  Future<_SearchPageResult> _fetchSearchPageRaw(String keyword, int page,
      {PlaySource? source}) async {
    final target = source ?? _currentSource;
    if (target == null) return _emptySearchPage;
    try {
      final url = '${target.url}'
          '?ac=detail&wd=${Uri.encodeQueryComponent(keyword)}&pg=$page';
      final rawData = await _httpGet(url);
      if (rawData == null) return _emptySearchPage;
      final json = _parseResponseData(rawData);
      final movies = _parseMovieListFromResponse(rawData);
      final pagecount =
          int.tryParse(json?['pagecount']?.toString() ?? '1') ?? 1;
      return _SearchPageResult(
        movies: movies,
        pagecount: pagecount < 1 ? 1 : pagecount,
        page: page,
      );
    } catch (e) {
      debugPrint('搜索第 $page 页失败: $e');
      return _emptySearchPage;
    }
  }

  // 分类名 → type_id 的匹配已迁移至 `CmsCategoryResolver`：
  // 采集站把内容挂在子类（动作片 / 喜剧片…），旧实现只返回单个父类 id，
  // 于是「电影」只剩个位数条目（2026-09-29 修复）。

  /// 去重键统一走 [MovieDedupe]，避免与 Provider 层口径漂移。
  static String _dedupeKeyForMovie(Movie m) => MovieDedupe.key(m);

  /// 分类树缓存（源 url → 节点表），避免每个子类请求都重拉一次 `ac=list`。
  final Map<String, _CategoryTreeCacheEntry> _categoryTreeCache = {};

  /// 分类树缓存的源数量上限（超出淘汰最旧的）。
  ///
  /// 缓存条目持有整棵分类树节点列表；用户增删播放源后条目单调增长，
  /// 不设上限就是无界缓存。
  static const int _maxCategoryTreeCacheEntries = 16;

  /// 分类树缓存有效期。
  static const Duration _categoryTreeTtl = Duration(minutes: 10);

  /// 同一源内多个子类并发取页的并发度，兼顾速度与站点限流。
  static const int _categoryFetchConcurrency = 6;

  /// 单关键词单源搜索最多翻页数（每页约 20 条）。
  ///
  /// 苹果CMS `wd=` 搜索是分页的（通常 20 条/页，响应带 `pagecount`）。
  /// 旧实现只取 `pg=1`，导致「周星驰」这类同名多作品只返回 ~20 条。
  /// 翻页聚合后单源最多拿到 `_maxSearchPagesPerSource × 20` 条；
  /// 上限是为了避免对站点发起过多请求被限流。
  static const int _maxSearchPagesPerSource = 10;

  /// 分类节点表（含 `type_pid` 父子关系，部分站点缺该字段）。
  Future<Map<int, CmsCategoryNode>> categoryTreeForSourceUrl(
    String sourceUrl,
  ) async {
    final hit = _categoryTreeCache[sourceUrl];
    if (hit != null &&
        DateTime.now().difference(hit.fetchedAt) < _categoryTreeTtl) {
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
    while (_categoryTreeCache.length > _maxCategoryTreeCacheEntries) {
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

  /// 切 Tab 首屏默认展开的子类数（每个子类 1 页）。
  ///
  /// 实测代价（2026-10-21）：「电影」全展开 = 12 子类 × 5 源 ≈ 60 个
  /// `ac=detail` 请求、每页 961KB ≈ **57MB**，首屏要等 10s 以上。
  /// 收到 3 个子类 ≈ 15 请求 ≈ 14MB，约 2s 出内容；其余子类等用户点
  /// 「小分类」chip 再按需拉取（见 [_expandTypeIds] 的 [subClassId]）。
  static const int defaultSubClassCount = 3;

  /// 分批并发执行，避免一次抛出几十个请求把站点打限流。
  static Future<List<T>> _mapInBatches<S, T>(
    List<S> items,
    int batchSize,
    Future<T> Function(S item) run,
  ) async {
    final out = <T>[];
    for (var i = 0; i < items.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, items.length);
      out.addAll(await Future.wait(items.sublist(i, end).map(run)));
    }
    return out;
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
      limit: allSubClasses ? null : (limit ?? defaultSubClassCount),
    );
    if (typeIds.isEmpty) {
      debugPrint('⚠️ 源 ${source.name} 无分类「$category」，跳过该源');
      return const CmsListPage(movies: [], hasMore: false, unsupported: true);
    }
    final pages = await _mapInBatches<int, CmsListPage>(
      typeIds,
      _categoryFetchConcurrency,
      (tid) => _fetchCmsListPageForSource(
        source,
        page: page,
        typeId: tid,
        area: region,
        year: year,
      ),
    );
    return _mergeCategoryPages(pages);
  }

  /// 合并同一分类下多个子类的同页结果（按 名称+年份 去重，保持子类顺序）。
  static CmsListPage _mergeCategoryPages(List<CmsListPage> pages) {
    final seen = <String>{};
    final movies = <Movie>[];
    var hasMore = false;
    for (final p in pages) {
      if (p.hasMore) hasMore = true;
      for (final m in p.movies) {
        if (seen.add(_dedupeKeyForMovie(m))) movies.add(m);
      }
    }
    return CmsListPage(
      movies: movies,
      hasMore: hasMore && movies.isNotEmpty,
      unsupported: pages.isNotEmpty && pages.every((p) => p.unsupported),
    );
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
        if (seen.add(_dedupeKeyForMovie(m))) merged.add(m);
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
        if (seen.add(_dedupeKeyForMovie(m))) merged.add(m);
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
      final pages = await _mapInBatches<int, CmsListPage>(
        typeIds,
        2,
        (tid) => _fetchCmsListPageForSource(
          source,
          page: page,
          typeId: tid,
        ),
      );
      return _mergeCategoryPages(pages);
    } catch (e) {
      debugPrint('类型检索失败（${source.name} / $genre）: $e');
      return const CmsListPage(movies: [], hasMore: false, unsupported: true);
    }
  }

  /// 按**一组片名**批量检索（人名搜索用：豆瓣给出代表作，逐部按片名搜源站）。
  ///
  /// 与 [searchFromAllSources] 的区别：
  /// * 只取每个片名的**第 1 页**（人名搜索要的是「这个人有哪些片」，
  ///   不是某部片的全部资源，补页纯属浪费）；
  /// * **不做关键词相关性过滤** —— 关键词是人名，片名当然不含它；
  /// * 但对**作品名本身**做精确匹配 + 年份校验。实测 `wd=功夫` 返回 83 条
  ///   （功夫女足 / 功夫星猫 / 功夫小子闯佛山…），不校验的话「搜周星驰」
  ///   会出来一堆无关的「功夫 XX」；
  /// * 每批 3 部并发，避免 8 部 × 6 源 = 48 个请求同时打出去被限流。
  Future<List<Movie>> searchByTitles(
    List<TitleQuery> works, {
    required List<PlaySource> sources,
    int maxTitles = 6,
  }) async {
    final picked = works
        .where((w) => w.title.trim().isNotEmpty)
        .take(maxTitles)
        .toList(growable: false);
    if (picked.isEmpty || sources.isEmpty) return const [];

    final perTitle = await _mapInBatches<TitleQuery, List<Movie>>(
      picked,
      3,
      (work) async {
        final out = <Movie>[];
        await for (final event in _searchSourcesConcurrently(
          sources,
          work.title.trim(),
          1,
          // 只要第 1 页：人名搜索要的是「这个人有哪些片」，不是某部片的
          // 全部资源。补页会让 6 部作品 × N 个源炸成几百个请求。
          fillPages: false,
        )) {
          if (event.error != null) continue;
          final hits = event.movies
              .where((m) => matchesTitleQuery(m.name, m.year, work))
              .toList(growable: false);
          if (hits.isEmpty) continue;
          _mergeMultiSourceSearchResults(out, hits, event.source);
        }
        // 精确同名的排前面（「喜剧之王」1999 要压过「喜剧之王单口季」）。
        final exact = _relevanceKey(work.title);
        out.sort((a, b) {
          final ae = _relevanceKey(a.name) == exact ? 0 : 1;
          final be = _relevanceKey(b.name) == exact ? 0 : 1;
          if (ae != be) return ae - be;
          return b.rating.compareTo(a.rating);
        });
        return out;
      },
    );

    // 跨作品去重：同一个源的不同作品之间可能重复（续集/合集），
    // 以及同一部片被算进两部代表作里。
    final all = <Movie>[];
    for (final list in perTitle) {
      for (final m in list) {
        final idx = all.indexWhere((e) => isSameMovieForMerge(e, m));
        if (idx < 0) {
          all.add(m);
          continue;
        }
        final keeper = all[idx];
        if (keeper.alternateSources.isEmpty && m.alternateSources.isEmpty) {
          continue;
        }
        all[idx] = keeper.copyWith(
          alternateSources: [
            ...keeper.alternateSources,
            ...m.alternateSources.where(
              (a) => !keeper.alternateSources.any(
                (b) => b.sourceId == a.sourceId && b.movieId == a.movieId,
              ),
            ),
          ],
        );
      }
    }
    return all;
  }

  /// 逐个片名去源站查，**第一个命中的源就停**（2026-10-28）。
  ///
  /// 为什么不做「全源并发」：人名通道现在要查几十部片（周星驰 58 部），
  /// 全源并发 = 58 × 6 源 ≈ 350 个请求，而且每部都要等**最慢的那个源**
  /// 才返回，实测能把整轮拖到分钟级。实测量子资源对这批老片的命中率是
  /// 52/56 ≈ 93%，按源顺序试、命中即停，平均每部 1.1 个请求。
  Future<List<Movie>> _searchOneTitleFirstHit(
    TitleQuery work,
    List<PlaySource> sources,
  ) async {
    final keyword = work.title.trim();
    if (keyword.isEmpty) return const [];
    for (final source in sources) {
      final events = <SourceSearchResult>[];
      try {
        await _searchSingleSourceStaged(
          source,
          keyword,
          1,
          events.add,
          // 只要第 1 页：要的是「这部片在不在」，不是它的全部线路。
          fillPages: false,
        );
      } catch (e) {
        debugPrint('按片名检索失败（${source.name} / $keyword）: $e');
        continue;
      }
      final out = <Movie>[];
      for (final event in events) {
        if (event.error != null) continue;
        final hits = event.movies
            .where((m) => matchesTitleQuery(m.name, m.year, work))
            // 解说类不是正片（`功夫[电影解说]` 也能命中「功夫」）：
            // 过滤后若一条不剩，会继续试下一个源，而不是把「只有解说版」
            // 当成这部片已经找到了。
            .where((m) => !CommentaryContentFilter.isMovie(m))
            .toList(growable: false);
        if (hits.isEmpty) continue;
        _mergeMultiSourceSearchResults(out, hits, event.source);
      }
      if (out.isNotEmpty) return out;
    }
    return const [];
  }

  /// 人名搜索的**全量作品**通道（2026-10-28）。
  ///
  /// 与 [searchByTitles] 的区别：
  /// * 上限从 6 部提到 [maxTitles]（默认 120）—— 豆瓣作品全集能给出
  ///   71 部电影（含导演身份），卡在 40 部等于把后面的作品全丢了；
  /// * 每部「首个命中源即停」，不是全源并发（见 [_searchOneTitleFirstHit]）；
  /// * [onProgress] 每命中一部就回调**累计结果**，页面可以边查边投递，
  ///   用户看到 30 → 38 → 45 逐步长出来，而不是转圈等一次性替换。
  Future<List<Movie>> searchPersonWorks(
    List<TitleQuery> works, {
    required List<PlaySource> sources,
    int maxTitles = 120,
    void Function(List<Movie> merged)? onProgress,
  }) async {
    final picked = works
        .where((w) => w.title.trim().isNotEmpty)
        .take(maxTitles)
        .toList(growable: false);
    if (picked.isEmpty || sources.isEmpty) return const [];

    final merged = <Movie>[];
    await _mapInBatches<TitleQuery, int>(picked, 3, (work) async {
      final hits = await _searchOneTitleFirstHit(work, sources);
      if (hits.isEmpty) return 0;
      for (final m in hits) {
        // 同一部片可能被两个作品名同时命中（续集/合集），只留一份。
        if (merged.any((e) => isSameMovieForMerge(e, m))) continue;
        merged.add(m);
      }
      onProgress?.call(List<Movie>.unmodifiable(merged));
      return 1;
    });
    return merged;
  }

  /// 一条源站结果是否真的是 [work] 这部片（纯函数，供单测）。
  ///
  /// 规则：
  /// 1. 归一化后**完全同名** → 命中（年份不参与，源站年份常为空）；
  /// 2. 互相包含 → 只有在**年份一致**时才算命中。这一步是必须的：
  ///    实测 `wd=功夫` 返回 83 条，全是「功夫女足」「功夫星猫」这类，
  ///    而豆瓣给的年份 2004 正好能把它们全部排除。
  @visibleForTesting
  static bool matchesTitleQuery(
      String name, String movieYear, TitleQuery work) {
    final t = _relevanceKey(work.title);
    final n = _relevanceKey(name);
    if (t.isEmpty || n.isEmpty) return false;
    if (n == t) return true;
    if (!n.contains(t) && !t.contains(n)) return false;

    final wy = work.year.trim();
    final my = movieYear.trim();
    if (wy.length != 4 || my.isEmpty) {
      // 没有年份就没法区分同名衍生内容 —— 放行，宁可多留。
      return true;
    }
    return my == wy;
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
        DateTime.now().difference(hit.fetchedAt) >= _categoryTreeTtl) {
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

  /// 解析API响应中的影片列表
  List<Movie> _parseMovieListFromResponse(dynamic data) {
    try {
      final json = _parseResponseData(data);
      if (json == null) return [];

      // 安全检查 list 字段类型
      final listRaw = json['list'];
      if (listRaw is! List || listRaw.isEmpty) return [];

      return listRaw
          .whereType<Map<String, dynamic>>()
          .map((e) => Movie.fromCmsJson(e))
          .where((m) => !CommentaryContentFilter.isMovie(m))
          .toList();
    } catch (e) {
      debugPrint('解析影片列表失败: $e');
      return [];
    }
  }

  /// 解析响应数据
  ///
  /// 苹果CMS返回格式：
  /// {
  ///   "code": 200,
  ///   "msg": "ok",
  ///   "page": 1,
  ///   "pagecount": 100,
  ///   "limit": "20",
  ///   "total": 2000,
  ///   "list": [...],
  ///   "class": [...]
  /// }
  Map<String, dynamic>? _parseResponseData(dynamic data) {
    try {
      Map<String, dynamic> json;
      if (data is String) {
        // 清理字符串：去除 BOM、尾部空白、控制字符
        String cleaned = data.trim();
        cleaned =
            cleaned.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
        json = jsonDecode(cleaned) as Map<String, dynamic>;
      } else if (data is Map<String, dynamic>) {
        json = data;
      } else {
        return null;
      }

      // 检查返回码（苹果CMS通常返回1或200表示成功）
      final code = json['code'];
      if (code != null &&
          code != 200 &&
          code != '200' &&
          code != 1 &&
          code != '1') {
        debugPrint('API返回错误码: $code, 消息: ${json['msg']}');
        return null;
      }

      return json;
    } catch (e) {
      debugPrint('解析响应数据失败: $e');
      return null;
    }
  }

  /// 检测源是否有效
  ///
  /// 苹果CMS检测方式：GET {url}?ac=list
  /// 检查是否返回200状态码和正确的JSON格式
  Future<bool> checkSource(PlaySource source) async {
    try {
      final url = '${source.url}?ac=list';
      final rawData = await _httpGet(url);
      if (rawData == null) return false;

      final json = jsonDecode(rawData) as Map<String, dynamic>;
      final code = json['code'];
      return code == 200 || code == '200' || code == 1 || code == '1';
    } catch (e) {
      debugPrint('检测源失败: ${source.url}, 错误: $e');
      return false;
    }
  }

  /// 去掉片名末尾季数，便于搜到同系列其它季（如「…第四季」→「…这档事」前的基名）。
  static String stripSeasonFromTitleForRecommend(String name) {
    var t = name.trim();
    final m1 = RegExp(r'第[一二三四五六七八九十百千万零两〇0-9]+季').firstMatch(t);
    if (m1 != null && m1.start > 0) {
      return t.substring(0, m1.start).trim();
    }
    final m2 = RegExp(r'(?:第)?[一二三四五六七八九十0-9]+季\s*$').firstMatch(t);
    if (m2 != null && m2.start >= 2) {
      return t.substring(0, m2.start).trim();
    }
    t = t.replaceAll(RegExp(r'\s*[Ss]\d{1,2}\s*$'), '').trim();
    return t;
  }

  /// 详情页侧栏「相关推荐」：用**类型、去季片名、全名**等对当前源做 `wd` 搜索并去重合并。
  ///
  /// 苹果 CMS 无独立推荐接口；旧逻辑仅用 [Movie.genres] 第一项且常与 [_loadData] 竞态，导致大量「暂无推荐」。
  Future<List<Movie>> getDetailSideRecommendations(Movie movie) async {
    if (_currentSource == null) return [];

    if (AppEnv.isTestMode) {
      return List<Movie>.generate(
        5,
        (i) => Movie(
          id: 'mock_rec_$i',
          name: '推荐 ${i + 1}（${movie.name}）',
          rating: 8.0,
          genres: movie.genres.isNotEmpty ? movie.genres : const ['剧情'],
          year: movie.year.isNotEmpty ? movie.year : '2024',
        ),
      );
    }

    final movieId = movie.id;
    final out = <Movie>[];
    final seen = <String>{};

    Future<void> tryKeyword(String raw, {int minNameScore = 0}) async {
      final kw = raw.trim();
      if (kw.length < 2) return;
      try {
        // 相关推荐只需首页（最多 ~20 条），避免翻页聚合在详情页发起过多请求。
        final list = await searchMovies(kw, page: 1, maxPages: 1);
        for (final m in list) {
          if (m.id == movieId) continue;
          // 仅兜底用的弱关键词（类型词）要求名字与当前片有包含/相似关系，
          // 否则会混入「剧情攻略手册」这类纯类型词垃圾。
          if (minNameScore > 0 &&
              DetailSourceMatcher.nameScore(m.name, movie.name) <
                  minNameScore) {
            continue;
          }
          if (seen.contains(m.id)) continue;
          seen.add(m.id);
          out.add(m);
          if (out.length >= 10) return;
        }
      } catch (e) {
        debugPrint('推荐搜索失败 keyword=$kw: $e');
      }
    }

    // 主推：与当前片强相关的关键词（同一作品 / 同导演 / 别名）。
    if (movie.name.trim().length >= 2) {
      await tryKeyword(movie.name.trim());
    }
    final baseTitle = stripSeasonFromTitleForRecommend(movie.name);
    if (baseTitle.length >= 2 && baseTitle != movie.name.trim()) {
      await tryKeyword(baseTitle);
    }
    if (out.length < 6 && movie.alias.trim().length >= 2) {
      await tryKeyword(movie.alias.trim());
    }
    if (out.length < 6 && movie.director.trim().length >= 2) {
      await tryKeyword(movie.director.trim());
    }

    // 兜底：类型词只取前两个 genre 的第一段，并过滤名字明显无关的，
    // 避免旧逻辑把「动作/爱情」等类型词全量搜出的垃圾塞进推荐。
    if (out.length < 6) {
      for (final g in movie.genres.take(2)) {
        final part = g.split(RegExp(r'[,，/、]')).first.trim();
        if (part.length >= 2) {
          await tryKeyword(part, minNameScore: 70);
          if (out.length >= 10) break;
        }
      }
    }

    return out.take(10).toList();
  }

  /// 获取影片推荐（先拉详情再走 [getDetailSideRecommendations]）
  Future<List<Movie>> getRecommendations(String movieId) async {
    if (_currentSource == null) return [];

    try {
      final movie = await getMovieDetail(movieId);
      if (movie == null) return [];
      return getDetailSideRecommendations(movie);
    } catch (e) {
      debugPrint('获取推荐失败: $e');
      return [];
    }
  }

  /// 多源并发搜索
  ///
  /// 并发请求所有已启用的源，通过 Stream 流式返回结果。
  /// 源列表由调用方通过 [sources] 参数传入，避免 ApiService 内部依赖 Provider。
  Stream<MultiSourceSearchEvent> searchFromAllSources(
    String keyword, {
    required List<PlaySource> sources,
    int page = 1,
    SearchRelevance relevance = SearchRelevance.strict,
  }) async* {
    if (keyword.trim().isEmpty || sources.isEmpty) {
      yield MultiSourceSearchProgress(
        completed: 0,
        total: 0,
        results: [],
      );
      return;
    }

    int completedCount = 0;
    int readyCount = 0;
    int finalCount = 0;
    final countedReady = <String>{};
    final allResults = <Movie>[];

    /// 本轮是否有源因为「严格片名匹配一条都没有」而被放宽了一档。
    /// 传给 UI 用于提示，避免用户以为自己搜的词被悄悄换了。
    var relaxedAny = false;

    // 先发送初始进度事件。
    // 注意：results 必须发**防御性拷贝**，不能发 allResults 活引用——
    // 下方合并会原地改 allResults，消费者（provider 的 _multiSearchResults
    // 直接存 event.results 引用）若在事件之间读它，会看到与 completed/
    // readySources/statusText 自相矛盾的数据（初始事件说"0/1 个源"，
    // 列表里却已经躺着合并后的结果）。后续事件（下方）发的就是拷贝，
    // 初始事件漏了这层，被 api_service_multi_source_stream_test 抓个正着。
    yield MultiSourceSearchProgress(
      completed: 0,
      total: sources.length,
      results: List<Movie>.from(allResults),
    );

    // 并发请求所有源，谁先返回谁先处理
    await for (final event
        in _searchSourcesConcurrently(sources, keyword, page)) {
      if (event.error != null) {
        debugPrint('源 "${event.source.name}" 搜索失败: ${event.error}');
      }

      final beforeLen = allResults.length;
      // 2026-10-28 用户反馈「搜出来的影视资源一大半不相干」：
      // 采集站搜索是模糊匹配，会顺带返回续集/同名短片/无关条目，
      // 直接并集后条数轻易破百。这里先按「与关键词相关」过一遍。
      //
      // 但同一个过滤不能套在所有人身上（用户当天第二次反馈「怎么跟二极管
      // 一样」）：搜人名「周星驰」、搜类型「科幻」时，结果片名里本来就不会
      // 出现关键词，硬过滤等于把这些能力全砍掉。所以：
      //   - 人名 / 类型 / 分类 → 调用方传 [SearchRelevance.off]，不过滤；
      //   - 片名 → 严格过滤，但**严格命中为 0 时自动放宽一档**
      //     （[isSearchResultLooselyRelevant]），至少命中一个词就留下，
      //     绝不因为「没人完全对上」而把一个源整个清空。
      final rawMovies = event.movies;
      var sourceMovies = rawMovies;
      var relaxedThisSource = false;
      if (relevance == SearchRelevance.strict && rawMovies.isNotEmpty) {
        final strictHits = rawMovies
            .where((m) => isSearchResultRelevant(keyword, m.name))
            .toList(growable: false);
        if (strictHits.isNotEmpty) {
          sourceMovies = strictHits;
        } else {
          final looseHits = rawMovies
              .where((m) => isSearchResultLooselyRelevant(keyword, m.name))
              .toList(growable: false);
          // 一个词都不沾 → 真的无关，保持为空（宁缺勿滥）；
          // 沾了至少一个词 → 放宽保留，并给 UI 一个提示。
          sourceMovies = looseHits;
          relaxedThisSource = looseHits.isNotEmpty;
        }
      }
      if (relaxedThisSource) relaxedAny = true;
      final dropped = rawMovies.length - sourceMovies.length;
      if (dropped > 0) {
        debugPrint(
          '源 "${event.source.name}" 过滤无关结果: '
          '${rawMovies.length} → ${sourceMovies.length}（丢弃 $dropped 条，'
          '${relaxedThisSource ? "已放宽片名匹配" : "严格片名匹配"}）',
        );
      }
      _mergeMultiSourceSearchResults(allResults, sourceMovies, event.source);
      // 两段式投递：阶段 1（第 1 页）与阶段 2（补齐页）分属两次事件。
      //   - 该源第一次投递 → 计入「已出结果的源数」（用户感知的进度）；
      //   - 该源最后一次投递（isFinal）→ 计入「彻底搜完的源数」。
      // 单页源只投递一次，两种计数同时 +1。
      if (countedReady.add(event.source.id) && event.error == null) {
        readyCount++;
      }
      if (event.isFinal) {
        completedCount++;
        finalCount++;
      }

      yield MultiSourceSearchProgress(
        completed: completedCount,
        total: sources.length,
        results: List<Movie>.from(allResults),
        newMovies: allResults.length > beforeLen
            ? allResults.sublist(beforeLen)
            : const [],
        readySources: readyCount,
        allSourcesDone: finalCount >= sources.length,
        relevanceRelaxed: relaxedAny,
      );
    }
  }

  /// 最大并发请求数（多源搜索 / 多源详情聚合共用）
  static const _maxConcurrent = 4;

  /// 并发请求多个源
  ///
  /// 谁先返回谁先 yield，实现流式效果。并发上限 [_maxConcurrent]（滑动窗口：
  /// 完成一个补一个，保证全部源都会被搜索到）。
  ///
  /// 实现说明（释放纪律）：合并直接走**单一事件队列**，不为每个源建
  /// StreamController——旧实现给每个源建 controller 再由 [_mergeStreams]
  /// 逐个 listen 转发，存在三个问题：
  /// 1. 装配时快照：窗口滑动后新增的 controller 永远拿不到 listener，
  ///    超过 4 个源时第 5 个以后的结果被静默丢弃、流提前收摊；
  /// 2. 那些 listen 订阅没有取消路径，消费者提前取消即泄漏 N 个订阅；
  /// 3. 两个 Completer 只写不读。
  /// 现在消费者取消时 finally 统一关闭队列，在飞任务的结果因 `isClosed`
  /// 检查而无处可投，任务自然结束后整张对象图即可回收。
  Stream<SourceSearchResult> _searchSourcesConcurrently(
    List<PlaySource> sources,
    String keyword,
    int page, {
    /// 是否在阶段 1 之后**后台补齐第 2..N 页**。
    ///
    /// 首页搜索要补（多拿结果）；而**按片名批量检索**（人名搜索：一次 6 部
    /// 代表作 × N 个源）绝对不能补 —— 每部片、每个源都去拉满 10 页，
    /// 请求量是 6×6×9 ≈ 300+ 个，`await for` 要等它们全部回来才结束，
    /// 表现就是搜「周星驰」转圈两分钟以上还没有任何结果。
    bool fillPages = true,
  }) async* {
    if (sources.isEmpty) return;

    final eventQueue = StreamController<SourceSearchResult>();
    final total = sources.length;
    int running = 0;
    int index = 0;
    int finished = 0;

    // 2026-10-24：后台补齐页（阶段 2）**不再占用并发槽位**。
    //
    // 旧实现里阶段 2 跑在 [_searchSingleSourceStaged] 内部，槽位要等
    // 「补齐最多 10 页」全部结束才释放 → 一个慢源就能占死 4 个槽位中的
    // 一个，排队的第 5~N 个源**连启动都被推迟**。用户观感正是
    // 「第一个主源出来的时间还可以，其他源很慢」：首个源的阶段 1
    // （第 1 页）~2s 就到，屏幕有东西了；但第 5~8 个源要等前面几个源
    // 补完页才开跑，首屏就停在"只有一两个源"。
    //
    // 现在：阶段 1 交付后本方法立即返回 → 槽位立刻给下一个源用；
    // 阶段 2 变成脱离槽位的后台任务，回来后再 deliver 一次。
    // 队列关闭条件相应改为「所有源的阶段 1 都结束 **且** 所有后台补页都结束」。
    int backgroundPending = 0;

    void deliver(SourceSearchResult event) {
      if (!eventQueue.isClosed) eventQueue.add(event);
    }

    void maybeCloseQueue() {
      if (finished >= total && backgroundPending == 0 && !eventQueue.isClosed) {
        unawaited(eventQueue.close());
      }
    }

    void startNext() {
      while (running < _maxConcurrent && index < total) {
        final source = sources[index++];
        running++;
        _searchSingleSourceStaged(
          source,
          keyword,
          page,
          deliver,
          fillPages: fillPages,
          onBackground: (background) {
            backgroundPending++;
            background.whenComplete(() {
              backgroundPending--;
              maybeCloseQueue();
            });
          },
        ).catchError((e) {
          deliver(
            SourceSearchResult(
              source: source,
              movies: [],
              error: e.toString(),
            ),
          );
        }).whenComplete(() {
          running--;
          finished++;
          // 全部源的阶段 1 都已返回（且后台补页已收口）→ 关闭队列，
          // 使 await for 退出。
          maybeCloseQueue();
          startNext();
        });
      }
    }

    try {
      startNext();
      await for (final event in eventQueue.stream) {
        yield event;
      }
    } finally {
      // 消费者提前取消 / 上游异常：关闭队列收口。在飞请求（Dio 有 30s
      // 超时）无法取消，但 deliver 内判 isClosed，其结果不会进入队列，
      // 请求结束后引用链自然断开。
      if (!eventQueue.isClosed) unawaited(eventQueue.close());
    }
  }

  /// 搜索单个源（**两段式投递**）。
  ///
  /// 2026-10-22：原先要等这个源把 [_maxSearchPagesPerSource]（10）页**全部**
  /// 拉完才交付结果，首屏因此被放大约 10 倍（用户反馈「以前秒出，现在很慢」）。
  /// 现在拆成两段：
  ///  * 阶段 1：只取第 1 页 → 立刻 [deliver]，首屏秒回；
  ///  * 阶段 2：后台补齐第 2..N 页 → 再 [deliver] 一次，
  ///    保留「同名多作品」场景下拿到更多结果的能力。
  ///
  /// 2026-10-24：阶段 2 进一步**脱离并发槽位**——阶段 1 交付后本方法立刻
  /// 返回（槽位马上给下一个源用），阶段 2 作为后台任务交给 [onBackground]。
  /// 旧实现阶段 2 占着槽位不放，是「第一个源快、其他源慢」的根因。
  ///
  /// 两段都带同一个 [source]，合并层按 id 去重，不会重复。
  ///
  /// 自动化测试模式直接返回稳定的模拟结果（单段）。
  Future<void> _searchSingleSourceStaged(
    PlaySource source,
    String keyword,
    int page,
    void Function(SourceSearchResult) deliver, {
    bool fillPages = true,
    void Function(Future<void> background)? onBackground,
  }) async {
    final sid = source.id;
    List<Movie> tag(List<Movie> list) => list
        .map((m) => m.sourceId.isEmpty ? m.copyWith(sourceId: sid) : m)
        .toList();

    if (AppEnv.isTestMode) {
      final mock = List<Movie>.generate(
        10,
        (i) => Movie(
          id: 'mock_search_${page}_$i',
          name: '搜索结果 ${i + 1}：$keyword',
          rating: 7.5,
          genres: const ['剧情'],
          year: '2024',
          updateStatus: i.isEven ? '已完结' : '更新中',
        ),
      );
      deliver(SourceSearchResult(source: source, movies: tag(mock)));
      return;
    }

    // 阶段 1：只取第 1 页。
    final first = await _fetchSearchPageRaw(keyword, page, source: source);
    final upper = first.pagecount > _maxSearchPagesPerSource
        ? _maxSearchPagesPerSource
        : first.pagecount;

    // 没有后续页 → 一次性交付（isFinal=true）。
    // 这样「只有 1 页的源」仍然只产生**一个**事件，与两段式之前的契约一致
    // （既有流式测试依赖这个不变量）。
    if (!fillPages || first.pagecount <= page || upper <= page) {
      deliver(
        SourceSearchResult(
          source: source,
          movies: tag(first.movies),
          isFinal: true,
        ),
      );
      return;
    }

    // 有后续页 → 阶段 1 先交付，阶段 2 补齐后再交付。
    deliver(
      SourceSearchResult(
        source: source,
        movies: tag(first.movies),
        isFinal: false,
      ),
    );

    // 阶段 2：补齐后续页（同一源内按 id 去重）。
    // 2026-10-24：作为**脱离槽位的后台任务**启动，本方法立刻返回 →
    // 并发槽位立刻空出来给下一个源，补齐页回来后再 deliver 一次。
    final background = _fetchRemainingPages(
      keyword: keyword,
      source: source,
      page: page,
      upper: upper,
      firstMovies: first.movies,
      tag: tag,
      deliver: deliver,
    );
    onBackground?.call(background);
  }

  /// 阶段 2：补齐第 2..N 页（**后台任务**，不占并发槽位）。
  ///
  /// 独立成方法，是为了让 [_searchSingleSourceStaged] 交付阶段 1 后能立刻
  /// 返回，把槽位让给排队中的下一个源。异常在这里就地吞掉（不能让后台
  /// 任务的错误变成未捕获异常），补页失败只是少几页结果，不影响已交付的
  /// 阶段 1。
  Future<void> _fetchRemainingPages({
    required String keyword,
    required PlaySource source,
    required int page,
    required int upper,
    required List<Movie> firstMovies,
    required List<Movie> Function(List<Movie>) tag,
    required void Function(SourceSearchResult) deliver,
  }) async {
    try {
      final rest = <Movie>[];
      final pages = <int>[];
      for (var p = page + 1; p <= upper; p++) {
        pages.add(p);
      }
      if (pages.isNotEmpty) {
        final batches = await _mapInBatches<int, List<Movie>>(
          pages,
          3,
          (p) => _fetchSearchPageRaw(keyword, p, source: source)
              .then((r) => r.movies),
        );
        final seen = <String>{...firstMovies.map((m) => m.id)};
        for (final list in batches) {
          for (final m in list) {
            if (seen.add(m.id)) rest.add(m);
          }
        }
      }
      deliver(
        SourceSearchResult(
          source: source,
          movies: tag(rest),
          isFinal: true,
        ),
      );
    } catch (e) {
      debugPrint('源 "${source.name}" 补齐页失败: $e');
    }
  }

  /// 多源搜索合并：同款影片只保留一行，并把其它源的 [MovieAlternateSource] 记在首条上。
  void _mergeMultiSourceSearchResults(
    List<Movie> allResults,
    List<Movie> newMovies,
    PlaySource source,
  ) {
    for (final raw in newMovies) {
      final movie =
          raw.sourceId.isEmpty ? raw.copyWith(sourceId: source.id) : raw;

      final idx = allResults.indexWhere((e) => isSameMovieForMerge(e, movie));
      if (idx < 0) {
        allResults.add(movie);
        continue;
      }

      final keeper = allResults[idx];
      if (keeper.id == movie.id && keeper.sourceId == movie.sourceId) {
        continue;
      }
      if (keeper.sourceId == movie.sourceId) {
        continue;
      }
      final exists = keeper.alternateSources.any(
        (a) => a.sourceId == movie.sourceId && a.movieId == movie.id,
      );
      if (exists) continue;

      allResults[idx] = keeper.copyWith(
        alternateSources: [
          ...keeper.alternateSources,
          MovieAlternateSource(
            sourceId: movie.sourceId,
            movieId: movie.id,
            sourceDisplayName: source.name,
          ),
        ],
      );
    }
  }

  /// 判断是否为同一部影片（严格匹配）
  ///
  /// 判定两条搜索结果是否为同一部影片（**季数感知**）—— 公开以便单测。
  ///
  /// 规则：**季数一致** + 名称标准化后一致 + 年份一致 + 类型有交集。
  ///
  /// ⚠️ 季数必须要比：`_normalizeName` 会抹掉「第 X 季」，
  /// 而采集站是把每一季当作**独立影片**收录的（如「万妖图录传第七季 /
  /// 第九季 / 第十季」各自有 vod_id）。若不做季数判定，多源聚合会把
  /// 同一部剧的所有季合并成一行 —— 用户搜索「万妖图录传」就只能看到
  /// 第一条命中的季（通常是最早返回的源返回的那一季），其余季全丢。
  static bool isSameMovieForMerge(Movie a, Movie b) {
    // 季数必须一致（都无季数、或都是同一季）。中文写法与阿拉伯写法归一化后比较，
    // 因此「第七季」与「第 7 季」算同一季。
    if (seasonKeyOfName(a.name) != seasonKeyOfName(b.name)) return false;

    // 名称比较：用抹掉季数后的「基名」，这样不同写法（空格/第7季 vs 第七季）
    // 仍能归一到同一部剧；季数差异已由上一步挡掉。
    final nameA = _normalizeName(a.name);
    final nameB = _normalizeName(b.name);
    if (nameA != nameB) return false;

    // 年份比较（如果双方都有年份）
    if (a.year.isNotEmpty && b.year.isNotEmpty && a.year != b.year) {
      return false;
    }

    // 类型比较（如果双方都有类型，取交集判断）
    if (a.genres.isNotEmpty && b.genres.isNotEmpty) {
      final hasOverlap = a.genres.any((g) => b.genres.contains(g));
      if (!hasOverlap) return false;
    }

    return true;
  }

  static final RegExp _seasonCnRe = RegExp(
    r'第\s*([0-9]+|[一二三四五六七八九十百千万零两〇]+)\s*[季部]',
  );
  static final RegExp _seasonEnRe = RegExp(
    r'[Ss]eason\s*([0-9]{1,2})|(?:^|[^A-Za-z0-9])[Ss]([0-9]{1,2})(?![0-9])',
  );

  /// 抽取片名里的季数标识，统一成 `S<数字>`（无季数返回空串）。
  ///
  /// 支持「第七季 / 第7季 / 第七部 / Season 7 / S07」等常见写法，
  /// 用于判定两条结果是否为**同一季**。
  static String seasonKeyOfName(String name) {
    final cn = _seasonCnRe.firstMatch(name);
    if (cn != null) {
      final n = _parseSeasonNumber(cn.group(1)!);
      if (n != null) return 'S$n';
    }
    final en = _seasonEnRe.firstMatch(name);
    final g = en?.group(1) ?? en?.group(2);
    if (g != null) {
      final n = int.tryParse(g);
      if (n != null) return 'S$n';
    }
    return '';
  }

  /// 解析季数（阿拉伯数字或中文数字），如「7」「十一」。
  static int? _parseSeasonNumber(String raw) {
    final direct = int.tryParse(raw);
    if (direct != null) return direct;

    const digits = <String, int>{
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    const units = <String, int>{'十': 10, '百': 100, '千': 1000};

    var section = 0;
    var number = 0;
    for (final ch in raw.split('')) {
      final d = digits[ch];
      if (d != null) {
        number = d;
        continue;
      }
      final u = units[ch];
      if (u == null) return null;
      section += (number == 0 ? 1 : number) * u;
      number = 0;
    }
    final total = section + number;
    return total > 0 ? total : null;
  }

  /// 标准化影片名称
  ///
  /// [keepSeason] 为 false（默认）时抹掉「第 X 季/部」后缀，用于跨源匹配同一部剧；
  /// 为 true 时保留季数，用于区分同剧的不同季。
  static String _normalizeName(String name, {bool keepSeason = false}) {
    var s = name
        .replaceAll(RegExp(r'\s+'), '') // 去除空格
        .replaceAll(RegExp(r'[·\-_:：]'), ''); // 去除常见分隔符
    if (!keepSeason) {
      s = s
          .replaceAll(RegExp(r'第[一二三四五六七八九十\d]+季'), '') // 去除季数后缀
          .replaceAll(RegExp(r'第[一二三四五六七八九十\d]+部'), ''); // 去除部数后缀
    }
    return s.toLowerCase();
  }

  static final RegExp _cjkRe = RegExp(r'[\u4e00-\u9fff]');

  /// 只保留「中日韩汉字 + 英文字母 + 数字」，用于相关性比较。
  ///
  /// 采集站的片名常带书名号、年份括号、副标题分隔符，不归一化会漏判。
  static String _relevanceKey(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\u4e00-\u9fffa-z0-9]'), '');

  /// 判断一条 CMS 搜索结果是否与用户输入的关键词**相关**。
  ///
  /// ## 为什么需要它（2026-10-28 用户反馈）
  ///
  /// 搜索页「影视资源(N)」是**所有已启用采集源结果的直接并集**
  /// （见 [searchFromAllSources] → [_mergeMultiSourceSearchResults]），
  /// 去重口径只有 [isSameMovieForMerge]（季数 + 片名 + 年份 + 类型），
  /// **没有任何相关性判断**。而采集站自身的搜索是模糊匹配，会顺带返回
  /// 续集、同名短片、同演员合集甚至完全不相关的条目；6 个源 × 每源
  /// 20~30 条 → 条数轻松破百（实测搜「流浪地球」= 154 条），
  /// 用户观感就是「一堆不相干的东西」。
  ///
  /// 磁力侧早已有同口径过滤（[isTorrentResultRelevant]），CMS 侧补齐。
  ///
  /// ## 判定规则（偏宽松，宁可多留不可错杀）
  /// 1. 关键词为空 → 放行；
  /// 2. 关键词与结果名**一个含中文、一个不含** → 跨语种无法可靠比较，放行
  ///    （部分采集站只收录英文名，硬过滤会把整源清空）；
  /// 3. 归一化后互相包含（「流浪地球」⊂「流浪地球2：...」）→ 相关；
  /// 4. 否则按非字母数字切词，命中过半 → 相关。
  static bool isSearchResultRelevant(String keyword, String movieName) {
    final q = _relevanceKey(keyword);
    if (q.isEmpty) return true;
    final n = _relevanceKey(movieName);
    if (n.isEmpty) return false;

    // 跨语种（中文关键词 vs 英文片名，或反之）不做判断。
    if (_cjkRe.hasMatch(keyword) != _cjkRe.hasMatch(movieName)) return true;

    if (n.contains(q) || q.contains(n)) return true;

    final tokens = _relevanceTokens(keyword);
    if (tokens.isEmpty) return false;
    var hit = 0;
    for (final t in tokens) {
      if (n.contains(t)) hit++;
    }
    return hit * 2 >= tokens.length;
  }

  /// 比 [isSearchResultRelevant] 更宽的判定：**命中任意一个词**即算相关。
  ///
  /// 用途只有一个：严格过滤把某个源清空时的**兜底**。严格判定要求「过半数
  /// 词命中」，搜「流浪地球2 飞跃2020」时源站返回的《流浪地球》只命中一个词
  /// 会被判不相关 —— 全部源都这样时用户看到「没有结果」，但源站其实找到了
  /// 相关的片子。放宽到「命中 1 个词」既能兜住这种情况，又不会把完全无关的
  /// 条目放进来（一个词都不沾的仍然丢弃）。
  static bool isSearchResultLooselyRelevant(String keyword, String movieName) {
    final q = _relevanceKey(keyword);
    if (q.isEmpty) return true;
    final n = _relevanceKey(movieName);
    if (n.isEmpty) return false;
    if (_cjkRe.hasMatch(keyword) != _cjkRe.hasMatch(movieName)) return true;
    if (n.contains(q) || q.contains(n)) return true;

    final tokens = _relevanceTokens(keyword);
    if (tokens.isEmpty) return false;
    for (final t in tokens) {
      if (n.contains(t)) return true;
    }
    return false;
  }

  static List<String> _relevanceTokens(String keyword) => keyword
      .toLowerCase()
      .split(RegExp(r'[^\u4e00-\u9fffa-z0-9]+'))
      .where((t) => t.length >= 2)
      .toList();
}

/// 首页数据
class HomeData {
  /// 轮播图列表
  final List<Movie> bannerList;

  /// 热门推荐
  final List<Movie> hotMovies;

  /// 最近更新
  final List<Movie> latestMovies;

  /// 高分榜单
  final List<Movie> topRatedMovies;

  /// 经典合集
  final List<Movie> classicMovies;

  HomeData({
    this.bannerList = const [],
    this.hotMovies = const [],
    this.latestMovies = const [],
    this.topRatedMovies = const [],
    this.classicMovies = const [],
  });

  /// 无数据时返回空状态（使用mock数据展示）
  factory HomeData.empty() {
    return HomeData(
      bannerList: _generateMockMovies(5),
      hotMovies: _generateMockMovies(10),
      latestMovies: _generateMockMovies(10),
      topRatedMovies: _generateMockMovies(10),
      classicMovies: _generateMockMovies(10),
    );
  }

  /// 生成模拟数据（用于无源时的展示）
  static List<Movie> _generateMockMovies(int count) {
    final movies = <Movie>[];
    for (int i = 0; i < count; i++) {
      movies.add(
        Movie(
          id: 'mock_$i',
          name: '示例影片 ${i + 1}',
          cover: '',
          rating: (7.0 + (i % 3)).toDouble(),
          genres: ['动作', '科幻'],
          year: '2024',
          updateStatus: i % 2 == 0 ? '已完结' : '更新至第${i + 1}集',
        ),
      );
    }
    return movies;
  }
}

/// 多源搜索事件（基类）
abstract class MultiSourceSearchEvent {}

/// 搜索进度事件
///
/// 每当有源返回结果时，都会发送一个进度事件，
/// UI 可以据此更新搜索结果列表和进度提示。
class MultiSourceSearchProgress extends MultiSourceSearchEvent {
  /// 已完成的源数量
  final int completed;

  /// 源总数
  final int total;

  /// 当前所有去重后的搜索结果
  final List<Movie> results;

  /// 本次新增的影片（用于UI动画效果）
  final List<Movie> newMovies;

  /// 已产出结果的源数量（**不等于** [completed]）。
  ///
  /// 2026-10-22：多源搜索改为两段式投递后，[completed] 统计的是「彻底搜完的
  /// 源数」（含补齐页），而用户在意的进度是「已经拿到结果的源数」——
  /// 两段式下前者会明显滞后（源还在补页时 completed 还没涨）。
  final int readySources;

  /// 所有源是否都已**彻底**搜完（含两段式投递的补齐页）。
  ///
  /// 2026-10-22：多源搜索改为两段式投递后，[completed] 统计的是「已出首屏的
  /// 源数」（阶段 1），与「全部搜完」不再等价，故单独用本字段表达终态。
  final bool allSourcesDone;

  /// 本轮是否有源因为「片名严格匹配一条都没有」而放宽到了宽松匹配。
  ///
  /// 2026-10-28：严格过滤修掉了「搜《死侍》出《战狼》」，但不能因此让用户
  /// 什么都搜不到。放宽时把事实告诉用户（「以下包含近似结果」），
  /// 比默默清空或者默默塞满都诚实。
  final bool relevanceRelaxed;

  MultiSourceSearchProgress({
    required this.completed,
    required this.total,
    required this.results,
    this.newMovies = const [],
    this.readySources = 0,
    this.allSourcesDone = false,
    this.relevanceRelaxed = false,
  });

  /// 是否所有源都已搜索完毕
  bool get isFinished => allSourcesDone || completed >= total;

  /// 搜索状态文本（用于底部进度提示）
  String get statusText {
    final multi = results.where((m) => m.alternateSources.isNotEmpty).length;
    // 还有源在补页时，明确告诉用户"结果还会继续增加"，别让人以为卡住了。
    final tail = allSourcesDone ? '' : '，仍在加载更多';
    // 放宽过匹配：明说，别让用户以为这些是精确结果。
    final loose = relevanceRelaxed ? '（未找到片名完全一致的条目，以下含近似结果）' : '';
    if (multi > 0) {
      return '已从 $readySources/$total 个源取到结果，共 ${results.length} 条结果'
          '（$multi 条在多个源有资源，卡片内可切换来源）$tail$loose';
    }
    return '已从 $readySources/$total 个源取到结果，共找到 ${results.length} 部$tail$loose';
  }
}

/// 单个源的搜索结果
class SourceSearchResult {
  /// 搜索的源
  final PlaySource source;

  /// 该源返回的影片列表
  final List<Movie> movies;

  /// 错误信息（如果搜索失败）
  final String? error;

  /// 本次投递是否为该源的**最后一段**。
  ///
  /// 2026-10-22 起多源搜索改为**两段式投递**：同一源会先投一次「第 1 页」
  /// （让首屏秒出），再投一次「补齐页」。只有 `isFinal == true` 的那次
  /// 才代表该源彻底搜完，可以计入「已完成源数」。
  final bool isFinal;

  SourceSearchResult({
    required this.source,
    required this.movies,
    this.error,
    this.isFinal = true,
  });
}
