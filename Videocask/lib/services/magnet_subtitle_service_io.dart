import 'dart:io' show Directory, File, HttpClient;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:libtorrent_flutter/libtorrent_flutter.dart' as lt;
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';
import '../pages/detail/playback/subtitle_file_policy.dart';
import 'torrent_player_models.dart' show buildEnhancedMagnet;
import 'torrent_player_service_io.dart' show TorrentPlayerService;

/// S3：把种子里**独立的** `.srt/.ass/.ssa/.vtt/.sub` 中文字幕取出并落盘。
///
/// 为什么不改 C++：插件的 `lt_get_files` 能列出全部文件，
/// `lt_start_stream(..., file_index, ...)` 显式传索引时不检查扩展名，
/// `StreamInfo.url` 是本地 HTTP URL，字幕几百 KB 落在 head 保护区内可整份读。
///
/// 🔴 为什么不复用正在播放的那个 torrent：`lt_start_stream` 会把
/// **所有 piece 先置为 dont_download** 再只放行当前文件范围
///（`torrent_bridge.cpp:2487`）。同一个 handle 上再起一条字幕流会重置
/// 视频流的 piece 调度，等效于历史事故「有做种却播不出来」。
/// 因此这里用**第二个独立、短命的磁力任务**，取完字节立刻停流删种。
/// 绝不调用 `setFilePriorities`。
class MagnetSubtitleService {
  MagnetSubtitleService._();

  static final MagnetSubtitleService instance = MagnetSubtitleService._();

  factory MagnetSubtitleService() => instance;

  /// 代次计数器：换集时新任务会作废旧任务，旧字幕不会串到新一集。
  int _generation = 0;
  int? _torrentId;
  int? _streamId;

  /// 作废当前任务并清理它建出来的种子 / 流。
  /// 下一次 [fetchChineseSubtitle] 开头会自动调用。
  void cancel() {
    _generation++;
    _stopOwned(_torrentId, _streamId);
    _torrentId = null;
    _streamId = null;
  }

  /// 返回可交给 `setExternalSubtitleFromFile` 的本地路径；
  /// 任何失败都返回 null，由编排器静默降级到在线简中字幕。
  Future<String?> fetchChineseSubtitle({
    required String magnetUri,
  }) async {
    if (kIsWeb || magnetUri.trim().isEmpty) return null;
    cancel();
    final gen = _generation;
    bool alive() => gen == _generation;

    int? torrentId;
    int? streamId;
    try {
      // 复用播放服务已初始化的 session（含 enableIpv6:false 等真机调优），
      // 另起 session 会踩回「绑 [::] 连不上 peer」的坑。
      await TorrentPlayerService().init();
      if (!alive() || !lt.LibtorrentFlutter.isInitialized) return null;

      final savePath = await _ensureDir('movie_app/magnet_subtitle_session');
      if (!alive()) return null;

      final enhanced = buildEnhancedMagnet(magnetUri, _preferredTrackers);
      final id = lt.LibtorrentFlutter.instance.addMagnet(
        enhanced,
        savePath,
        true, // streamOnly：只为取字节，不写盘
      );
      if (id < 0) {
        DebugLog.log(
          'MagnetSub',
          '第二个磁力任务未建成（引擎拒绝同 hash），静默降级到在线字幕',
        );
        return null;
      }

      // 🔴 若引擎把同 hash 合并回播放 handle，绝不能碰它：
      // 一旦 removeTorrent，删掉的就是正在播的种子。
      if (id == TorrentPlayerService().currentTorrentId) {
        DebugLog.log('MagnetSub', '磁力被合并到播放种子，跳过以免误删');
        return null;
      }

      torrentId = id;
      _torrentId = id;
      final files = await _waitForFiles(id, alive);
      if (files == null || files.isEmpty || !alive()) return null;

      final pick = pickChineseSubtitleFile(
        files.map(
          (f) => TorrentSubtitleCandidate(
            index: f.index,
            name: f.name,
            size: f.size,
          ),
        ),
      );
      if (pick == null) {
        // 纯视频种子：不再起流，额外开销到此为止。
        DebugLog.log('MagnetSub', '种子内无中文字幕文件，不建流');
        return null;
      }

      final info = lt.LibtorrentFlutter.instance.startStream(
        id,
        fileIndex: pick.index,
        maxCacheBytes: 8 * 1024 * 1024,
      );
      streamId = info.id;
      _streamId = info.id;
      if (info.url.isEmpty) return null;

      final bytes = await _httpGetAll(info.url, alive);
      if (bytes == null || bytes.isEmpty || !alive()) return null;

      final path = await _writeSubtitle(pick.name, bytes);
      DebugLog.log(
        'MagnetSub',
        '种子内中文字幕就位: ${pick.name} (${bytes.length}B) → $path',
      );
      return path;
    } catch (e) {
      DebugLog.log('MagnetSub', '种子内字幕读取失败，静默降级: $e');
      return null;
    } finally {
      // 只清理属于本任务的资源。若已被新任务 cancel，旧资源已由 cancel
      // 清掉，这里不能再动实例字段（那时已经是新任务的 id 了）。
      if (alive()) {
        _stopOwned(torrentId, streamId);
        _torrentId = null;
        _streamId = null;
      }
    }
  }

