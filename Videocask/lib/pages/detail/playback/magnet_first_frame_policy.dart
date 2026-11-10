/// 交接后等待首帧的结局。
///
/// 2026-10-28 真机实测把「0:00 黑屏」拆成了两种完全不同的成因，必须分开说，
/// 否则会像第一版那样一律写成「编码不支持」：
/// * [noData]：节点连上了但一个字节都不下发（日志 `peers=2 speed=0 buffer=6%`
///   卡住不动）——这是种子/网络问题，换资源或换时间；
/// * [unsupported]：数据一直在动，但 mpv 始终解析不出时长/画面——这才是
///   封装（moov 在尾部的非 faststart mp4）或编码不被支持。
enum MagnetFirstFrameOutcome {
  /// 已出画（位置推进或时长出现）。
  arrived,

  /// 本次播放已被取代 / 页面销毁：不要写任何状态。
  cancelled,

  /// 节点连上了，但等待期内几乎没有数据下发。
  noData,

  /// 数据在动，但播放器始终读不出画面。
  unsupported,
}

/// 磁力起播「首帧看门狗」的判定规则（纯函数，可单测）。
///
/// 背景（2026-10-28 真机反馈）：「磁力资源这个没有时长的黑屏，一直黑屏，
/// 换一个资源能播放」——截图里播放器是 `0:00 / 0:00`，既没解析出时长，
/// 也没有任何画面，而且会**一直黑下去**。
///
/// 根因是「缓冲 > 0」被当成了起播成功的判据：流确实有数据，mpv 也 open
/// 了地址，但容器头没解析出来（mp4 的 moov 在文件尾部、需要额外一段
/// 远距离 range 请求），或者首帧解码迟迟不完成。这种情况下 mpv 不报错、
/// 我们能看到的只有「一直黑」。所以必须由我们自己在交接后盯一段时间，
/// 拿不到时长/推进就当作这一次失败，交给外层自动重试。
abstract final class MagnetFirstFramePolicy {
  /// 轮询间隔：比 position 更新频率略慢，避免空转。
  static const Duration pollInterval = Duration(milliseconds: 400);

  /// 播放位置推进多少才算「真的出画」。
  ///
  /// 用位置推进而不是「有画面」的原因：media_kit 在 Android 上没有稳的
  /// first-frame 事件，而位置只有在解复用 + 解码都正常时才会走。
  static const Duration advanceThreshold = Duration(milliseconds: 400);

  /// 到了这个时间开始判「是不是卡死」：数据还在流就继续等，彻底不动就放弃。
  ///
  /// 真机实测该种子（长津湖 HDRip HEVC）从交接（buffer 12%）到出画面
  /// 只用了 1~2s，正常资源都远低于这个窗口。
  static const Duration stallTimeout = Duration(seconds: 25);

  /// 判「卡死」需要在 [stallTimeout] 之后再连续多久没有任何数据流动。
  static const Duration stallWindow = Duration(seconds: 8);

  /// 硬上限：即使一直有数据在流，等这么久也没画面就重开一轮。
  ///
  /// 有些种子的尾部 piece 长期没有 peer 提供（moov 拿不到），表现是「速度
  /// 一直有、缓冲一直涨、画面永远没有」。这种情况继续等也等不出来，重试
  /// （重新打洞、重新申请头尾片）比干等更有希望，所以给一个绝对的终点。
  static const Duration hardTimeout = Duration(seconds: 40);

  /// 同一个资源连续「交接后读不出画面」几次就放弃自动重试。
  ///
  /// 连不上节点是**可恢复**的（重试无限次合理）；读不出画面多半是封装
  /// （moov 在尾部的非 faststart mp4）或编码不被这台设备支持，重试一百
  /// 次也一样。给 1 次重试机会，第二次就明说「建议换资源」。
  static const int maxNoFrameStrikes = 2;

  /// 交接给播放器前至少要预缓冲到这个比例（相对流首部窗口）。
  ///
  /// 真机 2026-11-08：buffer=6% 就交接，实际只下到 117KB，HEVC-10bit
  /// 只够播 3s；之后 `pos=3s buffered=3s estimated-vf-fps=` 永久定格。
  /// 低于此比例直接判本次起流失败，交给上层自动重试（重新打洞 / 重新申请
  /// 头尾 piece），而不是把「假播放」丢给用户。
  static const int minHandoverBufferPct = 12;

  /// 交接是否过薄：只看字节比例，不看「有数据」这个布尔。
  static bool handoverTooThin({required int bufferPct}) {
    return bufferPct < minHandoverBufferPct;
  }

  /// 交接后是否已经确认出画。
  ///
  /// * [beforePosition] / [beforeDuration]：交出流之前的位置与时长
  ///   （上一部片可能还残留着非零时长，直接判 `duration > 0` 会误判成功）；
  /// * 位置推进过阈值是唯一硬证据；
  /// * 时长就绪**不算**出画：mpv 只要读到了容器头就会把 duration 填好
  ///   （真机 `dur=7507s` 但 `estimated-vf-fps=` 空 = 一帧都没解出来）。
  ///   旧实现把它当成功，于是「缓冲 3s、位置钉死、零解码」的空流被判
  ///   `arrived`，首帧看门狗放行、UI 进入 playing，随后永久卡死。
  ///   现在只有时长就绪**且**确实在出帧才提前放行，避免误杀慢种子。
  static bool frameArrived({
    required Duration beforePosition,
    required Duration beforeDuration,
    required Duration position,
    required Duration duration,
    bool decodingFrames = false,
  }) {
    if (position - beforePosition >= advanceThreshold) return true;
    final durationReady = duration > Duration.zero && duration != beforeDuration;
    return durationReady && decodingFrames;
  }

  /// 放弃等待的原因，顺带就是「卡在哪」的归因；不需要放弃时返回 null。
  ///
  /// [elapsed]：交接后已经等了多久；
  /// [stalledFor]：距离最后一次「有数据在动」过了多久。
  ///
  /// 为什么用「放弃原因」而不是另算一个「见没见过数据流动」来判断归因：
  /// 2026-10-28 真机实测（长津湖 HDRip，`peers=2 buffer=6% speed=0`）证明，
  /// 只要出现过**一个字节**的速度，`sawDataFlow` 就会永久变 true，于是
  /// 「节点根本不给数据」被错报成「编码不支持」。而放弃原因本身已经区分得
  /// 很清楚：卡满 [stallWindow] 没数据 → 节点不给数据；一直有数据流到
  /// [hardTimeout] → 解不出画面。
  static MagnetFirstFrameOutcome? giveUpReason({
    required Duration elapsed,
    required Duration stalledFor,
  }) {
    // 数据一直在流却始终出不了画：封装/编码层面解不开。
    if (elapsed >= hardTimeout) return MagnetFirstFrameOutcome.unsupported;
    // 到了判定时间点，并且已经连续一段时间完全没数据。
    if (elapsed >= stallTimeout && stalledFor >= stallWindow) {
      return MagnetFirstFrameOutcome.noData;
    }
    return null;
  }

  /// mpv 主动报错时的归因：刚连上就报错多半是读不到数据，
  /// 已经流了一段时间才报错才更像「解码/封装不支持」。
  static MagnetFirstFrameOutcome classifyStall({
    required Duration stalledFor,
  }) {
    return stalledFor >= stallWindow
        ? MagnetFirstFrameOutcome.noData
        : MagnetFirstFrameOutcome.unsupported;
  }
}
