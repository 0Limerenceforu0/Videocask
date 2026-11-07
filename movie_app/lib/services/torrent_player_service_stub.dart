import 'dart:async';

import 'package:flutter/foundation.dart';

import 'torrent_player_models.dart';

/// Web 等非 IO 平台占位实现（无 libtorrent / FFI）。
///
/// Web 平台没有 libtorrent native binding，原生 P2P 不可用。常见替代方案：
/// 1. 引导用户切到 安卓 / Windows / macOS / Linux 端（推荐，体验最佳）
/// 2. 走「云端 HTTP 种子代理」——用户在设置里填一个兼容 BitTorrent 的 HTTP 网关
///    （如自部署 qBittorrent WebUI、Cloud Torrent、BTorrent-Streaming 等），
///    本服务只做 URL 透传
class TorrentPlayerService with ChangeNotifier {
  static final TorrentPlayerService _instance =
      TorrentPlayerService._internal();
  factory TorrentPlayerService() => _instance;
  TorrentPlayerService._internal();

  TorrentPlayState _state = TorrentPlayState.idle;
  TorrentPlayState get state => _state;

  String _errorMessage = 'Web 端暂不支持原生磁力链接（P2P）播放';
  String get errorMessage => _errorMessage;

  double _downloadProgress = 0;
  double get downloadProgress => _downloadProgress;

  int _downloadSpeed = 0;
  int get downloadSpeed => _downloadSpeed;

  /// Web 占位：没有播放种子，恒 null（与 IO 实现保持同形 API）。
  int? get currentTorrentId => null;

  int _uploadSpeed = 0;
  int get uploadSpeed => _uploadSpeed;

  int _peers = 0;
  int get peers => _peers;

  /// 节点数展示值（Web 占位：恒「0」，保留与 IO 实现同形的 API）。
  String get peersDisplay => formatSwarmCount(_peers);

  int _seeds = 0;
  int get seeds => _seeds;

  /// 做种数展示值（Web 占位：恒「0」，保留与 IO 实现同形的 API）。
  String get seedsDisplay => formatSwarmCount(_seeds);

  /// 在连节点数（Web 占位：恒 0，保留与 IO 实现同形的 API）。
  int _activePeers = 0;
  int get activePeers => _activePeers;
  String get activePeersDisplay => formatSwarmCount(_activePeers);

  /// Web 端没有真实 P2P 引擎（走云端代理），永远不存在「连不上节点」。
  bool get handoverWithoutPeers => false;

  /// 与 IO 实现同形的空实现（Web 端没有死种结论可清）。
  void clearDeadSwarm() {}

  String? _streamUrl;
  String? get streamUrl => _streamUrl;

  List<TorrentFileItem> _files = [];
  List<TorrentFileItem> get files => _files;

  String _torrentName = '';
  String get torrentName => _torrentName;

  int _totalSize = 0;
  int get totalSize => _totalSize;

  int _bufferPct = 0;
  int get bufferPct => _bufferPct;

  int _etaSeconds = -1;
  int get etaSeconds => _etaSeconds;

  int _metaWaitSeconds = 0;
  int get metaWaitSeconds => _metaWaitSeconds;

  int _streamStage = 0;
  int get streamStage => _streamStage;

  bool get isInitialized => false;

  /// 当前是否处于「已用云端代理解析成功但仍在缓冲」状态。
  /// 该标志用于上层 UI 在 Web 端显示「云端种子中转」入口。
  bool _cloudProxyInUse = false;
  bool get cloudProxyInUse => _cloudProxyInUse;

  /// Web 端「云端 HTTP 代理」URL（在设置中由用户配置）。
  /// 例如 https://my-seedbox.example.com/torrent/play?magnet=...
  String? _cloudProxyBase;
  String? get cloudProxyBase => _cloudProxyBase;

  void setCloudProxyBase(String? base) {
    _cloudProxyBase =
        (base != null && base.trim().isNotEmpty) ? base.trim() : null;
  }

  /// Web 端「用云端代理试播」：把 magnet 拼到代理 URL 上，由代理服务器做种子解析与转码。
  /// 若 [magnet] 为空或未配置代理，返回 null。
  String? buildCloudProxyStreamUrl(String magnet) {
    if (_cloudProxyBase == null || magnet.isEmpty) return null;
    final encoded = Uri.encodeComponent(magnet);
    final sep = _cloudProxyBase!.contains('?') ? '&' : '?';
    return '$_cloudProxyBase$sep.magnet=$encoded';
  }

  Future<void> init() async {
    // Web 端无 libtorrent 引擎，仅把状态置为「未就绪」，UI 上展示说明。
    if (_state != TorrentPlayState.error) {
      _setState(TorrentPlayState.error, _errorMessage);
    }
  }

  Future<bool> addMagnet(String magnetUri) async {
    if (magnetUri.isEmpty) return false;
    // Web 端不直接播放，但可以解析 magnet 的 info_hash 给 UI 显示状态。
    _setState(TorrentPlayState.error, _errorMessage);
    return false;
  }

  void fetchFiles() {}

  Future<String?> playFile(int fileIndex) async => null;

  Future<void> stop() async {
    _streamUrl = null;
    _files = [];
    _torrentName = '';
    _totalSize = 0;
    _downloadProgress = 0;
    _downloadSpeed = 0;
    _uploadSpeed = 0;
    _peers = 0;
    _seeds = 0;
    _activePeers = 0;
    _bufferPct = 0;
    _etaSeconds = -1;
    _streamStage = 0;
    _metaWaitSeconds = 0;
    _cloudProxyInUse = false;
    _setState(TorrentPlayState.idle, '');
  }

  String get downloadSpeedFormatted => '0 B/s';
  String get uploadSpeedFormatted => '0 B/s';

  /// Web 端无引擎可释放；保留与 IO 版一致的 `Future<void> dispose()` 签名，
  /// 避免调用方落到 [ChangeNotifier.dispose]（void）上。
  ///
  /// 幂等：单例可能被应用退出路径与测试析构多次调用，重复 super.dispose()
  /// 后再 notifyListeners 会抛断言。
  bool _released = false;

  @override
  Future<void> dispose() async {
    if (_released) return;
    _released = true;
    super.dispose();
  }

  String get progressFormatted => '0.0%';
  String get etaFormatted => '--';
  String get metaWaitFormatted => '';

  void _setState(TorrentPlayState state, String error) {
    if (_released) return;
    _state = state;
    _errorMessage = error;
    notifyListeners();
  }
}
