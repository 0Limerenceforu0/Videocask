import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/debug_log.dart';
import '../services/torrent_player_service.dart';
import '../utils/magnet_episode_parser.dart';

/// 磁力播放自检 deeplink（**仅 debug 构建**）。
///
/// 用法：
/// ```bash
/// adb shell am start -a android.intent.action.VIEW \
///   -d "movieapp://magnetprobe?uri=magnet%3A%3Fxt%3Durn%3Abtih%3A<40位hash>%26dn%3D..."
/// ```
///
/// 为什么要有它：
/// 「磁力播不出来」在界面上只有一个转圈，看不出卡在**取元数据**、
/// **连不上 peer**、还是**流起了但没数据**。这个探针把四段分别计时并写进
/// `DebugLog`（tag=`MagnetProbe`），产出可对比的数字：
/// 1. 引擎初始化耗时
/// 2. addMagnet → 元数据就绪耗时（含期间 seeds/peers）
/// 3. startStream → 流就绪耗时、buffer 百分比
/// 4. **真实拉流**：对本地流地址发 Range 请求，测「首字节耗时 + 前 1MB 速率」
///
/// 第 4 步才是「能不能播」的硬证据——只拿到 URL 不代表有数据。
///
/// 约束：不进入任何页面、不改播放器单例状态（结尾统一 `stop()` 清理），
/// release 构建直接返回 null。
/// 探针是否正在执行。`app_links` 在冷启动时可能同时从 `getInitialLink()`
/// 和 `uriLinkStream` 各投递一次同一个链接，若不去重会并发跑两个探针，
/// 它们共用同一个 libtorrent 会话、互相删种，导致结论完全失真。
bool _probeRunning = false;

Future<String?> runMagnetProbeDeeplink(Uri uri) async {
  if (!kDebugMode) return null;

  final magnet = uri.queryParameters['uri'] ?? '';
  if (magnet.isEmpty) {
    return 'magnetprobe: 缺少 uri 参数（需 URL 编码的完整 magnet）';
  }

  if (_probeRunning) {
    DebugLog.log('MagnetProbe', '已有探针在执行，忽略重复投递', flush: true);
    return 'magnetprobe: 已有探针在执行（忽略重复投递）';
  }
  _probeRunning = true;

  final svc = TorrentPlayerService();
  final total = Stopwatch()..start();
  void log(String msg) {
    final line = '[${total.elapsedMilliseconds}ms] $msg';
    DebugLog.log('MagnetProbe', line, flush: true);
    debugPrint('MagnetProbe $line');
  }

  log('开始 probe，magnet 长度=${magnet.length}');

  try {
    // ---- 1. 引擎初始化 ----
    final tInit = Stopwatch()..start();
    await svc.init();
    tInit.stop();
    log('① init: ${tInit.elapsedMilliseconds}ms, '
        'isInitialized=${svc.isInitialized}');
    if (!svc.isInitialized) {
      log('结论: 引擎初始化失败 → ${svc.errorMessage}');
      return 'magnetprobe: init 失败';
    }

    // ---- 2. addMagnet + 等元数据 ----
    final tMeta = Stopwatch()..start();
    final added = await svc.addMagnet(magnet);
    log('② addMagnet 返回=$added, state=${svc.state}');
    if (!added) {
      log('结论: addMagnet 失败 → ${svc.errorMessage}');
      return 'magnetprobe: addMagnet 失败';
    }

    const metaTimeout = Duration(seconds: 90);
    var lastTick = 0;
    while (tMeta.elapsed < metaTimeout) {
      if (svc.state == TorrentPlayState.error) break;
      if (svc.files.isNotEmpty) break;
      final sec = tMeta.elapsed.inSeconds;
      if (sec >= lastTick + 10) {
        lastTick = sec;
        log('   等元数据 ${sec}s: state=${svc.state.name}, '
            'seeds=${svc.seeds}, peers=${svc.peers}, '
            'down=${svc.downloadSpeedFormatted}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    tMeta.stop();

    final files = svc.files;
    log('② 元数据结果: ${tMeta.elapsedMilliseconds}ms, '
        'files=${files.length}, seeds=${svc.seeds}, peers=${svc.peers}, '
        'state=${svc.state.name}, err=${svc.errorMessage}');
    if (files.isEmpty) {
      log('结论: 元数据未就绪（seeds=${svc.seeds}, peers=${svc.peers}）');
      return 'magnetprobe: 无元数据';
    }
    for (final f in files.take(5)) {
      log('   文件[${f.index}] ${f.name} (${f.sizeFormatted})');
    }

    // ---- 3. 选文件 + 起流 ----
    final idx = MagnetEpisodeParser.pickFileIndex(files, episodeIndex: 0);
    log('③ 选中文件 index=$idx');
    if (idx == null) {
      log('结论: 无可播视频文件');
      return 'magnetprobe: 无视频文件';
    }

    final tStream = Stopwatch()..start();
    final url = await svc.playFile(idx);
    tStream.stop();
    log('③ startStream+等缓冲: ${tStream.elapsedMilliseconds}ms, '
        'url=$url, buffer=${svc.bufferPct}%, '
        'seeds=${svc.seeds}, peers=${svc.peers}');
    if (url == null || url.isEmpty) {
      log('结论: 起流失败 → ${svc.errorMessage}');
      return 'magnetprobe: 起流失败';
    }

    // ---- 4. 真实拉流：Range 请求测首字节与吞吐 ----
    final tRead = Stopwatch()..start();
    var firstByteMs = -1;
    var received = 0;
    var speedBps = 0;
    String readNote = '';
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1048575');
      final resp = await req.close();
      log('④ HTTP status=${resp.statusCode}, '
          'contentType=${resp.headers.contentType}, '
          'contentLength=${resp.contentLength}');
      await for (final chunk in resp) {
        if (firstByteMs < 0) {
          firstByteMs = tRead.elapsedMilliseconds;
          log('④ 首字节到达: ${firstByteMs}ms');
        }
        received += chunk.length;
        if (received >= 1024 * 1024) break;
        if (tRead.elapsed > const Duration(seconds: 25)) {
          readNote = '（25s 超时截断）';
          break;
        }
      }
      speedBps = tRead.elapsedMilliseconds > 0
          ? (received * 1000) ~/ tRead.elapsedMilliseconds
          : 0;
      client.close(force: true);
    } catch (e) {
      readNote = '拉流异常: $e';
    }
    tRead.stop();

    log('④ 拉流结果: ${received}B / ${tRead.elapsedMilliseconds}ms '
        '= ${(speedBps / 1024).toStringAsFixed(1)} KB/s $readNote');
    log('结论: ${received > 0 ? "✅ 可播（已拿到真实数据）" : "❌ 拿不到数据"}');
    return 'magnetprobe: ${received > 0 ? "可播" : "失败"} '
        '(${received}B, ${(speedBps / 1024).toStringAsFixed(1)}KB/s)';
  } catch (e, st) {
    log('探针异常: $e');
    debugPrint('$st');
    return 'magnetprobe: 异常 $e';
  } finally {
    try {
      await svc.stop();
    } catch (_) {}
    _probeRunning = false;
    log('清理完成（总耗时 ${total.elapsedMilliseconds}ms）');
  }
}
