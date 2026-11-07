/// demuxer 缓冲挡位。
///
/// 背景：`demuxer-max-bytes` / `demuxer-readahead-bytes` 之前三档策略全部写死
/// 512MB。512MB 不是「缓存越多越好」——它同时把 mpv 的 demuxer 队列顶到很高，
/// 后台/暂停时仍按 3.5 倍速预读，实测 TOTAL PSS 冲到 1.39GB 被 lmkd 杀进程。
///
/// 这里按设备物理内存给一个折中值：小内存机 128MB（保命），大内存机最多
/// 512MB（够拖），用户也可手动钉死某一档。
class BufferTier {
  BufferTier._();

  static const int _mb = 1024 * 1024;

  /// 自动挡位的 key（持久化值）
  static const String autoKey = 'auto';

  /// 允许的手动挡位（MB），升序
  static const List<int> manualMegabytes = [128, 192, 256, 384, 512];

  /// 所有可选 key（含 auto）
  static List<String> get allKeys =>
      [autoKey, ...manualMegabytes.map((e) => '$e')];

  static const int minBytes = 128 * _mb;
  static const int maxBytes = 512 * _mb;

  /// 探测不到物理内存时的保守默认值（中低端机常见档）。
  static const int fallbackBytes = 192 * _mb;

  /// 自动挡的动态评估周期（仅在播放中计时）。
  ///
  /// 10 分钟：既能把「可用内存被别的 App 吃掉」这种情况及时反映出来，
  /// 又不会频繁改 mpv 参数（每次改都会让 demuxer 队列重排）。
  static const Duration autoTuneInterval = Duration(minutes: 10);

  /// demuxer 缓存最多占用「系统当前可用内存」的 1/4。
  ///
  /// mpv 的 demuxer 队列在原生堆里，和硬解缓冲、Flutter 引擎抢同一块内存。
  /// 拿 1/4 是留出足够余量给解码器与系统，避免「缓存攒满 → lmkd 杀掉整机」。
  static const int availableShareDivisor = 4;

  /// 按物理内存推算自动挡位。
  ///
  /// 阈值参考 Android 主流机型的分档（Go 版/入门 3GB、中端 6~8GB、旗舰 12GB+）。
  /// 留 1.5GB 左右给解码器、Flutter 引擎和系统，不让缓存把整机吃干。
  static int autoBytesFor(int totalMemoryBytes) {
    if (totalMemoryBytes <= 0) return fallbackBytes;
    final double gb = totalMemoryBytes / (1024 * 1024 * 1024);
    if (gb <= 3.5) return 128 * _mb;
    if (gb <= 4.5) return 192 * _mb;
    if (gb <= 6.5) return 256 * _mb;
    if (gb <= 8.5) return 384 * _mb;
    return 512 * _mb;
  }

  /// 把持久化的挡位 key 解成实际字节数。
  ///
  /// 非法/缺失的 key 一律按自动处理，并夹到 [minBytes]~[maxBytes]，
  /// 防止手工改配置把缓冲设成 0（等于退回 mpv 默认的几秒浅窗口）。
  static int resolveBytes(
      {required String tier, required int totalMemoryBytes}) {
    if (tier == autoKey) return autoBytesFor(totalMemoryBytes);
    final mb = int.tryParse(tier);
    if (mb == null) return autoBytesFor(totalMemoryBytes);
    final bytes = mb * _mb;
    if (bytes < minBytes) return minBytes;
    if (bytes > maxBytes) return maxBytes;
    return bytes;
  }

