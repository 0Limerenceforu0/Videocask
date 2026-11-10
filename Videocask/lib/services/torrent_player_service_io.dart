import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, HttpClient, Platform;
import 'package:flutter/foundation.dart';

import 'package:flutter/widgets.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'torrent_player_models.dart';

import 'debug_log.dart';
import 'playback_experiment.dart';

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
///    「所选文件」迟迟凑不齐可播 piece。这一层由原生 `startStream` 处理——
///    它先把所有 piece 置为 `dont_download`，再只放行所选文件的 head/tail。
///    **不要**再调 `setFilePriorities`，它会异步摧毁这套 piece 调度
///    （详见 [playFile] 的注释）。
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

  /// 原生 `download_rate` 原值（仅诊断用）。
  ///
  /// 为什么不直接用 [_downloadSpeed] = 原生值：2026-10-24 真机实测发现
  /// 插件上报的 download_rate 与实际吞吐不符（piece 每 ~1.4s 完成一个却报
  /// 个位数 B/s），UI 速度 chip 因此「数字不动」。现在 [_downloadSpeed]
  /// 一律由 [totalDone] 差分计算（见 [_onTorrentUpdate]），真实且必然变动。
  int _nativeDownloadRate = 0;
  int get nativeDownloadRate => _nativeDownloadRate;

  /// [totalDone] 上一次采样值/时刻，用于差分算真实下行速度。
  int _lastTotalDone = -1;
  DateTime? _lastSpeedSampleAt;

  /// 上传速度同样以差分算（原生 upload_rate 同一字段通路）。
  int _lastTotalUploaded = -1;

  int _uploadSpeed = 0;
  int get uploadSpeed => _uploadSpeed;

  int _peers = 0;
  int get peers => _peers;

  /// 节点数展示值：-1（libtorrent「未知」哨兵）→ 「未知」。
  String get peersDisplay => formatSwarmCount(_peers);

  int _seeds = 0;
  int get seeds => _seeds;

  /// 做种数展示值：-1（libtorrent「未知」哨兵）→ 「未知」。
  String get seedsDisplay => formatSwarmCount(_seeds);

  /// 流引擎上报的「真实在连节点数」（来自 [StreamInfo.activePeers]）。
  ///
  /// 与 [_peers]/[_seeds]（torrent status，原生 `lt_get_all_statuses` 的
  /// flag=0x8 未带 peer 统计位 → 恒为 -1「未知」哨兵）不同，[activePeers]
  /// 由原生 `fill_stream_status` 调 `handle.status()`（无 flag，libtorrent
  /// **无条件**计算 `num_peers`，见 libtorrent `torrent::status()` 源码）
  /// 得到，是真实在连 peer 数。用途：
  /// 1. 「正在连接 N 个节点」UX（替代冻结的速度数字）；
  /// 2. 死种判定（真·零节点 + 零下行 → 早停换源）。
  ///
  /// ⚠️ 实证待核实：2026-10-24 e2e 前未知 2.1.1 是否真的无条件填充，
  /// 故 [activePeers] 仍以 -1 兜底（见 [_isDeadSwarm]）。
  int _activePeers = 0;
  int get activePeers => _activePeers;
  String get activePeersDisplay => formatSwarmCount(_activePeers);

  /// —— 以下三个字段纯粹是**诊断快照**，不参与任何控制流 ——
  ///
  /// 为什么需要：2026-11-08 的现场里，`done` 停在 28.5MB、`activePeers` 掉到 0，
  /// 但无法判断「种子被暂停」「种子认为已下完」还是「本地流服务器不再请求」。
  /// `isPaused` / `isFinished` / `streamState` / `readHead` 正好把这四种情况
  /// 区分开，一行日志即可定案。
  String _diagTorrent = '-';
  String _diagStream = '-';
  int _diagReadHead = -1;

  /// 正在播的文件 index（供「供数停滞兜底」重新放行该文件下载优先级）。
  int _currentPlayFileIndex = -1;

  /// 供数停滞兜底：最后一次看到的 totalDone 与时刻。
  int _stallDoneSnapshot = -1;
  DateTime? _stallDoneAt;
  bool _stallLogged = false;

  /// 本次流「曾经连上过的最大节点数」：判定「是否从未连上过任何节点」用。
  /// 见 [_isDeadSwarm] 的说明（只作诊断，不触发早停）。
  int _maxActivePeers = 0;
  int get maxActivePeers => _maxActivePeers;

  /// 45s 缓冲窗口结束时**一个节点都没连上**，已被迫把空流交给 mpv。
  ///
  /// 这是「点开磁力 → 黑屏 → 什么都不说」的根因（2026-10-27 真机实测：
  /// `metaWait=48s activePeers 9→17→0 speed=0 B/s`，交接后 120s 纯黑）。
  ///
  /// 服务层刻意**不**置 error（置 error 会让 mpv 交接被当成失败、把用户弹回
  /// 详情页，见 [_waitForStreamReady] 的复盘），所以这个状态只用于让 UI
  /// **显式告诉用户「这个资源没有可用节点」**，而不是继续转圈。
  ///
  /// 🔴 用**时间戳**而不是 bool：交接之后 `stop()` / 状态复位会被调用一次
  /// （2026-10-27 真机实测：交接后 0.01s 就 `playInternal`，随后状态被清空），
  /// bool 会被顺手抹掉 —— 那样横幅永远不会出现。时间戳只在新一轮等待开始时
  /// 作废，保证「这次确实连不上」的结论能留给 UI。
  DateTime? _deadSwarmAt;

  bool get handoverWithoutPeers {
    final at = _deadSwarmAt;
    if (at == null) return false;
    // 10 分钟内有效，避免陈旧结论挂到下一次播放上。
    return DateTime.now().difference(at).inMinutes < 10;
  }

  /// 新一轮磁力尝试开始时调用：把上一轮「连不上任何节点」的结论作废。
  ///
  /// 自动重试是无限次的（用户不要按钮），如果旧结论一直挂着，UI 会整个重试
  /// 期间都显示「这个资源连不上任何节点」，反而看不出引擎还在动。
  void clearDeadSwarm() => _deadSwarmAt = null;

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

  /// 当前播放种子的 id（只读）。
  /// 旁路任务（如 S3 种子内字幕）用它判断引擎是否把同 hash 合并回播放
  /// handle，避免 `removeTorrent` 误删正在播的种子。
  int? get currentTorrentId => _currentTorrentId;
  int? _currentStreamId;

  String _torrentName = '';
  String get torrentName => _torrentName;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// 幂等守卫：单例的 dispose 可能被「应用退出路径」与「测试装配-卸载周期」
  /// 多次触碰；ChangeNotifier 重复 dispose 后再 notifyListeners 会直接抛断言。
  bool _released = false;

  StreamSubscription<Map<int, TorrentInfo>>? _torrentSub;
  StreamSubscription<Map<int, StreamInfo>>? _streamSub;

  /// 当前种子在等待元数据时已等待的秒数（用于 UI 反馈「解析较慢」）。
  int _metaWaitSeconds = 0;
  int get metaWaitSeconds => _metaWaitSeconds;

  /// 用户可见的加载阶段：0 解析元数据 / 1 缓冲头 / 2 已可播。
  int _streamStage = 0;
  int get streamStage => _streamStage;

  /// 「元数据就绪」是否已记过诊断日志（每个种子只记一次，避免刷屏）。
  bool _metaLogged = false;

  /// 「首次发现 swarm」是否已记过诊断日志（同上）。
  bool _swarmLogged = false;

  /// 精选 tracker 列表（**顺序即优先级**）。
  ///
  /// ## 🔴 2026-10-24 实测：**列表越长，起播越慢**（这条比「哪个 tracker 好」更重要）
  ///
  /// run3 真机日志（`e2e/logcat.txt`）把整条 peer 发现链路摊开了：
  /// - `addMagnet` 在 11:30:18，第一个 peer **11:30:47** 才连上（29s）；
  /// - 期间 tracker announce 是**一串**的：11:30:30 超时 → 11:30:39 超时 →
  ///   11:30:49 超时 → 11:30:59 才有一条 `received peers: 42`；
  /// - 也就是说：**最先被 announce 的那几条全是死 tracker，每条烧掉 ~10s
  ///   超时**；真正能返回 peer 的那条排在 40s 之后，等它返回时 DHT 早就
  ///   把 peer 找来了（11:30:47），它对起播没有任何贡献。
  ///
  /// 更糟的是插件默认行为：`LibtorrentFlutter.init(fetchTrackers: true)`
  /// 会去 GitHub 拉 ngosang 的 `trackers_best.txt`（约 20 条，绝大多数 UDP）
  /// 并**追加到我们列表后面** → 磁力里实际有 **26 + 20 ≈ 46 条 tracker**。
  /// 46 条串行 announce 的尾部要等 2 分钟以上，等于白占带宽与队列。
  ///
  /// 因此本版做两件事：
  /// 1. `fetchTrackers: false` —— 关掉插件的隐式追加，列表只由这里决定；
  /// 2. 列表**砍到 9 条**，且把「真机/探针实测返回过 peer」的放最前。
  ///
  /// ## 排序依据（实测，勿凭直觉改）
  /// - 受限网络（国内移动网络 / 企业网）里 HTTPS 最不可靠：曾试 9 条
  ///   `https://…:443`，8 条 DNS/握手失败、1 条 403，一条没生效 → 不用 HTTPS；
  /// - `tracker.opentrackr.org:1337` 用真实 infohash announce 返回 **35 peers**；
  /// - `qu.ax:6969` / `dler.org:6969` / `itzmx` 返回 3~7 peers；
  /// - run3 真机里 `udp://tracker.tryhackx.org:6969` 返回 **42 peers**（UDP
  ///   并非全被封，故保留 3 条 UDP 作兜底；但 UDP 首包丢失重传要 ~40s，
  ///   所以 HTTP 仍排在它前面）。
  ///
  /// 探针脚本见 `tool/tracker_probe.py`。
  static const _extraTrackers = <String>[
    // —— HTTP(TCP)：实测可达，按返回 peer 数排序（应最先 announce） ——
    'http://tracker.opentrackr.org:1337/announce', // 实测 35 peers
    'http://tracker.qu.ax:6969/announce', // 实测 7 peers
    'http://tracker.dler.org:6969/announce', // 实测 4 peers
    'http://tracker2.itzmx.com:6961/announce', // 实测 4 peers
    'http://open.tracker.cl:1337/announce', // 实测有 peer（含做种）
    'http://nyaa.tracker.wf:7777/announce', // 存活（动画资源）
    // —— UDP tracker：网络放行 UDP 时补充（实测 tryhackx 42 peers） ——
    'udp://tracker.tryhackx.org:6969/announce',
    'udp://tracker.moeking.me:6969/announce',
    'udp://open.stealth.si:80/announce',
    // —— 追加常用公开 tracker（GitHub 兜底在部分手机网拉不到时的静态安全网） ——
    'udp://open.demonii.com:1337/announce',
    'udp://tracker.leechers-paradise.org:6969/announce',
    'udp://exodus.desync.com:6969/announce',
    'http://tracker.torrent.eu.org/announce',
    'udp://tracker.torrent.eu.org:451/announce',
  ];

  /// 运行时从网络拉取的「新鲜」公开 tracker 兜底列表（ngosang trackers_best）。
  ///
  /// 🔴 为什么要它：9-11 之后我们把 [LibtorrentFlutter.init] 的 `fetchTrackers`
  /// 关了、只用写死的 [_extraTrackers]，等于押宝在 2026-10-24 的快照上——一旦
  /// 其中几条 tracker 失效，连通性直接退化（这正是「以前能播、现在不能」的
  /// 高可疑点：改动前 `fetchTrackers:true` 会自动注入实时 tracker）。
  /// 这里在 init 时 best-effort 拉一份实时列表做**兜底**：写死的优选仍排最前
  /// （保证首 announce 命中率高），拉到的实时列表追加在后扩大覆盖。拉取失败
  /// （设备网络不通 GitHub）则退回只用 [_extraTrackers]，行为等同改动前、不更差。
  static List<String> _fetchedTrackers = <String>[];
  static bool _trackerRefreshDone = false;

  /// 引擎初始化的去重 Future。
  ///
  /// 2026-10-24 实测教训：`init()` 只有 `if (_isInitialized) return;` 一道
  /// 非原子守卫时，「启动期预热」与「用户点播放」两个调用会同时穿过守卫、
  /// 双双进 `LibtorrentFlutter.init()`，其中一个必在
  /// `cacert.pem.pending → cacert.pem` 的重命名上撞
  /// `PathNotFoundException`（失败方还会顺手把状态置成 error）。
  /// 用 Future 去重后并发调用共享同一次初始化，从根上消灭该竞态。
  Future<void>? _initFuture;

  /// 初始化 P2P 引擎（幂等 + 并发去重 + 失败可重试）。
  ///
  /// - 已初始化：立即返回。
  /// - 初始化中：返回同一个 Future（并发调用方排队等同一次初始化）。
  /// - 上次失败：`_initFuture` 已清掉，本次真正重试——启动期预热失败
  ///   （如飞行模式）不该把「以后都失败」焊死，用户真播放时必须能再试。
  Future<void> init() {
    if (_isInitialized) return Future.value();
    final pending = _initFuture;
    if (pending != null) return pending;
    final future = _doInit();
    _initFuture = future;
    // _doInit 自己吞掉异常（只打日志）。失败后清掉去重标记放行重试；
    // 成功时留着无所谓——[_isInitialized] 会先短路。
    future.whenComplete(() {
      if (!_isInitialized) _initFuture = null;
    });
    return future;
  }

  Future<void> _doInit() async {
    if (_isFlutterWidgetTest()) {
      debugPrint('TorrentPlayerService: Widget 测试环境跳过 libtorrent 初始化');
      return;
    }

    try {
      await LibtorrentFlutter.init(
        // 🔴 必须 false：插件默认会拉 ngosang 的 ~20 条 tracker 并追加到磁力
        // 末尾（`TrackerManager.injectTrackers`），叠加我们自己的列表后单条
        // 磁力里会有 ~46 条 tracker。libtorrent 是逐条 announce 的，尾部
        // 那些要等 2 分钟以上，期间死 tracker 的 ~10s 超时还会堵住后面的
        // 好 tracker（run3 真机：29s 才连上第一个 peer，且最先 announce 的
        // 几条全是死链）。tracker 列表改由 [_extraTrackers] 唯一决定。
        fetchTrackers: false,
        pollInterval: const Duration(milliseconds: 500),
      );
      _engine = LibtorrentFlutter.instance;

      // 原生调试日志落盘（Android 上 logcat 常被 ROM 关闭，插件自身的 TB_LOG
      // 在 Android 又恒为空操作）。必须写「外置存储应用私有目录」，
      // 否则 release 包（不可 run-as）连 adb pull 都取不出来。
      try {
        final ext = await getExternalStorageDirectory();
        final base = ext ?? Directory.systemTemp;
        _engine.setNativeLogPath(
          '${base.path}${Platform.pathSeparator}ltbridge_native.log',
        );
      } catch (_) {}

      // 关键性能调优：在 init 之后立刻下发到原生 session。
      _engine.configureSession(_buildPerformanceConfig());

      _torrentSub = _engine.torrentUpdates.listen(_onTorrentUpdate);
      _streamSub = _engine.streamUpdates.listen(_onStreamUpdate);

      // best-effort 拉取实时 tracker 兜底（不阻塞引擎就绪；5s 超时自保护）。
      // 拉到则扩大 tracker 覆盖，拉不到则退回写死的 [_extraTrackers]。
      unawaited(_refreshFetchedTrackers());

      _isInitialized = true;
      debugPrint('TorrentPlayerService: P2P 引擎初始化 + 性能配置已下发');
      DebugLog.log('Magnet', 'P2P 引擎初始化成功', flush: true);
    } catch (e) {
      // 注意：**不置 error 态**。init 失败只意味着引擎没起来，此时用户并没
      // 在看播放器；提前置 error 会让详情页/播放器 UI 挂着一条与用户操作
      // 无关的失败文案。真正的播放入口（addMagnet / play）都会先
      // `await init()` 再查 isInitialized，失败在那里以准确的原因呈现。
      debugPrint('TorrentPlayerService: 初始化失败 - $e');
      DebugLog.log('Magnet', 'P2P 引擎初始化失败: $e', flush: true);
    }
  }

  /// 单个种子的并发 peer 上限（= 原生默认值 / TorrServer 默认）。
  ///
  /// 曾经被「优化」成 200，结果适得其反：
  /// - 会话级上限被原生成 `cfg * 20` = 4000，连接与 fd 开销失控；
  /// - 单种子扇出 200，piece 请求摊薄到几百个 peer，起播所需的头几个 piece
  ///   被最慢的 peer 队头阻塞 —— 这正是「做种数不少却迟迟起播不了」的推手。
  ///
  /// 流播放的瓶颈是「头几个 piece 的到达时间」，不是总吞吐，
  /// 少量快 peer 精喂远比大量 peer 摊薄快。
  static const int _streamConnectionsPerTorrent = 25;

  /// 会话级 BtConfig：与 TorrServer 默认对齐但拉高「流播放」相关参数。
  BtConfig _buildPerformanceConfig() {
    const mb = 1024 * 1024;
    final btCacheMb = PlaybackExperiment.intOf('bt_cache_mb');
    return BtConfig(
      // 256MB 内存 piece cache：头 30 秒下载量能完整装下，避开边读边丢。
      cacheSize: (btCacheMb ?? 256) * mb,
      // 100% read-ahead：牺牲随机读 IO 换顺序流读写命中率。
      readerReadAhead: PlaybackExperiment.intOf('reader_read_ahead_pct') ?? 100,
      // 80% 预热：startStream 那一刻就让 reader 预读 80% 缓存大小，避开冷启动。
      preloadCache: 80,
      // 单种子 peer 上限。这个值会被原生同时用在两个地方：
      //   1) handle.set_max_connections(cfg) → 单种子连接数
      //   2) sp.set_int(connections_limit, cfg * 20) → 会话级上限（torrent_bridge.cpp:2847）
      // 也就是说传 200 会让会话上限变成 4000，单种子扇出 200。
      // 原生默认值与 TorrServer 都是 25：流播放靠「少量快 peer 精喂头部 piece」，
      // 扇出过大反而被最慢的 peer 队头阻塞。见 [_streamConnectionsPerTorrent]。
      connectionsLimit: _streamConnectionsPerTorrent,
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
      // 注：不是「不限速」——之前的诊断误把原生默认值 0 当成了实际生效值。
      uploadRateLimit: PlaybackExperiment.intOf('upload_kb') ?? 4096,
      // 注意：原生层并没有真正读取 peersListenPort（torrent_bridge.cpp 里只出现在
      // 默认值与回读），监听端口实际由 listen_interfaces 决定，见下方 enableIpv6。
      peersListenPort: 0,
      // 🔴 实测（2026-10-28 真机 HONOR FNE-AN00 / 手机蜂窝 IPv4 网络）：
      // 传 true 时 libtorrent 把出站 tracker / DHT 套接字源地址绑成 IPv6 `[::]`，
      // 而手机蜂窝网通常只有 IPv4 出口、无 IPv6 默认路由 → 全部
      // "Network is unreachable" / "skipping tracker announce (unreachable)"，
      // 导致 peers=0、拿不到元数据。传 false 强制走 IPv4，出站连接用随机 IPv4
      // 临时端口（不受下方 listen_interfaces 影响），tracker/DHT 才连得上。
      //
      // 关于"关掉会硬编码 0.0.0.0:6881"的顾虑：那只决定**入站监听端口**，
      // 出站 tracker 连接始终走随机临时端口，不受 6881 影响；而 6881 入站端口对
      // 主要靠"出站连 seeder"的客户端影响有限。两害相权，IPv4 可达性优先。
      enableIpv6: false,
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

    // 上一次残留的残缺数据会让 libtorrent 反复 recheck、并把坏 piece 交给 mpv
    // （见 [_wipeTorrentDataDir] 的实测说明）。必须在 add 之前清掉。
    _wipeTorrentDataDir();

    _setState(TorrentPlayState.fetchingMeta, '');
    _metaWaitSeconds = 0;
    _streamStage = 0;
    _metaLogged = false;
    _swarmLogged = false;
    // 速度差分基线重置：上一个种子的 totalDone 不能带进新种子。
    _lastTotalDone = -1;
    _lastTotalUploaded = -1;
    _lastSpeedSampleAt = null;
    _downloadSpeed = 0;
    _uploadSpeed = 0;
    // 诊断快照 / 兜底状态随新种子复位。
    _diagTorrent = '-';
    _diagStream = '-';
    _diagReadHead = -1;
    _currentPlayFileIndex = -1;
    _stallDoneSnapshot = -1;
    _stallDoneAt = null;
    _stallLogged = false;

    try {
      final enhancedMagnet = _enhanceMagnet(magnetUri);

      // streamOnly = true：不写盘，纯流模式，省 IO 与存储。
      _currentTorrentId = _engine.addMagnet(
        enhancedMagnet,
        _resolveSavePath(),
        true,
      );
      debugPrint(
        'TorrentPlayerService: 已添加磁力链接 '
        '(tracker 总数 ${_countTrackers(enhancedMagnet)}, streamOnly=true), '
        'torrentId=$_currentTorrentId',
      );
      DebugLog.log(
        'Magnet',
        'addMagnet 成功: torrentId=$_currentTorrentId, '
        'tracker=${_countTrackers(enhancedMagnet)} 个（含补充）, '
        'btih=${_btihOf(magnetUri)}',
        flush: true,
      );

      _startMetaWaitTicker();
      _startStatsTicker();

      return true;
    } catch (e) {
      debugPrint('TorrentPlayerService: 添加磁力链接失败 - $e');
      DebugLog.log('Magnet', 'addMagnet 失败: $e', flush: true);
      _setState(TorrentPlayState.error, '添加磁力链接失败: $e');
      return false;
    }
  }

  /// 从磁力链接里取 btih（仅用于日志诊断，避免整条 magnet 刷屏）。
  static String _btihOf(String magnetUri) {
    final m = RegExp(r'btih:([a-fA-F0-9]+)').firstMatch(magnetUri);
    final h = m?.group(1);
    return h == null ? '?' : h.substring(0, h.length.clamp(0, 12));
  }

  /// 给磁力补充 tracker：**[_extraTrackers]（写死优选，排最前） + [_fetchedTrackers]
  /// （运行时拉到的实时兜底，去重后追加）**。
  ///
  /// 顺序很重要：libtorrent 逐条 announce，前面的命中率高 → 起播快；后面的
  /// 实时列表纯粹扩大覆盖、兜住「写死列表里几条失效」的情况。站点自带 `tr`
  /// 由 [buildEnhancedMagnet] 进一步挪到队尾。
  static String _enhanceMagnet(String magnetUri) {
    final merged = <String>[
      ..._extraTrackers,
      for (final t in _fetchedTrackers)
        if (!_extraTrackers.contains(t)) t,
    ];
    return buildEnhancedMagnet(magnetUri, merged);
  }

  /// best-effort 拉取实时 tracker 列表（ngosang trackers_best.txt，HTTPS，5s 超时）。
  ///
  /// 纯兜底：拉取失败 / 超时一律吞掉，绝不影响播放链路——拉不到就退回
  /// [_extraTrackers]。用 [HttpClient]（与插件同源）而非 http 包，避免额外依赖。
  static Future<void> _refreshFetchedTrackers() async {
    if (_trackerRefreshDone) return;
    _trackerRefreshDone = true;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(Uri.parse(
        'https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt',
      ));
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final list = body
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (list.isNotEmpty) {
          _fetchedTrackers = list;
          debugPrint('TorrentPlayerService: 已拉取 ${list.length} 条实时 tracker 兜底');
          DebugLog.log('Magnet', '拉取实时 tracker: ${list.length} 条', flush: true);
        }
      }
      client.close(force: true);
    } catch (e) {
      debugPrint('TorrentPlayerService: 拉取实时 tracker 失败（退回写死列表）: $e');
    }
  }

  /// 统计磁力里的 tracker 数量（仅用于日志诊断）。
  static int _countTrackers(String magnetUri) =>
      RegExp(r'[?&]tr=').allMatches(magnetUri).length;

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

  /// 加载期 1s 统计打点（tag=`Magnet`，行前缀 `stat:`）。
  ///
  /// 为什么需要：用户报「首次加载分钟级、速度个位数 KB/s 且数字不动」。
  /// 原生 download_rate 与实际吞吐脱钩（见 [_nativeDownloadRate] 注释），
  /// 必须把「差分速度 / 原生速度 / totalDone / peers / seeds / buffer」
  /// 同时打出来才能定位瓶颈在 peer 发现、元数据还是吞吐本身。
  /// 日志量：加载期每秒 1 行，起播即停，可接受。
  Timer? _statsTimer;
  int _statsTick = 0;
  void _startStatsTicker() {
    _statsTimer?.cancel();
    _statsTick = 0;
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _statsTick++;
      if (_state == TorrentPlayState.idle) {
        _stopStatsTicker();
        return;
      }
      // 起播后**不再停止**统计，只降频到 5s 一行。
      //
      // 为什么必须留着：2026-11-08 真机现场，起播后 stat 立刻停写，播放又
      // 以 ~0.02x 速度「一格一格」推进，日志里既没有下载速率也没有缓存状态，
      // 无法判断是「种子断供」还是「本地流服务器堵住」——只能靠猜。
      // 降频到 5s 后，2 小时片长也只多出 ~1400 行，完全可接受。
      if (_state == TorrentPlayState.playing && _statsTick % 5 != 0) {
        return;
      }
      // 兜底恢复：见 [playFile] 里关于「原生 metadata 暂停 alert 晚到」的说明。
      // 我们从不主动 pause 种子，所以这里 resume 一定是安全的（幂等）。
      final tid = _currentTorrentId;
      if (tid != null &&
          (_state == TorrentPlayState.buffering ||
              _state == TorrentPlayState.playing)) {
        try {
          _engine.resumeTorrent(tid);
        } catch (_) {}
      }
      DebugLog.log(
        'Magnet',
        'stat: state=${_state.name} speed=${_formatBytes(_downloadSpeed)}/s '
        'up=${_formatBytes(_uploadSpeed)}/s '
        '(native=${_formatBytes(_nativeDownloadRate)}/s) '
        'done=${_formatBytes(_lastTotalDone < 0 ? 0 : _lastTotalDone)} '
        'progress=${(_downloadProgress * 100).toStringAsFixed(1)}% '
        'peers=$_peers seeds=$_seeds activePeers=$_activePeers buf=$_bufferPct% '
        'stage=$_streamStage metaWait=${_metaWaitSeconds}s '
        '| torrent=$_diagTorrent stream=$_diagStream readHead=$_diagReadHead '
        'tid=$_currentTorrentId files=${_files.length} '
        'file=$_currentPlayFileIndex',
        flush: true,
      );
      if (_state == TorrentPlayState.playing) _logDeliveryStall();
    });
  }

  void _stopStatsTicker() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  /// 供数停滞观察（仅诊断，不改控制流）。
  ///
  /// ⚠️ 这里**故意不调 `setFilePriorities`**：`prioritize_files()` 是异步的，
  /// 会把 `startStream` 精心设好的「头部 top_priority + 紧 deadline」整体冲掉，
  /// 退回 rarest-first 随机下载 —— 实测（6086/6087）反而让 mpv 连容器都解析
  /// 不出来（`Failed to recognize file format`、`readHead` 恒 0）。
  /// 源码 `playFile` 上方那段注释警告的就是这件事，别再用它「兜底」。
  void _logDeliveryStall() {
    final done = _lastTotalDone;
    final now = DateTime.now();
    final since = _stallDoneAt;
    if (done != _stallDoneSnapshot) {
      _stallDoneSnapshot = done;
      _stallDoneAt = now;
      return;
    }
    if (since == null || now.difference(since) < const Duration(seconds: 20)) {
      return;
    }
    if (_stallLogged) return;
    _stallLogged = true;
    DebugLog.log(
      'Magnet',
      '供数停滞 20s: done=$done readHead=$_diagReadHead '
          'peers=$_activePeers buf=$_bufferPct%（仅记录，不干预调度）',
      flush: true,
    );
    // 把 libtorrent 自己的告警抖出来 —— release 下 logcat 里没有 print 输出，
    // 只有这里能看到「种子被暂停 / 文件错误 / 校验失败」这类真正原因。
    try {
      final alerts = _engine.recentAlertLines;
      final tail = alerts.length > 40
          ? alerts.sublist(alerts.length - 40)
          : alerts;
      DebugLog.log(
        'Magnet',
        'libtorrent 告警(${alerts.length} 条, 末 40): ${tail.join(' ⏎ ')}',
        flush: true,
      );
    } catch (e) {
      DebugLog.log('Magnet', '读取 libtorrent 告警失败: $e', flush: true);
    }
  }

  void fetchFiles() {
    if (_currentTorrentId == null) return;

    try {
      final rawFiles = _engine.getFiles(_currentTorrentId!);
      if (rawFiles.isEmpty) {
        _setState(TorrentPlayState.error, '未找到可播放的文件');
        DebugLog.log('Magnet', '元数据就绪但无文件', flush: true);
        return;
      }
      _applyFiles(rawFiles);
    } catch (e) {
      debugPrint('TorrentPlayerService: 获取文件列表失败 - $e');
      DebugLog.log('Magnet', '获取文件列表失败: $e', flush: true);
      _setState(TorrentPlayState.error, '获取文件列表失败: $e');
    }
  }

  /// 静默探测文件列表：元数据未就绪时 `getFiles` 返回空属于**正常状态**，不能报错。
  ///
  /// 为什么需要它：上游插件 `TorrentInfo.hasMetadata` 在部分机型/版本上会滞后甚至
  /// 恒为 false。实测（libtorrent_flutter 1.9.9 + Android 16）：原生已打印
  /// `metadata successfully received`，Dart 侧 `hasMetadata` 仍为 false →
  /// `fetchFiles()` 永远不触发 → 界面一直停在「取元数据」转圈。
  /// 但原生 `torrent_file()` 一旦元数据到达就能列出文件，
  /// 所以这里**以文件列表本身为唯一真相**，不再单信标志位。
  void _tryFetchFilesSilently() {
    if (_currentTorrentId == null) return;
    try {
      final rawFiles = _engine.getFiles(_currentTorrentId!);
      if (rawFiles.isEmpty) return;
      _applyFiles(rawFiles);
    } catch (_) {
      // 元数据尚未到达时原生可能抛错，静默等下一轮轮询。
    }
  }

  /// 把原生文件列表落到状态里（排序 + 置 ready + 只记一次日志）。
  void _applyFiles(List<FileInfo> rawFiles) {
    _files = rawFiles
        .map(
          (f) => TorrentFileItem(
            index: f.index,
            name: f.name,
            size: f.size,
            isStreamable: f.isStreamable,
          ),
        )
        .toList()
      ..sort((a, b) => b.size.compareTo(a.size));

    _setState(TorrentPlayState.ready, '');
    if (!_metaLogged) {
      _metaLogged = true;
      DebugLog.log(
        'Magnet',
        '元数据就绪: ${_files.length} 个文件, '
        '最大=${_files.first.name}(${_files.first.size}B)',
        flush: true,
      );
    }
  }

  /// 启动流并立刻把缓存策略下到位。
  ///
  /// **这里绝不能调用 `setFilePriorities`**（曾经的写法，是「有做种却播不出来」的
  /// 直接原因）。原生 `lt_start_stream` 里有明确警告：
  ///
  /// > DO NOT use prioritize_files() here! prioritize_files() is ASYNC — it
  /// > completes later and resets ALL piece priorities back to match file
  /// > priorities, undoing our careful prioritize_pieces() call below. This
  /// > race condition causes libtorrent to download random (rarest-first) pieces.
  ///
  /// 而 `lt_set_file_priorities` 内部调用的就是 `prioritize_files()`。
  /// 于是出现了竞态：我们在 startStream 前设的文件优先级，会在 startStream
  /// 调好 `prioritize_pieces()`（把「文件开头 1~5 个 piece」设为 top_priority
  /// 并挂 tight deadline）**之后**异步生效，把这些关键 piece 优先级整体重置，
  /// libtorrent 随即退回 rarest-first 随机下载 —— 文件头迟迟下不来，
  /// 缓冲永远是 0%，表现就是「明明有做种数，但死活播不出来」。
  ///
  /// 实际上 startStream 已经把所有 piece 先置为 `dont_download`，再只放行
  /// 当前文件的 head / tail，比「文件级优先级」更精确，无需我们再干预。
  Future<String?> playFile(int fileIndex) async {
    if (_currentTorrentId == null) return null;

    _setState(TorrentPlayState.buffering, '');

    try {
      // 防御：正常流程下 addMagnet() 已经 stop() 过，此处不该还有残留流。
      // 若真有，说明上一集留下了泄漏的流 —— 每个流都是一个独立的 HTTP server
      // 线程 + 256MB TorrCache，且多个流会各自 prioritize_pieces() 互相覆盖，
      // 必须清掉再起新流，否则新集拉不到数据。
      await _stopCurrentStream();

      final torrentId = _currentTorrentId;
      if (torrentId == null) {
        // 停流时把 ephemeral 种子一并移除了（见 _stopCurrentStream 注释），
        // 此时已无种子可播，与其空指针崩溃，不如明确报错让上层重新 addMagnet。
        _setState(TorrentPlayState.error, '播放流已失效，请重新选择资源');
        return null;
      }

      final streamInfo = _engine.startStream(
        torrentId,
        fileIndex: fileIndex,
        // 256MB stream cache：单个流在 4K HDR 也能稳定缓冲。
        maxCacheBytes: 256 * 1024 * 1024,
      );

      _currentStreamId = streamInfo.id;
      _streamUrl = streamInfo.url;
      _streamStage = 1; // 进入「缓冲头」阶段
      _bufferPct = 0;
      _etaSeconds = -1;
      _currentPlayFileIndex = fileIndex;
      // 新的流 = 新的供数周期，兜底状态全部复位。
      _stallDoneSnapshot = -1;
      _stallDoneAt = null;
      _stallLogged = false;

      debugPrint('TorrentPlayerService: 流已启动, url=${streamInfo.url}');
      DebugLog.log(
        'Magnet',
        'startStream 成功: fileIndex=$fileIndex, streamId=${streamInfo.id}, '
        'url=${streamInfo.url}',
        flush: true,
      );

      // 每流独立的 cache 参数：256MB 缓存 + 100% read-ahead。
      //
      // connectionsLimit 用 [_streamConnectionsPerTorrent]，不要随手放大：
      // 它会被原生成 `handle.set_max_connections()`，即**单个种子的 peer 上限**。
      // 扇出过大时，time-critical picker 把 piece 请求摊到几百个 peer 上，
      // 进度被最慢的那个拖住（队头阻塞），头几个起播 piece 反而更晚到。
      const mb = 1024 * 1024;
      final expCapMb = PlaybackExperiment.intOf('stream_cache_mb');
      final expPreloadMb = PlaybackExperiment.intOf('preload_mb');
      final expConn = PlaybackExperiment.intOf('connections');
      final expRaPct = PlaybackExperiment.intOf('stream_read_ahead_pct');
      _engine.setCacheSettings(
        _currentStreamId!,
        capacity: (expCapMb ?? 256) * mb,
        readAheadPct: expRaPct ?? 100,
        connectionsLimit: expConn ?? _streamConnectionsPerTorrent,
      );

      // 立刻把首部 64MB 拉满，mpv 切到这一帧时就能立即解码。
      _engine.preloadStream(
        _currentStreamId!,
        preloadBytes: (expPreloadMb ?? 64) * mb,
      );
      if (PlaybackExperiment.enabled) {
        DebugLog.log(
          'Experiment',
          'BT 参数 runId=${PlaybackExperiment.runId} '
              'streamCache=${expCapMb ?? 256}MB preload=${expPreloadMb ?? 64}MB '
              'conn=${expConn ?? _streamConnectionsPerTorrent} '
              'raPct=${expRaPct ?? 100} '
              'btCache=${PlaybackExperiment.intOf('bt_cache_mb') ?? 256}MB '
              'uploadKb=${PlaybackExperiment.intOf('upload_kb') ?? 4096}',
          flush: true,
        );
      }

      // 🔴 2026-11-08 真机定案（本轮根因）——原生会把 streamOnly 种子暂停。
      //
      // `torrent_bridge.cpp:1134-1153` 在 `metadata_received_alert` 里对
      // **ephemeral（streamOnly=true）** 种子执行「全文件 dont_download +
      // handle.pause()」。该 alert 由 libtorrent 告警线程异步投递，**完全可能
      // 晚于 startStream 内部的 handle.resume() 到达**，于是种子在起播后几秒
      // 被暂停：done 停在「头部刚下完的那几 MB」不再增长、num_peers 掉到 0，
      // mpv 读完头部就 EOF 定格。
      //
      // 实测证据（6083 诊断包）：11:37:35 done=5.3MB / 11:37:40 done=5.4MB 且
      // activePeers 999→0，此后 5 分钟零增长 —— 而网络直测有 1.98MB/s、WiFi
      // RSSI -49。不是死种、不是限速，就是种子被暂停了。
      //
      // 交接后显式恢复一次；统计 ticker 里每拍再兜底（resume 幂等）。
      _engine.resumeTorrent(torrentId);

      await _waitForStreamReady();

      if (_streamUrl != null && _state != TorrentPlayState.error) {
        _setState(TorrentPlayState.playing, '');
        _streamStage = 2;
        return _streamUrl;
      }

      return _streamUrl;
    } catch (e) {
      debugPrint('TorrentPlayerService: 启动流失败 - $e');
      DebugLog.log('Magnet', 'startStream 失败: fileIndex=$fileIndex, $e', flush: true);
      _setState(TorrentPlayState.error, '启动播放流失败: $e');
      return null;
    }
  }

  /// 停掉当前流（若存在）。
  ///
  /// **副作用警告**：我们用 `streamOnly=true` 添加种子，原生会把它登记为
  /// ephemeral（`torrent_bridge.cpp:2197`），而 `lt_stop_stream` 对 ephemeral
  /// 种子会连带调用 `lt_remove_torrent()`（2613–2624 行）。
  /// 也就是说：**停流的代价是种子一起被移除**，`_currentTorrentId` 随之失效。
  ///
  /// 因此这里必须把 torrentId 一并清空，否则后续 `startStream` 会拿到一个
  /// 已被删除的 id，原生返回 "torrent not found"（-1），表现为彻底播不出。
  /// 真正要复用种子切集是做不到的 —— 见 [DetailMagnetPlayback.play] 的说明。
  Future<void> _stopCurrentStream() async {
    final sid = _currentStreamId;
    if (sid == null || !_isInitialized) return;
    _currentStreamId = null;
    // 见上方注释：ephemeral 种子会随流一起被移除。
    _currentTorrentId = null;
    try {
      _engine.stopStream(sid);
      debugPrint('TorrentPlayerService: 已停止上一个流 streamId=$sid');
    } catch (e) {
      debugPrint('TorrentPlayerService: stopStream($sid) 失败 - $e');
    }
  }

  /// 诊断：本次流**是否从未连上过任何节点**（`maxActivePeers == 0`）。
  ///
  /// ⚠️ 仅用于 45s 交接时的日志文案，**不再触发 error / 中断播放**。
  ///
  /// 为什么不能再当「早停判据」：2026-10-24 真机实测，20s 时 activePeers
  /// 仍为 0（旧逻辑判死）→ 21s 立刻连上 1 个并涨到 5；run2 也是 43s 才收到
  /// 首 piece。受限网络下 peer 连接本就要 20–45s，用「当前 activePeers==0」
  /// 提前判死会误杀可恢复的弱 swarm。要区分「真死」只有等满整个缓冲窗口。
  ///
  /// 用「曾经的最大值」而非「当前值」，是为了避免中途全部断连被误判成
  /// 「从未连上」——只要连上过一次，就说明该 swarm 活着。
  bool _isDeadSwarm() => _maxActivePeers == 0;

  /// 做种/节点数展示值：-1（libtorrent「未知」哨兵）→ 「未知」（见
  /// [formatSwarmCount]，定义在 torrent_player_models.dart，双平台共用）。

  Future<void> _waitForStreamReady() async {
    // 新一轮等待开始 → 上一次「连不上节点」的结论作废。
    _deadSwarmAt = null;
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
          // ⚠️ StreamInfo.bufferPct 是 0.0–1.0 的小数（见插件 models.dart
          /// 「Backward-compatible buffer percentage (0.0–1.0)」），必须先 ×100
          /// 再转 int。曾经直接 clamp(0,100).toInt() 把 0.25 截成 0，导致
          /// 5% 就绪门永远打不开、每次必等满 45s 超时才肯起播。
          _bufferPct = (info.bufferPct * 100).clamp(0, 100).toInt();
          // 真实在连节点数（见 [activePeers] 注释），双路兜底：streamUpdates
          // 与这里的主动轮询都写，避免任一路不触发导致死种判定误伤活 swarm。
          _activePeers = info.activePeers;
          if (_activePeers > _maxActivePeers) _maxActivePeers = _activePeers;
          // 5% 缓冲就允许 mpv 起播（边下边播）
          if (info.isReady || _bufferPct >= 5) {
            _deadSwarmAt = null;
            debugPrint(
              'TorrentPlayerService: 流已就绪, buffer=${_bufferPct}% (elapsed=${elapsed.inSeconds}s)',
            );
            DebugLog.log(
              'Magnet',
              '流已就绪: buffer=$_bufferPct%, elapsed=${elapsed.inSeconds}s, '
              'seeds=$_seeds, peers=$_peers, speed=$_downloadSpeed',
              flush: true,
            );
            return;
          }
        }
      }

      // 【已移除：基于节点数的死种早停】
      //
      // 2026-10-24 真机实测**证伪**了「activePeers==0 就该提前判死」：
      // 受限网络下 peer 连接要 20–45s 才完成——本次实测 20s 时 activePeers
      // 仍为 0（旧逻辑在此判死并置 error），**仅 1 秒后**就变成 1 并一路涨到
      // 5；run2 同样是 43s 才收到首个 piece。提前判死会误杀**可恢复的弱
      // swarm**，且 error 态让播放器不交接、用户被留在详情页（本次 t45s
      // 截图实锤：等 20s 后回详情页，正是最差观感）。
      //
      // 现策略：
      // 1. 不提前判死；等待期由 UI 用真实 [activePeers] 显示「连接中… /
      //    节点 N」，用户能看见到底连上没有（不再是黑盒转圈）。
      // 2. 45s 仍未缓冲则把 URL 交接给 mpv 自行等待首 piece；死种最终由
      //    mpv 侧 read_piece 超时报错呈现（有界，不会永久转圈）。
      // 3. [_isDeadSwarm] 降级为「45s 交接时的诊断文案」——只回答「是否
      //    从未连上过任何节点」，不再触发 error / 中断播放。
      await Future<void>.delayed(checkInterval);
      elapsed += checkInterval;
    }

    // 曾经这里只要拿到 URL 就「尝试播放」，哪怕一个字节都没缓冲到。
    // mpv 打开一个空流只会卡在 0 秒不动，界面上就是永远转圈、看不出原因。
    if (_streamUrl != null && _bufferPct > 0) {
      debugPrint('TorrentPlayerService: 流就绪超时，尝试播放（已缓冲 $_bufferPct%）');
      return;
    }

    // 45s 仍零缓冲：**不置 error 态，直接把 URL 交出去让 mpv 起播**。
    //
    // 2026-10-24 真机实测（run2）：45s 到点置 error + 交接 URL 的组合下，
    // mpv 在 53s（首个 piece 真正到达）打开流成功，播放器却在数据到达的
    // 瞬间被拆掉，用户被弹回详情页 —— 这就是「分钟级加载还失败」的观感来源。
    // error 态会让随后的 mpv 交接被 UI 当成失败处理，宁可晚播也不能假失败。
    //
    // 不再有任何「提前判死」：死种与弱种统一交给 mpv 侧兜底——插件
    // serve_range 的 read_piece 10s 超时会关闭连接，mpv 随即报错，由播放器
    // 错误 UI 呈现（有界，不会永久转圈）。[_isDeadSwarm] 只用于下面的诊断
    // 日志（本次是否从未连上过任何节点），不改变控制流。
    debugPrint('TorrentPlayerService: 流就绪超时，交接 URL 由 mpv 自行等待首 piece');
    // 交接时为「从未连上过任何节点」→ 让 UI 明说原因，而不是让用户对着黑屏猜。
    _deadSwarmAt = _isDeadSwarm() ? DateTime.now() : null;
    DebugLog.log(
      'Magnet',
      '缓冲超时但仍交接: seeds=$_seeds peers=$_peers '
      'activePeers=$_activePeers maxActivePeers=$_maxActivePeers '
      'speed=$_downloadSpeed B/s buffer=$_bufferPct% '
      'neverConnected=${_isDeadSwarm()}',
      flush: true,
    );
  }

  void _onTorrentUpdate(Map<int, TorrentInfo> torrents) {
    if (_currentTorrentId == null || !torrents.containsKey(_currentTorrentId)) {
      return;
    }

    final t = torrents[_currentTorrentId!]!;

    if (t.name.isNotEmpty && _torrentName.isEmpty) {
      _torrentName = t.name;
      DebugLog.log('Magnet', '种子名: ${t.name}', flush: true);
    }

    _downloadProgress = t.progress;
    _nativeDownloadRate = t.downloadRate;
    _diagTorrent =
        'state=${t.state.name},paused=${t.isPaused},finished=${t.isFinished}';
    // 真的开始下数据了 → 之前的「没有可用节点」提示自动撤销。
    if (_deadSwarmAt != null && (t.progress > 0 || t.totalDone > 0)) {
      _deadSwarmAt = null;
    }
    // 真实下行速度一律用 totalDone 差分算，不信原生 download_rate——
    // 真机实测该字段与实际吞吐脱钩（piece 连续完成却只报个位数 B/s），
    // UI 速度 chip 会「数字不动」，用户观感即「卡死」。
    final now = DateTime.now();
    if (_lastTotalDone >= 0 && _lastSpeedSampleAt != null) {
      final dtMs = now.difference(_lastSpeedSampleAt!).inMilliseconds;
      if (dtMs >= 300) {
        final doneDelta = t.totalDone - _lastTotalDone;
        if (doneDelta > 0) {
          _downloadSpeed = (doneDelta * 1000 / dtMs).round();
        } else if (dtMs >= 1000) {
          // 1s 以上零增长才判 0，避免轮询抖动把速度闪成 0。
          _downloadSpeed = 0;
        }
        final upDelta = t.totalUploaded - _lastTotalUploaded;
        if (upDelta > 0) {
          _uploadSpeed = (upDelta * 1000 / dtMs).round();
        } else if (dtMs >= 1000) {
          _uploadSpeed = 0;
        }
        _lastTotalDone = t.totalDone;
        _lastTotalUploaded = t.totalUploaded;
        _lastSpeedSampleAt = now;
      }
    } else {
      _lastTotalDone = t.totalDone;
      _lastTotalUploaded = t.totalUploaded;
      _lastSpeedSampleAt = now;
    }
    _peers = t.numPeers;
    _seeds = t.numSeeds;
    _totalSize = t.totalWanted;

    // 首次拿到真实在连节点时记一笔（之后每次更新都记会刷爆日志）。
    // 「元数据 2 分钟拿不到」与「连上一个 peer 都没有」是两类完全不同的故障：
    // 前者多半是 UDP/DHT 被网络封杀，后者是资源本身已死。
    // 注意：torrent status 的 numPeers/numSeeds 恒为 -1（查询未带统计位），
    // 这里改用流状态的真实 activePeers（libtorrent 无条件计算）。
    if (!_swarmLogged && _activePeers > 0) {
      _swarmLogged = true;
      DebugLog.log(
        'Magnet',
        '首次发现 swarm: activePeers=$_activePeers, '
        'progress=${(t.progress * 100).toStringAsFixed(1)}%',
        flush: true,
      );
    }

    if (t.hasMetadata) {
      _stopMetaWaitTicker();
    }

    if (t.state.label == 'Error') {
      _stopMetaWaitTicker();
      DebugLog.log('Magnet', '种子状态 Error: name=${t.name}', flush: true);
      _setState(TorrentPlayState.error, '下载出错');
      return;
    }

    // 不只信 `status.hasMetadata`（原因见 `_tryFetchFilesSilently`）：
    // 有明确标志时走会报错的正式路径，否则静默探测文件列表，拿到就进 ready。
    if (_state == TorrentPlayState.fetchingMeta && _files.isEmpty) {
      if (t.hasMetadata) {
        fetchFiles();
      } else {
        _tryFetchFilesSilently();
      }
    }

    notifyListeners();
  }

  void _onStreamUpdate(Map<int, StreamInfo> streams) {
    if (_currentStreamId == null || !streams.containsKey(_currentStreamId)) {
      return;
    }

    final s = streams[_currentStreamId];
    if (s == null) return;

    // 同 _waitForStreamReady：bufferPct 是 0.0–1.0 小数，×100 才是百分比。
    _bufferPct = (s.bufferPct * 100).clamp(0, 100).toInt();
    // 真实在连节点数（见 [activePeers] 注释）：torrent status 的 peers/seeds
    // 因查询未带 peer 统计位恒为 -1，这里才是 libtorrent 无条件算出的真值。
    _activePeers = s.activePeers;
    if (_activePeers > _maxActivePeers) _maxActivePeers = _activePeers;
    _diagStream = s.streamState.name;
    _diagReadHead = s.readHead;
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
    _stopStatsTicker();
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
      DebugLog.log('Magnet', 'stop 出错: $e', flush: true);
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
    _activePeers = 0;
    _maxActivePeers = 0;
    _bufferPct = 0;
    _etaSeconds = -1;
    _streamStage = 0;
    _metaWaitSeconds = 0;
    _metaLogged = false;
    _swarmLogged = false;
    _setState(TorrentPlayState.idle, '');
  }

  @override
  Future<void> dispose() async {
    // 幂等：第二次起直接空转。单例跨测试共享，app 卸载与测试析构
    // 可能先后调用；重复走 stop() → notifyListeners() 会抛
    // debugAssertNotDisposed（ChangeNotifier 已死）。
    if (_released) return;
    _released = true;
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
    // 放行后续 init：dispose 后（测试装配-卸载周期 / 引擎重建）允许重新初始化，
    // 否则 _initFuture 里悬着一个已失效的 Future，新 init() 会直接拿到它空转。
    _initFuture = null;
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

  /// 清空磁力数据目录（每次起播前调用）。
  ///
  /// 🔴 2026-11-08 真机定案 —— 这是「磁力起播十几秒就定格」的最后一块拼图。
  ///
  /// 本服务固定用 `<systemTemp>/movie_app_torrent` 当保存目录，而 `streamOnly`
  /// 断流时**不会删数据**。反复起播同一条磁力后，目录里留下上一次被强杀时
  /// 写了一半的稀疏文件，于是每次 add 都出现：
  ///   1. libtorrent 进入 `checking_files` 校验（stat 里该状态长期不消失），
  ///      **校验期间不能下载** → `done` 卡在十几 MB 不动；
  ///   2. 校验把「残缺 piece」也标成已有 → `read_piece` 直接把这些字节交给
  ///      mpv → 容器解析失败（`Failed to recognize file format`），或者
  ///      头几个 piece 恰好完整、播到 ~11s 就 EOF 定格。
  ///
  /// 这两条现象在 6083~6086 四个包里全部复现过。磁力本来就是从头播，没有
  /// 跨会话续传的价值，每次起播前清干净最稳，顺带解决临时目录无限增长。
  void _wipeTorrentDataDir() {
    try {
      final dir = Directory(_resolveSavePath());
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
        DebugLog.log(
          'Magnet',
          '已清空种子数据目录（避免 recheck / 残缺 piece 污染）',
          flush: true,
        );
      }
    } catch (e) {
      DebugLog.log('Magnet', '清空种子数据目录失败（忽略）: $e', flush: true);
    }
  }

  void _setState(TorrentPlayState state, String error) {
    if (_released) return; // 已释放：不再通知（notifyListeners 对已死的
    // ChangeNotifier 会抛断言；且此时无人在听）。
    _state = state;
    _errorMessage = error;
    notifyListeners();
  }
}
