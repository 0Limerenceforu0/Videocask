import 'dart:async';

import '../../models/movie.dart';
import '../../models/torrent_info.dart';
import '../../services/imdb_lookup_service.dart';
import '../../services/torrent_search_service.dart';

/// 磁力搜索相关逻辑
class DetailTorrent {
  /// 磁力搜索服务
  final TorrentSearchService torrentSearchService = TorrentSearchService();

  /// 磁力搜索结果列表
  List<TorrentInfo> torrentSearchResults = [];

  /// 是否已自动搜索过磁力资源（避免重复搜索）
  bool torrentAutoSearched = false;

  /// 纯磁力详情页：是否已跑过宽松自动搜索（与 CMS 详情 strict 搜索分离）
  bool magnetPageBroadSearchDone = false;

  /// 手动输入的磁力链接
  String magnetInput = '';

  /// 磁力播放版本号（用于取消正在进行的磁力等待循环）
  int magnetPlayVersion = 0;

  /// 磁力搜索状态
  bool isSearching = false;
  String searchMessage = '';

  int _searchGeneration = 0;

  /// 换片或重进详情时清空磁力列表与状态。
  void resetForNewMovie() {
    _searchGeneration++;
    torrentSearchResults.clear();
    torrentAutoSearched = false;
    searchMessage = '';
    isSearching = false;
  }

  /// CMS 详情页：与搜索页相同策略（IMDb 优先 + 片名/年份/别名，默认宽松过滤）。
  ///
  /// [strict] 为 `true` 时更严，仅用于手动「精准检索」；自动进入详情应传 `false`。
  Future<void> searchForMovieDetail(
    Movie movie, {
    required bool strict,
  }) async {
    final generation = ++_searchGeneration;
    isSearching = true;
    searchMessage = strict ? '正在按片名/年份精准检索磁力…' : '正在检索磁力资源…';

    final displayTitle = movie.name.trim();
    final year = movie.year.trim().isNotEmpty
        ? movie.year.trim()
        : ImdbLookupService.yearFromUserQuery(displayTitle);
    final alias = movie.alias.trim().isNotEmpty ? movie.alias.trim() : null;

    try {
      final results = await torrentSearchService
          .searchPreferringImdb(
            displayTitle: displayTitle,
            year: year,
            alias: alias,
            strictMatchForDetailPage: strict,
          )
          .timeout(const Duration(seconds: 45));
      if (generation != _searchGeneration) return;
      torrentSearchResults = results;
      torrentAutoSearched = true;
      if (torrentSearchResults.isEmpty) {
        searchMessage =
            strict ? '未找到严格匹配的磁力，可尝试「扩大范围」或全站搜索' : '暂无磁力结果，请检查磁力源配置或换关键词搜索';
      } else {
        searchMessage = '';
      }
    } on TimeoutException {
      if (generation != _searchGeneration) return;
      torrentSearchResults = [];
      searchMessage = '磁力搜索超时，请检查网络后重试';
    } catch (e) {
      if (generation != _searchGeneration) return;
      torrentSearchResults = [];
      searchMessage = '磁力搜索失败: $e';
    } finally {
      if (generation == _searchGeneration) {
        isSearching = false;
      }
    }
  }

  /// 搜索磁力资源
  Future<List<TorrentInfo>> search(String keyword) async {
    final generation = ++_searchGeneration;
    isSearching = true;
    searchMessage = '正在搜索磁力资源...';

    try {
      final results = await torrentSearchService
          .search(keyword)
          .timeout(const Duration(seconds: 45));
      if (generation != _searchGeneration) return [];
      torrentSearchResults = results;
      return results;
    } on TimeoutException {
      if (generation != _searchGeneration) return [];
      searchMessage = '磁力搜索超时，请检查网络后重试';
      return [];
    } catch (e) {
      if (generation != _searchGeneration) return [];
      searchMessage = '搜索失败: $e';
      return [];
    } finally {
      if (generation == _searchGeneration) {
        isSearching = false;
      }
    }
  }

  /// 搜索磁力资源（宽松模式）
  Future<List<TorrentInfo>> searchBroad(String keyword) async {
    final generation = ++_searchGeneration;
    isSearching = true;
    searchMessage = '正在搜索磁力资源...';

    try {
      final results = await torrentSearchService
          .search(keyword)
          .timeout(const Duration(seconds: 45));
      if (generation != _searchGeneration) return [];
      torrentSearchResults = results;
      magnetPageBroadSearchDone = true;
      return results;
    } on TimeoutException {
      if (generation != _searchGeneration) return [];
      searchMessage = '磁力搜索超时，请检查网络后重试';
      return [];
    } catch (e) {
      if (generation != _searchGeneration) return [];
      searchMessage = '搜索失败: $e';
      return [];
    } finally {
      if (generation == _searchGeneration) {
        isSearching = false;
      }
    }
  }

  /// 清除搜索结果
  void clearSearchResults() {
    torrentSearchResults.clear();
    searchMessage = '';
  }

  /// 释放资源
  void dispose() {
    // 释放磁力搜索服务
  }
}
