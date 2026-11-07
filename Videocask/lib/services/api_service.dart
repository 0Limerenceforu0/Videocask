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

part 'api_service_home.dart';
part 'api_service_detail.dart';
part 'api_service_search.dart';
part 'api_service_category.dart';

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

  /// 搜索影片
  ///
  /// 苹果CMS搜索接口：GET {url}?ac=detail&wd={关键词}&pg={页码}
  /// 单页搜索结果 + 总页数（供翻页聚合使用）。
  static const _SearchPageResult _emptySearchPage = _SearchPageResult(
    movies: [],
    pagecount: 1,
    page: 1,
  );

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

  /// 最大并发请求数（多源搜索 / 多源详情聚合共用）
  static const _maxConcurrent = 4;

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