  void _stopOwned(int? torrentId, int? streamId) {
    if (!lt.LibtorrentFlutter.isInitialized) return;
    final engine = lt.LibtorrentFlutter.instance;
    if (streamId != null) {
      try {
        engine.stopStream(streamId);
      } catch (_) {
        // streamOnly 停流本就会连带移除种子，重复清理可忽略。
      }
    }
    if (torrentId != null) {
      try {
        engine.removeTorrent(torrentId, deleteFiles: true);
      } catch (_) {
        // 引擎已退出或种子已被停流移除。
      }
    }
  }

  /// 等 metadata 就绪后拿到文件列表；超时即放弃，不拖起播。
  Future<List<lt.FileInfo>?> _waitForFiles(
    int id,
    bool Function() alive,
  ) async {
    const limit = Duration(seconds: 12);
    const step = Duration(milliseconds: 300);
    final sw = Stopwatch()..start();
    while (alive() && sw.elapsed < limit) {
      try {
        final files = lt.LibtorrentFlutter.instance.getFiles(id);
        if (files.isNotEmpty) return files;
      } catch (_) {
        // metadata 还没到，继续轮询。
      }
      await Future<void>.delayed(step);
    }
    return null;
  }

  /// 从本地 loopback HTTP 服务整份读字幕字节。
  /// 不设置 findProxy，避免环境代理把 127.0.0.1 请求转发出去。
  Future<List<int>?> _httpGetAll(
    String url,
    bool Function() alive,
  ) async {
    HttpClient? client;
    try {
      final uri = Uri.parse(url);
      if (uri.host.isEmpty) return null;
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      client.idleTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200 && response.statusCode != 206) return null;
      final out = <int>[];
      await for (final chunk in response) {
        if (!alive()) return null;
        if (out.length + chunk.length > maxTorrentSubtitleBytes) return null;
        out.addAll(chunk);
      }
      return out;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  /// 按真实扩展名落盘（ASS 不改成 SRT，特效才不会丢），只保留最近一份。
  Future<String> _writeSubtitle(String name, List<int> bytes) async {
    final dirPath = await _ensureDir('movie_app/torrent_subtitles');
    final dir = Directory(dirPath);
    for (final entity in dir.listSync()) {
      if (entity is File) {
        final base = entity.path.replaceAll('\\', '/').split('/').last;
        if (base.startsWith('torrent_sub_')) {
          try {
            entity.deleteSync();
          } catch (_) {
            // 占用中的旧文件留到下次清理，不影响本次挂载。
          }
        }
      }
    }
    final path = '$dirPath/torrent_sub_${name.hashCode.abs()}'
        '${subtitleFileExtension(name)}';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  Future<String> _ensureDir(String relative) async {
    // 字幕只有几百 KB，沿用应用临时目录（与在线字幕缓存同一套语义）；
    // 不往 C 盘写构建产物 / 大文件。
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/$relative');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  /// 与播放 / 下载链路同款的优选 tracker，单独留一份避免改动高风险播放服务。
  static const List<String> _preferredTrackers = <String>[
    'http://tracker.opentrackr.org:1337/announce',
    'http://tracker.qu.ax:6969/announce',
    'http://tracker.dler.org:6969/announce',
    'http://tracker2.itzmx.com:6961/announce',
    'http://open.tracker.cl:1337/announce',
    'http://nyaa.tracker.wf:7777/announce',
    'udp://tracker.tryhackx.org:6969/announce',
    'udp://tracker.moeking.me:6969/announce',
    'udp://open.stealth.si:80/announce',
  ];
}
