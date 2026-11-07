// 字幕与画面时轴的策略层（S4），全部为纯函数，可单测。
//
// 设计红线：**绝不自动乱调时间轴**。只有拿到明确证据（字幕文件名/标题里
// 写明基准帧率、字幕 cue 跨度与片长明显不符）才给出结论，其余一律
// `uncertain` / 返回 null，由调用方静默跳过。
//
// 事实约束：当前 mpv 链路能读到 `container-fps`、`estimated-vf-fps`、
// `duration`，但**读不到「首个音轨活动 / 场景切换」时间戳**。所以匹配判定
// 用「字幕 cue 跨度 vs 片长」与「首 cue 偏移」这两个可实测信号；音轨活动
// 只作为可选入参保留，未传入时不参与判定。

/// 归一化后的常见视频帧率。
enum VideoFrameRate {
  fps23976,
  fps24,
  fps25,
  fps2997,
  fps30,
  fps50,
  fps5994,
  fps60,
  unknown,
}

extension VideoFrameRateX on VideoFrameRate {
  /// 精确标称值，用分数表达 1000/1001 系列，避免 23.976 这类近似值累积误差。
  double get fps {
    switch (this) {
      case VideoFrameRate.fps23976:
        return 24000 / 1001;
      case VideoFrameRate.fps24:
        return 24;
      case VideoFrameRate.fps25:
        return 25;
      case VideoFrameRate.fps2997:
        return 30000 / 1001;
      case VideoFrameRate.fps30:
        return 30;
      case VideoFrameRate.fps50:
        return 50;
      case VideoFrameRate.fps5994:
        return 60000 / 1001;
      case VideoFrameRate.fps60:
        return 60;
      case VideoFrameRate.unknown:
        return 0;
    }
  }

  String get label {
    switch (this) {
      case VideoFrameRate.fps23976:
        return '23.976';
      case VideoFrameRate.fps24:
        return '24';
      case VideoFrameRate.fps25:
        return '25';
      case VideoFrameRate.fps2997:
        return '29.97';
      case VideoFrameRate.fps30:
        return '30';
      case VideoFrameRate.fps50:
        return '50';
      case VideoFrameRate.fps5994:
        return '59.94';
      case VideoFrameRate.fps60:
        return '60';
      case VideoFrameRate.unknown:
        return '未知';
    }
  }
}

/// 把 mpv 属性字符串归一到标称帧率。
///
/// 容差必须小于 0.024，否则 23.976 会被误判成 24、29.97 被误判成 30，
/// 这正是 PAL/NTSC 漂移纠偏最容易出错的地方。取 0.012 可同时容纳
/// mpv 返回的 `23.976023`、`29.970030` 等高精度值。
VideoFrameRate normalizeFrameRate(String? raw) {
  if (raw == null) return VideoFrameRate.unknown;
  final v = double.tryParse(raw.trim());
  if (v == null || v <= 0 || v > 240) return VideoFrameRate.unknown;
  const tolerance = 0.012;
  for (final rate in VideoFrameRate.values) {
    if (rate == VideoFrameRate.unknown) continue;
    if ((v - rate.fps).abs() <= tolerance) return rate;
  }
  return VideoFrameRate.unknown;
}

/// `container-fps`（容器帧率）优先，`estimated-vf-fps`（送显帧率）兜底。
/// 两者都拿不到时返回 unknown，调用方不得据此调整时间轴。
VideoFrameRate resolvePlaybackFrameRate({
  String? containerFps,
  String? estimatedVfFps,
}) {
  final container = normalizeFrameRate(containerFps);
  if (container != VideoFrameRate.unknown) return container;
  return normalizeFrameRate(estimatedVfFps);
}

/// 从字幕文件名 / release 名里识别**明确写出**的基准帧率。
///
/// 只认带单位的标记（`25fps` / `PAL` / `23.976` / `24000/1001`），不认孤立数字
/// —— 否则 `S01E25.srt`、`1080p.x264.srt` 会被误读成 25fps，进而把整条
/// 时间轴改坏。识别不到返回 null，调用方不设 `sub-speed`。
VideoFrameRate? detectSubtitleBaseFrameRate(String? nameOrTitle) {
  if (nameOrTitle == null || nameOrTitle.isEmpty) return null;
  final t = nameOrTitle.toLowerCase();
  // 23.976 / NTSC 系列先判，避免与 "24" 之类的宽松标记混淆。
  if (t.contains('23.976') ||
      t.contains('23,976') ||
      t.contains('23976') ||
      t.contains('24000/1001') ||
      t.contains('ntsc')) {
    return VideoFrameRate.fps23976;
  }
  if (t.contains('25fps') ||
      t.contains('25.000') ||
      t.contains('25p') ||
      t.contains('pal')) {
    return VideoFrameRate.fps25;
  }
  if (t.contains('24fps') || t.contains('24.000')) {
    return VideoFrameRate.fps24;
  }
  return null;
}

