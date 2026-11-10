/// 磁力资源「有没有中文字幕」的真实探测。
///
/// 与旧的标题关键词判定（`subtitle_availability_policy.dart`）的区别：
/// 那个只看发布名，名字里没写字幕就输出「未标注」，用户无法据此决策。
///
/// 🔴 2026-11-08 真机定案（分两层，别再合并回去）：
/// - **fast（列表自动）**：addMagnet → 等元数据 → 只看文件清单，
///   **绝不 startStream、绝不读任何视频字节**。实测元数据 6~12s 就能拿到。
/// - **deep（用户点徽标）**：在 fast 之上再读 MKV 文件头 2MB / 外挂字幕正文，
///   低频、播放中一律拒绝。
///
/// 为什么必须分：真机日志 `serve_range: piece=0 not ready ... lt_have=0 done=0MB`，
/// 5s/10s/15s 后 ABORT —— 刚 add 的种子在超时窗口内根本下不到文件头那 2MB。
/// 旧版让列表里几十条自动探测都去读头，结果是①全部降级「字幕未知」，
/// ②几十个种子同时挂在 libtorrent session 里，把播放首段缓冲拖到几分钟。
///
/// 约束：
/// - 播放磁力时**任何**探测都不放行（抢 peer 会把播放拖卡）；
/// - 自动探测排队受配额约束，用户主动请求不受配额；
/// - 结束必定 `stopStream` + `removeTorrent`；
/// - 结果按 info-hash 缓存，deep 结论不会被后来的 fast 结论覆盖。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../debug_log.dart';
import '../../pages/detail/playback/subtitle_format_policy.dart';
import '../storage_service.dart';
import '../subtitle_service.dart';
import '../torrent_player_service.dart';
import 'mkv_track_parser.dart';
import 'subtitle_probe_verdict.dart';

class TorrentSubtitleProbeService {
  TorrentSubtitleProbeService._();

  static final TorrentSubtitleProbeService instance =
      TorrentSubtitleProbeService._();

  /// 读文件头时最多取这么多字节（仅 deep）。MKV 的 Tracks 元素几乎总在首个 1 MB 内。
  static const int _headBytes = 2 * 1024 * 1024;

  /// 外挂字幕正文只取前 8KB 判 CJK（仅 deep）。
  static const int _subtitleTextBytes = 8 * 1024;

  /// 等元数据的上限。有 peer 时实测 2~12s 就能拿到，拿不到的多半是死种。
  static const Duration _metaTimeout = Duration(seconds: 12);

  /// 等文件头数据的上限（仅 deep，用户主动发起时才等得起）。
  static const Duration _headTimeout = Duration(seconds: 30);

  /// 自动探测的排队上限（含正在跑的）。
  ///
  /// 搜索页是 Column 一次性渲染全部条目（实测一次 56 条），不加上限就会
  /// 同时 add 几十个种子。超过配额的条目直接给「字幕未知」，用户仍可点徽标
  /// 单独深挖；配额随任务完成释放，滚动到后面的条目还能继续自动探测。
  static const int _maxAutoPending = 12;

  /// 缓存键前缀。判定逻辑有实质变更时必须升版本，否则旧结论会一直盖住新逻辑。
  /// v2：外挂字幕必须带语言标记才算中文（v1 把任意 .srt 都算成中文）。
  /// v3：chs/cht + TrackName 参与简繁判定、PGS 也判简繁、外挂字幕可读正文 CJK。
  /// v4：拆分 fast/deep、列表不再读视频字节、结论带深度。
  static const String _storagePrefix = 'subtitle_probe_v4_';

  final Map<String, SubtitleProbeResult> _cache = {};

  /// hash → 正在跑的探测任务。同一资源被多个徽标同时请求时共用同一个 Future。
  final Map<String, Future<SubtitleProbeResult>> _jobs = {};

  /// 排队中的任务（并发闸门）。
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  int _active = 0;
  int _autoPending = 0;
  bool _playbackActive = false;

  bool get _playbackNow => TorrentPlayerService().currentTorrentId != null;

