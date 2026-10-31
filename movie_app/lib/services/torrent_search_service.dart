import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../config/magnet_source_catalog.dart';
import '../models/magnet_source_config.dart';
import '../models/torrent_info.dart';
import '../utils/commentary_content_filter.dart';
import 'imdb_lookup_service.dart';
import 'storage_service.dart';
import 'torrent_player_models.dart';
import 'video_title_resolve_service.dart';

/// Torrentio 单条流的统计信息（从 `streams[].title` 的
/// `👤 208 💾 6.64 GB` 段解析而来）。
class TorrentioStreamStats {
  final int seeders;
  final int sizeBytes;

  const TorrentioStreamStats({this.seeders = 0, this.sizeBytes = 0});

  bool get isEmpty => seeders == 0 && sizeBytes == 0;
}

/// 磁力链接搜索服务
///
/// 按「设置 → 磁力搜索源」中的启用项聚合；支持内置 YTS / Torrentio / 1337x / BT4G / Nyaa / Apibay 及 Jackett、自定义模板。
class TorrentSearchService {
  static final TorrentSearchService _instance =
      TorrentSearchService._internal();
  factory TorrentSearchService() => _instance;
  TorrentSearchService._internal();

  static final RegExp _btihPattern =
      RegExp(r'btih:([0-9a-fA-F]{40})', caseSensitive: false);

  static final RegExp _cjkPattern = RegExp(r'[\u4e00-\u9fff]');

  /// 单个磁力源的硬超时（2026-10-27 改为**按源分级**）。
  ///
  /// ## 为什么不能一刀切
  ///
  /// 真机 5G 实测（2026-10-27）：
  /// - YTS / 1337x / BT4G / Nyaa：TCP 层直接超时，纯粹在拖后腿 → **6s** 足够判死；
  /// - Torrentio：同一网络下可能需要 >5s 才建连（收到 5s 连接超时的实测日志），
  ///   但它**是唯一能出结果的源** → 必须给足余量。
  ///
  /// 曾经用 15s 一刀切，导致 4 个死源各耗 15s、整轮 28.6s；
  /// 后来收到 6s 一刀切，又把 Torrentio 自己掐死了。分级才对。
  static const Duration _fastSourceTimeout = Duration(seconds: 12);
  static const Duration _slowSourceTimeout = Duration(seconds: 35);

  /// `searchPreferringImdb` 的**总体预算**：超过这个时长就不再跑第二轮。
  ///
  /// 慢源（Torrentio）实测可能吃掉 20–30s，如果它空手而归还要再跑一轮
  /// 标题搜索，就会撞上调用方的 45s 整体超时 —— 整轮结果被当超时丢掉，
  /// 用户看到的是「磁力模块直接没了」。宁可不跑第二轮，也要把第一轮的
  /// 结果（哪怕是空）按时交出去。
  static const Duration _roundBudget = Duration(seconds: 34);

