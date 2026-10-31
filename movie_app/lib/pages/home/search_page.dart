import 'dart:async' show Timer, unawaited, TimeoutException;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/movie.dart';
import '../../models/play_source.dart';
import '../../models/torrent_info.dart';
import '../../providers/movie_provider.dart';
import '../../providers/source_provider.dart';
import '../../services/search_service.dart';
import '../../services/search_intent_service.dart';
import '../../services/search_type_word.dart';
import '../../services/api_service.dart'
    show ApiService, SearchRelevance, TitleQuery;
import '../../services/cms_category_resolver.dart';
import '../../services/imdb_lookup_service.dart';
import '../../services/magnet_chinese_name_service.dart';
import '../../services/person_works_merge.dart';
import '../../services/torrent_search_service.dart';
import '../../services/torrent_player_models.dart';
import '../../utils/commentary_content_filter.dart';
import '../../utils/title_relevance.dart';
import '../../utils/torrent_title_display.dart';
import '../home/movie_card.dart';
import 'search_channel_gate.dart';
import '../../config/routes.dart';
import '../../widgets/empty_widget.dart';
import '../../widgets/loading_widget.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/hifi_design_tokens.dart';

/// 搜索页
class SearchPage extends StatefulWidget {
  /// 初始搜索关键词
  final String initialQuery;

  const SearchPage({
    super.key,
    this.initialQuery = '',
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  /// 搜索控制器
  final TextEditingController _searchController = TextEditingController();

  /// 搜索服务（用于搜索历史和建议）
  final SearchService _searchService = SearchService();

  /// 焦点节点
  final FocusNode _focusNode = FocusNode();

  /// 搜索结果（本地状态，用于多源搜索的流式展示）
  List<Movie> _searchResults = [];

  /// 是否显示搜索建议
  bool _showSuggestions = false;

  /// 搜索建议
  List<String> _suggestions = [];

  /// 当前搜索关键词
  String _currentQuery = '';

  /// 真正拿去检索的词（[_currentQuery] 去掉《》「」等装饰性标点）。
  /// 「其他相关结果」的词面判定必须用它，否则《功夫》和「功夫」对不上。
  String _searchTerm = '';

  /// 热门搜索
  List<String> _hotKeywords = [];

  /// 滚动控制器
  final ScrollController _scrollController = ScrollController();

  /// 防抖定时器（用于**搜索建议**）
  ///
  /// 2026-10-22：原先搜索与建议**共用**这一个定时器，于是用户打字时的
  /// `_onQueryChanged` 会把 `initState` 排好的搜索定时器取消掉 —— 搜索静默
  /// 不执行，用户等不到结果再点一次搜索，两次 `_performSearch` 交叠，
  /// 结果互相覆盖。搜索改用 [_searchDebounceTimer]。
  Timer? _debounceTimer;

  /// 防抖定时器（用于**发起搜索**），与建议的 [_debounceTimer] 分开。
  Timer? _searchDebounceTimer;

  /// 搜索代次：每次发起搜索自增，异步回调回来时比对。
  ///
  /// 2026-10-22：修复「页面来回跳」——旧查询的磁力/聚合回调晚到时会把新查询
  /// 的结果清空或覆盖，表现为「聚合资源 → 加载中 → 只有磁力 → 没有结果 →
  /// 又有聚合又有磁力」的反复横跳。过期的一律丢弃。
  int _searchGeneration = 0;

  /// 上一次从 MovieProvider 镜像过来的结果列表（用于判断"有没有新事件"）。
  List<Movie>? _lastMirroredResults;

  /// 多源搜索状态文本
  String _multiSearchStatusText = '';

  /// 是否正在执行多源搜索
  bool _isMultiSourceSearching = false;

  /// 最近一次搜索因「没有任何已启用的搜索源」而未能发起（与「关键词无结果」区分）
  bool _searchBlockedNoSources = false;

  /// 搜索词命中一级分类词（如「动漫」）时的分类名；空 = 普通关键词搜索。
  ///
  /// 实测（2026-10-21）源站 `wd=` 只匹配片名，`wd=动漫` total=0，
  /// 因此分类词改走 `ac=detail&t=` 分类列表（见 [_performSearch]）。
  String _typeWordCategory = '';

  /// 搜索词命中细分类型词（如「动作」）时的类型词；作为本地筛选条件。
  String _typeWordGenre = '';

  /// 本轮结果是否由「类型子类通道」检索得到（见 [_performSearch] 的类型分支）。
  ///
  /// 为 true 时 [_filteredResults] **不再做本地类型筛选**：源站已经按
  /// 「科幻片」这个子类把内容筛过一遍了，再拿 `vod_class` 卡一次，会把
  /// 那些 `vod_class` 写着「剧情,冒险」但确实归在科幻子类里的片子误杀
  /// —— 用户看到的就是「分类里有 20 部，列表里只剩 3 部」。
  bool _resultsFromGenreChannel = false;

  /// 「××× 的作品」列表已经覆盖到界面上。
  ///
  /// 人名通道与关键词搜索现在**并行**：关键词先出结果（快），豆瓣代表作
  /// 列表回来后再覆盖成更准的一份。一旦覆盖，provider 那轮的关键词批次
  /// 就不能再镜像回来，否则界面会在两份列表之间来回跳。
  bool _personWorksApplied = false;

  /// 关键词那轮**最新**的流式结果（代表作合并的基底）。
  ///
  /// 不能在开始补全时快照一次：关键词是多源流式投递的，2~3s 内还在不断
  /// 追加批次；快照早了，后到的那些就永远进不了合并结果（第一次实现就是
  /// 这么丢的）。这里每次镜像都更新，代表作回调按它合并。
  List<Movie> _keywordBaseline = const [];

  /// 本轮是「确认人名」搜索（豆瓣确认了这个词是一个人）。
  bool _isPersonQuery = false;

  /// 「其他相关结果」分组是否展开（默认收起）。
  bool _isOthersExpanded = false;

  /// 作品通道命中的片名（归一化）。这些片子片名里不含人名却确实相关，
  /// 不参与词面相关性判定，必须留在主列表里。
  final Set<String> _trustedTitles = <String>{};

  /// 作品通道已投递的累计结果（电影 + 剧集，电影在前）。
  ///
  /// 两阶段投递（电影先出、剧集后补）需要它：第二阶段是**追加**，不能
  /// 拿新的剧集列表去覆盖掉前面已经显示的 71 部电影。
  List<Movie> _personWorksAccum = const [];

  /// 磁力源搜索结果
  final TorrentSearchService _torrentSearchService = TorrentSearchService();
  List<TorrentInfo> _magnetResults = [];

  /// 是否正在搜索磁力源
  bool _isMagnetSearching = false;

  /// 磁力搜索失败/超时/空结果的用户可见说明（空 = 正常态）。
  ///
  /// 2026-10-22：Torrentio URL 模板修复前，磁力搜索失败时 UI 只显示
  /// 「磁力资源（0）」+ 空列表，用户完全看不出是源挂了还是真没资源。
  String _magnetSearchError = '';

  /// 磁力资源名 → 中文片名（2026-10-25）。
  ///
  /// 磁力源给的资源名几乎全是英文发布名（`The.Godfather.1972.1080p...`），
  /// 光看名字认不出是哪部片子。这里存「资源名 → 中文名」，
  /// 由 [MagnetChineseNameService] 解析（CMS 年份对齐 / 中文搜索词 / 豆瓣联想）。
  /// 没有可信中文名的资源不会出现在这张表里（宁可不显示，也不要显示错的）。
  Map<String, String> _magnetChineseNames = const {};

  // ========== 折叠功能状态 ==========

  /// 影视区块是否展开（默认展开）。
  ///
  /// 2026-10-31 用户要求：影视区块的标题固定在顶部，下面是正常结果；
  /// 「其他影视」是挂在影视下面的次级分组，**影视收起时它一并收起**。
  bool _isMovieExpanded = true;

  /// 是否展开磁力源结果
  bool _isMagnetSourcesExpanded = true;

  // ========== 筛选相关状态 ==========

  /// 类型筛选标签（空字符串表示"全部"）
  String _filterGenre = '';

  /// 排序方式（空字符串表示默认排序）
  String _filterSort = '';

  /// 可选的类型筛选列表
  static const List<String> _genreFilters = [
    '', // 全部
    '电影',
    '电视剧',
    '动漫',
    '综艺',
    '纪录片',
  ];

  /// 可选的排序方式列表
  static const List<MapEntry<String, String>> _sortOptions = [
    MapEntry('', '默认'),
    MapEntry('rating', '评分↓'),
    MapEntry('year_desc', '年份↓'),
    MapEntry('year_asc', '年份↑'),
  ];

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery;
    _currentQuery = widget.initialQuery;

    if (widget.initialQuery.isNotEmpty) {
      _doSearch(widget.initialQuery);
    }

    _focusNode.addListener(_onFocusChange);
    _searchController.addListener(_onQueryChanged);
    _scrollController.addListener(_onScroll);

    _loadInitialData();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 加载初始数据
  void _loadInitialData() {
    _hotKeywords = _searchService.hotKeywords.toList();
  }

  /// 焦点变化
  void _onFocusChange() {
    setState(() {
      _showSuggestions = _focusNode.hasFocus;
    });
  }

  /// 查询变化（带防抖）
  void _onQueryChanged() {
    final query = _searchController.text.trim();
    // 取消之前的防抖定时器
    _debounceTimer?.cancel();
    if (query.isNotEmpty && _focusNode.hasFocus) {
      // 防抖：用户停止输入 500ms 后才发起搜索建议请求
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        _updateSuggestions(query);
      });
    } else {
      setState(() {
        _suggestions = [];
      });
    }
  }

