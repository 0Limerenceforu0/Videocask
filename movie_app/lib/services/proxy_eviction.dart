/// HLS / 远程代理会话的 LRU 淘汰纯逻辑。
///
/// 历史背景：长时间播放（尤其加密去广告源、DLNA 投屏）会不断新建代理会话与
/// `HttpClient`，若只增不淘汰，会话/连接会随观看数量无限累积，fd 与内存压力
/// 持续上升，是 SIGABRT 闪退的潜在诱因之一。为防此，代理层对每个类型的会话
/// 设上限（HLS 会话 / 远程代理各 8 个），超出即淘汰最旧的。
///
/// 本文件把「淘汰最旧条目」抽成**纯函数** [evictOldest]，便于单元测试验证：
/// 删除的是**最旧（按插入顺序）**的、且数量恰好为多出部分、插入顺序被保留。
/// 调用方（[LocalMediaHttpServer]）据返回的被淘汰条目关闭底层资源。
///
/// Dart 的 `Map` 字面量与常规插入保持**插入顺序**，因此 `map.keys.first` 即最旧项。
List<MapEntry<K, V>> evictOldest<K, V>(Map<K, V> map, int maxCount) {
  final removed = <MapEntry<K, V>>[];
  final cap = maxCount < 0 ? 0 : maxCount;
  while (map.length > cap) {
    final key = map.keys.first;
    final value = map.remove(key)!;
    removed.add(MapEntry<K, V>(key, value));
  }
  return removed;
}
