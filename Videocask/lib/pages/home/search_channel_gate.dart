/// 搜索页两条通道的开关判定（纯函数，可单测）。
///
/// 存在的理由（2026-10-28 真机回归）：磁力通道曾被写成
/// `titleLikeQuery = !isTypeWord && !personLike` 再复用它去开磁力，
/// 而 `personLike` 来自启发式 `looksLikePersonName`（判据是
/// 「2~6 个汉字、无年份无标点」）—— 于是「功夫」「长江七号」
/// 「权力的游戏」全部被当成「像人名」，`titleLikeQuery` 变 false，
/// 磁力通道整片关闭，用户看到的就是「磁力资源模块不见了」。
///
/// 🔴 关键约束：这个函数的入参**只有三种确定的事实**
/// （类型词 / 豆瓣确认的人名 / 探测失败），**不接收任何「看起来像」**。
/// 启发式只能用于「要不要去问豆瓣」，绝不能用于决定通道开关。
class SearchChannelGate {
  const SearchChannelGate({
    required this.strictTitleFilter,
    required this.runMagnet,
  });

  /// 是否对源站结果做**严格片名相关性过滤**。
  ///
  /// 只有「确定是片名」时才过滤：类型词、确认人名、探测失败三种情况
  /// 都不能过滤 —— 尤其是探测失败，过滤会把源站已经命中的演员结果
  /// 全部杀掉（实测 `wd=周星驰` 在量子资源能出 20 部）。
  final bool strictTitleFilter;

  /// 是否发起磁力搜索。
  ///
  /// 磁力源只认片名 / IMDb tt-id：确认是人名或输入是类型词时跳过，
  /// 其余一律照搜（探测失败也要搜 —— 用户的输入很可能就是个片名）。
  final bool runMagnet;

  /// [isTypeWord]：输入命中站点分类/类型词（「科幻」「动漫」）。
  /// [isConfirmedPerson]：豆瓣明确认出这是人物。
  /// [personProbeFailed]：探测失败（网络/结构异常/熔断），事实未知。
  static SearchChannelGate resolve({
    required bool isTypeWord,
    required bool isConfirmedPerson,
    required bool personProbeFailed,
  }) {
    return SearchChannelGate(
      strictTitleFilter:
          !isTypeWord && !isConfirmedPerson && !personProbeFailed,
      runMagnet: !isTypeWord && !isConfirmedPerson,
    );
  }
}
