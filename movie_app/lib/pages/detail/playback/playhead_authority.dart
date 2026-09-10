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

  /// 当前应展示的播放位置（进度条、落盘、换线保留均使用此值）。
  Duration get authoritative => _authoritative;

  Duration get lastPlayerReport => _lastPlayerReport;

  /// 显式设定进度（用户拖动、续播 startAt、换线 preserve）。
  void setExplicit(Duration position, {Duration? durationCap}) {
    _authoritative = _clamp(position, durationCap);
    _lastPlayerReport = _authoritative;
  }

  void reset() {
    _authoritative = Duration.zero;
    _lastPlayerReport = Duration.zero;
  }

  ///  ingest mpv 上报；返回应执行的动作。
  PlayheadTickAction ingest(Duration reported, {Duration? duration}) {
    _lastPlayerReport = reported;
    if (_isSuspiciousBackward(reported)) {
      return PlayheadTickAction.discontinuity;
    }
    if (reported > _authoritative + const Duration(milliseconds: 800)) {
      _authoritative = _clamp(reported, duration);
      return PlayheadTickAction.accept;
    }
    if (reported > _authoritative) {
      _authoritative = _clamp(reported, duration);
    }
    return PlayheadTickAction.ignoreBackward;
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
    if (reported > const Duration(seconds: 15)) return false;
    return _authoritative - reported > const Duration(seconds: 20);
  }

  static Duration _clamp(Duration value, Duration? cap) {
    if (cap == null || cap <= Duration.zero) return value;
    if (value >= cap) return cap;
    return value;
  }
}
