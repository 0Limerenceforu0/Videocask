/// 弱 swarm（做种极少 + 几乎不下行）的判定与止损规则（纯函数，可单测）。
///
/// 2026-11-10 真机反馈：905.9MB 的 HDRip，Torrentio 索引写「做种 17」，
/// 实际只连上 1 个 peer、下行几十 KB/s。旧逻辑全程把它当「慢种子」对待：
/// 45s 缓冲超时仍交接给 mpv，再等 40s 首帧、就地重开 2×20s，最后才判失败；
/// 重试又是 `stop()` + `addMagnet` 冷启动，已下载进度清零 —— 四轮下来约 8
/// 分钟，用户体感就是「加载非常慢，最后失败了」。
///
/// 这里把「swarm 本身就没货」单独识别出来：连续一个确认窗口内 peer 数低于
/// 阈值且下行低于阈值，就不再空等，直接中止这次起流并让上层有限次重试后
/// 明说「资源做种太少」，而不是把 900MB 的期待耗在 1 个 peer 上。
abstract final class MagnetWeakSwarmPolicy {
  /// 低于这个「在连 peer 数」视为 swarm 太弱。
  ///
  /// 不要求为 0：真机上「索引 17 做种、实际只连上 1 个」是常见情况，而
  /// 1 个 peer 供 900MB 文件，在几分钟的等待窗口里不可能凑够起播数据。
  static const int minHealthyPeers = 2;

  /// 下行低于这个值视为「供数不足」（120 KB/s）。
  ///
  /// 参照：起播要预载头部 64MB，120KB/s 需要约 9 分钟，远超任何合理等待
  /// 窗口；而能正常起播的资源实测都在 MB/s 量级。
  static const int minSpeedBytesPerSec = 120 * 1024;

  /// 连续满足「弱」条件多久才判定。
  ///
  /// 不能一出现就判：刚 `addMagnet` 时 peer 数是 0→1→N 渐进涨的，太早
  /// 判定会误杀「连得慢但能连上」的正常资源。实测能起播的资源都在几秒内
  /// 连到多个 peer，18s 足够区分「慢」和「没货」。
  static const Duration confirmWindow = Duration(seconds: 18);

  /// 同一资源连续几次弱 swarm 就彻底放弃（不再无限重试）。
  ///
  /// 给 1 次重试机会：重新打洞 / 换 tracker 偶尔能连上新的 peer；
  /// 第二次仍然只有个位数 peer 就说明这个种子真的没货了，继续重试只是
  /// 让用户多等一个确认窗口。
  static const int maxWeakStrikes = 2;

  /// 当前是否处于「弱」状态。
  ///
  /// [bufferPct] 已达起播门槛（[readyBufferPct]）时一律不算弱 —— 有足够
  /// 数据能出画就不是 swarm 的问题，交给首帧看门狗判断即可。
  static bool isWeak({
    required int activePeers,
    required int downloadSpeed,
    required int bufferPct,
    required int readyBufferPct,
  }) {
    if (bufferPct >= readyBufferPct) return false;
    return activePeers < minHealthyPeers &&
        downloadSpeed < minSpeedBytesPerSec;
  }
}