  /// 探测并发上限。播放中自动/主动探测都已停止，这里留 1 是给边界兜底。
  int get _maxConcurrent => _playbackActive ? 1 : 3;

  /// 每次有机会都同步播放状态；**开始播放时立刻清空排队**，
  /// 让还没 add 种子的任务不再占用连接。
  void _syncPlayback() {
    final now = _playbackNow;
    if (now == _playbackActive) return;
    _playbackActive = now;
    if (now) {
      DebugLog.log('SubtitleProbe', '检测到开始播放，清空探测等待队列', flush: true);
      while (_waiters.isNotEmpty) {
        final w = _waiters.removeFirst();
        if (!w.isCompleted) w.complete();
      }
    }
  }

  /// 返回 false 表示「排队期间开始播放，本次探测取消」。
  Future<bool> _acquire() async {
    while (true) {
      _syncPlayback();
      if (_playbackActive) return false;
      if (_active < _maxConcurrent) {
        _active++;
        return true;
      }
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
  }

  void _release() {
    if (_active > 0) _active--;
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeFirst();
      if (!next.isCompleted) next.complete();
    }
  }

  /// 取缓存结果（不触发探测）。同步，可直接在 build 里调用。
  SubtitleProbeResult? cached(String magnetUri) {
    final key = infoHashOf(magnetUri);
    if (key == null) return null;
    final mem = _cache[key];
    if (mem != null) return mem;

    try {
      final raw = StorageService().getSetting('$_storagePrefix$key');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final result = _decodeResult(decoded);
      _cache[key] = result;
      return result;
    } catch (_) {
      return null;
    }
  }

  /// 触发一次探测。
  ///
  /// [deep] = 用户主动点徽标，会额外读 MKV 文件头 / 外挂字幕正文；
  /// 默认 false 是列表自动走的快速层，只看元数据 + 文件清单。
  /// [order] 只用于日志排序定位，不参与判定。
  Future<SubtitleProbeResult> probe(
    String magnetUri, {
    bool deep = false,
    int order = 0,
  }) {
    final key = infoHashOf(magnetUri);
    if (key == null) {
      return Future.value(
        const SubtitleProbeResult(
          verdict: SubtitleProbeVerdict.unknown,
          reason: '磁力链接里没有 info-hash',
        ),
      );
    }

    final tag = '[${key.substring(0, 8)}]';
    final hit = cached(magnetUri);
    if (hit != null) {
      // 快速层已经有明确结论时不需要再深挖；深挖过的结论也不重跑。
      if (!deep || hit.depth == SubtitleProbeDepth.deep || hit.hasChinese) {
        DebugLog.log(
          'SubtitleProbe',
          '$tag 命中缓存 ${hit.verdict.name}/${hit.depth.name} deep=$deep',
          flush: true,
        );
        return Future.value(hit);
      }
    }

    final running = _jobs[key];
    if (running != null) {
      DebugLog.log(
        'SubtitleProbe',
        '$tag 复用进行中的任务 deep=$deep',
        flush: true,
      );
      return running;
    }

    _syncPlayback();
    final admission = admitProbe(
      playbackActive: _playbackActive,
      userInitiated: deep,
      pending: _autoPending,
      maxPending: _maxAutoPending,
    );
    if (admission != ProbeAdmission.run) {
      // 🔴 不缓存：播放结束 / 配额释放后，同一条资源还能重新自动探测。
      final reason = admission == ProbeAdmission.skipPlayback
          ? '正在播放磁力，已暂停字幕探测'
          : '自动探测已达上限，点击徽标可单独检测';
      DebugLog.log(
        'SubtitleProbe',
        '$tag 探测被拒 ${admission.name} deep=$deep pending=$_autoPending',
        flush: true,
      );
      return Future.value(
        SubtitleProbeResult(
          verdict: SubtitleProbeVerdict.unknown,
          reason: reason,
          // 临时结论（没真的去探测过），允许用户之后点徽标重试。
          depth: SubtitleProbeDepth.fast,
        ),
      );
    }

    DebugLog.log(
      'SubtitleProbe',
      '$tag 放行 ${deep ? "深挖" : "快速"} order=$order pending=$_autoPending',
      flush: true,
    );
    final isAuto = !deep;
    if (isAuto) _autoPending++;
    final job = _run(magnetUri, key, deep, order, isAuto);
    _jobs[key] = job;
    job.whenComplete(() => _jobs.remove(key));
    return job;
  }

