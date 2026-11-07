import 'package:flutter/foundation.dart';

import '../models/movie.dart';
import '../models/torrent_info.dart';
import '../utils/magnet_chinese_title.dart';
import 'douban_lookup_service.dart';

/// 磁力资源的中文名解析（搜索页用）。
///
/// ## 为什么需要
///
/// 磁力源返回的资源名几乎全是英文发布名
/// （`The.Godfather.1972.1080p.BluRay.x264-GROUP`），搜索页的磁力卡片
/// 直接显示它，用户认不出是哪部片子。
///
/// ## 三级来源（按可信度）
///
/// 1. **本次搜索已加载的影视结果**（CMS 采集站）—— `vod_name` 就是中文片名，
///    按年份对齐即可。**零网络开销**。
/// 2. **用户搜索词本身是中文** —— 搜「教父」时搜索词就是中文名。**零网络开销**。
/// 3. **豆瓣联想** —— 搜英文片名时唯一能拿到中文名的路。
///    豆瓣联想接口对英文查询同样返回结果，且 `title` 字段是中文片名
///    （实测 `q=Shawshank` → `title: 肖申克的救赎` / `sub_title: The Shawshank Redemption`）。
///    这一级有网络开销，因此**按「基础标题」去重 + 缓存**：
///    同一次搜索的几十条磁力通常只对应一两部片子，实际只会发一两个请求。
class MagnetChineseNameService {
  MagnetChineseNameService._();
  static final MagnetChineseNameService instance = MagnetChineseNameService._();

  /// 基础标题（英文，去掉画质 / 年份标签）→ 中文名。
  /// 值为 null 表示「查过但没有可信中文名」，避免反复发请求。
  final Map<String, String?> _cache = {};

  /// 解析一批磁力资源的中文名。
  ///
  /// 返回 `资源名 → 中文名` 的映射；没有可信中文名的资源**不会出现在结果里**
  /// （调用方据此决定要不要显示中文名行）。
  ///
  /// [query] 用户搜索词（中文搜索词时可直接当中文名用，省掉网络请求）。
  /// [searchResults] 本次搜索已加载的影视结果（CMS），可提供零成本的中文名。
  Future<Map<String, String>> resolveNames(
    List<TorrentInfo> torrents, {
    String? query,
    List<Movie> searchResults = const [],
  }) async {
    if (torrents.isEmpty) return const {};

    final out = <String, String>{};

    // ── 第 1/2 级：零网络开销（CMS 年份对齐 / 中文搜索词）──
    final needLookup = <String, TorrentInfo>{};
    for (final t in torrents) {
      final zh = resolveChineseTitleForTorrent(
        torrentName: t.name,
        searchResults: searchResults,
        query: query,
      );
      if (zh != null && zh.isNotEmpty) {
        out[t.name] = zh;
        continue;
      }
      // 还不知道 → 走第 3 级（豆瓣）。同一基础标题只查一次。
      final base = baseTitleOf(t.name);
      if (base.isEmpty) continue;
      if (_cache.containsKey(base)) {
        final cached = _cache[base];
        if (cached != null && cached.isNotEmpty) out[t.name] = cached;
        continue;
      }
      needLookup[base] = t;
    }

    if (needLookup.isEmpty) return out;

    // ── 第 3 级：豆瓣联想（按基础标题去重，并发查）──
    await Future.wait(
      needLookup.keys.map((base) => _lookupOne(base)),
    );
    for (final entry in needLookup.entries) {
      final zh = _cache[entry.key];
      if (zh == null || zh.isEmpty) continue;
      out[entry.value.name] = zh;
    }
    return out;
  }

  /// 查一个基础标题的中文名（结果写进缓存）。
  Future<void> _lookupOne(String base) async {
    try {
      final match = await DoubanLookupService.instance
          .suggest(base)
          .timeout(const Duration(seconds: 8));
      final zh = match?.title.trim() ?? '';
      // 豆瓣的 `title` 本身就是中文片名；空结果视为「查不到」。
      _cache[base] = zh.isEmpty ? null : zh;
    } catch (e) {
      debugPrint('磁力资源中文名解析失败 ($base): $e');
      _cache[base] = null;
    }
  }

  /// 清空缓存（设置页「清缓存」或换源后调用）。
  void clearCache() {
    _cache.clear();
  }
}
