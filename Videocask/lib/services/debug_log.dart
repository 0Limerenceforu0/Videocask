import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config/constants.dart';
import '../utils/app_data_paths.dart';

/// 诊断日志：把播放 / 代理 / 续播 / 异常等关键事件写入本地文件，便于复现问题时提取。
///
/// 目录选择（优先「用户容易拿到」的位置）：
/// - 桌面端（Win/Linux/macOS）：软件所在目录下的 `guanzi_logs/`（绿色便携、跟着 exe 走）
/// - Android：外置存储应用私有目录
///   `.../Android/data/com.example.movie_app/files/guanzi_logs/`
/// - iOS：应用支持目录下的 `guanzi_logs/`
/// - Web：不写文件（Web 走同源代理日志，见 web_dev_server.py）
///
/// 提取方式（回复中会写明）：
/// - Windows：直接打开 exe 旁的 `guanzi_logs` 文件夹
/// - Android：用文件管理器进入 `Android/data/com.example.movie_app/files/guanzi_logs`，
///   或用电脑 `adb pull /storage/emulated/0/Android/data/com.example.movie_app/files/guanzi_logs`
abstract final class DebugLog {
  static Directory? _dir;
  static File? _file;
  static IOSink? _sink;
  static final List<String> _mem = <String>[];
  static const int _memCap = 5000;
  static bool enabled = true;
  static Timer? _flushTimer;
  static int _resTick = 0;

  static Directory? get directory => _dir;
  static String get directoryPath => _dir?.path ?? '(日志未初始化)';
  /// 当前正在写入的日志文件绝对路径（清空日志时跳过，避免删掉正在写的句柄）。
  static String? get currentFilePath => _file?.path;