  Future<SubtitleProbeResult> _run(
    String magnetUri,
    String key,
    bool deep,
    int order,
    bool isAuto,
  ) async {
    final acquired = await _acquire();
    if (!acquired) {
      if (isAuto && _autoPending > 0) _autoPending--;
      return const SubtitleProbeResult(
        verdict: SubtitleProbeVerdict.unknown,
        reason: '开始播放，已取消字幕探测',
        depth: SubtitleProbeDepth.fast,
      );
    }
    try {
      // 🔴 总超时兜底：原生 addMagnet / startStream 是同步 FFI，一旦被引擎锁
      // 卡住就不受 Dart 超时控制。没有这层保护，闸门会被永久占住。
      final budget = deep ? 60 : 25;
      final result = await _probeInternal(
        magnetUri,
        key,
        deep: deep,
        order: order,
      ).timeout(
        Duration(seconds: budget),
        onTimeout: () {
          DebugLog.log(
            'SubtitleProbe',
            '[${key.substring(0, 8)}] ${deep ? "深挖" : "快速"}整体超时 ${budget}s',
            flush: true,
          );
          return const SubtitleProbeResult(
            verdict: SubtitleProbeVerdict.unknown,
            reason: '探测超时',
          );
        },
      );
      final tagged = result.copyWith(
        depth: deep ? SubtitleProbeDepth.deep : SubtitleProbeDepth.fast,
      );
      // deep 结论不能被后来的 fast 结论降级。
      final existing = _cache[key];
      if (existing == null ||
          existing.depth != SubtitleProbeDepth.deep ||
          tagged.depth == SubtitleProbeDepth.deep) {
        _cache[key] = tagged;
        _persist(key, tagged);
      }
      return tagged;
    } catch (e) {
      DebugLog.log(
        'SubtitleProbe',
        '[${key.substring(0, 8)}] 探测异常: $e',
        flush: true,
      );
      return const SubtitleProbeResult(
        verdict: SubtitleProbeVerdict.unknown,
        reason: '探测异常，可点击徽标重试',
        depth: SubtitleProbeDepth.fast,
      );
    } finally {
      _release();
      if (isAuto && _autoPending > 0) _autoPending--;
    }
  }

  /// 从磁力链接取 40 位 info-hash（小写）。取不到返回 null。
  static String? infoHashOf(String magnetUri) {
    final hex = RegExp(r'btih:([a-fA-F0-9]{40})').firstMatch(magnetUri);
    if (hex != null) return hex.group(1)!.toLowerCase();

    // base32（32 位）也支持，转 hex 太麻烦，直接用原串做缓存键。
    final b32 = RegExp(r'btih:([A-Za-z2-7]{32})').firstMatch(magnetUri);
    return b32?.group(1)?.toLowerCase();
  }

  /// 与播放/字幕服务同一套 HTTP tracker。
  ///
  /// 🔴 实测环境里 **UDP tracker 全部超时，只有 HTTP/HTTPS 能拿到 peer**。
  /// 探测只拉元数据，tracker 命中率直接决定成败，所以必须补这一批。
  static const List<String> _probeTrackers = <String>[
    'http://tracker.opentrackr.org:1337/announce',
    'http://tracker.qu.ax:6969/announce',
    'http://tracker.dler.org:6969/announce',
    'http://tracker2.itzmx.com:6961/announce',
    'http://open.tracker.cl:1337/announce',
    'http://nyaa.tracker.wf:7777/announce',
  ];

