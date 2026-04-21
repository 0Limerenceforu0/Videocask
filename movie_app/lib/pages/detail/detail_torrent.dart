import 'dart:async';

import '../../models/movie.dart';
import '../../models/torrent_info.dart';
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

  /// 换片或重进详情时清空磁力列表与状态。
  void resetForNewMovie() {
    torrentSearchResults.clear();
    torrentAutoSearched = false;
    searchMessage = '';
    isSearching = false;
  }

  /// CMS 详情页：优先 IMDb 解析 + 聚合源搜索，并按片名/别名/年份做相关度与 [strictMatchForDetailPage] 过滤。
  ///
  /// [strict] 为 `true` 时更严，适合首屏；`false` 时等同搜索页宽松度，用于「扩大范围」。
  Future<void> searchForMovieDetail(
    Movie movie, {
    required bool strict,
  }) async {
    if (isSearching) return;
    isSearching = true;
    searchMessage = strict ? '正在按片名/年份精准检索磁力…' : '正在扩大范围检索磁力…';

    try {
      torrentSearchResults = await torrentSearchService.searchPreferringImdb(
        displayTitle: movie.name,
        year: movie.year.trim().isNotEmpty ? movie.year.trim() : null,
        alias: movie.alias.trim().isNotEmpty ? movie.alias.trim() : null,
        strictMatchForDetailPage: strict,
      );
      torrentAutoSearched = true;
      if (torrentSearchResults.isEmpty) {
        searchMessage =
            strict ? '未找到严格匹配的磁力，可尝试「扩大范围」或全站搜索' : '暂无磁力结果，请检查磁力源配置或换关键词搜索';
      } else {
        searchMessage = '';
      }
    } catch (e) {
      torrentSearchResults = [];
      searchMessage = '磁力搜索失败: $e';
    } finally {
      isSearching = false;
    }
  }

  /// 搜索磁力资源
  Future<List<TorrentInfo>> search(String keyword) async {
    isSearching = true;
    searchMessage = '正在搜索磁力资源...';

    try {
      final results = await torrentSearchService.search(keyword);
      torrentSearchResults = results;
      return results;
    } catch (e) {
      searchMessage = '搜索失败: $e';
      return [];
    } finally {
      isSearching = false;
    }
  }

  /// 搜索磁力资源（宽松模式）
  Future<List<TorrentInfo>> searchBroad(String keyword) async {
    isSearching = true;
    searchMessage = '正在搜索磁力资源...';

    try {
      final results = await torrentSearchService.search(keyword);
      torrentSearchResults = results;
      magnetPageBroadSearchDone = true;
      return results;
    } catch (e) {
      searchMessage = '搜索失败: $e';
      return [];
    } finally {
      isSearching = false;
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