/// 计算 mpv `sub-speed`（字幕时间轴速度倍率 = 视频帧率 / 字幕基准帧率）。
///
/// **只对 25 ↔ 23.976/24 这一对 PAL/NTSC 转换动手**，因为只有这个组合有
/// 确定的 1.0417 倍漂移物理含义。其它组合（含 unknown、同帧率）一律返回
/// null 或 1.0，绝不凭猜测改写整条时间轴。
double? computeSubSpeed({
  required VideoFrameRate video,
  VideoFrameRate? subtitleBase,
}) {
  if (video == VideoFrameRate.unknown) return null;
  if (subtitleBase == null || subtitleBase == VideoFrameRate.unknown) return null;
  if (video == subtitleBase) return 1.0;
  const pal = {VideoFrameRate.fps25};
  const film = {VideoFrameRate.fps23976, VideoFrameRate.fps24};
  final isPalFilmPair =
      (pal.contains(video) && film.contains(subtitleBase)) ||
      (film.contains(video) && pal.contains(subtitleBase));
  if (!isPalFilmPair) return null;
  final speed = video.fps / subtitleBase.fps;
  return double.parse(speed.toStringAsFixed(5));
}

/// 字幕文本里解析出的 cue 覆盖范围（秒）。
class SubtitleCueRange {
  const SubtitleCueRange({
    required this.firstCueSeconds,
    required this.lastCueSeconds,
    required this.cueCount,
  });

  final double? firstCueSeconds;
  final double? lastCueSeconds;
  final int cueCount;

  bool get isValid =>
      cueCount >= 2 &&
      firstCueSeconds != null &&
      lastCueSeconds != null &&
      lastCueSeconds! > firstCueSeconds!;

  double get spanSeconds =>
      isValid ? lastCueSeconds! - firstCueSeconds! : 0.0;

  static const empty = SubtitleCueRange(
    firstCueSeconds: null,
    lastCueSeconds: null,
    cueCount: 0,
  );
}

final RegExp _timeToken = RegExp(r'(\d{1,3}):(\d{2}):(\d{2})[,.](\d{1,3})');

double _timeTokenToSeconds(RegExpMatch m) {
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  final sec = int.parse(m.group(3)!);
  final fracRaw = m.group(4)!;
  final frac = int.parse(fracRaw) / _pow10(fracRaw.length);
  return h * 3600 + min * 60 + sec + frac;
}

double _pow10(int n) {
  var v = 1.0;
  for (var i = 0; i < n; i++) {
    v *= 10;
  }
  return v;
}

/// 解析 SRT / VTT（`-->`）与 ASS（`Dialogue:`）的首末 cue 时间。
///
/// 只取时间轴，不做编码探测、不改动文本。ASS 的 `0:00:02.50` 与 SRT 的
/// `00:00:02,500` 共用同一个时间 token 正则。
SubtitleCueRange parseSubtitleCueRange(String text) {
  if (text.isEmpty) return SubtitleCueRange.empty;
  double? first;
  double? last;
  var count = 0;
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    final isArrow = line.contains('-->');
    final isAss = line.toLowerCase().startsWith('dialogue:');
    if (!isArrow && !isAss) continue;
    final matches = _timeToken.allMatches(line).toList();
    if (matches.length < 2) continue;
    final start = _timeTokenToSeconds(matches[0]);
    final end = _timeTokenToSeconds(matches[1]);
    if (end <= start) continue;
    count++;
    if (first == null || start < first) first = start;
    if (last == null || end > last) last = end;
  }
  if (count == 0) return SubtitleCueRange.empty;
  return SubtitleCueRange(
    firstCueSeconds: first,
    lastCueSeconds: last,
    cueCount: count,
  );
}

/// 字幕与画面的匹配结论。
enum SubtitleMatchVerdict {
  /// 有足够证据认为匹配。
  matched,

  /// 证据不足（片长未知 / cue 太少 / 无音轨活动数据），不提示、不调整。
  uncertain,

  /// 有明确证据认为不是同一版本，只提示用户换字幕，绝不自动改时间轴。
  mismatched,
}

/// 字幕与画面可能不匹配时给用户的提示（只在 mismatched 时展示）。
const String subtitleMismatchHint = '字幕与画面可能不匹配，建议换一个字幕';

/// 用「cue 跨度 vs 片长」「首 cue 偏移」判定字幕是否可能是另一个版本。
///
/// 阈值取向：宁可 `uncertain` 放过，也不误报打扰用户。片长未知、cue 少于
/// 2 条、时间轴反向都返回 uncertain。
SubtitleMatchVerdict judgeSubtitleMatch({
  required SubtitleCueRange range,
  required double videoDurationSeconds,
  double? firstAudioActivitySeconds,
}) {
  if (!range.isValid) return SubtitleMatchVerdict.uncertain;
  if (videoDurationSeconds <= 0) return SubtitleMatchVerdict.uncertain;
  final first = range.firstCueSeconds!;

  // 首条字幕晚于片长 1/4：几乎不可能是同一剪辑。
  if (first > videoDurationSeconds * 0.25) {
    return SubtitleMatchVerdict.mismatched;
  }
  // 字幕覆盖的时长与片长差太多：多半是别的版本 / 缺半部。
  final ratio = range.spanSeconds / videoDurationSeconds;
  if (ratio < 0.7 || ratio > 1.35) {
    return SubtitleMatchVerdict.mismatched;
  }
  // 可选信号：拿到真实音轨活动起点时，与首 cue 相差过大也判不匹配。
  if (firstAudioActivitySeconds != null &&
      firstAudioActivitySeconds >= 0 &&
      (first - firstAudioActivitySeconds).abs() > 8.0) {
    return SubtitleMatchVerdict.mismatched;
  }
  return SubtitleMatchVerdict.matched;
}
