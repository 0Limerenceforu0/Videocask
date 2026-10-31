/// 磁力链接播放状态
enum TorrentPlayState {
  idle,
  fetchingMeta,
  ready,
  buffering,
  playing,
  error,
}

/// 做种/节点数的人类可读值：-1（libtorrent 的「未知」哨兵）→ 「未知」。
///
/// libtorrent 2.x 的 `torrent_status::num_peers/num_seeds` 在 status 查询
/// 未带 peer 统计位时返回 -1（含义「未知」，不是 0）。2026-10-24 真机实测
/// 整个磁力加载期都是 -1，直接把 -1 显示成「做种 -1」或灌进判定条件
/// （`_seeds == 0` 永假 → 死种早停失效）都会误导用户，统一在此归一。
///
/// 作为顶层函数放在此文件（被 IO / Web 双实现与测试共同引用），避免
/// 各平台实现各写一份导致web 目标 analyze 报 undefined。
String formatSwarmCount(int v) => v < 0 ? '未知' : '$v';

final RegExp _cjkRe = RegExp(r'[\u4e00-\u9fff]');

/// 磁力结果与显示标题的**相关性**判定（2026-10-24 提取为纯函数，便于测试）。
///
/// 🔴 关键修正：**中文标题 + 英文发布名无法判定相关性** —— 既不互相包含，
/// 分词也永远命中不了（"教父" vs "the.godfather.1972…" 的 matchCount 恒为 0）。
/// 旧实现据此把**每一个**结果都判为不相关 → 磁力搜索返回空列表 →
/// 用户看到的正是「磁力资源模块直接没了」。
///
/// 现在：拿不到可比的英文基准（标题是中文、结果名是英文）时**不做过滤**——
/// 源站本身已按标题检索过，兜底不该把结果全杀掉。真正精确的过滤依赖
/// 豆瓣 / IMDb / CMS 别名解析出的英文名（见 `VideoTitleResolveService`）。
bool isTorrentResultRelevant(String resultName, String displayTitle) {
  final name = resultName.toLowerCase();
  final title = displayTitle.toLowerCase();
  if (title.isEmpty) return true;

  // 中文标题 + 英文结果名 → 无法判定，放行。
  if (_cjkRe.hasMatch(title) && !_cjkRe.hasMatch(name)) return true;

  if (name.contains(title)) return true;
  if (title.contains(name)) return true;

  final titleTokens = title.split(RegExp(r'[\s\-_.·《》\[\]（）(),]+'));
  final resultTokens = name.split(RegExp(r'[\s\-_.·《》\[\]（）(),]+'));
  var matchCount = 0;
  for (final token in titleTokens) {
    if (token.length >= 2 &&
        resultTokens.any(
          (rt) => rt.contains(token) || token.contains(rt),
        )) {
      matchCount++;
    }
  }
  return matchCount >= titleTokens.length / 2;
}

/// 搜索页**是否要展示「磁力资源」模块**（2026-10-24 提取为纯函数）。
///
/// 🔴 旧条件只看「有结果 / 还在搜」，于是磁力搜索一旦返回空列表或超时，
/// 模块连同它内部的提示一起被隐藏 → 用户看到「磁力资源模块直接没了」。
/// 现在：只要本轮磁力**报过错**（超时/失败/为空）也要展示，
/// 让「没有找到磁力资源 / 磁力搜索超时」这条提示有出口。
bool shouldShowMagnetSection({
  required int resultCount,
  required bool isSearching,
  required bool hasError,
}) =>
    resultCount > 0 || isSearching || hasError;

/// 重建磁力 URI：**[preferredTrackers] 排在最前，站点自带 tracker 挪到最后**。
///
/// ## 为什么不能简单 append（2026-10-24 真机实证）
///
/// libtorrent 对 tracker 是**逐条 announce** 的，死链每条要烧约 10s 超时。
/// 旧实现把精选列表 append 在站点自带 tracker 之后，而搜索站返回的磁力几乎
/// 都自带 1~3 条（多为已下线）——于是死链占住了最前面的 announce 名额，
/// 真能返回 peer 的精选 tracker 被堵到 40s 之后才轮到（run3 日志：11:30:18
/// 添加磁力 → 11:30:30 / 11:30:39 / 11:30:49 连续三条超时 → 11:30:59 才
/// 收到 peers，而 DHT 早在 11:30:47 就先把 peer 找来了）。
///
/// 因此这里重建而不是拼接：
/// 1. `xt` / `dn` 等非 tr 参数**原样、原序**保留（不改编码，避免拼出坏磁力）；
/// 2. 精选 tracker 去重后依次写入；
/// 3. 站点自带 tracker 仍保留（不丢可能存活的源），但排到队尾。
///
/// 无法解析（非 `magnet:?` 前缀 / 没有 xt）时原样返回，绝不冒险拼非法 URI。
String buildEnhancedMagnet(
  String magnetUri,
  List<String> preferredTrackers,
) {
  const prefix = 'magnet:?';
  if (!magnetUri.startsWith(prefix)) return magnetUri;

  final nonTr = <String>[];
  final originalTr = <String>[];
  var hasInfoHash = false;
  for (final part in magnetUri.substring(prefix.length).split('&')) {
    if (part.isEmpty) continue;
    if (part.startsWith('tr=')) {
      originalTr.add(part.substring(3));
    } else {
      nonTr.add(part);
      if (part.startsWith('xt=')) hasInfoHash = true;
    }
  }
  // 没有 xt 就不是可用的磁力：原样返回，不往里塞 tracker。
  if (!hasInfoHash) return magnetUri;

  final existing = <String>{};
  for (final raw in originalTr) {
    try {
      existing.add(Uri.decodeComponent(raw).trim());
    } catch (_) {
      existing.add(raw.trim());
    }
  }

  final out = <String>[...nonTr];
  for (final t in preferredTrackers) {
    if (existing.contains(t)) continue;
    out.add('tr=${Uri.encodeComponent(t)}');
  }
  for (final raw in originalTr) {
    out.add('tr=$raw');
  }
  return '$prefix${out.join('&')}';
}

/// 磁力链接中的文件信息
class TorrentFileItem {
  final int index;
  final String name;
  final int size;
  final bool isStreamable;

  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  const TorrentFileItem({
    required this.index,
    required this.name,
    required this.size,
    required this.isStreamable,
  });
}
