import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';

import 'torrent_player_models.dart';

/// `flutter test` 的绑定类型名包含 TestWidgets，避免在 VM 测试中初始化原生 libtorrent。
bool _isFlutterWidgetTest() {
  try {
    final name = WidgetsBinding.instance.runtimeType.toString();
    return name.contains('TestWidgets') ||
        name.contains('AutomatedTestWidgets');
  } catch (_) {
    return false;
  }
}

/// 磁力链接播放服务（IO 平台，基于 libtorrent_flutter）
class TorrentPlayerService with ChangeNotifier {
  static final TorrentPlayerService _instance =
      TorrentPlayerService._internal();
  factory TorrentPlayerService() => _instance;
  TorrentPlayerService._internal();

  late LibtorrentFlutter _engine;

  TorrentPlayState _state = TorrentPlayState.idle;
  TorrentPlayState get state => _state;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  double _downloadProgress = 0;
  double get downloadProgress => _downloadProgress;

  int _downloadSpeed = 0;
  int get downloadSpeed => _downloadSpeed;

  int _peers = 0;
  int get peers => _peers;

  int _seeds = 0;
  int get seeds => _seeds;

  String? _streamUrl;
  String? get streamUrl => _streamUrl;

  List<TorrentFileItem> _files = [];
  List<TorrentFileItem> get files => _files;

  int? _currentTorrentId;
  int? _currentStreamId;

  String _torrentName = '';
  String get torrentName => _torrentName;

  int _totalSize = 0;
  int get totalSize => _totalSize;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  StreamSubscription<Map<int, TorrentInfo>>? _torrentSub;
  StreamSubscription<Map<int, StreamInfo>>? _streamSub;

  Future<void> init() async {
    if (_isInitialized) return;

    if (_isFlutterWidgetTest()) {
      debugPrint('TorrentPlayerService: Widget 测试环境跳过 libtorrent 初始化');
      return;
    }

    try {
      await LibtorrentFlutter.init(
        fetchTrackers: true,
        pollInterval: const Duration(milliseconds: 500),
      );
      _engine = LibtorrentFlutter.instance;

      _torrentSub = _engine.torrentUpdates.listen(_onTorrentUpdate);
      _streamSub = _engine.streamUpdates.listen(_onStreamUpdate);

      _isInitialized = true;
      debugPrint('TorrentPlayerService: P2P引擎初始化成功');
    } catch (e) {
      debugPrint('TorrentPlayerService: 初始化失败 - $e');
      _setState(TorrentPlayState.error, 'P2P引擎初始化失败: $e');
    }
  }

  Future<bool> addMagnet(String magnetUri) async {
    if (!_isInitialized) {
      await init();
      if (!_isInitialized) return false;
    }

    await stop();
    if (_state != TorrentPlayState.idle) return false;

    _setState(TorrentPlayState.fetchingMeta, '');

    try {
      const extraTrackers = [
        'udp://tracker.opentrackr.org:1337/announce',
        'udp://open.tracker.cl:1337/announce',
        'udp://tracker.openbittorrent.com:6969/announce',
        'udp://open.stealth.si:80/announce',
        'udp://exodus.desync.com:6969/announce',
        'udp://tracker.torrent.eu.org:451/announce',
        'http://tracker.openbittorrent.com:80/announce',
        'udp://tracker.tiny-vps.com:6969/announce',
        'udp://tracker.moeking.me:6969/announce',
        'udp://explodie.org:6969/announce',
      ];

      String enhancedMagnet = magnetUri;
      if (!magnetUri.contains('&tr=')) {
        enhancedMagnet += '&tr=${Uri.encodeComponent(extraTrackers[0])}';
      }
      for (int i = 1; i < extraTrackers.length; i++) {
        enhancedMagnet += '&tr=${Uri.encodeComponent(extraTrackers[i])}';
      }

      _currentTorrentId = _engine.addMagnet(enhancedMagnet);
      debugPrint(
        'TorrentPlayerService: 已添加磁力链接 (含${extraTrackers.length}个额外tracker), torrentId=$_currentTorrentId',
      );
      return true;
    } catch (e) {
      debugPrint('TorrentPlayerService: 添加磁力链接失败 - $e');
      _setState(TorrentPlayState.error, '添加磁力链接失败: $e');
      return false;
    }
  }

  void fetchFiles() {
    if (_currentTorrentId == null) return;

    try {
      final rawFiles = _engine.getFiles(_currentTorrentId!);
      _files = rawFiles
          .map(
            (f) => TorrentFileItem(
              index: f.index,
              name: f.name,
              size: f.size,
              isStreamable: f.isStreamable,
            ),
          )
          .toList();

      _files.sort((a, b) => b.size.compareTo(a.size));

      if (_files.isNotEmpty) {
        _setState(TorrentPlayState.ready, '');
      } else {
        _setState(TorrentPlayState.error, '未找到可播放的文件');
      }
    } catch (e) {
      debugPrint('TorrentPlayerService: 获取文件列表失败 - $e');
      _setState(TorrentPlayState.error, '获取文件列表失败: $e');
    }
  }

