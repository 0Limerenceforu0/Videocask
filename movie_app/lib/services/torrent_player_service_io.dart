import 'dart:async';
import 'dart:io' show Directory, Platform;

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
///
/// ## 加载慢的几个根因 & 本服务对应优化
///
/// 1. **piece 拉取策略松散**：默认 `connectionsLimit=25`、缓存 64MB、首字节缓冲只
///    16MB，热门资源在头 10 秒内就触顶。这里把 per-stream 提到 200/256MB/64MB，
///    让首屏缓冲 4 倍速到位。
/// 2. **下载散到所有文件**：种子含多文件时，下载配额被稀释到所有文件，导致
///    「所选文件」迟迟凑不齐可播 piece。本服务选中文件后立刻 `setFilePriorities`
///    把其它文件置 0。
/// 3. **首启顺序错**：默认先打开 stream 等到 16MB 头再交给 mpv；
///    改为「addMagnet + 选文件 + setPriorities + startStream + preloadStream」四步紧贴，
///    减少空窗期。
/// 4. **种子源少**：默认 10 个 tracker 多半已下线。本服务用一份在 2025–2026
///    仍持续响应的公开 tracker 列表。
/// 5. **streamOnly 没启用**：TorrServer 在 stream 模式下不写盘，节省 I/O。
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

  int _uploadSpeed = 0;
  int get uploadSpeed => _uploadSpeed;

  int _peers = 0;
  int get peers => _peers;

  int _seeds = 0;
  int get seeds => _seeds;

  int _totalSize = 0;
  int get totalSize => _totalSize;

  /// 0–100，已预缓冲数据相对流首部首 MB 的比例（来自 [StreamInfo.bufferPct]）。
  int _bufferPct = 0;
  int get bufferPct => _bufferPct;

  /// 估算的剩余缓冲秒数：当前缓冲大小 ÷ 当前下载速度。
  /// -1 表示未知（速度为 0 或缓冲为 0）。
  int _etaSeconds = -1;
  int get etaSeconds => _etaSeconds;

  String? _streamUrl;
  String? get streamUrl => _streamUrl;

  List<TorrentFileItem> _files = [];
  List<TorrentFileItem> get files => _files;

  int? _currentTorrentId;
  int? _currentStreamId;

  String _torrentName = '';
  String get torrentName => _torrentName;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  StreamSubscription<Map<int, TorrentInfo>>? _torrentSub;
  StreamSubscription<Map<int, StreamInfo>>? _streamSub;

  /// 当前种子在等待元数据时已等待的秒数（用于 UI 反馈「解析较慢」）。
  int _metaWaitSeconds = 0;
  int get metaWaitSeconds => _metaWaitSeconds;

  /// 用户可见的加载阶段：0 解析元数据 / 1 缓冲头 / 2 已可播。
  int _streamStage = 0;
  int get streamStage => _streamStage;

  /// 2025–2026 仍持续响应的公开 tracker（保留 http + udp，避免只 udp 被墙）。
  static const _extraTrackers = <String>[
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.tracker.cl:1337/announce',
    'udp://open.stealth.si:80/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://tracker.tiny-vps.com:6969/announce',
    'udp://tracker.moeking.me:6969/announce',
    'udp://explodie.org:6969/announce',
    'udp://tracker.dump.cl:6969/announce',
    'udp://tracker.bittor.pw:1337/announce',
    'udp://ns1.monika.lol:6969/announce',
    'udp://retracker.lanta.me:2710/announce',
    'udp://tracker.4.babico.name.tr:1337/announce',
    'udp://tracker2.dler.org:80/announce',
    'udp://tracker.zemoj.com:6969/announce',
    'http://tracker.openbittorrent.com:80/announce',
    'http://tracker.bt4g.com:2095/announce',
    'http://bt.okmp3.ru:2710/announce',
  ];

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

      // 关键性能调优：在 init 之后立刻下发到原生 session。
      _engine.configureSession(_buildPerformanceConfig());

      _torrentSub = _engine.torrentUpdates.listen(_onTorrentUpdate);
      _streamSub = _engine.streamUpdates.listen(_onStreamUpdate);

      _isInitialized = true;
      debugPrint('TorrentPlayerService: P2P 引擎初始化 + 性能配置已下发');
    } catch (e) {
      debugPrint('TorrentPlayerService: 初始化失败 - $e');
      _setState(TorrentPlayState.error, 'P2P引擎初始化失败: $e');
    }
  }

  /// 会话级 BtConfig：与 TorrServer 默认对齐但拉高「流播放」相关参数。
  BtConfig _buildPerformanceConfig() {
    return BtConfig(
      // 256MB 内存 piece cache：头 30 秒下载量能完整装下，避开边读边丢。
      cacheSize: 256 * 1024 * 1024,
      // 100% read-ahead：牺牲随机读 IO 换顺序流读写命中率。
      readerReadAhead: 100,
      // 80% 预热：startStream 那一刻就让 reader 预读 80% 缓存大小，避开冷启动。
      preloadCache: 80,
      // 200 并发 piece 请求：25 是磁盘优化，对流播放是瓶颈。
      connectionsLimit: 200,
      // 60s 闲置超时，给点时间等后续 piece 拉齐。
      torrentDisconnectTimeout: 60,
      // 不强制加密：很多热门种子的对端只走明文；强制加密会丢一半 peer。
      forceEncrypt: false,
      // 留两条路：TCP 直连穿透好，UTP 在丢包网络下更稳。
      disableTcp: false,
      disableUtp: false,
      // 上传不禁用：做种信用影响下载速度。
      disableUpload: false,
      // DHT 必开：去中心化发现 peer 的关键。
      disableDht: false,
      // UPnP 开启：争取拿到公网入站端口，提高 peer 主动连接命中率。
      disableUpnp: false,
      // 限速 0 = 不限；播放期间也不要限速。
      downloadRateLimit: 0,
      // 上传限速 4MB/s 防止上传吃满带宽影响下行。
      uploadRateLimit: 4096,
      // 0 = 随机端口。
      peersListenPort: 0,
      // responsiveMode 打开：piece 预取更激进。
      responsiveMode: true,
    );
  }

  Future<bool> addMagnet(String magnetUri) async {
    if (!_isInitialized) {
      await init();
      if (!_isInitialized) return false;
    }

    await stop();
    if (_state != TorrentPlayState.idle) return false;

    _setState(TorrentPlayState.fetchingMeta, '');
    _metaWaitSeconds = 0;
    _streamStage = 0;

    try {
      String enhancedMagnet = magnetUri;
      if (!magnetUri.contains('&tr=')) {
        enhancedMagnet += '&tr=${Uri.encodeComponent(_extraTrackers[0])}';
        for (int i = 1; i < _extraTrackers.length; i++) {
          enhancedMagnet += '&tr=${Uri.encodeComponent(_extraTrackers[i])}';
        }
      }

      // streamOnly = true：不写盘，纯流模式，省 IO 与存储。
      _currentTorrentId = _engine.addMagnet(
        enhancedMagnet,
        _resolveSavePath(),
        true,
      );
      debugPrint(
        'TorrentPlayerService: 已添加磁力链接 (含${_extraTrackers.length}个 tracker, streamOnly=true), torrentId=$_currentTorrentId',
      );

      _startMetaWaitTicker();

      return true;
    } catch (e) {
      debugPrint('TorrentPlayerService: 添加磁力链接失败 - $e');
      _setState(TorrentPlayState.error, '添加磁力链接失败: $e');
      return false;
    }
  }

  Timer? _metaWaitTimer;
  void _startMetaWaitTicker() {
    _metaWaitTimer?.cancel();
    _metaWaitSeconds = 0;
    _metaWaitTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _metaWaitSeconds += 1;
      // meta 解析超过 30s 时给 UI 一个「重试 / 换源」入口。
      notifyListeners();
    });
  }

  void _stopMetaWaitTicker() {
    _metaWaitTimer?.cancel();
    _metaWaitTimer = null;
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

  /// 启动流并立刻把 piece 优先权与缓存策略下到位。
  ///
  /// 重要：`setFilePriorities` 必须 **在 startStream 之前** 调用，
  /// 否则前几秒的下载已经按默认优先级被浪费在副文件上。
  Future<String?> playFile(int fileIndex) async {
    if (_currentTorrentId == null) return null;

    _setState(TorrentPlayState.buffering, '');

    try {
      _applyFilePriority(fileIndex);

      final streamInfo = _engine.startStream(
        _currentTorrentId!,
        fileIndex: fileIndex,
        // 256MB stream cache：单个流在 4K HDR 也能稳定缓冲。
        maxCacheBytes: 256 * 1024 * 1024,
      );

      _currentStreamId = streamInfo.id;
      _streamUrl = streamInfo.url;
      _streamStage = 1; // 进入「缓冲头」阶段
      _bufferPct = 0;
      _etaSeconds = -1;

      debugPrint('TorrentPlayerService: 流已启动, url=${streamInfo.url}');

      // 每流独立的 cache 参数：256MB 缓存 + 100% read-ahead + 200 并发 piece 请求。
      _engine.setCacheSettings(
        _currentStreamId!,
        capacity: 256 * 1024 * 1024,
        readAheadPct: 100,
        connectionsLimit: 200,
      );

      // 立刻把首部 64MB 拉满，mpv 切到这一帧时就能立即解码。
      _engine.preloadStream(_currentStreamId!, preloadBytes: 64 * 1024 * 1024);

      await _waitForStreamReady();

      if (_streamUrl != null && _state != TorrentPlayState.error) {
        _setState(TorrentPlayState.playing, '');
        _streamStage = 2;
        return _streamUrl;
      }

      return _streamUrl;
    } catch (e) {
      debugPrint('TorrentPlayerService: 启动流失败 - $e');
      _setState(TorrentPlayState.error, '启动播放流失败: $e');
      return null;
    }
  }

  /// 把当前选中文件置为最高优先级（7），其余文件置 0（不下载）。
  void _applyFilePriority(int fileIndex) {
    if (_currentTorrentId == null) return;
    final files = _engine.getFiles(_currentTorrentId!);
    if (files.isEmpty) return;
    final priorities = <int>[];
    for (var i = 0; i < files.length; i++) {
      if (files[i].index == fileIndex) {
        priorities.add(7);
      } else {
        priorities.add(0);
      }
    }
    try {
      _engine.setFilePriorities(_currentTorrentId!, priorities);
      debugPrint(
        'TorrentPlayerService: 已设置文件优先级 fileIndex=$fileIndex 高优，其余置 0',
      );
    } catch (e) {
      debugPrint('TorrentPlayerService: setFilePriorities 失败 - $e');
    }
  }

  Future<void> _waitForStreamReady() async {
    const maxWait = Duration(seconds: 45);
    const checkInterval = Duration(milliseconds: 250);
    var elapsed = Duration.zero;

    while (elapsed < maxWait) {
      if (_state == TorrentPlayState.error || _state == TorrentPlayState.idle) {
        return;
      }

      final streamId = _currentStreamId;
      if (streamId != null) {
        final info = _engine.getStreamInfo(streamId);
        if (info != null) {
          _bufferPct = info.bufferPct.clamp(0, 100).toInt();
          // 5% 缓冲就允许 mpv 起播（边下边播）
          if (info.isReady || _bufferPct >= 5) {
            debugPrint(
              'TorrentPlayerService: 流已就绪, buffer=${_bufferPct}% (elapsed=${elapsed.inSeconds}s)',
            );
            return;
          }
        }
      }

      await Future<void>.delayed(checkInterval);
      elapsed += checkInterval;
    }

    if (_streamUrl != null) {
      debugPrint('TorrentPlayerService: 流就绪超时，尝试播放（已缓冲 $_bufferPct%）');
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
    _uploadSpeed = t.uploadRate;
    _peers = t.numPeers;
    _seeds = t.numSeeds;
    _totalSize = t.totalWanted;

    if (t.hasMetadata) {
      _stopMetaWaitTicker();
    }

    if (t.state.label == 'Error') {
      _stopMetaWaitTicker();
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

    _bufferPct = s.bufferPct.clamp(0, 100).toInt();
    if (_downloadSpeed > 0 && _bufferPct < 100) {
      final target = 30;
      if (_bufferPct < target) {
        final needPct = target - _bufferPct;
        final needBytes = (_totalSize * needPct) ~/ 100;
        _etaSeconds = (needBytes / _downloadSpeed).clamp(0, 9999).toInt();
      } else {
        _etaSeconds = 0;
      }
    } else {
      _etaSeconds = -1;
    }

    if (s.isReady && _state == TorrentPlayState.buffering) {
      _setState(TorrentPlayState.playing, '');
      _streamStage = 2;
    }

    notifyListeners();
  }

  Future<void> stop() async {
    _stopMetaWaitTicker();
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
    _uploadSpeed = 0;
    _peers = 0;
    _seeds = 0;
    _bufferPct = 0;
    _etaSeconds = -1;
    _streamStage = 0;
    _metaWaitSeconds = 0;
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

  String get downloadSpeedFormatted => _formatBytes(_downloadSpeed) + '/s';
  String get uploadSpeedFormatted => _formatBytes(_uploadSpeed) + '/s';

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get progressFormatted =>
      '${(_downloadProgress * 100).toStringAsFixed(1)}%';

  /// 人类可读的 ETA：45s / 1m23s / 12m5s
  String get etaFormatted {
    if (_etaSeconds < 0) return '--';
    if (_etaSeconds < 60) return '${_etaSeconds}s';
    final m = _etaSeconds ~/ 60;
    final s = _etaSeconds % 60;
    if (m < 60) return '${m}m${s.toString().padLeft(2, '0')}s';
    final h = m ~/ 60;
    final mm = m % 60;
    return '${h}h${mm.toString().padLeft(2, '0')}m';
  }

  /// 解析元数据等待秒数的友好文本。
  String get metaWaitFormatted {
    if (_metaWaitSeconds <= 0) return '';
    if (_metaWaitSeconds < 60) return '${_metaWaitSeconds}s';
    final m = _metaWaitSeconds ~/ 60;
    final s = _metaWaitSeconds % 60;
    return '${m}m${s.toString().padLeft(2, '0')}s';
  }

  /// 选一个 libtorrent 可写的临时目录（streamOnly=true 时不会真写盘，仅占位）。
  String _resolveSavePath() {
    try {
      final tmp = Directory.systemTemp.path;
      return '$tmp${Platform.pathSeparator}movie_app_torrent';
    } catch (_) {
      return '.';
    }
  }

  void _setState(TorrentPlayState state, String error) {
    _state = state;
    _errorMessage = error;
    notifyListeners();
  }
}