  Future<SubtitleProbeResult> _probeInternal(
    String magnetUri,
    String key, {
    required bool deep,
    required int order,
  }) async {
    // 引擎是全局单例，若用户还没播放过就不会被初始化。init() 幂等且正在
    // 播放时是 no-op，所以这里直接调是安全的。
    await TorrentPlayerService().init();

    final engine = LibtorrentFlutter.instance;
    final sw = Stopwatch()..start();
    final tag = '[${key.substring(0, 8)}#$order]';
    DebugLog.log(
      'SubtitleProbe',
      '$tag 开始${deep ? "深挖" : "快速"}探测',
      flush: true,
    );

    int? tid;
    int? sid;

    try {
      final saveDir = await getTemporaryDirectory();
      final savePath = '${saveDir.path}/subtitle_probe';
      // 🔴 目录必须先建出来。原生 add_torrent 拿到一个不存在的 save_path
      // 会卡在内部而不是立刻报错（真机实测：整条探测队列被堵死）。
      final dir = Directory(savePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final enhanced = buildEnhancedMagnet(magnetUri, _probeTrackers);

      DebugLog.log('SubtitleProbe', '$tag 调用 addMagnet…', flush: true);
      final id = engine.addMagnet(enhanced, savePath, true);
      DebugLog.log('SubtitleProbe', '$tag addMagnet 返回 id=$id', flush: true);
      if (id < 0) {
        return const SubtitleProbeResult(
          verdict: SubtitleProbeVerdict.unknown,
          reason: '添加种子失败',
        );
      }

      // 🔴 引擎对同 info-hash 会复用同一个 handle。若这条就是正在播的种子，
      // **绝不能 removeTorrent**。此时直接读它的现有文件列表给结论。
      if (id == TorrentPlayerService().currentTorrentId) {
        DebugLog.log(
          'SubtitleProbe',
          '$tag 命中正在播放的种子，只做清单判定',
          flush: true,
        );
        final existing = engine.getFiles(id);
        if (existing.isEmpty) {
          return const SubtitleProbeResult(
            verdict: SubtitleProbeVerdict.unknown,
            reason: '资源正在播放，暂未取到文件列表',
          );
        }
        return judgeSubtitle(
          files: existing
              .map((f) => ProbeFile(path: f.name, size: f.size))
              .toList(growable: false),
          fileListOnly: true,
        );
      }

      tid = id;

      // ---- 1. 等元数据（fast 和 deep 共有，不读任何视频数据）----
      List<FileInfo> files = const [];
      while (sw.elapsed < _metaTimeout) {
        try {
          final raw = engine.getFiles(tid);
          if (raw.isNotEmpty) {
            files = raw;
            break;
          }
        } catch (_) {
          // 元数据未到时原生可能抛错，继续等。
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }

      if (files.isEmpty) {
        DebugLog.log(
          'SubtitleProbe',
          '$tag 元数据超时 ${sw.elapsedMilliseconds}ms（无 peer 或死种）',
          flush: true,
        );
        return const SubtitleProbeResult(
          verdict: SubtitleProbeVerdict.unknown,
          reason: '没连上节点拿到种子信息',
        );
      }

      final probeFiles = files
          .map((f) => ProbeFile(path: f.name, size: f.size))
          .toList(growable: false);
      DebugLog.log(
        'SubtitleProbe',
        '$tag 元数据就绪 ${sw.elapsedMilliseconds}ms，${probeFiles.length} 个文件：'
            '${probeFiles.map((f) => '${f.path}(${f.size}B)').join(' | ')}',
        flush: true,
      );

      // ---- 2. 文件清单判定 ----
      // 🔴 fileListOnly=true 时绝不写「未读到文件头」这种零证据结论：
      // 快速层压根没去读，只能说「可能有内封轨」。
      final quick = judgeSubtitle(
        files: probeFiles,
        fileListOnly: !deep,
      );
      DebugLog.log(
        'SubtitleProbe',
        '$tag 文件清单判定 ${quick.verdict.name}: ${quick.reason}',
        flush: true,
      );
      if (quick.verdict != SubtitleProbeVerdict.unknown) return quick;

      // 🔴 快速层到此为止。读正文 / 读文件头都要新建流、下 piece 0，
      // 真机实测一条都没成功过，还会把播放拖卡。只留给用户主动深挖。
      if (!deep) return quick;

      // ---- 3. deep：外挂字幕正文 CJK 实证 ----
      if (quick.isExternal) {
        final textVerdict = await _probeExternalText(engine, tid, files);
        DebugLog.log(
          'SubtitleProbe',
          '$tag 外挂字幕正文判定: $textVerdict',
          flush: true,
        );
        if (textVerdict == null) return quick;
        final judged = judgeSubtitle(
          files: probeFiles,
          externalTextIsChinese: textVerdict,
        );
        DebugLog.log(
          'SubtitleProbe',
          '$tag 正文判定结果 ${judged.verdict.name}: ${judged.reason}',
          flush: true,
        );
        return judged;
      }

      // ---- 4. deep：单 MKV 读文件头判内封轨 ----
      final videos = probeFiles
          .where((f) => _isVideo(f.path))
          .toList(growable: false);
      if (videos.length != 1) {
        DebugLog.log(
          'SubtitleProbe',
          '$tag 视频文件 ${videos.length} 个，不读头',
          flush: true,
        );
        return quick;
      }

      final video = videos.first;
      if (!video.lowerPath.endsWith('.mkv')) {
        DebugLog.log(
          'SubtitleProbe',
          '$tag 不是 MKV（${video.path}）',
          flush: true,
        );
        return quick;
      }

      final fileInfo = files.firstWhere(
        (f) => f.name == video.path,
        orElse: () => files.first,
      );

      final headSw = Stopwatch()..start();
      final streamInfo = engine.startStream(
        tid,
        fileIndex: fileInfo.index,
        maxCacheBytes: 8 * 1024 * 1024,
      );
      sid = streamInfo.id;
      try {
        engine.preloadStream(sid, preloadBytes: _headBytes);
      } catch (_) {}

      final head = await _readHead(streamInfo.url, _headBytes, _headTimeout);
      DebugLog.log(
        'SubtitleProbe',
        '$tag 读文件头 ${head.length}B / ${headSw.elapsedMilliseconds}ms',
        flush: true,
      );
      if (head.length < 64) {
        return const SubtitleProbeResult(
          verdict: SubtitleProbeVerdict.unknown,
          reason: '没读到文件头数据（种子首块未下载到）',
        );
      }

      final tracks = parseMkvTracks(Uint8List.fromList(head));
      DebugLog.log(
        'SubtitleProbe',
        '$tag 轨道解析: found=${tracks.foundTracksElement} '
            '共${tracks.tracks.length}条 字幕${tracks.subtitleTracks.length}条 '
            '${tracks.tracks.join(" ")}',
        flush: true,
      );

      final result = judgeSubtitle(files: probeFiles, mkvTracks: tracks);
      DebugLog.log(
        'SubtitleProbe',
        '$tag 判定 ${result.verdict.name}: ${result.reason}',
        flush: true,
      );
      return result;
    } catch (e) {
      DebugLog.log('SubtitleProbe', '$tag 探测失败: $e', flush: true);
      return const SubtitleProbeResult(
        verdict: SubtitleProbeVerdict.unknown,
        reason: '探测过程出错',
      );
    } finally {
      // 清理顺序：先停流再删种。原生对「仍有活跃流绑定的种子」会拒绝删除。
      try {
        if (sid != null) engine.stopStream(sid);
      } catch (_) {}
      try {
        if (tid != null && tid >= 0) engine.removeTorrent(tid);
      } catch (_) {}
    }
  }

  /// 外挂字幕文件名没标语言时，读正文前 8KB 用 CJK 实证判是不是中文（仅 deep）。
  ///
  /// 返回 `true` = 至少一个候选含中文；`false` = 候选都读到且都不含中文；
  /// `null` = 一个都没读到，**不能下结论**，由外层保持「字幕未知」。
  Future<bool?> _probeExternalText(
    LibtorrentFlutter engine,
    int tid,
    List<FileInfo> files,
  ) async {
    final candidates = files
        .where((f) => _isTextSubtitlePath(f.name))
        .take(2)
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    var judgedAny = false;
    for (final f in candidates) {
      int? sid;
      try {
        final info = engine.startStream(
          tid,
          fileIndex: f.index,
          maxCacheBytes: 1024 * 1024,
        );
        sid = info.id;
        try {
          engine.preloadStream(sid, preloadBytes: _subtitleTextBytes);
        } catch (_) {}
        final bytes = await _readHead(
          info.url,
          _subtitleTextBytes,
          const Duration(seconds: 8),
        );
        if (bytes.length < 32) continue;
        final text = decodeSubtitleBytes(bytes).text;
        // 🔴 GBK/BIG5 拿不到可信文本时不下「非中文」结论，继续下一个候选。
        if (text == null) continue;
        judgedAny = true;
        if (subtitleTextHasChinese(text)) return true;
      } catch (e) {
        DebugLog.log('SubtitleProbe', '读外挂字幕正文失败: $e', flush: true);
      } finally {
        // 每个候选读完立刻停流，否则同一种子上会挂多个活跃流，
        // removeTorrent 会被原生拒绝。
        if (sid != null) {
          try {
            engine.stopStream(sid);
          } catch (_) {}
        }
      }
    }
    return judgedAny ? false : null;
  }

  static bool _isTextSubtitlePath(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.srt') ||
        p.endsWith('.ass') ||
        p.endsWith('.ssa') ||
        p.endsWith('.vtt');
  }

  /// 用 HTTP Range 只取文件开头 [bytes] 字节。
  ///
  /// 外层再套一层总超时：`Stream.timeout` 只在「两个事件之间」计时，若服务器
  /// 一直挂着不响应头，光靠它不足以脱身。
  Future<List<int>> _readHead(String url, int bytes, Duration timeout) {
    return _readHeadInner(url, bytes, timeout).timeout(
      timeout + const Duration(seconds: 3),
      onTimeout: () => <int>[],
    );
  }

  Future<List<int>> _readHeadInner(
    String url,
    int bytes,
    Duration timeout,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-${bytes - 1}');
      final res = await req.close().timeout(timeout);

      final out = <int>[];
      await for (final chunk in res.timeout(timeout)) {
        out.addAll(chunk);
        if (out.length >= bytes) break;
      }
      return out.length > bytes ? out.sublist(0, bytes) : out;
    } finally {
      client.close(force: true);
    }
  }

  static bool _isVideo(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.mkv') ||
        p.endsWith('.mp4') ||
        p.endsWith('.avi') ||
        p.endsWith('.ts') ||
        p.endsWith('.m2ts') ||
        p.endsWith('.mov') ||
        p.endsWith('.webm');
  }

  void _persist(String key, SubtitleProbeResult result) {
    try {
      StorageService().saveSetting(
        '$_storagePrefix$key',
        jsonEncode(_encodeResult(result)),
      );
    } catch (_) {
      // 缓存写失败不影响本次结果。
    }
  }

  Map<String, Object?> _encodeResult(SubtitleProbeResult r) => {
        'v': r.verdict.name,
        'r': r.reason,
        'e': r.isExternal,
        's': r.isSimplified,
        't': r.isTraditional,
        'src': r.source.name,
        'd': r.depth.name,
      };

  SubtitleProbeResult _decodeResult(Map<dynamic, dynamic> map) {
    final verdictName = map['v'] as String? ?? '';
    final verdict = SubtitleProbeVerdict.values.firstWhere(
      (v) => v.name == verdictName,
      orElse: () => SubtitleProbeVerdict.unknown,
    );
    final sourceName = map['src'] as String? ?? '';
    final source = SubtitleProbeSource.values.firstWhere(
      (v) => v.name == sourceName,
      orElse: () => SubtitleProbeSource.none,
    );
    final depthName = map['d'] as String? ?? '';
    final depth = SubtitleProbeDepth.values.firstWhere(
      (v) => v.name == depthName,
      orElse: () => SubtitleProbeDepth.fast,
    );
    return SubtitleProbeResult(
      verdict: verdict,
      reason: map['r'] as String? ?? '',
      isExternal: map['e'] == true,
      isSimplified: map['s'] == true,
      isTraditional: map['t'] == true,
      source: source,
      depth: depth,
    );
  }
}