  static final Map<String, String> _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  final Dio _dio = Dio(
    BaseOptions(
      // 快源（HTML / JSON 文本站）：连不上就是连不上，不值得等太久。
      // apibay 实测偶尔要 8s+ 才回包（真机 18:38 记录），留到 8s/12s。
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 12),
    ),
  );

  /// 慢源专用（Torrentio）：国内到 `torrentio.strem.fun` 建连可能超过 5s，
  /// 但它又是唯一稳定出结果的源 —— 用快源的超时会把它直接掐死
  /// （2026-10-27 实测：connect timeout 5s，一条结果都没拿到）。
  final Dio _slowDio = Dio(
    BaseOptions(
      // 真机实测（2026-10-27 18:46）：`curl -m 15` 拿不到完整响应体，
      // 但 ping 稳定 350ms、HTTP 200 —— Torrentio 是**服务端慢**
      // （它要实时聚合多个 provider），不是网络不通。必须给足预算。
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 34),
    ),
  );

  static bool magnetHasValidBtih(String? magnet) {
    if (magnet == null || magnet.isEmpty) return false;
    final m = magnet.trim();
    if (!m.startsWith('magnet:?')) return false;
    return _btihPattern.hasMatch(m);
  }

  static String? extractBtih(String magnet) {
    final m = _btihPattern.firstMatch(magnet);
    return m?.group(1)?.toLowerCase();
  }

  /// 判断一段输入是否为磁力链接（或裸 40 位 btih 哈希）。
  ///
  /// 用于搜索框：用户直接粘贴磁力链接时应跳过普通搜索、直进详情页。
  static bool isMagnetLink(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    if (t.toLowerCase().startsWith('magnet:?')) {
      return magnetHasValidBtih(t);
    }
    // 裸 40 位 btih（不含空格、不含冒号前缀）也视作磁力，便于直接粘贴 infohash。
    return !t.contains(' ') &&
        !t.contains(':') &&
        _btihPattern.hasMatch('btih:$t');
  }

  /// 从原始磁力链接构造 [TorrentInfo]（搜索框「贴磁力直接进详情」用）。
  ///
  /// 裸 btih 会被补齐成完整 `magnet:?xt=urn:btih:...`；名称优先取磁力里的
  /// `dn`（display name）参数，没有则回退到「磁力链接」。
  static TorrentInfo torrentInfoFromRawMagnet(String raw) {
    final t = raw.trim();
    final isBareHash = !t.toLowerCase().startsWith('magnet:?') &&
        !t.contains(' ') &&
        !t.contains(':') &&
        _btihPattern.hasMatch('btih:$t');
    final magnetUri = isBareHash ? 'magnet:?xt=urn:btih:$t' : t;
    // 用标准 URI 查询解析取 `dn`，同时兼容 `%20` 与 `+`（HTML 表单式空格）。
    String? dn;
    try {
      dn = Uri.parse(magnetUri).queryParameters['dn'];
    } catch (_) {
      dn = null;
    }
    if (dn == null) {
      final dnMatch =
          RegExp(r'[?&]dn=([^&]+)', caseSensitive: false).firstMatch(magnetUri);
      dn = dnMatch != null ? Uri.decodeComponent(dnMatch.group(1) ?? '') : null;
    }
    final name = (dn?.trim() ?? '').isNotEmpty ? dn!.trim() : '磁力链接';
    return TorrentInfo(
      name: name,
      size: 0,
      seeders: 0,
      leechers: 0,
      magnetUri: Uri.decodeFull(magnetUri),
      source: '本地磁力',
    );
  }

  /// 探测单源是否可达（任意 2xx/3xx 视为可连；具体解析不校验）
  Future<(bool ok, String message)> probeSource(
    MagnetSourceConfig config,
  ) async {
    try {
      // Torrentio 是 IMDb id 索引，对任意占位词（如 'test'）返回 404/空
      // streams —— 用真实 tt id 探测才能反映网络真实可达性。
      final probeQuery =
          config.driver == MagnetSourceDriver.torrentioJson ? 'tt0111161' : 'test';
      final url = config.buildUrl(probeQuery, page: 1);
      final resp = await _dio.get<String>(
        url,
        options: Options(
          validateStatus: (s) => s != null && s < 500,
          responseType: ResponseType.plain,
          headers: config.driver == MagnetSourceDriver.ytsMxApi ||
                  config.driver == MagnetSourceDriver.torrentioJson ||
                  config.driver == MagnetSourceDriver.apibay ||
                  config.driver == MagnetSourceDriver.jackettApi
              ? {'User-Agent': _browserHeaders['User-Agent']!}
              : _browserHeaders,
        ),
      );
      final code = resp.statusCode ?? 0;
      if (code >= 200 && code < 400) {
        return (true, 'HTTP $code');
      }
      return (false, 'HTTP $code');
    } catch (e) {
      return (false, e.toString());
    }
  }

  /// 当前已启用的磁力源配置（无本地配置时使用内置默认）
  List<MagnetSourceConfig> activeConfigs() {
    final raw = StorageService().getSetting(AppConstants.keyMagnetSources);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = MagnetSourceCatalog.decodeList(raw);
        final on = list.where((c) => c.enabled).toList();
        if (on.isNotEmpty) return on;
      } catch (e, st) {
        debugPrint('磁力源配置 JSON 解析失败，将使用内置默认: $e');
        assert(() {
          debugPrint('$st');
          return true;
        }());
      }
    }
    return MagnetSourceCatalog.builtInDefaults.where((c) => c.enabled).toList();
  }

  /// 搜索磁力链接（聚合多源）
  Future<List<TorrentInfo>> search(
    String query, {
    int page = 1,
    String? refineTitle,
    String? refineYear,
    String? refineAlias,
    int? refineEpisodeIndexZeroBased,
    bool strictMatchForDetailPage = false,
    String? refineImdbId,
    Set<MagnetSourceDriver>? restrictDrivers,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final title = (refineTitle ?? q).trim();
    var configs = activeConfigs();
    // 2026-10-25：IMDb 轮只允许「tt-id 索引源」（Torrentio / YTS）参与。
    // 把 `tt` id 丢给 1337x / BT4G / Apibay / Nyaa / Solid / Jackett 这类
    // 文本源只会返回垃圾并各自撞 15s 超时，`Future.wait` 等最慢的源 →
    // 整轮被拖到 15s+，正是「搜索框磁力出来很慢」的根因。
    if (restrictDrivers != null && restrictDrivers.isNotEmpty) {
      configs =
          configs.where((c) => restrictDrivers.contains(c.driver)).toList();
    }
    if (configs.isEmpty) return [];

    // 2026-10-24：给每个源加**独立硬超时**。
    //
    // Dio 自身的 connect 12s + receive 18s，单源最坏 30s；`Future.wait`
    // 等的是**最慢的那个源**，所以一个半死不活的源能把整轮搜索拖到 30s。
    // 而 `searchPreferringImdb` 最多跑两轮（IMDb 轮 + 回退标题轮），
    // 最坏 60s —— 必然撞上调用方的 45s 整体超时，于是整轮结果被当作
    // 超时丢弃（用户看到的就是「磁力资源模块直接没了」）。
    // 封顶 15s/源后：单轮 ≤15s，两轮 ≤30s + 解析，稳定落在 45s 以内。
    final futures = configs.map((c) {
      final limit = _isSlowDriver(c.driver)
          ? _slowSourceTimeout
          : _fastSourceTimeout;
      return _searchWithConfig(c, q, page).timeout(
            limit,
            onTimeout: () => null,
          );
    });
    final responses = await Future.wait(futures, eagerError: false);

    final results = <TorrentInfo>[];
    for (final response in responses) {
      if (response != null) {
        results.addAll(response);
      }
    }

    return _finalizeResults(
      results,
      refineTitle: title,
      refineYear: refineYear?.trim(),
      refineAlias: refineAlias?.trim(),
      refineEpisodeIndexZeroBased: refineEpisodeIndexZeroBased,
      strictMatchForDetailPage: strictMatchForDetailPage,
      refineImdbId: refineImdbId?.trim(),
    );
  }

  /// 先解析 IMDb ID（豆瓣 / TMDB / IMDb 联想）并用 `tt` 搜磁力，无结果再回退片名搜索。
  Future<List<TorrentInfo>> searchPreferringImdb({
    required String displayTitle,
    String? year,
    String? alias,
    int? refineEpisodeIndexZeroBased,
    bool strictMatchForDetailPage = false,
  }) async {
    final sw = Stopwatch()..start();
    final resolved = await VideoTitleResolveService.instance.resolve(
      displayTitle,
      year: year,
      alias: alias,
    );
    final effectiveYear = resolved?.year ?? year;
    final relevanceTitle = _relevanceTitleForResolved(
      displayTitle,
      alias,
      resolved,
    );

    final direct = ImdbLookupService.parseImdbIdFromText(displayTitle);
    final imdb = direct ?? resolved?.imdbId;
    if (imdb != null) {
      // IMDb 轮：只查 tt-id 索引源（Torrentio / YTS），不把 `tt` id 丢给文本源。
      // 文本源对 tt id 返回垃圾并各自撞 15s 超时，会拖垮整轮。
      final narrowed = await search(
        imdb,
        refineTitle: displayTitle,
        refineYear: effectiveYear,
        refineAlias: alias,
        refineEpisodeIndexZeroBased: refineEpisodeIndexZeroBased,
        strictMatchForDetailPage: strictMatchForDetailPage,
        refineImdbId: imdb,
        restrictDrivers: const {
          MagnetSourceDriver.torrentioJson,
          MagnetSourceDriver.ytsMxApi,
        },
      );
      final trustedImdb = resolved?.imdbId != null && resolved!.imdbId == imdb;
      if (narrowed.isNotEmpty &&
          (trustedImdb || _areResultsRelevant(narrowed, relevanceTitle))) {
        return narrowed;
      }
    }
    if (sw.elapsed >= _roundBudget) {
      debugPrint(
        '磁力两轮预算用尽(${sw.elapsed.inSeconds}s)，跳过标题轮，'
        '避免撞调用方 45s 整体超时',
      );
      return const [];
    }
    final q = _buildFallbackTitleQuery(
      displayTitle,
      effectiveYear,
      alias,
      resolved: resolved,
    );
    // 回退标题轮：用片名查所有源。此处**不再**传 `refineImdbId` ——
    // 标题轮结果来自文本源，名字里不含 tt id，传了反而被
    // `_finalizeResults` 的 imdb 硬过滤整批删光（旧实现「详情页磁力一直为空」）。
    final results = await search(
      q,
      refineTitle: displayTitle,
      refineYear: effectiveYear,
      refineAlias: alias,
      refineEpisodeIndexZeroBased: refineEpisodeIndexZeroBased,
      strictMatchForDetailPage: strictMatchForDetailPage,
    );
    return results
        .where((result) => _isResultRelevant(result, relevanceTitle))
        .toList();
  }

  /// 优先用 TMDB/豆瓣解析出的英文名，否则别名或显示标题。
  String _relevanceTitleForResolved(
    String displayTitle,
    String? alias,
    VideoTitleResolveResult? resolved,
  ) {
    final en = resolved?.englishTitle?.trim() ?? '';
    if (en.isNotEmpty) return en;
    return _relevanceTitleFor(displayTitle, alias);
  }

  /// 中文主标题时用 CMS 英文别名与磁力发布名比对；否则用显示标题。
  String _relevanceTitleFor(String displayTitle, String? alias) {
    final a = alias?.trim() ?? '';
    if (a.isNotEmpty &&
        _cjkPattern.hasMatch(displayTitle) &&
        !_cjkPattern.hasMatch(a)) {
      return a;
    }
    return displayTitle;
  }

  /// 检查搜索结果是否与显示标题相关
  bool _areResultsRelevant(List<TorrentInfo> results, String displayTitle) {
    if (results.isEmpty) return false;
    // 至少有一半的结果应该与显示标题相关
    final relevantCount = results
        .where((result) => _isResultRelevant(result, displayTitle))
        .length;
    return relevantCount >= results.length / 2;
  }

  /// 检查单个搜索结果是否与显示标题相关
  ///
  /// 2026-10-24：判定逻辑抽到 `isTorrentResultRelevant`（纯函数，可单测）。
  bool _isResultRelevant(TorrentInfo result, String displayTitle) {
    return isTorrentResultRelevant(result.name, displayTitle);
  }

  String _buildFallbackTitleQuery(
    String title,
    String? year,
    String? alias, {
    VideoTitleResolveResult? resolved,
  }) {
    final en = resolved?.englishTitle?.trim() ?? '';
    if (en.isNotEmpty && _cjkPattern.hasMatch(title.trim())) {
      return _buildFallbackTitleQuery(en, resolved?.year ?? year, null);
    }
    final t = title.trim();
    final a = alias?.trim() ?? '';
    var base = t;
    if (a.isNotEmpty && _cjkPattern.hasMatch(t) && !_cjkPattern.hasMatch(a)) {
      base = a;
    }
    var q = base;
    final y = year?.trim();
    if (y != null && y.isNotEmpty && y != '0') {
      q = '$q $y';
    }
    if (a.isNotEmpty &&
        a.toLowerCase() != t.toLowerCase() &&
        a.length > 1 &&
        base != a) {
      q = '$q $a';
    }
    return q;
  }

  /// 该源是否要按「慢源」给足超时（Torrentio / 用户自建 Jackett）。
  static bool _isSlowDriver(MagnetSourceDriver d) {
    switch (d) {
      case MagnetSourceDriver.torrentioJson:
      case MagnetSourceDriver.jackettApi:
        return true;
      case MagnetSourceDriver.ytsMxApi:
      case MagnetSourceDriver.html1337x:
      case MagnetSourceDriver.htmlBt4g:
      case MagnetSourceDriver.rssNyaa:
      case MagnetSourceDriver.apibay:
      case MagnetSourceDriver.solidHtml:
        return false;
    }
  }

  /// 该源是否**只索引拉丁字母发布名**（中文查询对它没有意义）。
  static bool _isLatinOnlyDriver(MagnetSourceDriver d) {
    switch (d) {
      case MagnetSourceDriver.torrentioJson:
      case MagnetSourceDriver.jackettApi:
        // Torrentio 靠 IMDb id；Jackett 是用户自建索引器，可能带中文库。
        return false;
      case MagnetSourceDriver.ytsMxApi:
      case MagnetSourceDriver.html1337x:
      case MagnetSourceDriver.htmlBt4g:
      case MagnetSourceDriver.rssNyaa:
      case MagnetSourceDriver.apibay:
      case MagnetSourceDriver.solidHtml:
        return true;
    }
  }

  Future<List<TorrentInfo>?> _searchWithConfig(
    MagnetSourceConfig c,
    String query,
    int page,
  ) async {
    // 🔴 中文查询词**不要**丢给「只索引英文发布名」的文本源。
    //
    // 2026-10-27 真机实测：搜「流浪地球」时 apibay 的
    // `q.php?q=流浪地球` 并不返回空，而是返回一份**无关热门榜**
    // （成人片 Dangerous Women / Adobe Photoshop 破解 / 蜘蛛侠），
    // 本机 curl 复验同样如此（英文 `inception` 则正常返回 791 做种）。
    // 这些垃圾会被当成本次搜索结果，再被贴上「流浪地球」的中文名 ——
    // 用户看到的就是「搜流浪地球，出来一堆成人片」。
    //
    // 这类源只有在查询词是拉丁字母时才有意义；中文查询一律跳过，
    // 由 IMDb 轮（Torrentio / YTS，走 tt-id）负责。
    if (_cjkPattern.hasMatch(query) && _isLatinOnlyDriver(c.driver)) {
      debugPrint('磁力源 ${c.displayName} 跳过：查询词含中文，该源不索引中文名');
      return null;
    }
    try {
      switch (c.driver) {
        case MagnetSourceDriver.ytsMxApi:
          return _searchYtsAt(c.buildUrl(query, page: page), c.displayName);
        case MagnetSourceDriver.torrentioJson:
          return _searchTorrentioAt(c, query, c.displayName);
        case MagnetSourceDriver.html1337x:
          return _search1337xAt(c.buildUrl(query, page: page), c.displayName);
        case MagnetSourceDriver.htmlBt4g:
          return _searchBt4gAt(c.buildUrl(query, page: page), c.displayName);
        case MagnetSourceDriver.rssNyaa:
          return _searchNyaaRssAt(c.buildUrl(query, page: page), c.displayName);
        case MagnetSourceDriver.apibay:
          return _searchApibayAt(c.buildUrl(query, page: page), c.displayName);
        case MagnetSourceDriver.solidHtml:
          return _searchSolidAt(c.buildUrl(query, page: page), c.displayName);
        case MagnetSourceDriver.jackettApi:
          return _searchJackettAt(c.buildUrl(query, page: page), c.displayName);
      }
    } catch (e) {
      debugPrint('磁力源 ${c.displayName} 搜索失败: $e');
      return null;
    }
  }

  Future<List<TorrentInfo>?> _searchYtsAt(
    String url,
    String sourceLabel,
  ) async {
    try {
      final resp = await _dio.get(url);
      return _parseYtsBody(resp.data, sourceLabel);
    } catch (e) {
      debugPrint('YTS 搜索失败: $e');
      return null;
    }
  }

  List<TorrentInfo>? _parseYtsBody(dynamic data, String sourceLabel) {
    if (data is! Map) return null;
    final movies = data['data']?['movies'];
    if (movies is! List || movies.isEmpty) return null;

    final results = <TorrentInfo>[];
    for (final movie in movies) {
      if (movie is! Map) continue;
      final mTitle = (movie['title']?.toString()) ?? '';
      final mYear = (movie['year']?.toString()) ?? '';
      final imdbRaw = (movie['imdb_code']?.toString() ?? '').trim();
      final imdbId = RegExp(r'^tt\d+$', caseSensitive: false).hasMatch(imdbRaw)
          ? imdbRaw.toLowerCase()
          : null;
      final torrents = movie['torrents'];
      if (torrents is! List) continue;

      for (final t in torrents) {
        if (t is! Map) continue;
        final quality = (t['quality']?.toString()) ?? '';
        final name = '$mTitle ($mYear) $quality';
        final magnet = (t['url']?.toString()) ?? '';
        if (!magnetHasValidBtih(magnet)) continue;
        final seeders = int.tryParse(t['seeds']?.toString() ?? '0') ?? 0;
        if (name.isNotEmpty) {
          results.add(
            TorrentInfo(
              name: name,
              size: int.tryParse(t['size_bytes']?.toString() ?? '0') ?? 0,
              seeders: seeders,
              leechers: int.tryParse(t['peers']?.toString() ?? '0') ?? 0,
              magnetUri: magnet,
              source: sourceLabel,
              imdbId: imdbId,
            ),
          );
        }
      }
    }
    return results.isEmpty ? null : results;
  }

  /// Torrentio URL 候选列表（纯函数，便于单测）。
  ///
  /// Torrentio（Stremio 生态）是 **IMDb id 索引**：
  /// - 只接受带媒体类型的路径 `movie/{tt}.json` / `series/{tt}.json`，
  ///   无前缀的 `stream/{tt}.json` 恒返 404（2026-10-22 实测）。旧内置模板
  ///   就是漏了 `movie/`，导致国内唯一稳定可达的磁力源永远搜不到东西。
  /// - `stream/search/{片名}.json` 端点存在但实测返回空 `{"streams":[]}`，
  ///   片名查询对 Torrentio 无效，直接跳过（返回空候选）省一次请求。
  static List<String> torrentioUrlCandidates(
    String urlTemplate,
    String query,
  ) {
    final q = query.trim();
    // IMDb title id 形如 tt0111161（tt + 至少 7 位数字；历史上 7 位起，
    // 新片已到 8-9 位）。少位数的（如 tt011116）不是合法 id，发了也 404。
    if (!RegExp(r'^tt\d{7,}$', caseSensitive: false).hasMatch(q)) {
      return const [];
    }
    final primary = urlTemplate.replaceAll('{query}', q);
    // 个别资源只收录在 series 侧（模板含 /movie/ 路径段时才生成兜底候选；
    // 用户自定义模板没有该段时只发一次请求）。
    final alt = primary.replaceFirst(RegExp(r'/movie/'), '/series/');
    if (alt == primary) return [primary];
    return [primary, alt];
  }

  Future<List<TorrentInfo>?> _searchTorrentioAt(
    MagnetSourceConfig config,
    String query,
    String sourceLabel,
  ) async {
    final urls = torrentioUrlCandidates(config.urlTemplate, query);
    if (urls.isEmpty) return null;

    // **串行**尝试候选（`movie/` → `series/`）。
    //
    // 2026-10-27 真机实测教训：改成并行发两个候选后，Torrentio 两个请求
    // **双双 receive timeout(18s)**；串行时第一个候选就能成功返回。
    // 对端明显不耐并发，宁可串行 —— 第一个候选命中就直接结束，
    // 只有它失败/为空才轮到第二个。
    for (final url in urls) {
      try {
        final resp = await _slowDio.get(url);
        final parsed = parseTorrentioBody(
          resp.data,
          sourceLabel,
          imdbId: query,
        );
        if (parsed != null && parsed.isNotEmpty) return parsed;
      } catch (e) {
        debugPrint('Torrentio 搜索失败($url): $e');
      }
    }
    return null;
  }

  /// Torrentio 流标题里的统计信息（`👤 208 💾 6.64 GB`）。
  ///
  /// ## 为什么需要单独解析
  ///
  /// Torrentio 的 `streams[].title` 是**两行**：
  /// ```
  /// Inception 2010 1080p BluRay x264-YIFY
  /// 👤 208 💾 6.64 GB ⚙️ YTS
  /// ```
  /// 旧实现把整串当片名、并把 `size/seeders/leechers` 一律写死成 `0`
  /// （2026-10-27 真机实测）：卡片标题写着 `6.64 GB`，下面一行却写「体积 0 B」
  /// 「做种 0」。做种数是用户判断「这资源到底能不能播」的唯一依据，
  /// 全显示 0 会让所有资源看起来都是死种。
  ///
  /// 解析不出来时返回全 0（下游按「未知」处理，不做假显示）。
  static TorrentioStreamStats parseTorrentioStats(String rawTitle) {
    if (rawTitle.isEmpty) return const TorrentioStreamStats();

    var seeders = 0;
    final seedMatch = _torrentioSeedersPattern.firstMatch(rawTitle);
    if (seedMatch != null) {
      seeders = int.tryParse(
            seedMatch.group(1)!.replaceAll(',', ''),
          ) ??
          0;
    }

    var sizeBytes = 0;
    final sizeMatch = _torrentioSizePattern.firstMatch(rawTitle);
    if (sizeMatch != null) {
      final value = double.tryParse(sizeMatch.group(1)!) ?? 0;
      sizeBytes = (value * _byteMultiplier(sizeMatch.group(2)!)).round();
    }

    return TorrentioStreamStats(seeders: seeders, sizeBytes: sizeBytes);
  }

  static final RegExp _torrentioSeedersPattern = RegExp(r'👤\s*([\d,]+)');

  static final RegExp _torrentioSizePattern = RegExp(
    r'💾\s*([\d.]+)\s*([KMGT]i?B)',
    caseSensitive: false,
  );

  static double _byteMultiplier(String unit) {
    final u = unit.toUpperCase().replaceAll('I', '');
    switch (u) {
      case 'KB':
        return 1024;
      case 'MB':
        return 1024 * 1024;
      case 'TB':
        return 1024 * 1024 * 1024 * 1024;
      case 'GB':
      default:
        return 1024 * 1024 * 1024;
    }
  }

  /// 从 Torrentio 流标题里取**干净的发布名**（丢掉统计行与 emoji）。
  ///
  /// 旧实现只把 `\n` 换成空格，于是详情页标题成了
  /// `👤 11 💾 2.15 GB ⚙️ ThePirateBay Dual Audio / 🇬🇧 🇵🇹`，
  /// 三四行糊满屏、片名被挤到看不见（2026-10-27 真机截图）。
  static String torrentioDisplayName(String rawTitle) {
    var s = rawTitle.replaceAll('\r', '').trim();
    if (s.isEmpty) return '';

    // 统计行通常在第二行：取第一行非空内容。
    final lines = s
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '';
    s = lines.first;

    // 单行时统计信息会内联在片名后面：从第一个「👤」处截断。
    final cut = s.indexOf('👤');
    if (cut > 0) s = s.substring(0, cut).trim();

    return s;
  }

  /// Torrentio 响应解析（纯函数，便于单测）。
  ///
  /// Torrentio 是 **IMDb id 索引**：响应体里**不带**每条流的 imdbId，
  /// 但整批流都属于本次查询的 `tt` id。把查询 id 回填到每条结果（[imdbId]）
  /// 后，`_finalizeResults` 的 imdb 硬过滤才能认出这批结果，否则详情页/搜索框
  /// 的磁力会被「整批删光」（`2026-10-25` 复盘）。
  static List<TorrentInfo>? parseTorrentioBody(
    dynamic data,
    String sourceLabel, {
    String? imdbId,
  }) {
    if (data is! Map) return null;
    dynamic streams = data['streams'];
    if (streams == null && data['stream'] != null) {
      streams = data['stream'];
    }
    if (streams is! List || streams.isEmpty) return null;

    final results = <TorrentInfo>[];
    for (final s in streams) {
      if (s is! Map) continue;
      String? magnet = s['url']?.toString();
      final rawTitle = (s['title'] ?? s['name'] ?? sourceLabel).toString();
      final cleanName = torrentioDisplayName(rawTitle);
      if (magnet == null || !magnet.startsWith('magnet:')) {
        final ih = s['infoHash']?.toString().trim() ?? '';
        if (ih.length == 40 && !RegExp(r'[^0-9a-fA-F]').hasMatch(ih)) {
          magnet = 'magnet:?xt=urn:btih:${ih.toLowerCase()}'
              '&dn=${Uri.encodeComponent(cleanName.isEmpty ? sourceLabel : cleanName)}';
        }
      }
      if (magnet == null || !magnetHasValidBtih(magnet)) continue;
      final name = cleanName.isEmpty ? sourceLabel : cleanName;
      final stats = parseTorrentioStats(rawTitle);
      results.add(
        TorrentInfo(
          name: name,
          // 旧实现写死 0 —— 见 [parseTorrentioStats] 注释。
          size: stats.sizeBytes,
          seeders: stats.seeders,
          leechers: 0,
          magnetUri: Uri.decodeFull(magnet),
          source: sourceLabel,
          imdbId: imdbId,
        ),
      );
    }
    return results.isEmpty ? null : results;
  }

  Future<List<TorrentInfo>?> _searchApibayAt(
    String url,
    String sourceLabel,
  ) async {
    try {
      final resp = await _dio.get(url);
      final data = resp.data;
      if (data is! List) return null;
      if (data.isEmpty ||
          (data.length == 1 &&
              data[0] is Map &&
              data[0]['name']?.toString() == 'No results returned')) {
        return null;
      }

      return data
          .whereType<Map<dynamic, dynamic>>()
          .map((item) {
            final name = (item['name']?.toString()) ?? '';
            final infoHash = (item['info_hash']?.toString() ?? '').trim();
            if (infoHash.length != 40 ||
                RegExp(r'[^0-9a-fA-F]').hasMatch(infoHash)) {
              return null;
            }
            final hashLower = infoHash.toLowerCase();
            final imdbRaw = (item['imdb']?.toString() ?? '').trim();
            final imdbId =
                RegExp(r'^tt\d+$', caseSensitive: false).hasMatch(imdbRaw)
                    ? imdbRaw.toLowerCase()
                    : null;
            return TorrentInfo(
              name: name,
              size: int.tryParse(item['size']?.toString() ?? '0') ?? 0,
              seeders: int.tryParse(item['seeders']?.toString() ?? '0') ?? 0,
              leechers: int.tryParse(item['leechers']?.toString() ?? '0') ?? 0,
              magnetUri:
                  'magnet:?xt=urn:btih:$hashLower&dn=${Uri.encodeComponent(name)}'
                  '&tr=udp://tracker.opentrackr.org:1337/announce'
                  '&tr=udp://open.tracker.cl:1337/announce'
                  '&tr=udp://tracker.openbittorrent.com:6969/announce',
              source: sourceLabel,
              imdbId: imdbId,
            );
          })
          .whereType<TorrentInfo>()
          .where((t) => t.name.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Apibay 搜索失败: $e');
      return null;
    }
  }

  Future<List<TorrentInfo>?> _searchSolidAt(
    String url,
    String sourceLabel,
  ) async {
    try {
      final resp = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: _browserHeaders,
        ),
      );

      final html = resp.data ?? '';
      final results = <TorrentInfo>[];

      final itemPattern = RegExp(
        r'<div class="result-item"[^>]*>([\s\S]*?)</div>\s*</div>\s*</div>',
        dotAll: true,
      );
      final titlePattern =
          RegExp(r'<div class="title"[^>]*>\s*<a[^>]*>([^<]+)</a>');
      final magnetPattern = RegExp(r'href="(magnet:\?[^"]+)"');
      final sizePattern = RegExp(r'class="size"[^>]*>([^<]+)<');
      final seedersPattern = RegExp(r'class="seeders"[^>]*>([^<]+)<');

      for (final item in itemPattern.allMatches(html)) {
        final itemHtml = item.group(1) ?? '';
        final titleMatch = titlePattern.firstMatch(itemHtml);
        final magnetMatch = magnetPattern.firstMatch(itemHtml);
        if (titleMatch == null) continue;

        final ttitle = titleMatch.group(1)?.trim() ?? '';
        final magnetRaw = magnetMatch?.group(1)?.trim() ?? '';
        final magnet = Uri.decodeFull(magnetRaw);
        if (!magnetHasValidBtih(magnet)) continue;

        final sizeStr =
            sizePattern.firstMatch(itemHtml)?.group(1)?.trim() ?? '';
        final seeders = int.tryParse(
              seedersPattern.firstMatch(itemHtml)?.group(1)?.trim() ?? '0',
            ) ??
            0;

        if (ttitle.isNotEmpty) {
          results.add(
            TorrentInfo(
              name: ttitle,
              size: _parseSizeString(sizeStr),
              seeders: seeders,
              leechers: 0,
              magnetUri: magnet,
              source: sourceLabel,
            ),
          );
        }
      }
      return results.isEmpty ? null : results;
    } catch (e) {
      debugPrint('SolidTorrents 搜索失败: $e');
      return null;
    }
  }

  Future<List<TorrentInfo>?> _search1337xAt(
    String url,
    String sourceLabel,
  ) async {
    try {
      final resp = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: _browserHeaders,
        ),
      );

      final html = resp.data ?? '';
      final results = <TorrentInfo>[];

      final rowPattern = RegExp(r'<tr>\s*<td[^>]*>.*?</tr>', dotAll: true);
      final titlePattern = RegExp(r'href="/torrent/[^"]*"[^>]*>([^<]+)</a>');
      final magnetPattern = RegExp(r'href="(magnet:\?[^"]+)"');
      final sizePattern = RegExp(r'text-nowrap">\s*([\d.]+\s*[KMGT]?i?B)\s*<');
      final seedersPattern = RegExp(r'class="seeds"[^>]*>\s*(\d+)\s*<');

      for (final row in rowPattern.allMatches(html)) {
        final rowHtml = row.group(0) ?? '';
        final titleMatch = titlePattern.firstMatch(rowHtml);
        final magnetMatch = magnetPattern.firstMatch(rowHtml);
        if (titleMatch == null) continue;

        final ttitle = titleMatch.group(1)?.trim() ?? '';
        final magnetRaw = magnetMatch?.group(1) ?? '';
        final magnet = Uri.decodeFull(magnetRaw);
        if (!magnetHasValidBtih(magnet)) continue;

        final sizeStr = sizePattern.firstMatch(rowHtml)?.group(1)?.trim() ?? '';
        final seeders =
            int.tryParse(seedersPattern.firstMatch(rowHtml)?.group(1) ?? '0') ??
                0;

        if (ttitle.isNotEmpty) {
          results.add(
            TorrentInfo(
              name: ttitle,
              size: _parseSizeString(sizeStr),
              seeders: seeders,
              leechers: 0,
              magnetUri: magnet,
              source: sourceLabel,
            ),
          );
        }
      }
      return results.isEmpty ? null : results;
    } catch (e) {
      debugPrint('1337x 搜索失败: $e');
      return null;
    }
  }

  Future<List<TorrentInfo>?> _searchBt4gAt(
    String url,
    String sourceLabel,
  ) async {
    try {
      final resp = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: _browserHeaders,
        ),
      );
      final html = resp.data ?? '';
      final results = <TorrentInfo>[];

      final rowMag = RegExp(
        r'href="(magnet:\?[^"]+)"[^>]*(?:title="([^"]*)")?',
        caseSensitive: false,
      );
      for (final m in rowMag.allMatches(html)) {
        final magnet = Uri.decodeFull(m.group(1) ?? '');
        if (!magnetHasValidBtih(magnet)) continue;
        var name = (m.group(2) ?? '').trim();
        if (name.isEmpty) {
          final dn = RegExp(r'[?&]dn=([^&]+)').firstMatch(magnet);
          if (dn != null) {
            name = Uri.decodeComponent(dn.group(1) ?? '');
          }
        }
        if (name.isEmpty) name = sourceLabel;
        results.add(
          TorrentInfo(
            name: name,
            size: 0,
            seeders: 0,
            leechers: 0,
            magnetUri: magnet,
            source: sourceLabel,
          ),
        );
      }
      return results.isEmpty ? null : results;
    } catch (e) {
      debugPrint('BT4G 搜索失败: $e');
      return null;
    }
  }

  Future<List<TorrentInfo>?> _searchNyaaRssAt(
    String url,
    String sourceLabel,
  ) async {
    try {
      final resp = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: _browserHeaders,
        ),
      );
      final xml = resp.data ?? '';
      final results = <TorrentInfo>[];
      final itemRe = RegExp(r'<item>([\s\S]*?)</item>', multiLine: true);

      for (final im in itemRe.allMatches(xml)) {
        final block = im.group(1) ?? '';
        String title = '';
        final t1 = RegExp(r'<title><!\[CDATA\[(.*?)\]\]></title>', dotAll: true)
            .firstMatch(block);
        final t2 = RegExp(r'<title>([^<]+)</title>').firstMatch(block);
        if (t1 != null) {
          title = t1.group(1)?.trim() ?? '';
        } else if (t2 != null) {
          title = t2.group(1)?.trim() ?? '';
        }

        String? hash;
        final h1 = RegExp(
          r'<nyaa:infoHash>([^<]+)</nyaa:infoHash>',
          caseSensitive: false,
        ).firstMatch(block);
        final h2 = RegExp(r'<infoHash>([^<]+)</infoHash>', caseSensitive: false)
            .firstMatch(block);
        if (h1 != null) hash = h1.group(1)?.trim();
        if (hash == null && h2 != null) hash = h2.group(1)?.trim();

        String? magnet;
        final mag = RegExp(r'(magnet:\?[^\s<"&]+)').firstMatch(block);
        if (mag != null) magnet = mag.group(1);

        if ((magnet == null || !magnetHasValidBtih(magnet)) &&
            hash != null &&
            hash.length == 40 &&
            !RegExp(r'[^0-9a-fA-F]', caseSensitive: false).hasMatch(hash)) {
          magnet =
              'magnet:?xt=urn:btih:${hash.toLowerCase()}&dn=${Uri.encodeComponent(title)}';
        }

        if (magnet == null || !magnetHasValidBtih(magnet) || title.isEmpty) {
          continue;
        }

        final seeders = int.tryParse(
              RegExp(
                    r'<nyaa:seeders>(\d+)</nyaa:seeders>',
                    caseSensitive: false,
                  ).firstMatch(block)?.group(1) ??
                  '0',
            ) ??
            0;
        final leechers = int.tryParse(
              RegExp(
                    r'<nyaa:leechers>(\d+)</nyaa:leechers>',
                    caseSensitive: false,
                  ).firstMatch(block)?.group(1) ??
                  '0',
            ) ??
            0;

        results.add(
          TorrentInfo(
            name: title,
            size: _parseNyaaSize(block),
            seeders: seeders,
            leechers: leechers,
            magnetUri: Uri.decodeFull(magnet),
            source: sourceLabel,
          ),
        );
      }
      return results.isEmpty ? null : results;
    } catch (e) {
      debugPrint('Nyaa RSS 搜索失败: $e');
      return null;
    }
  }

  int _parseNyaaSize(String block) {
    final m = RegExp(r'<nyaa:size>([^<]+)</nyaa:size>', caseSensitive: false)
        .firstMatch(block);
    if (m == null) return 0;
    return _parseSizeString(m.group(1)?.trim() ?? '');
  }

  Future<List<TorrentInfo>?> _searchJackettAt(
    String url,
    String sourceLabel,
  ) async {
    try {
      final resp = await _dio.get(url);
      final data = resp.data;
      if (data is! Map) return null;
      final resultsList = data['Results'];
      if (resultsList is! List) return null;

      final results = <TorrentInfo>[];
      for (final r in resultsList) {
        if (r is! Map) continue;
        final magnet = r['MagnetUri']?.toString() ?? '';
        if (!magnetHasValidBtih(magnet)) continue;
        final name =
            r['Title']?.toString() ?? r['Tracker']?.toString() ?? sourceLabel;
        final size = int.tryParse(r['Size']?.toString() ?? '0') ?? 0;
        final seeders = int.tryParse(r['Seeders']?.toString() ?? '0') ?? 0;
        final peers = int.tryParse(r['Peers']?.toString() ?? '0') ?? 0;
        final leechers = (peers - seeders).clamp(0, peers);
        results.add(
          TorrentInfo(
            name: name,
            size: size,
            seeders: seeders,
            leechers: leechers,
            magnetUri: magnet,
            source: sourceLabel,
          ),
        );
      }
      return results.isEmpty ? null : results;
    } catch (e) {
      debugPrint('Jackett 搜索失败: $e');
      return null;
    }
  }

  List<TorrentInfo> _finalizeResults(
    List<TorrentInfo> raw, {
    required String refineTitle,
    String? refineYear,
    String? refineAlias,
    int? refineEpisodeIndexZeroBased,
    bool strictMatchForDetailPage = false,
    String? refineImdbId,
  }) {
    final imdbNeedle = refineImdbId?.trim().toLowerCase();
    final byHash = <String, TorrentInfo>{};
    for (final t in raw) {
      if (CommentaryContentFilter.isTorrent(t)) continue;
      if (!magnetHasValidBtih(t.magnetUri)) continue;
      final h = extractBtih(t.magnetUri);
      if (h == null) continue;
      final s = _rankScore(
        t,
        refineTitle: refineTitle,
        refineYear: refineYear,
        refineAlias: refineAlias,
      );
      final existing = byHash[h];
      if (existing == null) {
        byHash[h] = t;
      } else {
        final s0 = _rankScore(
          existing,
          refineTitle: refineTitle,
          refineYear: refineYear,
          refineAlias: refineAlias,
        );
        var pick = s > s0 ? t : existing;
        if (imdbNeedle != null && imdbNeedle.isNotEmpty) {
          final tOk = t.imdbId != null && t.imdbId!.toLowerCase() == imdbNeedle;
          final eOk = existing.imdbId != null &&
              existing.imdbId!.toLowerCase() == imdbNeedle;
          if (tOk && !eOk) pick = t;
          if (eOk && !tOk) pick = existing;
        }
        byHash[h] = pick;
      }
    }
    var list = byHash.values.toList();
    list.sort((a, b) {
      if (imdbNeedle != null && imdbNeedle.isNotEmpty) {
        final am = a.imdbId != null && a.imdbId!.toLowerCase() == imdbNeedle;
        final bm = b.imdbId != null && b.imdbId!.toLowerCase() == imdbNeedle;
        if (am != bm) return am ? -1 : 1;
      }
      final cmp = _rankScore(
        b,
        refineTitle: refineTitle,
        refineYear: refineYear,
        refineAlias: refineAlias,
      ).compareTo(
        _rankScore(
          a,
          refineTitle: refineTitle,
          refineYear: refineYear,
          refineAlias: refineAlias,
        ),
      );
      if (cmp != 0) return cmp;
      return b.seeders.compareTo(a.seeders);
    });

    var usedImdbMetaMatch = false;
    if (imdbNeedle != null && imdbNeedle.isNotEmpty) {
      final meta = list
          .where(
            (t) => t.imdbId != null && t.imdbId!.toLowerCase() == imdbNeedle,
          )
          .toList();
      if (meta.isNotEmpty) {
        list = meta;
        usedImdbMetaMatch = true;
      } else {
        list = list
            .where((t) => _torrentTextContainsImdbId(t, imdbNeedle))
            .toList();
      }
    }

    if (strictMatchForDetailPage && !usedImdbMetaMatch) {
      list = list
          .where(
            (t) => _passesStrictDetailFilter(
              t.name,
              refineTitle: refineTitle,
              refineYear: refineYear,
              refineAlias: refineAlias,
              episodeIndexZeroBased: refineEpisodeIndexZeroBased,
            ),
          )
          .toList();
    } else if (usedImdbMetaMatch && refineEpisodeIndexZeroBased != null) {
      final ep0 = refineEpisodeIndexZeroBased;
      final byEp = list
          .where(
            (t) => _episodeConsistentWithTorrent(t.name.toLowerCase(), ep0),
          )
          .toList();
      if (byEp.isNotEmpty) list = byEp;
    }
    return list;
  }

  String _magnetDnLower(TorrentInfo t) {
    final m =
        RegExp(r'[?&]dn=([^&]+)', caseSensitive: false).firstMatch(t.magnetUri);
    if (m == null) return '';
    return Uri.decodeComponent(m.group(1) ?? '').toLowerCase();
  }

  bool _torrentTextContainsImdbId(TorrentInfo t, String idLower) {
    if (t.name.toLowerCase().contains(idLower)) return true;
    if ((t.imdbId ?? '').toLowerCase() == idLower) return true;
    if (_magnetDnLower(t).contains(idLower)) return true;
    return false;
  }

  bool _passesStrictDetailFilter(
    String torrentName, {
    required String refineTitle,
    String? refineYear,
    String? refineAlias,
    int? episodeIndexZeroBased,
  }) {
    final n = torrentName.toLowerCase();
    final title = refineTitle.trim();
    if (title.isEmpty) return false;

    if (!_titleOrAliasContainedInTorrent(n, title, refineAlias)) {
      return false;
    }

    final y = (refineYear ?? '').trim();
    if (y.length == 4 && RegExp(r'^\d{4}$').hasMatch(y)) {
      if (!_yearOrSeriesConsistent(n, y, title)) {
        return false;
      }
    }

    if (episodeIndexZeroBased != null) {
      if (!_episodeConsistentWithTorrent(n, episodeIndexZeroBased)) {
        return false;
      }
    }

    return true;
  }

  bool _titleOrAliasContainedInTorrent(
    String nLower,
    String title,
    String? alias,
  ) {
    final p = title.toLowerCase().trim();
    if (p.isEmpty) return false;
    final compactP = p.replaceAll(RegExp(r'[\s·]+'), '');
    final compactN = nLower.replaceAll(RegExp(r'[\s·]+'), '');
    if (nLower.contains(p) ||
        (compactP.length >= 2 && compactN.contains(compactP))) {
      return true;
    }
    final a = (alias ?? '').trim().toLowerCase();
    if (a.length >= 3) {
      final ca = a.replaceAll(RegExp(r'[\s·]+'), '');
      if (nLower.contains(a) || (ca.length >= 3 && compactN.contains(ca))) {
        return true;
      }
    }
    return false;
  }

  bool _yearOrSeriesConsistent(String n, String year, String title) {
    if (n.contains(year)) return true;
    final t = title.toLowerCase();
    if (t.contains('第') && (t.contains('集') || t.contains('季'))) {
      return true;
    }
    if (t.contains('季')) return true;
    if (RegExp(r's\d{1,2}[\s._-]?e\d{1,2}', caseSensitive: false).hasMatch(n)) {
      return true;
    }
    if (RegExp(r'complete|season\s*\d|全集|全\s*\d+\s*集', caseSensitive: false)
        .hasMatch(n)) {
      return true;
    }
    if (!t.contains('集') && !t.contains('季')) {
      return true;
    }
    return false;
  }

  bool _episodeConsistentWithTorrent(String n, int epIdx0) {
    final expected = epIdx0 + 1;

    final sn =
        RegExp(r'\bs(\d{1,2})e(\d{1,2})\b', caseSensitive: false).firstMatch(n);
    if (sn != null) {
      final ep = int.tryParse(sn.group(2) ?? '') ?? -1;
      if (ep > 0 && ep != expected) return false;
    }

    final cn = RegExp(r'第\s*0*(\d{1,3})\s*集').firstMatch(n);
    if (cn != null) {
      final ep = int.tryParse(cn.group(1) ?? '') ?? -1;
      if (ep > 0 && ep != expected) return false;
    }

    final epOnly = RegExp(
      r'(^|[\s._-])e\s*0*(\d{1,2})([\s._-]|$)',
      caseSensitive: false,
    ).firstMatch(n);
    if (epOnly != null && !RegExp(r's\d', caseSensitive: false).hasMatch(n)) {
      final ep = int.tryParse(epOnly.group(2) ?? '') ?? -1;
      if (ep > 0 && ep != expected) return false;
    }

    return true;
  }

  double _rankScore(
    TorrentInfo t, {
    required String refineTitle,
    String? refineYear,
    String? refineAlias,
  }) {
    final rel = _relevanceScore(
      t.name,
      title: refineTitle,
      year: refineYear,
      alias: refineAlias,
    );
    final se = t.seeders.clamp(0, 500000);

    // 相关度分档，档内再按「做种健康度」排序。
    //
    // 旧实现是 `rel * 50000 + se`：标题命中一次就 +85，折算 85*50000 ≈ 425 万，
    // 而做种数通常只有 0~100，最多贡献百分量级 —— 做种数实际是「tie-breaker 的
    // tie-breaker」，完全不起作用。后果是「标题最像但 0 做种」的死种长期排在
    // 健康种前面，用户点进去就是「节点 1 · 10B/s」。
    //
    // 现在：档位（1e6 一档）保证相关度仍然是主导，做种健康度（上限约 8.6k）
    // 只在同档内起作用，不会让不相关的资源靠做种数窜上来。
    final tier = rel >= 140 ? 3 : (rel >= 85 ? 2 : (rel >= 40 ? 1 : 0));
    final health = se == 0
        ? 0.0
        : (math.log(se + 1) / math.ln10) * 2000 + math.min(se, 2000);
    return tier * 1000000 + health + rel;
  }

  double _relevanceScore(
    String torrentName, {
    required String title,
    String? year,
    String? alias,
  }) {
    final n = torrentName.toLowerCase();
    double score = 0;
    final y = year ?? '';
    if (y.length == 4 && RegExp(r'^\d{4}$').hasMatch(y) && n.contains(y)) {
      score += 40;
    }
    final primary = title.trim().toLowerCase();
    if (primary.isNotEmpty) {
      if (n.contains(primary)) score += 85;
      final compact = primary.replaceAll(RegExp(r'\s+'), '');
      if (compact.isNotEmpty && n.contains(compact)) score += 55;
      for (final token in primary.split(RegExp(r'[\s\-_.·《》\[\]（）(),]+'))) {
        if (token.length >= 2 && n.contains(token)) score += 6;
      }
    }
    final al = (alias ?? '').trim().toLowerCase();
    if (al.isNotEmpty && al != primary) {
      if (n.contains(al)) score += 42;
      for (final token in al.split(RegExp(r'[\s\-_.·《》\[\]（）(),]+'))) {
        if (token.length >= 4 && n.contains(token)) score += 10;
      }
    }
    return score;
  }

  int _parseSizeString(String sizeStr) {
    if (sizeStr.isEmpty) return 0;
    final s = sizeStr.toUpperCase().replaceAll('I', '');
    final match = RegExp(r'([0-9.]+)\s*(B|KB|MB|GB|TB)').firstMatch(s);
    if (match == null) return 0;
    final value = double.tryParse(match.group(1) ?? '0') ?? 0;
    final unit = match.group(2) ?? 'B';
    switch (unit) {
      case 'KB':
        return (value * 1024).toInt();
      case 'MB':
        return (value * 1024 * 1024).toInt();
      case 'GB':
        return (value * 1024 * 1024 * 1024).toInt();
      case 'TB':
        return (value * 1024 * 1024 * 1024 * 1024).toInt();
      default:
        return value.toInt();
    }
  }
}
