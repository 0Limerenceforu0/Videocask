// Windows 桌面端磁力探针（**默认跳过**，需显式开启）。
//
// 为什么需要它
// ------------
// Android 上有 adb + logcat，可以量出「点磁力 → 出画」的真实耗时；但 Windows
// 桌面端没有等价手段，GUI 也没法脚本化驱动。本测试直接在**宿主进程**里驱动
// 生产代码 `TorrentPlayerService`，量出与 Android e2e 同口径的四个数字：
//   ① 引擎 init 耗时
//   ② addMagnet → 元数据就绪（≈ 第一个 peer 送达 metadata 的时刻，
//      直接反映 tracker 列表是否奏效）
//   ③ addMagnet → 流就绪（5% 缓冲门）
//   ④ 真实 HTTP Range 拉流：首字节耗时 + 前 1MB 吞吐（"能不能播"的硬证据）
//
// 注意：`addMagnet()` 内部会调用 `_enhanceMagnet()`，即精选 tracker 列表
// （`buildEnhancedMagnet`）在这条路径上真实生效 —— 测到的就是优化后的行为。
//
// 运行方式（Windows 宿主）：
//   set RUN_MAGNET_PROBE=1
//   set PATH=<Release 目录>;%PATH%      // 让 libtorrent_flutter.dll 可被加载
//   flutter test test/probe/windows_magnet_probe_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/torrent_player_service.dart';

/// 探针用磁力（与 Android e2e 同一资源，便于跨端对比）。
const String kMagnet =
    'magnet:?xt=urn:btih:c3da9a3dc2ce14d0d4fc0e87d1b2023502f8dcd6'
    '&dn=The%20Shawshank%20Redemption%201994%201080p%20BrRip%20x264%20YIFY';

void main() {
  test('Windows 磁力探针：init → 元数据 → 起流 → 真实拉流', () async {
    if (Platform.environment['RUN_MAGNET_PROBE'] != '1') {
      markTestSkipped('需要环境变量 RUN_MAGNET_PROBE=1（会访问真实网络）');
      return;
    }

    // TestWidgetsFlutterBinding 会把所有 HttpClient mock 成 400，
    // 真 loopback 必须先解除（见项目记忆）。
    HttpOverrides.global = null;

    final svc = TorrentPlayerService();
    final total = Stopwatch()..start();
    void log(String msg) =>
        print('[PROBE ${total.elapsedMilliseconds}ms] $msg');

    log('平台=${Platform.operatingSystem} ${Platform.operatingSystemVersion}');

    // ---- ① 引擎初始化 ----
    final tInit = Stopwatch()..start();
    await svc.init();
    tInit.stop();
    log('① init=${tInit.elapsedMilliseconds}ms initialized=${svc.isInitialized}');
    if (!svc.isInitialized) {
      log('❌ 引擎初始化失败: ${svc.errorMessage}');
      fail('init 失败: ${svc.errorMessage}');
    }

    // ---- ② addMagnet → 元数据就绪 ----
    final tMeta = Stopwatch()..start();
    final added = await svc.addMagnet(kMagnet);
    log('② addMagnet 返回=$added state=${svc.state.name}');
    if (!added) {
      log('❌ addMagnet 失败: ${svc.errorMessage}');
      fail('addMagnet 失败: ${svc.errorMessage}');
    }

    int firstPeerMs = -1;
    int lastTick = 0;
    while (tMeta.elapsed < const Duration(seconds: 90)) {
      if (svc.state == TorrentPlayState.error) break;
      if (svc.activePeers > 0 && firstPeerMs < 0) {
        firstPeerMs = tMeta.elapsedMilliseconds;
        log('   ★ 首个真实 peer 出现: ${firstPeerMs}ms (activePeers=${svc.activePeers})');
      }
      if (svc.files.isNotEmpty) break;
      final sec = tMeta.elapsed.inSeconds;
      if (sec >= lastTick + 5) {
        lastTick = sec;
        log('   等元数据 ${sec}s: state=${svc.state.name} '
            'activePeers=${svc.activePeers} seeds=${svc.seeds} '
            'down=${svc.downloadSpeedFormatted}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    tMeta.stop();
    log('② 元数据就绪=${tMeta.elapsedMilliseconds}ms files=${svc.files.length} '
        'activePeers=${svc.activePeers} seeds=${svc.seeds} '
        'down=${svc.downloadSpeedFormatted} state=${svc.state.name}');
    if (svc.files.isEmpty) {
      log('❌ 元数据未就绪');
      fail('元数据未就绪（activePeers=${svc.activePeers}）');
    }
    for (final f in svc.files.take(5)) {
      log('   文件[${f.index}] ${f.name} ${f.sizeFormatted} streamable=${f.isStreamable}');
    }

    // ---- ③ 起流（5% 缓冲门）----
    final idx = svc.files
        .where((f) => f.isStreamable)
        .fold<int?>(null, (best, f) => best == null ? f.index : best);
    final pick = idx ?? svc.files.first.index;
    final tStream = Stopwatch()..start();
    final url = await svc.playFile(pick);
    tStream.stop();
    log('③ 起流=${tStream.elapsedMilliseconds}ms url=$url buffer=${svc.bufferPct}% '
        'activePeers=${svc.activePeers}');
    if (url == null || url.isEmpty) {
      log('❌ 起流失败: ${svc.errorMessage}');
      fail('起流失败: ${svc.errorMessage}');
    }

    // ---- ④ 真实拉流：首字节 + 前 1MB 吞吐 ----
    final tRead = Stopwatch()..start();
    var firstByteMs = -1;
    var received = 0;
    var note = '';
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1048575');
      final resp = await req.close();
      log('④ HTTP status=${resp.statusCode} length=${resp.contentLength}');
      await for (final chunk in resp) {
        if (firstByteMs < 0) {
          firstByteMs = tRead.elapsedMilliseconds;
          log('④ 首字节=${firstByteMs}ms');
        }
        received += chunk.length;
        if (received >= 1024 * 1024) break;
        if (tRead.elapsed > const Duration(seconds: 25)) {
          note = '（25s 截断）';
          break;
        }
      }
      client.close(force: true);
    } catch (e) {
      note = '拉流异常: $e';
    }
    tRead.stop();
    final kbPerSec = tRead.elapsedMilliseconds > 0
        ? (received * 1000 / tRead.elapsedMilliseconds / 1024)
        : 0.0;
    log('④ 拉流=${received}B / ${tRead.elapsedMilliseconds}ms '
        '= ${kbPerSec.toStringAsFixed(1)} KB/s $note');

    log('════ 结论 ════');
    log('init=${tInit.elapsedMilliseconds}ms '
        '首个peer=${firstPeerMs}ms '
        '元数据=${tMeta.elapsedMilliseconds}ms '
        '起流=${tStream.elapsedMilliseconds}ms '
        '首字节=${firstByteMs}ms '
        '吞吐=${kbPerSec.toStringAsFixed(1)}KB/s');
    log(received > 0 ? '✅ 可播（拿到真实数据）' : '❌ 拿不到数据');

    await svc.stop();
  }, timeout: const Timeout(Duration(minutes: 6)));
}