  /// 更新搜索建议
  void _updateSuggestions(String query) async {
    final suggestions = await _searchService.getSuggestions(query);
    if (mounted) {
      setState(() {
        _suggestions = suggestions;
      });
    }
  }

  /// 滚动监听（多源搜索模式下不需要分页加载更多）
  void _onScroll() {
    // 多源搜索结果一次性展示，无需滚动加载更多
  }

  /// 执行搜索（带防抖）
  void _doSearch(String query) {
    if (query.trim().isEmpty) return;

    // 取消之前的搜索防抖定时器（与建议的定时器分开，互不取消）
    _searchDebounceTimer?.cancel();
    // 防抖：用户停止输入 500ms 后才发起搜索请求
    _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_performSearch(query));
    });
  }

  /// 实际执行搜索（多源并发搜索）
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    // 2026-10-25：用户贴的是磁力链接 → 直接跳进该磁力的详情页去获取/播放，
    // 不再跑普通搜索（详情页进入时会按 autoPlayOnDetailEnter 自动起播）。
    if (TorrentSearchService.isMagnetLink(query.trim())) {
      final torrent =
          TorrentSearchService.torrentInfoFromRawMagnet(query.trim());
      AppRoutes.toMagnetTorrentDetail(context, torrent);
      return;
    }

    final l10n = AppLocalizations.of(context)!;

    // 检索词 = 用户输入去掉装饰性标点（《》「」""() 等）。
    // 用户习惯写《权力的游戏》，而采集站 `wd=` 是逐字匹配：带书名号
    // 在 ffzy 上 total=0，去掉后 9 条（2026-10-28 实测）。
    // 展示与搜索历史仍用原词，只有真正发给源站的检索用 [term]。
    final term = SearchIntentService.stripDecorations(query);

    // 类型词识别（2026-10-21）：「动漫」是内容分类，「动作」是类型筛选词。
    // 源站 `wd=` 只匹配片名字段，实测 `wd=动漫` / `wd=动作` 均返回 total=0 ——
    // 不先识别类型词，用户搜类型永远零结果（即「搜索不能搜索类型」）。
    //
    // 2026-10-28 用户反馈「严格搜索又没有了人名和类型搜索能力」：
    // 分类词 / 类型词 / 人名 / 片名是**四种不同的查询**，必须走不同的检索
    // 通道（详见 [SearchIntentKind]）。之前的实现把四者都塞进 `wd=` + 片名
    // 相关性过滤，片名搜索修好了，另外三种全废 —— 这就是"二极管"。
    final typeCategory = SearchTypeWord.categoryOf(term);
    final typeGenre =
        typeCategory == null ? SearchTypeWord.genreOf(term) : null;

    final sourceProvider = context.read<SourceProvider>();
    final movieProvider = context.read<MovieProvider>();
    final enabledSources = sourceProvider.enabledSources;
    final hasMagnetSources = _torrentSearchService.activeConfigs().isNotEmpty;

    // 取代次号：本轮的所有异步回调都必须比对，过期的一律丢弃。
    final generation = ++_searchGeneration;

    setState(() {
      _currentQuery = query;
      _searchTerm = term;
      _searchResults = [];
      _magnetResults = [];
      _magnetChineseNames = const {};
      _showSuggestions = false;
      _multiSearchStatusText = '正在搜索...';
      _searchBlockedNoSources = false;
      _magnetSearchError = '';
      // 类型筛选词直接作为筛选条件（chip 行会显示选中态）。
      _filterGenre = typeGenre ?? '';
      _filterSort = '';
      _typeWordCategory = typeCategory ?? '';
      _typeWordGenre = typeGenre ?? '';
      // 新的一轮默认走普通通道；类型分支拿到结果后会自己置 true。
      _resultsFromGenreChannel = false;
      // 新一轮：代表作升级还没发生。
      _personWorksApplied = false;
      _keywordBaseline = const [];
      // 新一轮：作品通道的可信片名、累计结果、「其他相关结果」展开态全部复位。
      _trustedTitles.clear();
      _personWorksAccum = const [];
      _isOthersExpanded = false;
      _isPersonQuery = false;
      // 新一轮：忘掉上一轮镜像过的列表身份，重新接受 provider 的新结果。
      _lastMirroredResults = null;
      // 2026-10-22：清空结果的**同一帧**必须进入 loading。
      // 旧实现先清空、后面才置 loading，中间那一帧两个列表都空、
      // 两个 loading 标志都是 false → 闪一帧「没有找到相关内容」，
      // 正是用户看到的「加载页 → 没有结果页」来回跳。
      _isMultiSourceSearching = enabledSources.isNotEmpty;
      _isMagnetSearching = hasMagnetSources;
    });

    _focusNode.unfocus();

    // 添加搜索历史：改到发起搜索**之后**异步做。
    // 旧实现先 await 一次 SharedPreferences 写盘才开始任何网络请求，
    // 白白拖慢首屏。
    unawaited(
      _searchService.addSearchHistory(query).catchError((Object e) {
        debugPrint('写入搜索历史失败: $e');
      }),
    );

    if (enabledSources.isEmpty && !hasMagnetSources) {
      if (mounted) {
        setState(() {
          _isMultiSourceSearching = false;
          _isMagnetSearching = false;
          _multiSearchStatusText = '';
          _searchBlockedNoSources = true;
        });
      }
      return;
    }

    // 分类词：不走 wd 搜索，改拉分类列表（与首页 Tab 同一条数据链，
    // `ac=detail&t=`）。注意只写本地 `_searchResults`，不碰 MovieProvider 的
    // 分类状态 —— 否则回首页会发现 Tab 被搜索结果污染。
    if (typeCategory != null) {
      if (enabledSources.isEmpty) {
        setState(() {
          _isMultiSourceSearching = false;
          _multiSearchStatusText = '';
        });
        return;
      }
      try {
        final page = await movieProvider.apiService.aggregateCategoryFirstPage(
          sources: enabledSources,
          category: typeCategory,
        );
        if (!mounted) return;
        // 过期的一轮：丢弃，别把新查询的结果冲掉。
        if (generation != _searchGeneration) return;
        final movies = _dropCommentary(page.movies);
        setState(() {
          _searchResults = movies;
          _isMultiSourceSearching = false;
          _multiSearchStatusText = '「$typeCategory」共 ${movies.length} 部';
        });
      } catch (e) {
        debugPrint('分类词搜索失败: $e');
        if (!mounted) return;
        if (generation != _searchGeneration) return;
        setState(() {
          _isMultiSourceSearching = false;
          _multiSearchStatusText = '';
        });
      }
      return;
    }

    // ===== 类型词（「科幻」「动作」）=====
    //
    // 走站点**类型子类**（`ac=detail&t=<科幻片>`），而不是 `wd=科幻`：
    // 2026-10-28 六源实测，`wd=科幻` 在 ffzy 上 `total=0`（`wd=` 只匹配片名），
    // 而 `class=科幻` 有 4211 条。这是参数用错了，不是过滤问题。
    if (typeGenre != null) {
      if (enabledSources.isNotEmpty) {
        try {
          final page = await movieProvider.apiService.aggregateGenreFirstPage(
            sources: enabledSources,
            genre: typeGenre,
          );
          if (!mounted) return;
          if (generation != _searchGeneration) return;
          if (page.movies.isNotEmpty) {
            final movies = _dropCommentary(page.movies);
            setState(() {
              _searchResults = movies;
              _isMultiSourceSearching = false;
              _isMagnetSearching = false;
              _resultsFromGenreChannel = true;
              _multiSearchStatusText = '「$typeGenre」共 ${movies.length} 部';
            });
            return;
          }
        } catch (e) {
          debugPrint('类型检索失败: $e');
        }
        if (!mounted) return;
        if (generation != _searchGeneration) return;
      }
      // 各源的分类树里都没有这个类型子类 → 继续往下走普通关键词搜索
      // （此时关闭片名相关性过滤），宁可给几条近似结果，也不留空列表。
    }

    // ===== 人名（「周星驰」）=====
    //
    // 源站没有演员检索参数（实测 `actor=周星驰` 被忽略、直接返回全库），
    // 所以先问豆瓣拿「人物 + 代表作」，再逐部按片名去源站搜。
    // 豆瓣对中文人名是一次请求两件事：`[{type:celebrity,title:周星驰},
    // {type:movie,title:功夫}, …]`。
    //
    // ⚠️ 2026-10-28 改：人名探测**只用来定性**，不再阻塞首屏。
    // 旧实现在这里直接 await `searchByTitles`（6~8 部作品 × N 源），
    // 真机「周星驰」跑满 20s 超时，然后兜底关键词搜索 2s 就拿回 20 部
    // （量子资源支持演员匹配）—— 那 20 秒纯属白等。
    // 现在：关键词搜索先出结果，代表作列表回来后覆盖成更准的一份。
    PersonHit? person;
    // 探测失败（网络/熔断）≠「豆瓣说这不是人名」。前者只能按人名放宽，
    // 否则源站已经命中的演员结果会被严格片名过滤杀光。
    var personProbeFailed = false;
    final personLike = typeGenre == null &&
        enabledSources.isNotEmpty &&
        SearchIntentService.looksLikePersonName(term);
    if (personLike) {
      try {
        // 一次豆瓣联想请求，正常几百毫秒；卡住就按「不知道」继续。
        final probe = await SearchIntentService.instance
            .probePerson(term)
            .timeout(const Duration(seconds: 6));
        person = probe.hit;
        personProbeFailed = probe.failed;
      } catch (e) {
        personProbeFailed = true;
        debugPrint('人名探测失败: $e');
      }
      if (!mounted) return;
      if (generation != _searchGeneration) return;
      // 记下这是人名搜索：「其他相关结果」的折叠要等作品通道首批结果回来
      // 再启用，否则这 1~40s 内主列表是空的（见 `_relevanceSplit`）。
      if (person != null) {
        setState(() => _isPersonQuery = true);
      }
    }

    // 两条通道的开关由 `SearchChannelGate` 统一决定（纯函数，可单测）。
    // 🔴 绝不能用 `looksLikePersonName` 这类启发式来决定磁力开关：
    // 它的判据是「2~6 个汉字、无年份无标点」，几乎命中所有中文片名
    // （「功夫」「长江七号」「权力的游戏」）→ 磁力通道整片关闭，
    // 用户看到的就是「磁力资源模块不见了」（2026-10-28 真机回归）。
    final gate = SearchChannelGate.resolve(
      isTypeWord: typeGenre != null,
      isConfirmedPerson: person != null,
      personProbeFailed: personProbeFailed,
    );
    final titleLikeQuery = gate.strictTitleFilter;
    if (!gate.runMagnet && _isMagnetSearching) {
      // 磁力源只认片名/tt-id，拿类型词或人名去搜纯属浪费 45s。
      setState(() {
        _isMagnetSearching = false;
      });
    }

    // 磁力通道的开关只看 `skipMagnet`（确认人名 / 类型词），
    // 不能挂 `titleLikeQuery`：后者在「探测失败」时也为 false，
    // 会把磁力一起关掉。
    if (hasMagnetSources && gate.runMagnet) {
      unawaited(
        _torrentSearchService
            .searchPreferringImdb(
              displayTitle: term,
              year: ImdbLookupService.yearFromUserQuery(term),
              strictMatchForDetailPage: false,
            )
            // 与详情页磁力搜索对齐的 45s 兜底：前置的片名→IMDb 解析
            // （豆瓣/TMDB/IMDb 联想）叠加各源超时后可能超过 45s，
            // 没有整体超时会让「搜索中」转圈到天荒地老。
            .timeout(const Duration(seconds: 45))
            .then((list) {
          if (!mounted) return;
          // 2026-10-22：过期的一轮直接丢弃。旧实现里旧查询的回调会把
          // 新查询的磁力结果清空（catchError 置 []）并提前关掉 loading，
          // 这正是「只有磁力 → 没有结果」来回跳的元凶。
          if (generation != _searchGeneration) return;
          final torrents = _dropCommentaryTorrents(list);
          setState(() {
            _magnetResults = torrents;
            _isMagnetSearching = false;
            _magnetSearchError =
                torrents.isEmpty ? l10n.magnetSearchEmptyHint : '';
          });
          // 中文名解析**不阻塞**结果展示：磁力列表先出来，中文名随后补上。
          unawaited(_resolveMagnetChineseNames(torrents, query, generation));
        }).catchError((Object e) {
          if (!mounted) return;
          if (generation != _searchGeneration) return;
          setState(() {
            _magnetResults = [];
            _isMagnetSearching = false;
            _magnetSearchError = e is TimeoutException
                ? l10n.magnetSearchTimeoutHint
                : l10n.magnetSearchFailedHint;
          });
        }),
      );
    }

    if (enabledSources.isNotEmpty) {
      // 代表作升级与关键词搜索**并行**：关键词这轮先出结果（真机 2~3s），
      // 豆瓣代表作那一份回来后再覆盖（更准，且按代表作排序）。
      if (person != null && person.hasWorks) {
        unawaited(
          _upgradeWithPersonWorks(
            person,
            movieProvider.apiService,
            enabledSources,
            generation,
          ),
        );
      }
      // 聚合结果由 MovieProvider 流式产出，搜索页从 provider 镜像
      // （见 [_syncMultiSearchState]）；这里 await 本轮结束，只为了在
      // 本轮结束时把本地 loading 标志关掉。
      await movieProvider.multiSourceSearch(
        term,
        sources: enabledSources,
        relevance:
            titleLikeQuery ? SearchRelevance.strict : SearchRelevance.off,
      );
      if (!mounted) return;
      if (generation != _searchGeneration) return;
      setState(() {
        _isMultiSourceSearching = false;
      });
    } else {
      setState(() {
        _isMultiSourceSearching = false;
        _multiSearchStatusText = '';
      });
    }
  }

  static final RegExp _cjkPattern = RegExp(r'[\u4e00-\u9fff]');

  /// 用「××× 的全部作品」补全关键词结果（2026-10-28）。
  ///
  /// 数据链：豆瓣人物作品全集（`celebrity/{id}/works`，周星驰 71 部电影，
  /// 含 16 部导演/编剧身份）→ 逐部按片名去源站查（首个命中源即停）
  /// → 每命中一部就增量并入列表。
  ///
  /// 为什么不用联想接口的「代表作」：`subject_suggest` 只回 **4 部**
  /// （功夫女足 / 少林足球 / 喜剧之王 / 功夫），这是「搜周星驰只有 30 条」
  /// 的根因；而源站实测对这 58 部的命中率是 52/56 ≈ 93%，不缺片。
  ///
  /// 投递方式：**合并**（代表作在前、关键词结果去重补后），不覆盖 ——
  /// 覆盖会让列表从 30 掉到 20 几，用户观感是「越搜越少」。
  /// 失败/超时**什么都不做**：界面上已经有可用的关键词结果。
  Future<void> _upgradeWithPersonWorks(
    PersonHit person,
    ApiService apiService,
    List<PlaySource> sources,
    int generation,
  ) async {
    // 关键词那轮的流式结果持续更新到 `_keywordBaseline`，这里不要快照。
    List<PersonWork> allWorks;
    try {
      allWorks = await SearchIntentService.instance
          // includeTv: 用户要求「电视剧、综艺等都要」。电影和剧集在豆瓣
          // 是同一次响应里的两类，不需要多发请求。
          .fetchPersonWorks(person.doubanId, includeTv: true)
          // 作品全集要翻 3 页（133 条 / 每页 50），单页上限 10s，
          // 整体给 40s；这条是并行通道，界面上早有关键词结果，不算阻塞。
          .timeout(const Duration(seconds: 40));
    } catch (e) {
      debugPrint('人物作品全集获取失败（保留关键词结果）: $e');
      return;
    }
    if (!mounted) return;
    if (generation != _searchGeneration) return;
    // 全集拿不到就退回联想给的那几部代表作，总比不出力强。
    final worksSource = allWorks.isNotEmpty ? allWorks : person.works;
    if (worksSource.isEmpty) return;

    // 把**豆瓣作品全集的标题**整体当作可信片名库。
    // 只记「实际命中的结果片名」不够：源站片名常带后缀（豆瓣《喜剧之王》
    // vs 源站《喜剧之王1999》），关键词通道带回的那条不在命中集里，就会被
    // 词面判定当成噪声折进「其他相关」，真机上表现为噪声组里全是正片。
    for (final w in worksSource) {
      _trustedTitles.add(TitleRelevance.normalize(w.title));
    }

    // 电影先出、剧集后补（2026-10-28 用户选择 B「电影先出」）。
    // 豆瓣一次响应里两类都有，但检索是逐部串行的：周星驰 71 部电影 + 60
    // 多部剧集，等全部跑完，用户要在「正在补全」上干等好几分钟；先把电影
    // 投递完，剧集在后台接着补，观感差别很大。
    final movies = worksSource.where((w) => !w.isTv).toList(growable: false);
    final tvs = worksSource.where((w) => w.isTv).toList(growable: false);

    _personWorksAccum = const [];
    await _runPersonWorksStage(
      movies,
      person: person,
      apiService: apiService,
      sources: sources,
      generation: generation,
      label: '电影',
      withEnglishName: true,
    );
    // 电影阶段跑完可能已经过了很久：用户换了搜索词就别再跑剧集，
    // 白耗流量还占着源站的并发位。
    if (!mounted || generation != _searchGeneration) return;
    await _runPersonWorksStage(
      tvs,
      person: person,
      apiService: apiService,
      sources: sources,
      generation: generation,
      label: '剧集 / 综艺',
      withEnglishName: false,
    );
  }

  /// 作品通道的单个阶段（电影 / 剧集），每命中一部就增量并入列表。
  ///
  /// 两个阶段共享 [_personWorksAccum]：第二阶段是**追加**，不能拿剧集
  /// 结果覆盖掉已经显示的电影。
  Future<void> _runPersonWorksStage(
    List<PersonWork> stage, {
    required PersonHit person,
    required ApiService apiService,
    required List<PlaySource> sources,
    required int generation,
    required String label,
    required bool withEnglishName,
  }) async {
    if (stage.isEmpty) return;

    final works = <TitleQuery>[
      ...stage.map((w) => TitleQuery(w.title, year: w.year)),
      // 英文名排最后：源站多是中文库（实测 `wd=Stephen Chow` total=0），
      // 但配上英文库的源可能命中，不值得占用前面的批次数。
      if (withEnglishName && person.englishName.isNotEmpty)
        TitleQuery(person.englishName),
    ];

    setState(() {
      _multiSearchStatusText = '正在补全$label…（${works.length} 部）';
    });

    final name = person.name;

    try {
      await apiService.searchPersonWorks(
        works,
        sources: sources,
        // 用户要求「参演、客串、导演的都要」：豆瓣电影全集有 71 部
        // （含 16 部纯导演/编剧），上限卡在 40 会把后面的丢光。
        // 结果边查边投递，所以耗时长一点不影响首屏。
        maxTitles: 200,
        onProgress: (list) {
          if (!mounted) return;
          if (generation != _searchGeneration) return;
          final accum = <Movie>[..._personWorksAccum, ...list];
          _personWorksAccum = accum;
          // 作品通道命中的片名一律视为「确实相关」：它们的片名里
          // 通常不含人名（《功夫》之于周星驰），词面判定会把它们
          // 错判成噪声。
          for (final m in accum) {
            _trustedTitles.add(TitleRelevance.normalize(m.name));
          }
          final merged =
              _dropCommentary(mergePersonWorks(accum, _keywordBaseline));
          setState(() {
            _personWorksApplied = true;
            _searchResults = merged;
            _isMultiSourceSearching = false;
            _multiSearchStatusText = '「$name」的作品 · 已匹配 ${merged.length} 部';
          });
        },
      )
          // 整体兜底：个别源卡住时不能让这条通道一直挂着。
          // 已经投递的结果会保留在界面上。
          .timeout(const Duration(seconds: 120));
    } catch (e) {
      debugPrint('作品全集补全中断（$label，已投递的结果保留）: $e');
    }
  }

  /// 解析磁力资源的中文名（2026-10-25）。
  ///
  /// 磁力源给的资源名几乎全是英文发布名，搜索页要显示中文名才认得出片子。
  /// 解析**不阻塞**结果展示：磁力列表先渲染，中文名解析完再补一次 setState。
  ///
  /// [generation] 本轮的请求代次：解析是异步的（可能要发豆瓣请求），
  /// 期间用户可能又搜了别的词 —— 过期的一律丢弃，绝不把上一轮的中文名
  /// 贴到这一轮的列表上。
  Future<void> _resolveMagnetChineseNames(
    List<TorrentInfo> torrents,
    String query,
    int generation,
  ) async {
    if (torrents.isEmpty) return;
    Map<String, String> names;
    try {
      names = await MagnetChineseNameService.instance.resolveNames(
        torrents,
        query: query,
        searchResults: _searchResults,
      );
    } catch (e) {
      debugPrint('磁力资源中文名解析失败: $e');
      return;
    }
    if (!mounted) return;
    if (generation != _searchGeneration) return;
    if (names.isEmpty) return;
    setState(() {
      _magnetChineseNames = names;
    });
  }

  /// 中文搜索词传给磁力详情，用于补全海报 / 简介 / 推荐。
  String? _magnetDisplayTitleHint() {
    final q = _currentQuery.trim();
    if (q.isEmpty) return null;
    if (_cjkPattern.hasMatch(q)) return q;
    return null;
  }

  /// 删除搜索历史
  void _deleteHistory(String keyword) async {
    await _searchService.deleteSearchHistory(keyword);
    if (mounted) {
      setState(() {});
    }
  }

  /// 清空搜索历史
  void _clearHistory() async {
    await _searchService.clearSearchHistory();
    if (mounted) {
      setState(() {});
    }
  }

  /// 获取筛选后的搜索结果
  ///
  /// 根据当前选中的类型和排序方式对原始搜索结果进行过滤和排序。
  List<Movie> get _filteredResults {
    var results = _searchResults;

    // 按类型筛选。
    // ⚠️ 不能用 `genres.contains(词)` 精确匹配：源站 `type_name` 是
    // 「海外动漫」「国产剧」这种带限定前缀的写法，与 chip 上的「动漫」
    // 永远不相等 —— 旧实现因此「选了类型结果就被清空」。
    // 统一走 CmsCategoryResolver.genreMatches 的包含匹配；无类型元数据时
    // 放行（未知 ≠ 不匹配），与首页类目筛选策略一致。
    if (_filterGenre.isNotEmpty && !_resultsFromGenreChannel) {
      results = results.where((m) {
        final tags = m.genreTags.isNotEmpty ? m.genreTags : m.genres;
        return CmsCategoryResolver.genreMatches(_filterGenre, tags);
      }).toList();
    }

    // 按排序方式排序（创建副本，避免修改原始列表顺序）
    if (_filterSort == 'rating') {
      results = List.from(results)
        ..sort((a, b) => b.rating.compareTo(a.rating));
    } else if (_filterSort == 'year_desc') {
      results = List.from(results)..sort((a, b) => b.year.compareTo(a.year));
    } else if (_filterSort == 'year_asc') {
      results = List.from(results)..sort((a, b) => a.year.compareTo(b.year));
    }

    return results;
  }

  /// 把筛选后的结果按**词面相关性**拆成「主列表 / 其他相关结果」。
  ///
  /// 采集站的 `wd=` 是模糊检索 + 相关推荐兜底：搜「周星驰」会带出
  /// 《007别传》《小不列颠》《情圣2016》。2026-10-28 用户要求不要丢，
  /// 但也不要混在主列表里 —— 折进可展开的分组。
  ///
  /// 类型词 / 分类词是「按标签取列表」，没有片名可对，全部算主列表。
  RelevanceSplit get _relevanceSplit {
    final all = _filteredResults;
    if (_typeWordCategory.isNotEmpty || _typeWordGenre.isNotEmpty) {
      return RelevanceSplit(all, const []);
    }
    // 纯英文查询不做词面判定：采集站常把英文片名存成中文译名
    // （搜 `The Matrix` 命中《黑客帝国》），两个字符串一点都不像，
    // 硬判定会把**正确结果**折进噪声组。中文查询才做词面比较。
    final latinOnly = !_cjkPattern.hasMatch(_searchTerm) &&
        _latinPattern.hasMatch(_searchTerm);
    if (latinOnly) return RelevanceSplit(all, const []);
    // 人名搜索的**过渡期**：作品通道首批结果还没回来。
    // 源站按演员字段匹配时，片名本来就不含人名（《功夫》不含「周星驰」），
    // 这时做词面判定会把 100 条全折进噪声组 —— 真机实测主列表直接空白，
    // 用户看到的是「搜索坏了」。作品结果一到，噪声自然沉底。
    if (_isPersonQuery && !_personWorksApplied) {
      return RelevanceSplit(all, const []);
    }
    return TitleRelevance.split(all, _searchTerm, trusted: _trustedTitles);
  }

  static final RegExp _latinPattern = RegExp(r'[a-zA-Z]');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMultiSearchState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    // 监听 MovieProvider 变化，实现多源搜索流式更新
    // 当 multiSourceSearch 内部调用 notifyListeners 时，
    // 这里会触发 rebuild，从而实现流式追加展示
    context.watch<MovieProvider>();

    final wide = HiFiDesignTokens.useWideTopBarShell(context);
    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: HiFiDesignTokens.shellMaxWidth,
                    ),
                    child: _buildWideSearchChrome(context, theme, l10n),
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: HiFiDesignTokens.shellMaxWidth,
                    ),
                    child: _buildBody(theme, l10n),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: _buildSearchField(theme),
        actions: [
          TextButton(
            onPressed: () => _doSearch(_searchController.text),
            child: Text(l10n.searchActionSearch),
          ),
        ],
      ),
      body: _buildBody(theme, l10n),
    );
  }

  /// 对齐 `hifi-screen-search-windows.html`：顶行返回 + 标题 + 设置；次行搜索框 + 主按钮。
  Widget _buildWideSearchChrome(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final backLabel = MaterialLocalizations.of(context).backButtonTooltip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: backLabel,
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
            ),
            Expanded(
              child: Text(
                l10n.toolbarSearch,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.toolbarSettings,
              onPressed: () => AppRoutes.toSettings(context),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildSearchField(theme)),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => _doSearch(_searchController.text),
              child: Text(l10n.toolbarSearch),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          l10n.searchWideAggregateHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.hintColor,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  /// 构建搜索框（B站风格：圆角12px，灰色背景，左侧搜索图标）
  Widget _buildSearchField(ThemeData theme) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _focusNode,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: '搜索影片，或粘贴磁力链接',
          hintStyle: TextStyle(
            color: theme.hintColor,
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: theme.hintColor,
            size: 20,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchResults = [];
                      _magnetResults = [];
                      _suggestions = [];
                      _currentQuery = '';
                      _multiSearchStatusText = '';
                      _isMultiSourceSearching = false;
                      _isMagnetSearching = false;
                      _magnetSearchError = '';
                      _searchBlockedNoSources = false;
                      _filterGenre = '';
                      _filterSort = '';
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: (value) => _performSearch(value),
        onChanged: (value) {
          setState(() {});
        },
      ),
    );
  }

  /// 构建主体
  Widget _buildBody(ThemeData theme, AppLocalizations l10n) {
    // 显示搜索建议
    if (_showSuggestions && _suggestions.isNotEmpty) {
      return _buildSuggestions(theme);
    }

    // 显示搜索结果
    if (_currentQuery.isNotEmpty) {
      return _buildSearchResults(theme, l10n);
    }

    // 显示搜索历史和热门搜索
    return _buildDefaultView(theme);
  }

  /// 搜索结果的最后一道过滤（2026-10-28 用户要求「不要[电影解说]」）。
  ///
  /// 数据层已经滤过一轮（`_parseMovieListFromResponse` / 磁力 `_finalizeResults`），
  /// 但三条通道（关键词、类型子类、作品全集）的出口各不相同，这里统一兜底：
  /// 漏网的解说条目会显示成「看起来正常」的片名，比少一条结果更让人困惑。
  List<Movie> _dropCommentary(List<Movie> list) => list
      .where((m) => !CommentaryContentFilter.isMovie(m))
      .toList(growable: false);

  List<TorrentInfo> _dropCommentaryTorrents(List<TorrentInfo> list) => list
      .where((t) => !CommentaryContentFilter.isTorrent(t))
      .toList(growable: false);

  /// 从 MovieProvider 同步多源搜索状态到本地
  ///
  /// 在 build 方法中调用，确保每次 MovieProvider 状态变化时
  /// 本地状态也同步更新，实现流式追加效果。
  ///
  /// 2026-10-22 修正三处「跨轮次/跨页面串扰」：
  /// 1. 只接受**关键词与自己当前一致**的那一轮 provider 结果。provider 是
  ///    app 级全局单例，首页的 `notifyListeners` 会带着上一轮的结果回来，
  ///    旧实现无条件镜像 → 把本轮结果冲掉。
  /// 2. 不再用「provider 是否在搜」当镜像条件。provider 可能在同一帧内
  ///    把所有事件跑完，此时 `isMultiSourceSearching` 已经是 false，
  ///    最后一批评选**永远镜像不到**（页面停在上一批结果）。
  ///    改为按「结果列表身份变化」判定 —— provider 每投一次事件就换一个
  ///    新列表实例，身份变了就说明有新结果。
  /// 3. loading 标志由本页面自己管（[_performSearch] await 完 provider 后关闭），
  ///    不再跟着 provider 抖。
  void _syncMultiSearchState() {
    final movieProvider = context.read<MovieProvider>();
    // 分类词搜索不走 provider 的 multiSourceSearch（只写本地 _searchResults），
    // 这里不能被 provider 状态反向覆盖，否则刚加载的分类列表会被冲掉。
    if (_typeWordCategory.isNotEmpty) {
      return;
    }
    // 基准始终跟着关键词流走（哪怕界面已经被代表作覆盖）：
    // 代表作合并不是覆盖，需要把关键词最新那批也带上。
    // 解说类不进基线，否则会被合并回最终列表。
    final results = movieProvider.multiSearchResults;
    final visible = _dropCommentary(results);
    _keywordBaseline = visible;
    // 代表作已经覆盖到界面：关键词那轮后续批次（流式，可能还在投递）
    // 一律不再镜像，否则「××× 的作品」会被冲回关键词结果、来回跳。
    if (_personWorksApplied) {
      return;
    }
    // 不是本轮关键词的结果，一律不认。
    if (movieProvider.multiSearchKeyword != _currentQuery) {
      return;
    }
    // 列表没换过 = 没有新事件，别做无谓的赋值。
    // （用原始引用判断，过滤后的新列表每次都是新实例，不能拿来比。）
    if (identical(results, _lastMirroredResults)) {
      return;
    }
    _lastMirroredResults = results;
    _searchResults = visible;
    _multiSearchStatusText = movieProvider.searchStatusText;
  }

  /// 构建搜索建议（B站风格下拉列表）
  Widget _buildSuggestions(ThemeData theme) {
    return ListView.separated(
      itemCount: _suggestions.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        color: theme.dividerColor.withValues(alpha: 0.3),
        indent: 48,
      ),
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        return InkWell(
          onTap: () {
            _searchController.text = suggestion;
            _doSearch(suggestion);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.search, color: theme.hintColor, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    suggestion,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                  ),
                ),
                Icon(Icons.arrow_upward, color: theme.hintColor, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 类型词提示横幅：解释「为什么搜类型给你的是分类内容」。
  ///
  /// 源站 `wd=` 只匹配片名（实测 `wd=动漫` total=0），分类词已改走分类列表、
  /// 类型词已转为本地筛选 —— 不显示这条提示，用户只会觉得「搜索坏了」。
  ///
  /// 2026-10-28 修正文案：类型词现在会先走**站点类型子类**（`ac=detail&t=科幻片`）
  /// 拿到干净的全量结果，只有该源分类树里没有这个类型时才退回关键词筛选。
  /// 之前不论走哪条路都写「源站只按片名搜索，结果可能不全」，
  /// 明明是按分类拿到的 64 条也被说成「可能不全」，用户会以为搜坏了。
  Widget _buildTypeWordBanner(ThemeData theme) {
    final text = _typeWordCategory.isNotEmpty
        ? '「$_typeWordCategory」是内容分类：源站的搜索只认片名，已改为按分类为你加载'
        : _resultsFromGenreChannel
            ? '已按类型「$_typeWordGenre」加载该类型的全部影片'
            : '已按类型「$_typeWordGenre」筛选结果；该源没有这个类型分类，结果可能不全';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.sell_outlined, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建搜索结果（支持多源流式追加展示 + 筛选）
  Widget _buildSearchResults(ThemeData theme, AppLocalizations l10n) {
    if (_searchBlockedNoSources) {
      return EmptyWidget(
        message: '没有已启用的影视搜索源，也未配置可用的磁力源。请在播放源管理中开启 CMS 源，或在设置中启用磁力搜索源。',
        icon: Icons.source_outlined,
        iconSize: 72,
        actionText: '去播放源管理',
        onAction: () => AppRoutes.toSourceManager(context),
      );
    }

    // 2026-10-24：磁力资源模块**不允许凭空消失**。
    // 旧条件只看「有结果 / 还在搜」，于是磁力搜索一旦**返回空列表或超时**
    // （catchError 把 _magnetResults 清空、_isMagnetSearching 置 false），
    // anyMagnet 变 false → 整个磁力区块连同它内部的「没有找到磁力资源 /
    // 搜索超时」提示一起被隐藏 —— 用户看到的就是「磁力资源模块直接没了」，
    // 完全不知道是搜不到还是超时了。
    // 判定抽到 `shouldShowMagnetSection`（纯函数，可单测）。
    final anyMagnet = shouldShowMagnetSection(
      resultCount: _magnetResults.length,
      isSearching: _isMagnetSearching,
      hasError: _magnetSearchError.isNotEmpty,
    );
    final nothingYet = _searchResults.isEmpty &&
        _magnetResults.isEmpty &&
        // 磁力这一路报错（超时/失败）时不能判「什么都没有」——
        // 否则会先返回「没有找到相关内容」，把「磁力搜索超时」这条
        // 真正有用的提示吞掉，用户只看到模块凭空消失。
        _magnetSearchError.isEmpty;
    final stillLoading = _isMultiSourceSearching || _isMagnetSearching;

    if (stillLoading && nothingYet) {
      return const LoadingWidget(message: '正在搜索影视与磁力...');
    }

    if (!stillLoading && nothingYet) {
      return NoSearchResultWidget(
        keyword: _currentQuery,
        onRetry: () => _performSearch(_currentQuery),
      );
    }

    final split = _relevanceSplit;
    final primaryResults = split.primary;
    final otherResults = split.others;
    final showMovieList = _searchResults.isNotEmpty;

    if (!showMovieList && anyMagnet) {
      return SingleChildScrollView(
        controller: _scrollController,
        // 同 CustomScrollView 分支：底部要让出系统手势区，否则最后一条
        // 磁力结果点不动。
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 72,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSourceSectionHeader(
                icon: Icons.link_rounded,
                title: '磁力资源（${_magnetResults.length}）',
                expanded: _isMagnetSourcesExpanded,
                loading: _isMagnetSearching,
                onToggle: () {
                  setState(() {
                    _isMagnetSourcesExpanded = !_isMagnetSourcesExpanded;
                  });
                },
              ),
              if (_isMagnetSourcesExpanded) ...[
                const SizedBox(height: 8),
                if (_isMagnetSearching && _magnetResults.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '正在从已启用的磁力源聚合结果…',
                      style: TextStyle(color: theme.hintColor, fontSize: 13),
                    ),
                  ),
                if (!_isMagnetSearching && _magnetSearchError.isNotEmpty)
                  _buildMagnetErrorHint(theme),
                ..._magnetResults
                    .map((t) => _buildMagnetSearchTile(theme, l10n, t)),
              ],
            ],
          ),
        ),
      );
    }

    // 磁力区块 + 影视列表不能放在同一个 Column 里：磁力条目多时总高度会超过一屏，
    // 在非 Expanded 的子节点上会直接触发 BOTTOM OVERFLOWED。统一放进可滚动视图。
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // 分组导航条（2026-10-28 用户要求「标题行固定在上面，不随页面滚动」）。
        // 影视结果有 300 多条时，磁力区块在最底下要滑一百多屏才看得到，
        // 等于没有入口。这一条用 pinned header 固定在顶部。
        // 影视区块标题固定在顶部（2026-10-31 用户要求）：不再用「影视/其他/磁力」
        // 三个互斥 pill 切换，改成一条连续的列表——影视结果下面接「其他影视」
        // （默认收起），磁力放最后。点这一行可收起整块影视，收起时挂在它下面的
        // 「其他影视」也一并收进去。
        SliverPersistentHeader(
          pinned: true,
          delegate: _SectionNavHeaderDelegate(
            child: Container(
              height: _SectionNavHeaderDelegate.height,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                // 必须不透明：pinned header 下面会滚过列表内容，透明会糊成一片。
                color: theme.scaffoldBackgroundColor,
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.35),
                  ),
                ),
              ),
              child: _buildSourceSectionHeader(
                icon: Icons.movie_outlined,
                title: '影视资源（${primaryResults.length}）',
                expanded: _isMovieExpanded,
                loading: _isMultiSourceSearching,
                onToggle: () {
                  setState(() => _isMovieExpanded = !_isMovieExpanded);
                },
              ),
            ),
          ),
        ),
        // 类型词提示横幅：「动漫」是分类、「动作」是类型筛选词，
        // 源站 wd= 只按片名搜，不说明白用户会以为搜索坏了。
        if (_typeWordCategory.isNotEmpty || _typeWordGenre.isNotEmpty)
          SliverToBoxAdapter(child: _buildTypeWordBanner(theme)),
        // 影视结果（紧跟固定在顶部的影视标题）。
        // 标题行已经固定在顶部，原地不再重复放一个「影视资源（N）」标题行。
        if (showMovieList) ...[
          if (_isMovieExpanded) ...[
            SliverToBoxAdapter(child: _buildFilterBar(theme)),
            if (!_isMultiSourceSearching &&
                primaryResults.isEmpty &&
                otherResults.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '没有符合筛选条件的结果',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _filterGenre = '';
                              _filterSort = '';
                            });
                          },
                          child: Text(l10n.searchClearFilters),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index >= primaryResults.length) {
                        return _buildSearchProgress(theme);
                      }
                      return MovieCardHorizontal(movie: primaryResults[index]);
                    },
                    childCount: primaryResults.length +
                        ((_isMultiSourceSearching ||
                                _multiSearchStatusText.isNotEmpty)
                            ? 1
                            : 0),
                  ),
                ),
              ),
          ],
        ],
        // 「其他相关结果」（2026-10-28 用户选择「噪声折叠」）。
        //
        // 采集站的 `wd=` 带相关推荐兜底：搜「周星驰」会返回《007别传》
        // 《小不列颠》《情圣2016》。这些不丢（用户可能真想要），但不能混在
        // 主列表里冒充作品 —— 折进可展开分组，默认收起。
        //
        // 它是挂在影视下面的次级分组：影视整块收起时，它一起被收进去。
        if (otherResults.isNotEmpty && _isMovieExpanded)
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSourceSectionHeader(
                    icon: Icons.help_outline,
                    title: '其他相关结果（${otherResults.length}）',
                    expanded: _isOthersExpanded,
                    loading: false,
                    onToggle: () {
                      setState(() {
                        _isOthersExpanded = !_isOthersExpanded;
                      });
                    },
                  ),
                  if (_isOthersExpanded) ...[
                    const SizedBox(height: 4),
                    ...otherResults.map(
                      (m) => MovieCardHorizontal(movie: m),
                    ),
                  ],
                ],
              ),
            ),
          ),
        // 磁力资源（放在后面）
        if (anyMagnet)
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSourceSectionHeader(
                    icon: Icons.link_rounded,
                    title: '磁力资源（${_magnetResults.length}）',
                    expanded: _isMagnetSourcesExpanded,
                    loading: _isMagnetSearching,
                    onToggle: () {
                      setState(() {
                        _isMagnetSourcesExpanded = !_isMagnetSourcesExpanded;
                      });
                    },
                  ),
                  if (_isMagnetSourcesExpanded) ...[
                    const SizedBox(height: 8),
                    if (_isMagnetSearching && _magnetResults.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '正在从已启用的磁力源聚合结果…',
                          style:
                              TextStyle(color: theme.hintColor, fontSize: 13),
                        ),
                      ),
                    if (!_isMagnetSearching && _magnetSearchError.isNotEmpty)
                      _buildMagnetErrorHint(theme),
                    ..._magnetResults
                        .map((t) => _buildMagnetSearchTile(theme, l10n, t)),
                  ],
                ],
              ),
            ),
          ),
        // 底部留白（2026-10-28 真机实测）：最后一个分组标题（「其他相关结果」）
        // 或最后一条磁力结果正好贴在屏幕最下沿时，会被系统手势导航区吞掉点击 ——
        // 表现为「这行标题怎么点都没反应」。留出安全区 + 一段余量，滚到底时
        // 它会被顶到可点区域。
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 72),
        ),
      ],
    );
  }

  /// 搜索结果分组标题（影视资源 / 磁力资源）。
  ///
  /// 2026-10-28 用户反馈两条：
  /// 1. 只能点右侧小箭头才能收起/展开 —— 这里把整行包进 [InkWell]，
  ///    标题文字、图标、右侧留白都算点击区（整行热区，符合移动端习惯）；
  /// 2. 标题前的 3px 竖条换成语义图标，比一根色条更能说明分组内容。
  Widget _buildSourceSectionHeader({
    required IconData icon,
    required String title,
    required bool expanded,
    required bool loading,
    required VoidCallback onToggle,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (loading) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              expanded ? Icons.expand_more : Icons.expand_less,
              size: 20,
              color: theme.hintColor,
            ),
          ],
        ),
      ),
    );
  }

  /// 磁力搜索失败/超时/空结果的说明条（2026-10-22 新增）。
  ///
  /// 背景：Torrentio URL 模板修复前，磁力搜索静默失败，UI 只有
  /// 「磁力资源（0）」+ 空白，用户无法区分「源挂了」与「真没资源」。
  Widget _buildMagnetErrorHint(ThemeData theme) {
    if (_magnetSearchError.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _magnetSearchError,
              style: TextStyle(color: theme.hintColor, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMagnetSearchTile(
    ThemeData theme,
    AppLocalizations l10n,
    TorrentInfo t,
  ) {
    final lines = splitTorrentDisplayTitle(t.name);
    final hint = _magnetDisplayTitleHint();
    // 中文名（2026-10-25）：磁力源给的资源名几乎全是英文发布名，
    // 光看名字认不出是哪部片子。这里显示解析出的中文片名。
    final zhName = _magnetChineseNames[t.name];
    // 「中文检索」提示与中文名重复时不再重复显示（中文搜索词时两者常常一样）。
    final showHint = hint != null && hint != zhName;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.link, color: theme.colorScheme.primary, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (zhName != null && zhName.isNotEmpty) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                zhName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              l10n.searchMagnetChineseName,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.hintColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                      ],
                      Text(
                        lines.primary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (lines.secondary != null &&
                          lines.secondary!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          lines.secondary!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.hintColor,
                          ),
                        ),
                      ],
                      if (showHint) ...[
                        const SizedBox(height: 4),
                        Text(
                          '中文检索：$hint',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _magnetMetaChip(
                  theme,
                  Icons.storage_outlined,
                  '体积 ${t.sizeFormatted}',
                ),
                _magnetMetaChip(
                  theme,
                  Icons.cloud_outlined,
                  '索引 ${t.source}',
                ),
                _magnetMetaChip(
                  theme,
                  Icons.arrow_upward,
                  '做种 ${t.seedersFormatted}',
                  valueColor: const Color(0xFF2E7D32),
                ),
                _magnetMetaChip(
                  theme,
                  Icons.arrow_downward,
                  '下载 ${t.leechers}',
                ),
                if (t.imdbId != null && t.imdbId!.isNotEmpty)
                  _magnetMetaChip(
                    theme,
                    Icons.movie_outlined,
                    'IMDb ${t.imdbId}',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => AppRoutes.toMagnetTorrentDetail(
                    context,
                    t,
                    displayTitleHint: _magnetDisplayTitleHint(),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 22),
                  label: Text(l10n.searchPlay),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => AppRoutes.toMagnetTorrentDetail(
                    context,
                    t,
                    displayTitleHint: _magnetDisplayTitleHint(),
                  ),
                  child: Text(l10n.searchOpenDetail),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _magnetMetaChip(
    ThemeData theme,
    IconData icon,
    String text, {
    Color? valueColor,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: valueColor ?? theme.hintColor),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: valueColor ?? theme.hintColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// 构建筛选栏（类型标签 + 排序按钮）
  Widget _buildFilterBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：类型筛选标签
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _genreFilters.map((genre) {
                final isSelected = _filterGenre == genre;
                final label = genre.isEmpty ? '全部' : genre;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _filterGenre = genre;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.textTheme.bodySmall?.color,
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // 第二行：排序选项
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _sortOptions.map((entry) {
                final isSelected = _filterSort == entry.key;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      // 再次点击已选中的排序方式时取消排序
                      _filterSort = isSelected ? '' : entry.key;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.secondaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.secondary
                            : theme.dividerColor,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected)
                          Icon(
                            Icons.sort,
                            size: 14,
                            color: theme.colorScheme.onSecondaryContainer,
                          )
                        else
                          const SizedBox(width: 14),
                        const SizedBox(width: 2),
                        Text(
                          entry.value,
                          style: TextStyle(
                            color: isSelected
                                ? theme.colorScheme.onSecondaryContainer
                                : theme.textTheme.bodySmall?.color,
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建搜索进度提示
  ///
  /// 显示在搜索结果列表底部，提示用户搜索进度。
  /// 搜索中显示加载动画，搜索完成后显示最终统计。
  Widget _buildSearchProgress(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 搜索中显示加载动画
            if (_isMultiSourceSearching)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (_isMultiSourceSearching) const SizedBox(width: 8),
            // 搜索状态文本
            // ⚠️ 必须限行：多源聚合状态（如「已搜索 6/6 个源，共 12 条结果（6 条在多个源有资源，已合并）」）
            // 在 360dp 宽下不换行会撑破 Row 右溢出（曾触发 RenderFlex overflow）。
            Text(
              _multiSearchStatusText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建默认视图（搜索历史 + 热门搜索）
  Widget _buildDefaultView(ThemeData theme) {
    // 按时间分组搜索历史
    final historyWithTime = _searchService.searchHistoryWithTime;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final todayKeywords = <String>[];
    final yesterdayKeywords = <String>[];
    final earlierKeywords = <String>[];

    for (final entry in historyWithTime) {
      final keyword = entry['keyword'] as String;
      final timeStr = entry['time'] as String?;
      DateTime? searchTime;
      if (timeStr != null) {
        searchTime = DateTime.tryParse(timeStr);
      }
      searchTime ??= now;

      final searchDate =
          DateTime(searchTime.year, searchTime.month, searchTime.day);
      if (searchDate == today || searchDate.isAfter(today)) {
        todayKeywords.add(keyword);
      } else if (searchDate == yesterday ||
          (searchDate.isAfter(yesterday) && searchDate.isBefore(today))) {
        yesterdayKeywords.add(keyword);
      } else {
        earlierKeywords.add(keyword);
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 搜索历史（按时间分组）
          if (historyWithTime.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    // B站风格左侧装饰条
                    Container(
                      width: 3,
                      height: 16,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '最近搜索',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: _clearHistory,
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: theme.hintColor,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '清空',
                        style: TextStyle(
                          color: theme.hintColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 今天
            if (todayKeywords.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '今天',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: todayKeywords.map((keyword) {
                  return _buildHistoryChip(theme, keyword);
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // 昨天
            if (yesterdayKeywords.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '昨天',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: yesterdayKeywords.map((keyword) {
                  return _buildHistoryChip(theme, keyword);
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // 更早
            if (earlierKeywords.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '更早',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: earlierKeywords.map((keyword) {
                  return _buildHistoryChip(theme, keyword);
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],
          ],

          // 热门搜索（B站风格标题）
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '热门搜索',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _hotKeywords.asMap().entries.map((entry) {
              final index = entry.key;
              final keyword = entry.value;
              return _buildHotChip(theme, keyword, index);
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 构建历史标签（B站风格圆角胶囊样式）
  Widget _buildHistoryChip(ThemeData theme, String keyword) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              _searchController.text = keyword;
              _doSearch(keyword);
            },
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history,
                    size: 14,
                    color: theme.hintColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    keyword,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 桌面端长按不可靠：提供可见删除按钮
          InkWell(
            onTap: () => _deleteHistory(keyword),
            borderRadius:
                const BorderRadius.horizontal(right: Radius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
              child: Icon(
                Icons.close,
                size: 16,
                color: theme.hintColor.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建热门搜索标签（B站风格）
  Widget _buildHotChip(ThemeData theme, String keyword, int index) {
    final isTopThree = index < 3;

    return GestureDetector(
      onTap: () {
        _searchController.text = keyword;
        _doSearch(keyword);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isTopThree
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: isTopThree
              ? Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  width: 1,
                )
              : Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.5),
                  width: 1,
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${index + 1}',
              style: TextStyle(
                color: isTopThree ? theme.colorScheme.primary : theme.hintColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              keyword,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 13,
                color: isTopThree ? theme.colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部固定「影视资源（N）」标题行用的 SliverPersistentHeader 代理。
///
/// 高度固定（内容只有一行标题 + 展开箭头），`pinned: true` 让它在列表滚动
/// 时一直贴在顶部 —— 用户明确要求「标题行固定在上面，不随页面滚动」。
/// 2026-10-31：原来这里是一排 pill（影视/其他/磁力）用于切换区块，已按用户
/// 要求去掉，改为只固定影视标题行，三个区块在列表里从上到下依次排列。
class _SectionNavHeaderDelegate extends SliverPersistentHeaderDelegate {
  static const double height = 46;

  final Widget child;

  const _SectionNavHeaderDelegate({required this.child});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) =>
      child;

  @override
  bool shouldRebuild(covariant _SectionNavHeaderDelegate oldDelegate) =>
      oldDelegate.child != child;
}
