/// mpv position 上报的处理结果。
enum PlayheadTickAction {
  /// 正常前进，UI 跟随 mpv。
  accept,

  /// 可疑回跳（HLS discontinuity / 广告），UI 保持权威进度，需纠正 mpv。
  discontinuity,

  /// 小幅回跳或抖动，忽略 mpv 报告。
  ignoreBackward,
}

/// **播放进度唯一权威**。
///
/// 设计约束：
/// - 业务层（历史、换线、DLNA、UI）只读 [authoritative]。
/// - mpv `position` 仅为遥测，不可直接当作真相。
/// - 只有 [setExplicit]（用户 seek / 续播 / 换线保留）可主动改写进度。
class PlayheadAuthority {
  Duration _authoritative = Duration.zero;
  Duration _lastPlayerReport = Duration.zero;

  /// 上一次 ingest 的墙钟时间（算「这段时间里最多能正常推进多久」用）。
  DateTime? _lastReportAt;

  /// 单次上报里「按真实时间可解释」的最大倍速。
  ///
  /// App 支持 2x 播放，再留一倍余量给「后台挂起后一次性补报」「卡顿后批量上报」。
  static const double _maxPlausibleRate = 4.0;

  /// 除了按时间可解释的推进量之外，还容忍的额外前跳（关键帧/上报间隔抖动）。
  static const Duration kForwardJumpSlack = Duration(seconds: 20);

  /// 当前应展示的播放位置（进度条、落盘、换线保留均使用此值）。
  Duration get authoritative => _authoritative;

  Duration get lastPlayerReport => _lastPlayerReport;

  /// 显式设定进度（用户拖动、续播 startAt、换线 preserve）。
  void setExplicit(Duration position, {Duration? durationCap}) {
    _authoritative = _clamp(position, durationCap);
    _lastPlayerReport = _authoritative;
    // 以「显式设定」为新基准：紧接着的位置上报从此刻重新计时。
    _lastReportAt = DateTime.now();
  }

  void reset() {
    _authoritative = Duration.zero;
    _lastPlayerReport = Duration.zero;
    _lastReportAt = null;
  }

  /// ingest mpv 上报；返回应执行的动作。
  ///
  /// **前后判据对称**：回退超过 20s 视为 discontinuity（广告/HLS 重建/流重连），
  /// 前跳同样要能被「真实经过的时间 × 合理倍速」解释，否则也是 discontinuity。
  ///
  /// 2026-11-05 之前的实现是「向前 >800ms 无条件接受」，于是任何一次 PTS 前跳
  /// （广告段绝对时间戳、HLS 重建）都会把进度条和续播记录一起弹走，而且再也
  /// 回不来——这也是「跳剧情」体感的一半来源。现在前跳必须过时间校验：
  /// 正常播放（哪怕 2x）与后台挂起后的补报都能通过，凭空 +N 分钟过不了。
  ///
  /// [now] 仅供测试注入墙钟；生产调用不要传。
  PlayheadTickAction ingest(
    Duration reported, {
    Duration? duration,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    _lastPlayerReport = reported;

    if (_isSuspiciousForward(reported, at) ||
        _isSuspiciousBackward(reported)) {
      _lastReportAt = at;
      return PlayheadTickAction.discontinuity;
    }
    _lastReportAt = at;

    if (reported > _authoritative + const Duration(milliseconds: 800)) {
      _authoritative = _clamp(reported, duration);
      return PlayheadTickAction.accept;
    }
    if (reported > _authoritative) {
      _authoritative = _clamp(reported, duration);
    }
    return PlayheadTickAction.ignoreBackward;
  }

  /// 前跳是否无法用「真实经过时间」解释。
  ///
  /// 关键：不能用固定阈值。App 切后台继续播的时候，位置上报可能整段停摆，
  /// 回前台第一条上报本来就会前跳几分钟——那是真进度，固定阈值会把它当
  /// discontinuity 再 seek 回去，等于倒带重播。所以按墙钟放宽：
  /// 允许 = 实际经过时间 × [_maxPlausibleRate] + [kForwardJumpSlack]。
  bool _isSuspiciousForward(Duration reported, DateTime now) {
    final forward = reported - _authoritative;
    if (forward <= Duration.zero) return false;
    final last = _lastReportAt;
    if (last == null) {
      // 没有基准（刚 reset / 首次上报）时只允许一个抖动余量。
      return forward > kForwardJumpSlack;
    }
    var elapsedMs = now.difference(last).inMilliseconds;
    if (elapsedMs < 0) elapsedMs = 0;
    // 防御：墙钟被改（用户调时间）时别算出一个天文数字的允许量。
    if (elapsedMs > const Duration(hours: 12).inMilliseconds) {
      elapsedMs = const Duration(hours: 12).inMilliseconds;
    }
    final allowed = Duration(
      milliseconds: (elapsedMs * _maxPlausibleRate).round(),
    ) +
        kForwardJumpSlack;
    return forward > allowed;
  }

  /// 换线 / 重试 open 时应 seek 到的位置；接近片尾返回 null。
  Duration? preserveForMediaSwitch({Duration? duration}) {
    final pos = _authoritative;
    if (pos <= const Duration(seconds: 2)) return null;
    if (duration != null &&
        duration > Duration.zero &&
        pos >= duration - const Duration(seconds: 5)) {
      return null;
    }
    return pos;
  }

  /// HLS 误报 duration 导致 premature completed。
  bool isPrematureComplete(Duration duration) {
    if (duration <= Duration.zero) return false;
    if (_authoritative <= const Duration(seconds: 30)) return false;
    return _authoritative < duration - const Duration(seconds: 45);
  }

  bool _isSuspiciousBackward(Duration reported) {
    if (_authoritative <= const Duration(seconds: 20)) return false;
    // 注意：不要用「reported 接近 0 就豁免」来避免误判 —— 那样会漏掉真实的
    // 流重连（看了很久后 mpv 位置归零），反而导致续播/播放卡死。
    // 主动 seek / 续播的正确豁免靠两条：① seek 一律走 DetailPlaybackCoordinator
    // 并 confirmExplicitPosition；② lifecycle == seeking 期间忽略 position 报告。
    return _authoritative - reported > const Duration(seconds: 20);
  }

  static Duration _clamp(Duration value, Duration? cap) {
    if (cap == null || cap <= Duration.zero) return value;
    if (value >= cap) return cap;
    return value;
  }
}
