/// 磁力本地流会话识别 + 「危险 seek / 误报完成」防护。
///
/// 2026-11-08 真机（4078）定案：
/// - 磁力真正 open 的是 `TorrentPlayerService` 起的本地 HTTP 流，
///   `currentPlayUrl` 只在一开始是 `magnet-file://<idx>` 伪地址，后续若干路径
///   （选集、软重载、换线路）会把它覆写成 streamUrl。只看伪地址的判定会漏判，
///   于是 90s 看门狗走了「重新 open 旧 url」→ 误报 completed → lifecycle=ended
///   → 权威进度被设成片长 → 纠偏 seek 到片尾，播放彻底死掉。
/// - 起播后的**任何**续播 seek（哪怕只有 3s）都会打断本地流的顺序预取，
///   目标 piece 还没下下来，mpv 就一直等数据（4076 定格 3s、4078 定格 7s）。
library;

import '../../../utils/magnet_episode_parser.dart';

/// 本地回环流 URL（磁力 HTTP 流服务器）。
bool isLocalTorrentStreamUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final lower = url.toLowerCase();
  return lower.startsWith('http://127.0.0.1:') ||
      lower.startsWith('http://localhost:');
}

/// 当前播放会话是否属于磁力本地流。
///
/// 三重信号，任一命中即可：伪地址最可信；本地回环流 + 磁力会话标记用于
/// `currentPlayUrl` 已被覆写的场景；[hasMagnetSession] 单独不成立，避免
/// 同一页面从磁力切到在线源后误判（此时 activeStreamUrl 是远端地址）。
bool isMagnetStreamSession({
  required String? currentPlayUrl,
  required String? activeStreamUrl,
  required bool hasMagnetSession,
}) {
  if (currentPlayUrl != null &&
      MagnetEpisodeParser.isMagnetFileUrl(currentPlayUrl)) {
    return true;
  }
  if (activeStreamUrl != null &&
      MagnetEpisodeParser.isMagnetFileUrl(activeStreamUrl)) {
    return true;
  }
  return hasMagnetSession && isLocalTorrentStreamUrl(activeStreamUrl);
}

/// 恢复 seek 的目标是否合法：绝不能把「片长」当成续播点。
///
/// 4078 真机：流误报完成后权威进度被置成 7507s（= 片长），纠偏直接
/// `seekPrecise(7507s)` 跳到片尾，`pos=7507s buffered=7506s` 永久定格。
/// 片尾 10s 内一律拒绝纠偏；过小目标（<20s）由原有规则排除。
bool isValidRecoverySeekTarget({
  required Duration target,
  required Duration duration,
}) {
  if (target <= const Duration(seconds: 20)) return false;
  if (duration <= Duration.zero) return true;
  return target < duration - const Duration(seconds: 10);
}

/// 磁力流上是否跳过「起播续播 seek」。
///
/// 旧实现只暂缓 `>30s` 的远端续播，但 3s 的小续播同样会让 mpv 对本地
/// HTTP 流发起 Range 请求，打断顺序预取（4078 日志 `target=3s` 后定格）。
bool shouldSkipResumeSeek({
  required bool isMagnet,
  required Duration pending,
}) {
  return isMagnet && pending > Duration.zero;
}

/// 磁力流的「提前完成」是否应忽略。
///
/// 本地流等待 piece 时 mpv 会误报 completed（4078：pos≈7s / dur=7507s）。
/// 一旦进 `_finishPlayback()`，lifecycle=ended、心跳被吞、权威进度=片长，
/// 后续所有恢复动作都会把片长当目标。这类误报只保留 buffering 等供数。
bool shouldIgnoreMagnetPrematureComplete({
  required bool isMagnet,
  required Duration position,
  required Duration duration,
}) {
  if (!isMagnet) return false;
  if (duration <= Duration.zero) return false;
  return position < duration - const Duration(seconds: 60);
}
