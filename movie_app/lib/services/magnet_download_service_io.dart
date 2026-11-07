import 'dart:async';
import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:libtorrent_flutter/libtorrent_flutter.dart' as lt;
import 'package:path_provider/path_provider.dart';

import 'torrent_player_models.dart' show buildEnhancedMagnet;
import 'torrent_player_service.dart' show TorrentPlayerService;

/// 一次「直接下载」任务的状态。
class MagnetDownloadTask {
  MagnetDownloadTask({
    required this.hash,
    required this.name,
    required this.torrentId,
    required this.savePath,
  });

  final String hash;
  final String name;
  final int torrentId;
  final String savePath;
  double progress = 0;
  bool finished = false;
}

/// 磁力资源「点一下就真的开始下载」。
///
/// 复用播放服务的同一个 libtorrent session（插件的 torrentUpdates 是
/// broadcast，多监听安全），用 `addMagnet(..., streamOnly: false)` 让原生
/// 真正把文件写到磁盘；**不需要改三端 C++**。`streamOnly=true` 是播放链路
/// 专用的不写盘模式，两者按 torrentId 互不干扰。
///
/// Web 没有 FFI session，直接返回不支持，由 UI 给出明确提示。
class MagnetDownloadService extends ChangeNotifier {
  MagnetDownloadService._();

  static final MagnetDownloadService instance = MagnetDownloadService._();

  factory MagnetDownloadService() => instance;

  final Map<String, MagnetDownloadTask> _tasks = <String, MagnetDownloadTask>{};
  StreamSubscription<Map<int, lt.TorrentInfo>>? _sub;

  List<MagnetDownloadTask> get tasks =>
      _tasks.values.toList(growable: false);

  MagnetDownloadTask? taskFor(String magnetUri) => _tasks[_hashOf(magnetUri)];

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }

  static String _hashOf(String magnetUri) {
    final m = RegExp(r'btih:([a-fA-F0-9]+)').firstMatch(magnetUri);
    return (m?.group(1) ?? magnetUri).toLowerCase();
  }

  /// 下载结果：`ok` 表示是否已开始（含「已在队列中」），`message` 给 SnackBar。
  Future<({bool ok, String message})> start({
    required String magnetUri,
    required String name,
  }) async {
    if (kIsWeb) {
      return (ok: false, message: 'Web 端暂不支持磁力下载，请在手机或桌面端使用');
    }
    final hash = _hashOf(magnetUri);
    final existing = _tasks[hash];
    if (existing != null) {
      return (
        ok: true,
        message: existing.finished
            ? '已下载完成，文件在 ${existing.savePath}'
            : '已在下载中（${(existing.progress * 100).toStringAsFixed(0)}%）',
      );
    }
    try {
      // 复用播放服务的初始化：里面带了 enableIpv6:false 等真机调优，
      // 自己另起 session 会踩回「绑 [::] 连不上 peer」的坑。
      await TorrentPlayerService().init();
      if (!lt.LibtorrentFlutter.isInitialized) {
        return (ok: false, message: '下载引擎未就绪，请稍后重试');
      }
      final dir = await _saveDirectory();
      final enhanced = buildEnhancedMagnet(magnetUri, _preferredTrackers);
      final id = lt.LibtorrentFlutter.instance.addMagnet(
        enhanced,
        dir,
        false, // streamOnly=false → 真正写盘下载
      );
      _tasks[hash] = MagnetDownloadTask(
        hash: hash,
        name: name,
        torrentId: id,
        savePath: dir,
      );
      _ensureSubscribed();
      notifyListeners();
      return (ok: true, message: '已开始下载，文件将保存到 $dir');
    } catch (e) {
      return (ok: false, message: '开始下载失败：$e');
    }
  }

  Future<String> _saveDirectory() async {
    Directory base;
    if (Platform.isAndroid) {
      // Android 没有公共 downloads 目录的 path_provider 实现，用应用外部目录：
      // 文件管理器可见、无需存储权限、也不会被系统当作缓存清掉。
      base = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      base = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base.path}/MagnetDownloads');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  void _ensureSubscribed() {
    final current = _sub;
    if (current != null) return;
    _sub = lt.LibtorrentFlutter.instance.torrentUpdates.listen((all) {
      var changed = false;
      for (final task in _tasks.values) {
        final info = all[task.torrentId];
        if (info == null) continue;
        final progress = info.progress.clamp(0.0, 1.0);
        final finished = info.isFinished || progress >= 0.999;
        if ((progress - task.progress).abs() > 0.001 ||
            finished != task.finished) {
          task.progress = progress;
          task.finished = finished;
          changed = true;
        }
      }
      if (changed) notifyListeners();
    });
  }

  /// 取消并删除已下载的文件（不碰播放链路的种子）。
  void cancel(String magnetUri) {
    final task = _tasks.remove(_hashOf(magnetUri));
    if (task == null) return;
    try {
      lt.LibtorrentFlutter.instance.removeTorrent(
        task.torrentId,
        deleteFiles: true,
      );
    } catch (_) {
      // 引擎已退出时忽略；状态已从列表移除。
    }
    notifyListeners();
  }

  /// 与播放链路同款的优选 tracker（死链靠后、HTTP 优先）。
  /// 单独留一份是为了不改动高风险播放服务的私有常量。
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