  /// 初始化日志文件，返回日志目录绝对路径（供 UI 展示）。
  static Future<String> init({bool enable = true}) async {
    enabled = enable;
    if (kIsWeb) {
      _dir = null;
      return '';
    }
    // 重复 init（热重启 / 多入口 / 测试）时先释放旧 sink 与旧定时器：
    // 否则旧 sink 保持打开 → 句柄泄漏，且后续写入与旧 close 竞态会抛异常。
    _flushTimer?.cancel();
    final oldSink = _sink;
    _sink = null;
    if (oldSink != null) {
      try {
        await oldSink.close();
      } catch (_) {}
    }
    Directory base;
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final ext = await getExternalStorageDirectory();
        base = ext ?? await getApplicationSupportDirectory();
      } catch (_) {
        base = await getApplicationSupportDirectory();
      }
    } else {
      base = await AppDataPaths.root();
    }
    _dir = Directory('${base.path}${Platform.pathSeparator}guanzi_logs');
    try {
      await _dir!.create(recursive: true);
    } catch (_) {}
    final now = DateTime.now();
    final name =
        'guanzi_debug_${now.year}${_pad2(now.month)}${_pad2(now.day)}.log';
    _file = File('${_dir!.path}${Platform.pathSeparator}$name');
    try {
      _sink = _file!.openWrite(mode: FileMode.append);
    } catch (_) {
      _sink = null;
    }
    _writePathPointer();
    _cleanupOldLogs();
    _flushTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      unawaited(flush());
      // 每 ~30s（300ms×100）记录一次进程 FD 数 / 线程数，用于诊断文件描述符泄漏
      // （长时间播放偶发 SIGABRT 的根因疑似 FD 耗尽）。仅 Android 有 /proc。
      if (Platform.isAndroid) {
        if (++_resTick % 100 == 0) _logResourceUsage();
      }
    });
    log('DebugLog', '========== 日志系统启动 ==========');
    log(
      'DebugLog',
      'App ${AppConstants.appVersion} | 平台 ${_platformTag()} | 目录 ${_dir!.path}',
    );
    // 设备指纹：fd 泄漏与 GPU/驱动强相关（media-kit#1391 就是特定机型），
    // 没有型号就没法判断「你的机器属于哪一类」。之前日志里缺这一行，
    // 排查时只能靠用户口述机型。
    final device = _deviceFingerprint();
    if (device != null) log('DebugLog', '设备: $device');
    _checkAbnormalExit();
    return _dir!.path;
  }

  static void _writePathPointer() {
    try {
      final pointer =
          File('${_dir!.path}${Platform.pathSeparator}_CURRENT_LOG.txt');
      pointer.writeAsStringSync(
        '罐子 诊断日志目录\n'
        '====================\n'
        '本目录：\n${_dir!.path}\n\n'
        '今日日志文件：\n${_file!.path}\n\n'
        '复现问题后，把整个 guanzi_logs 文件夹发给我即可。\n'
        '（Android 需用文件管理器进入 '
        'Android/data/com.example.movie_app/files/guanzi_logs，'
        '或用电脑 adb pull 该目录）\n',
      );
    } catch (_) {}
  }

  /// 清理 7 天前的日志，避免无限增长。
  static void _cleanupOldLogs() {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      _dir!.listSync().whereType<File>().where((f) {
        final name = f.path.split(Platform.pathSeparator).last;
        return name.startsWith('guanzi_debug_') && name.endsWith('.log');
      }).where((f) {
        try {
          return f.lastModifiedSync().isBefore(cutoff);
        } catch (_) {
          return false;
        }
      }).forEach((f) {
        try {
          f.deleteSync();
        } catch (_) {}
      });
    } catch (_) {}
  }

  static String _pad2(int n) => n < 10 ? '0$n' : '$n';

  static String _platformTag() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  /// 启动时检查上一次会话是否异常死亡（被系统 LMK 杀死 / 原生崩溃无栈）。
  static void _checkAbnormalExit() {
    if (_dir == null) return;
    try {
      final clean =
          File('${_dir!.path}${Platform.pathSeparator}clean_shutdown.txt');
      final marker =
          File('${_dir!.path}${Platform.pathSeparator}alive_marker.txt');
      if (clean.existsSync()) {
        // 上次是正常退出（写入了 clean_shutdown 标记）
        try {
          clean.deleteSync();
        } catch (_) {}
        try {
          marker.deleteSync();
        } catch (_) {}
        return;
      }
      if (marker.existsSync()) {
        final ts = int.tryParse(marker.readAsStringSync().trim());
        final now = DateTime.now().millisecondsSinceEpoch;
        if (ts != null && now - ts > 120000) {
          // 存活标记超过 120s 未更新且无 clean_shutdown → 疑似被系统杀死
          final dt = DateTime.fromMillisecondsSinceEpoch(ts);
          log(
            'Lifecycle',
            '上次会话疑似被系统(LMK/低内存)杀死：最后存活 '
            '${_pad2(dt.hour)}:${_pad2(dt.minute)}:${_pad2(dt.second)}，'
            '距本次启动 ${(now - ts) ~/ 1000}s（无 clean_shutdown 标记）',
            flush: true,
          );
        }
        try {
          marker.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 正常退出时调用：写 clean_shutdown 标记，供下次启动区分「正常关闭」与「异常死亡」。
  static void markCleanShutdown() {
    if (_dir == null) return;
    try {
      final f =
          File('${_dir!.path}${Platform.pathSeparator}clean_shutdown.txt');
      f.writeAsStringSync('${DateTime.now().millisecondsSinceEpoch}\n');
    } catch (_) {}
  }

  static String _ts() {
    final d = DateTime.now();
    return '${_pad2(d.hour)}:${_pad2(d.minute)}:${_pad2(d.second)}.'
        '${_pad2(d.millisecond ~/ 10)}';
  }

  /// 写一行日志。[flush]=true 时立即刷盘（用于崩溃/异常/关键事件，尽量保留现场）。
  static void log(String tag, String msg, {bool flush = false}) {
    if (!enabled) return;
    final line = '${_ts()} [$tag] $msg';
    if (_mem.length >= _memCap) _mem.removeAt(0);
    _mem.add(line);
    // 写盘失败绝不能让日志调用方崩掉。
    // 真实事故：close() 期间（_sink 尚未置空）周期日志写入会抛
    // `Bad state: StreamSink is bound to a stream`，而该异常发生在
    // recyclePlayer 内部 → 把整个重建流程打断（真机表现为
    // 「触发回收 197 次、recyclePlayer 开始 0 次」），且异常向上逃逸到
    // 未捕获区，ErrorHandler 再写日志又抛，形成连环失败。
    try {
      _sink?.writeln(line);
    } catch (_) {}
    if (kDebugMode) debugPrint(line);
    if (flush) unawaited(DebugLog.flush());
  }

  /// 异步刷盘（关键事件 await 用）。
  static Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {}
  }

  /// 按类型统计本进程 fd：socket / pipe / anon / file / other。
  ///
  /// 光有总数无法定位泄漏源：分类后能立刻区分「socket 未归还（网络/代理）」
  /// 「pipe 未关（子进程/管道）」「文件未关」——直接决定排查方向。
  ///
  /// [maxScan] 限制扫描条数：fd 涨到数万时全量遍历有开销，超过上限即采样。
  /// 返回空串表示不可用（web / 无 /proc）。
  /// 从匿名 inode 的 fd 链接目标里取出具体类型。
  ///
  /// ⚠️ 内核有两种形态，**都必须认**，否则真机最主要的泄漏类型会被吞掉：
  /// - `anon_inode:[eventfd]` —— 带方括号（eventfd / epoll / timerfd / signalfd）
  /// - `anon_inode:sync_file` —— 无方括号（GPU fence：`sync_file` / `dmabuf`）
  ///
  /// 只认第一种时，`sync_file` 会变成 `anon:?`，而它正是 media-kit Android
  /// 已知每帧泄漏的对象（media-kit#1391），分类一旦吞掉它就永远定位不到根因。
  ///
  /// 取不到时返回 `?`，保证分类字符串仍可读、不抛异常。
  static String _anonSubtype(String target) {
    final m = RegExp(
      r'anon_inode:(?:\[([^\]]+)\]|([A-Za-z0-9_.-]+))',
    ).firstMatch(target);
    final raw = (m?.group(1) ?? m?.group(2))?.trim();
    if (raw == null || raw.isEmpty) return '?';
    // dmabuf 常带后缀（如 `dmabuf:0123`），只保留主类型避免分类被拆散。
    return raw.split(':').first;
  }

  /// 把真机图形/内存相关的特殊路径单列成一类。
  ///
  /// 它们都以 `/` 开头，默认会被算进 `file`，于是「file 数稳定」会给人
  /// 「没有图形 buffer 泄漏」的错觉 —— 实测 media-kit 的 dmabuf 正是以
  /// `/dmabuf:` 形式出现（media-kit#1391），必须单独成类才看得到。
  static String? _specialPathKind(String target) {
    if (target.startsWith('/dmabuf')) return 'dmabuf';
    if (target.startsWith('/dev/ashmem')) return 'ashmem';
    if (target.startsWith('/dev/mali') || target.startsWith('/dev/kgsl')) {
      return 'gpu';
    }
    return null;
  }

  /// 测试入口：直接验证 fd 分类规则（纯字符串处理，不触碰 IO）。
  @visibleForTesting
  static String classifyFdTarget(String target) =>
      _specialPathKind(target) ??
      (target.startsWith('socket:')
          ? 'socket'
          : target.startsWith('pipe:')
              ? 'pipe'
              : target.startsWith('anon_inode:')
                  ? 'anon:${_anonSubtype(target)}'
                  : target.startsWith('/')
                      ? 'file'
                      : 'other');

  static String fdBreakdown({int maxScan = 3000}) {
    try {
      final dir = Directory('/proc/self/fd');
      final kinds = <String, int>{};
      var scanned = 0;
      for (final entry in dir.listSync()) {
        if (scanned++ >= maxScan) break;
        String target;
        try {
          target = Link(entry.path).targetSync();
        } catch (_) {
          target = '?';
        }
        final special = _specialPathKind(target);
        final kind = special ??
            (target.startsWith('socket:')
                ? 'socket'
                : target.startsWith('pipe:')
                    ? 'pipe'
                    : target.startsWith('anon_inode:')
                        // 细分 anon：这是排查 fd 泄漏的关键 —— 真机实测只有 anon
                        // 在涨（2026-10-21），必须能区分是 GPU fence（sync_file）
                        // 还是事件对象（eventfd/epoll/timerfd）。
                        ? 'anon:${_anonSubtype(target)}'
                        : target.startsWith('/')
                            ? 'file'
                            : 'other');
        kinds[kind] = (kinds[kind] ?? 0) + 1;
      }
      if (kinds.isEmpty) return '';
      final parts = kinds.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final suffix = scanned >= maxScan ? '(采样$maxScan)' : '';
      return suffix + parts.map((e) => '${e.key}=${e.value}').join(' ');
    } catch (_) {
      return '';
    }
  }

  /// 上一次采样时的 fd 号集合（差分出「新增」用）。
  ///
  /// 2026-10-22 真机日志暴露的诊断缺陷：`fdBreakdown` 只扫**前 3000 个**
  /// fd（`maxScan`），而泄漏的 fd 编号越来越大、永远落在扫描窗口之外 ——
  /// 于是日志里 `anon:sync_file` 冻结在 2716 不动、其它分类也全稳定，
  /// **总数却以 22 fd/s 线性涨**：泄漏的类型根本看不见。
  /// （2026-10-21 那一版日志同样是这个形态，所以泄漏源一直没能定位。）
  static Set<int>? _lastFdIds;

  /// fd 差分采样结果。
  ///
  /// - [total]：当前 fd 总数
  /// - [added]：**本周期新增** fd 的分类 ← 泄漏类型就是它
  /// - [removed]：本周期消失（已归还）的 fd 数
  /// - [fullKinds]：全量分类（仅在 fd 数不超过扫描上限时可信）
  /// - [fullCovered]：全量分类是否覆盖了全部 fd
  static ({int total, Map<String, int> added, int removed,
      Map<String, int> fullKinds, bool fullCovered}) fdDelta({
    int maxScan = 3000,
  }) {
    final empty = (
      total: 0,
      added: const <String, int>{},
      removed: 0,
      fullKinds: const <String, int>{},
      fullCovered: false,
    );
    try {
      final dir = Directory('/proc/self/fd');
      // 目录项本身很便宜（followLinks:false 不做 stat），
      // 贵的是 readlink —— 所以只对**新增**的 fd 做 readlink。
      final ids = <int>{};
      for (final entry in dir.listSync(followLinks: false)) {
        final name = entry.path.split(Platform.pathSeparator).last;
        final n = int.tryParse(name);
        if (n != null) ids.add(n);
      }
      final total = ids.length;
      final previous = _lastFdIds;
      _lastFdIds = ids;
      if (previous == null) {
        // 首次采样没有参照：给全量分类当基线。
        final full = fdBreakdown(maxScan: maxScan);
        final kinds = <String, int>{};
        for (final part in full.split(' ')) {
          if (part.contains('=')) {
            final kv = part.split('=');
            final v = int.tryParse(kv.last);
            if (v != null) kinds[kv.first] = v;
          }
        }
        return (
          total: total,
          added: const <String, int>{},
          removed: 0,
          fullKinds: kinds,
          fullCovered: total <= maxScan,
        );
      }
      final added = <String, int>{};
      for (final id in ids.difference(previous)) {
        String target;
        try {
          target = Link('${dir.path}${Platform.pathSeparator}$id')
              .targetSync();
        } catch (_) {
          target = '?';
        }
        final kind = classifyFdTarget(target);
        added[kind] = (added[kind] ?? 0) + 1;
      }
      final removed = previous.difference(ids).length;
      return (
        total: total,
        added: added,
        removed: removed,
        fullKinds: const <String, int>{},
        fullCovered: total <= maxScan,
      );
    } catch (_) {
      return empty;
    }
  }

  /// 本进程 fd 的软上限（`RLIMIT_NOFILE`），读不到返回 null。
  ///
  /// fd 泄漏之所以致命，是因为撞上这个上限后 `epoll_create1` 失败 → SIGABRT。
  /// 所以「多少算高」只能相对它来谈；脱离上限谈绝对值（700 / 1500 / 3000）
  /// 都是在拍脑袋。
  static int? fdLimit() {
    try {
      final lines = File('/proc/self/limits').readAsLinesSync();
      for (final line in lines) {
        if (!line.startsWith('Max open files')) continue;
        final parts = line.split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
        // 形如 `Max open files  4096  4096  files`：第 4 段是 soft limit。
        if (parts.length >= 4) return int.tryParse(parts.elementAt(3));
      }
    } catch (_) {}
    return null;
  }

  /// 上一次 FD 采样（用于算增长速率；仅诊断用途，不触发任何自动行为）。
  static int? _lastFdSample;
  static DateTime? _lastFdSampleAt;

  /// 设备指纹（厂商/型号/主板/SoC/Android 版本）。
  ///
  /// fd 泄漏与 GPU 驱动强相关（media-kit#1391 就是特定机型特有的），日志里没有
  /// 型号就无法判断「这台机器属于哪一类」。2026-10-22 排查时日志里缺这一行，
  /// 只能靠用户口述机型，白白多绕一轮。
  ///
  /// 不引第三方依赖：`/system/build.prop` 在 Android 上是全局只读的，直接解析。
  /// 读不到就返回 null，不影响其它日志。
  static String? _deviceFingerprint() {
    final cached = _cachedDeviceTag;
    if (cached != null) return cached.isEmpty ? null : cached;
    const wanted = <String>[
      'ro.product.manufacturer',
      'ro.product.model',
      'ro.product.board',
      'ro.hardware',
      'ro.board.platform',
      'ro.soc.model',
      'ro.build.version.release',
    ];
    final found = <String, String>{};
    try {
      for (final path in const <String>[
        '/system/build.prop',
        '/vendor/build.prop',
        '/system/etc/prop.default',
      ]) {
        final file = File(path);
        if (!file.existsSync()) continue;
        // 用 latin1 解码：build.prop 可能含非 UTF-8 字节，直接按行读会抛异常。
        final raw = String.fromCharCodes(file.readAsBytesSync());
        for (final line in raw.split('\n')) {
          final eq = line.indexOf('=');
          if (eq <= 0) continue;
          final key = line.substring(0, eq).trim();
          if (wanted.contains(key) && !found.containsKey(key)) {
            found[key] = line.substring(eq + 1).trim();
          }
        }
      }
    } catch (_) {
      _cachedDeviceTag = '';
      return null;
    }
    if (found.isEmpty) {
      _cachedDeviceTag = '';
      return null;
    }
    final tag = wanted
        .where(found.containsKey)
        .map((k) => '${k.split('.').last}=${found[k]}')
        .join(' ');
    _cachedDeviceTag = tag;
    return tag;
  }

  static String? _cachedDeviceTag;

  static void _logResourceUsage() {
    try {
      // 差分采样：既给全量分类（基线用），也给**新增 fd 的分类**。
      // 2026-10-22：泄漏类型只能从「新增」里看 —— 全量分类在 fd 上万之后
      // 只覆盖前 3000 个，泄漏的 fd 永远在窗口外。
      final sample = fdDelta();
      final fdCount = sample.total;
      var threadCount = 0;
      try {
        threadCount = Directory('/proc/self/task').listSync().length;
      } catch (_) {}
      final now = DateTime.now();
      double? rate;
      if (_lastFdSample != null && _lastFdSampleAt != null) {
        final spanSec = now.difference(_lastFdSampleAt!).inMilliseconds / 1000.0;
        if (spanSec > 0) rate = (fdCount - _lastFdSample!) / spanSec;
      }
      _lastFdSample = fdCount;
      _lastFdSampleAt = now;
      final limit = fdLimit();

      final addedText = sample.added.isEmpty
          ? ''
          : ' 新增[${_formatKinds(sample.added)}]';
      final removedText = sample.removed > 0 ? ' 消失=${sample.removed}' : '';
      final fullText = sample.fullKinds.isEmpty
          ? ''
          : ' 全量[${_formatKinds(sample.fullKinds)}]';

      log(
        'Res',
        'fds=$fdCount${limit == null ? '' : '/$limit'} threads=$threadCount'
        '${rate == null ? '' : ' rate=${rate >= 0 ? '+' : ''}${rate!.toStringAsFixed(1)}fd/s'}'
        '$addedText$removedText$fullText',
      );
      _lastFdSampleDetail =
          'fds=$fdCount/${limit ?? "?"} rate=${rate?.toStringAsFixed(1) ?? "?"}'
          '${addedText.isEmpty ? '' : addedText.trim()}';
      _persistFdState();
    } catch (_) {}
  }

  /// 把 fd 运行时状态写到日志目录的 `fd_state.txt`。
  ///
  /// 原生崩溃处理器（`crash_handler.cpp`）在写崩溃栈时附带这个文件，
  /// 于是「这次崩溃是不是撞上 fd 耗尽」可以直接看 —— 2026-10-22 的真机崩溃
  /// 正是 fd=32669/32768 时崩在系统硬解路径，崩溃文件里却没有 fd 数。
  static void _persistFdState() {
    try {
      final dir = _dir;
      if (dir == null) return;
      final file = File(
        '${dir.path}${Platform.pathSeparator}fd_state.txt',
      );
      file.writeAsStringSync(fdStateSnapshot(), flush: true);
    } catch (_) {}
  }

  /// 分类计数的紧凑表示（按数量倒序）。
  static String _formatKinds(Map<String, int> kinds) {
    final parts = kinds.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return parts.map((e) => '${e.key}=${e.value}').join(' ');
  }

  /// 最近一次 fd 采样摘要（供崩溃时落盘，见 [fdStateSnapshot]）。
  static String? _lastFdSampleDetail;

  /// fd 运行时状态快照（写入日志目录的 `fd_state.txt`）。
  ///
  /// 原生崩溃时由 `crash_handler.cpp` 读取并贴进崩溃文件 ——
  /// 于是「这次崩溃是不是撞上 fd 耗尽」能**直接看**，不必事后推算。
  /// 2026-10-22 真机日志：崩溃发生在 fd=32669/32768（99.7% 满）时，
  /// 崩在 `MediaCodec::handleOutputFormatChangeIfNeeded`（系统硬解路径），
  /// 但崩溃文件里**没有 fd 数**，当时只能靠日志正文反推。
  static String fdStateSnapshot() {
    final detail = _lastFdSampleDetail;
    if (detail == null) return '';
    return '$detail timestamp=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// 进程退出前调用。
  static Future<void> close() async {
    _flushTimer?.cancel();
    await flush();
    // 先摘引用再 close：`await sink.close()` 会挂起，若此时周期日志（300ms）
    // 仍持有旧 _sink 去写，会抛 StreamSink is bound to a stream。
    final sink = _sink;
    _sink = null;
    try {
      await sink?.close();
    } catch (_) {}
  }
}