  /// 自动挡的**动态**目标：按「当前系统可用内存」在 [manualMegabytes] 阶梯上
  /// 升降档，天花板仍是按物理内存算出的 [autoBytesFor]。
  ///
  /// 规则（纯函数，可单测）：
  /// - 预算 = 可用内存 / [availableShareDivisor]，目标档 = 不超过预算的最大档；
  /// - 预算 ≤ 128MB → 128MB（下限，不能再低）；
  /// - **升档要留 25% 余量**（预算 ≥ 目标档 × 1.25），避免在阈值附近反复升降；
  /// - **降档也要迟滞**（预算 < 当前档 × 0.8 才降），否则 320MB 预算会让
  ///   256↔192 每 10 分钟来回跳一次；
  /// - 可用内存探测失败（≤0）→ 不动，直接返回当前值。
  ///
  /// [currentBytes] 传入当前实际生效的字节数（首次评估时传天花板即可）。
  static int adaptiveBytesFor({
    required int totalMemoryBytes,
    required int availableMemoryBytes,
    required int currentBytes,
  }) {
    final ceilingBytes = autoBytesFor(totalMemoryBytes);
    final ceilingMb = ceilingBytes ~/ _mb;

    // 探测失败不能当作「内存极低」，否则一次通道异常就把缓冲砍到 128MB。
    if (availableMemoryBytes <= 0) return currentBytes;

    final currentMb =
        (currentBytes ~/ _mb).clamp(minBytes ~/ _mb, ceilingMb);
    final budgetMb =
        (availableMemoryBytes ~/ _mb) ~/ availableShareDivisor;

    // 阶梯里不超过物理内存天花板的档位
    final ladder = manualMegabytes.where((mb) => mb <= ceilingMb).toList();
    if (ladder.isEmpty) return ceilingBytes;

    var desiredMb = ladder.first;
    for (final mb in ladder) {
      if (mb <= budgetMb) desiredMb = mb;
    }

    if (desiredMb > currentMb) {
      // 升档：预算要比目标档多出 25%，防止在档位边界上抖
      if (budgetMb * 4 >= desiredMb * 5) return desiredMb * _mb;
      return currentMb * _mb;
    }
    if (desiredMb < currentMb) {
      // 降档：预算跌破当前档的 80% 才降，给突发的短暂波动留缓冲
      if (budgetMb * 5 < currentMb * 4) return desiredMb * _mb;
      return currentMb * _mb;
    }
    return currentMb * _mb;
  }

  /// 设置页显示用文案。
  ///
  /// [autoBytes] 传自动挡**当前**实际生效值（会随可用内存动态变），
  /// 不传则按物理内存推算的固定值。
  static String labelOf(String tier, {int? autoBytes}) {
    if (tier != autoKey) {
      final mb = int.tryParse(tier);
      return mb == null ? '自动' : '$mb MB';
    }
    if (autoBytes == null || autoBytes <= 0) return '自动';
    return '自动（${autoBytes ~/ _mb} MB）';
  }

  /// 设置页副标题：自动档要说明「按本机内存推出来是多少 / 现在可用多少」。
  static String describe({
    required String tier,
    required int totalMemoryBytes,
    int availableMemoryBytes = 0,
    int? autoBytes,
  }) {
    if (tier != autoKey) {
      final bytes = resolveBytes(
        tier: tier,
        totalMemoryBytes: totalMemoryBytes,
      );
      return '固定占用约 ${bytes ~/ _mb} MB 缓存空间';
    }

    final bytes = (autoBytes != null && autoBytes > 0)
        ? autoBytes
        : resolveBytes(tier: tier, totalMemoryBytes: totalMemoryBytes);
    final resolvedMb = bytes ~/ _mb;

    if (totalMemoryBytes <= 0) {
      // 桌面 / Web 的内存探测恒为 0（Android 上也可能暂时探测失败）。
      // 此时自动挡并不是「自动」：autoBytesFor 会退回 fallbackBytes，
      // 播放中也不会动态升降，所以 UI 不能把它标成自动挡。
      return '未探测到本机内存：固定 $resolvedMb MB，播放中不会动态调档';
    }
    final gb = (totalMemoryBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
    final buffer = StringBuffer('本机 ${gb}GB 内存 → $resolvedMb MB');
    if (availableMemoryBytes > 0) {
      final availGb =
          (availableMemoryBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
      buffer.write('，当前可用 ${availGb}GB');
    }
    return buffer.toString();
  }
}

