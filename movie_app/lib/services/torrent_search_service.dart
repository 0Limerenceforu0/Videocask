import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../config/magnet_source_catalog.dart';
import '../models/magnet_source_config.dart';
import '../models/torrent_info.dart';
import '../utils/commentary_content_filter.dart';
import 'imdb_lookup_service.dart';
import 'storage_service.dart';
import 'video_title_resolve_service.dart';

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

  static final Map<String, String> _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 18),
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

  /// 探测单源是否可达（任意 2xx/3xx 视为可连；具体解析不校验）
  Future<(bool ok, String message)> probeSource(
    MagnetSourceConfig config,
  ) async {
    try {
      final url = config.buildUrl('test', page: 1);
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
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final title = (refineTitle ?? q).trim();
    final configs = activeConfigs();
    if (configs.isEmpty) return [];

    final futures = configs.map((c) => _searchWithConfig(c, q, page));
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
      final narrowed = await search(
        imdb,
        refineTitle: displayTitle,
        refineYear: effectiveYear,
        refineAlias: alias,
        refineEpisodeIndexZeroBased: refineEpisodeIndexZeroBased,
        strictMatchForDetailPage: strictMatchForDetailPage,
        refineImdbId: imdb,
      );
      final trustedImdb = resolved?.imdbId != null && resolved!.imdbId == imdb;
      if (narrowed.isNotEmpty &&
          (trustedImdb || _areResultsRelevant(narrowed, relevanceTitle))) {
        return narrowed;
      }
    }
    final q = _buildFallbackTitleQuery(
      displayTitle,
      effectiveYear,
      alias,
      resolved: resolved,
    );
    final results = await search(
      q,
      refineTitle: displayTitle,
      refineYear: effectiveYear,
      refineAlias: alias,
      refineEpisodeIndexZeroBased: refineEpisodeIndexZeroBased,
      strictMatchForDetailPage: strictMatchForDetailPage,
      refineImdbId: imdb,
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
  bool _isResultRelevant(TorrentInfo result, String displayTitle) {
    final resultName = result.name.toLowerCase();
    final title = displayTitle.toLowerCase();

    // 检查标题是否包含在结果名称中
    if (resultName.contains(title)) {
      return true;
    }

    // 检查结果名称是否包含在标题中
    if (title.contains(resultName)) {
      return true;
    }

    // 检查分词匹配
    final titleTokens = title.split(RegExp(r'[\s\-_.·《》\[\]（）(),]+'));
    final resultTokens = resultName.split(RegExp(r'[\s\-_.·《》\[\]（）(),]+'));

    // 计算匹配的分词数量
    int matchCount = 0;
    for (final token in titleTokens) {
      if (token.length >= 2 &&
          resultTokens.any(
            (resultToken) =>
                resultToken.contains(token) || token.contains(resultToken),
          )) {
        matchCount++;
      }
    }

    // 如果匹配的分词数量超过标题分词数量的一半，则认为相关
    return matchCount >= titleTokens.length / 2;
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

  Future<List<TorrentInfo>?> _searchWithConfig(
    MagnetSourceConfig c,
    String query,
    int page,
  ) async {
    try {
      switch (c.driver) {
        case MagnetSourceDriver.ytsMxApi:
          return _searchYtsAt(c.buildUrl(query, page: page), c.displayName);
        case MagnetSourceDriver.torrentioJson:
          return _searchTorrentioAt(
            c.buildUrl(query, page: page),
            c.displayName,
          );
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

  Future<List<TorrentInfo>?> _searchTorrentioAt(
    String url,
    String sourceLabel,
  ) async {
    try {
      final resp = await _dio.get(url);
      final data = resp.data;
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
        if (magnet == null || !magnet.startsWith('magnet:')) {
          final ih = s['infoHash']?.toString().trim() ?? '';
          if (ih.length == 40 && !RegExp(r'[^0-9a-fA-F]').hasMatch(ih)) {
            final name = (s['title'] ?? s['name'] ?? 'torrent')
                .toString()
                .replaceAll('\n', ' ')
                .trim();
            magnet =
                'magnet:?xt=urn:btih:${ih.toLowerCase()}&dn=${Uri.encodeComponent(name)}';
          }
        }
        if (magnet == null || !magnetHasValidBtih(magnet)) continue;
        final name = (s['title'] ?? s['name'] ?? sourceLabel)
            .toString()
            .replaceAll('\n', ' ')
            .trim();
        results.add(
          TorrentInfo(
            name: name.isEmpty ? sourceLabel : name,
            size: 0,
            seeders: 0,
            leechers: 0,
            magnetUri: Uri.decodeFull(magnet),
            source: sourceLabel,
          ),
        );
      }
      return results.isEmpty ? null : results;
    } catch (e) {
      debugPrint('Torrentio 搜索失败: $e');
      return null;
    }
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
    return rel * 50000 + se;
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
