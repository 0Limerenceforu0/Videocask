import 'dart:collection';

import '../models/torrent_info.dart';

/// 磁力搜索结果缓存（P0-3）。
///
/// 内存 LRU，不落盘（磁力结果时效性强，几百 KB 也没必要写文件）。
///
/// 关键设计：
/// - key = 归一化标题|年份|strict（**不**拼磁力源配置，否则用户开关源就全失效）；
/// - 命中立即返回旧结果 + 后台静默刷新（stale-while-revalidate）；
/// - **只缓存非空结果**：空结果不缓存，避免「抖动一次就缓存了空 → 再点还是空」。
class TorrentSearchCache {
  TorrentSearchCache._();
  static final TorrentSearchCache _instance = TorrentSearchCache._();
  factory TorrentSearchCache() => _instance;

  static const Duration _ttl = Duration(minutes: 10);
  static const int _maxEntries = 100;

  final LinkedHashMap<String, _CacheEntry> _map = LinkedHashMap();

  static String key(String title, String? year, bool strict) =>
      '${title.trim().toLowerCase()}|${(year?.trim() ?? '').toLowerCase()}|${strict ? 1 : 0}';

  /// 命中且未过期返回缓存；否则返回 null。命中即视为最近使用（LRU 触达）。
  List<TorrentInfo>? get(String k) {
    final entry = _map[k];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.ts) > _ttl) {
      _map.remove(k);
      return null;
    }
    // LRU：移除后重新插入到末尾（最近使用排最后）
    _map.remove(k);
    _map[k] = entry;
    return entry.data;
  }

  void put(String k, List<TorrentInfo> data) {
    _map.remove(k);
    _map[k] = _CacheEntry(List.of(data), DateTime.now());
    while (_map.length > _maxEntries) {
      _map.remove(_map.keys.first);
    }
  }

  void invalidate(String k) => _map.remove(k);
}

class _CacheEntry {
  final List<TorrentInfo> data;
  final DateTime ts;
  _CacheEntry(this.data, this.ts);
}