  Future<String?> playFile(int fileIndex) async {
    if (_currentTorrentId == null) return null;

    _setState(TorrentPlayState.buffering, '');

    try {
      final streamInfo = _engine.startStream(
        _currentTorrentId!,
        fileIndex: fileIndex,
        maxCacheBytes: 1024 * 1024 * 1024,
      );

      _currentStreamId = streamInfo.id;
      _streamUrl = streamInfo.url;

      debugPrint('TorrentPlayerService: 流已启动, url=${streamInfo.url}');

      await _waitForStreamReady();

      if (_streamUrl != null && _state != TorrentPlayState.error) {
        _setState(TorrentPlayState.playing, '');
        return _streamUrl;
      }

      return null;
    } catch (e) {
      debugPrint('TorrentPlayerService: 启动流失败 - $e');
      _setState(TorrentPlayState.error, '启动播放流失败: $e');
      return null;
    }
  }

  Future<void> _waitForStreamReady() async {
    const maxWait = Duration(seconds: 10);
    const checkInterval = Duration(milliseconds: 300);
    var elapsed = Duration.zero;

    while (elapsed < maxWait) {
      if (_state == TorrentPlayState.error || _state == TorrentPlayState.idle) {
        return;
      }

      final info = _engine.getStreamInfo(_currentStreamId ?? 0);
      if (info != null && info.isReady) {
        debugPrint('TorrentPlayerService: 流已就绪, buffer=${info.bufferPct}%');
        return;
      }

      await Future<void>.delayed(checkInterval);
      elapsed += checkInterval;
    }

    if (_streamUrl != null) {
      debugPrint('TorrentPlayerService: 流就绪超时，尝试播放');
      return;
    }

    _setState(TorrentPlayState.error, '缓冲超时，做种数不足或网络不佳');
  }

  void _onTorrentUpdate(Map<int, TorrentInfo> torrents) {
    if (_currentTorrentId == null || !torrents.containsKey(_currentTorrentId)) {
      return;
    }

    final t = torrents[_currentTorrentId!]!;

    if (t.name.isNotEmpty && _torrentName.isEmpty) {
      _torrentName = t.name;
    }

    _downloadProgress = t.progress;
    _downloadSpeed = t.downloadRate;
    _peers = t.numPeers;
    _seeds = t.numSeeds;
    _totalSize = t.totalWanted;

    if (t.state.label == 'Error') {
      _setState(TorrentPlayState.error, '下载出错');
      return;
    }

    if (t.hasMetadata && _state == TorrentPlayState.fetchingMeta) {
      fetchFiles();
    }

    notifyListeners();
  }

  void _onStreamUpdate(Map<int, StreamInfo> streams) {
    if (_currentStreamId == null || !streams.containsKey(_currentStreamId)) {
      return;
    }

    final s = streams[_currentStreamId];
    if (s == null) return;

    if (s.isReady && _state == TorrentPlayState.buffering) {
      _setState(TorrentPlayState.playing, '');
    }

    notifyListeners();
  }

  Future<void> stop() async {
    try {
      if (_isInitialized && _currentStreamId != null) {
        _engine.stopStream(_currentStreamId!);
        _currentStreamId = null;
      }

      if (_isInitialized && _currentTorrentId != null) {
        _engine.removeTorrent(_currentTorrentId!);
        _currentTorrentId = null;
      }
    } catch (e) {
      debugPrint('TorrentPlayerService: 停止时出错 - $e');
    }

    _streamUrl = null;
    _files = [];
    _torrentName = '';
    _totalSize = 0;
    _downloadProgress = 0;
    _downloadSpeed = 0;
    _peers = 0;
    _seeds = 0;
    _setState(TorrentPlayState.idle, '');
  }

  @override
  Future<void> dispose() async {
    await stop();
    try {
      await _torrentSub?.cancel();
    } catch (e) {
      debugPrint('TorrentPlayerService: cancel torrentSub — $e');
    }
    try {
      await _streamSub?.cancel();
    } catch (e) {
      debugPrint('TorrentPlayerService: cancel streamSub — $e');
    }

    if (_isInitialized) {
      try {
        await _engine.dispose();
      } catch (e) {
        debugPrint('TorrentPlayerService: 销毁引擎出错 - $e');
      }
    }

    _isInitialized = false;
    super.dispose();
  }

  String get downloadSpeedFormatted {
    if (_downloadSpeed < 1024) return '$_downloadSpeed B/s';
    if (_downloadSpeed < 1024 * 1024) {
      return '${(_downloadSpeed / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(_downloadSpeed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String get progressFormatted =>
      '${(_downloadProgress * 100).toStringAsFixed(1)}%';

  void _setState(TorrentPlayState state, String error) {
    _state = state;
    _errorMessage = error;
    notifyListeners();
  }
}
