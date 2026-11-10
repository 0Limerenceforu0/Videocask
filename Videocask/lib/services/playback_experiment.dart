import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';

/// 真机 A/B 实验台（仅测试用）。
///
/// 只有当应用外部私有目录里存在 `experiment.json` 时才启用；文件不存在时
/// 所有默认值、播放策略、BT 参数 **一行都不变**。删掉该文件即回到正常行为。
///
/// 目的：用同一台设备、同一条种子，把 mpv 缓存参数 / cache-pause / 超时 /
/// BT 上传限速 / 原生 piece 缓存容量逐一做成可控变量，靠实测数据决定改法，
/// 而不是靠注释里的推断。
///
/// 支持播放中热切：每 15s 重读一次文件，`run_id` 变化会触发 [reapply] 回调
/// 重新下发 mpv 参数，于是单次播放就能分段对比多组参数，避免反复冷启动
/// 带来的种子缓存差异。
abstract final class PlaybackExperiment {
  static Map<String, dynamic> _cfg = const <String, dynamic>{};
  static String _runId = 'base';
  static String _raw = '';
  static bool _loaded = false;

  /// 由详情页 State 注册，用于播放中热切时重新下发 mpv 参数。
  static Future<void> Function()? reapply;

  static bool get enabled => _cfg.isNotEmpty;
  static String get runId => _runId;
  static String get raw => _raw;
  static bool get loaded => _loaded;
  static String get summary =>
      _cfg.entries.map((e) => '${e.key}=${e.value}').join(' ');

  static int? intOf(String key) {
    final v = _cfg[key];
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    if (v is double) return v.round();
    return null;
  }

  static String? strOf(String key) {
    final v = _cfg[key];
    return v is String ? v : null;
  }

  /// 返回新的 runId 表示配置发生变化；返回 null 表示无变化或未启用。
  static Future<String?> load() async {
    try {
      Directory base;
      if (Platform.isAndroid || Platform.isIOS) {
        base = await getExternalStorageDirectory() ?? Directory.systemTemp;
      } else {
        base = Directory.systemTemp;
      }
      final file = File('${base.path}${Platform.pathSeparator}experiment.json');
      if (!await file.exists()) {
        final had = _cfg.isNotEmpty;
        _cfg = const <String, dynamic>{};
        _runId = 'base';
        _raw = '';
        _loaded = true;
        return had ? 'base' : null;
      }
      final text = await file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        DebugLog.log('Experiment', '配置文件不是 JSON 对象，忽略');
        _loaded = true;
        return null;
      }
      final next = Map<String, dynamic>.from(decoded);
      final nextId = (next['run_id'] ?? 'base').toString();
      final changed = nextId != _runId || text != _raw;
      _cfg = next;
      _runId = nextId;
      _raw = text;
      _loaded = true;
      return changed ? nextId : null;
    } catch (e) {
      DebugLog.log('Experiment', '读取 experiment.json 失败: $e');
      _loaded = true;
      return null;
    }
  }

  /// 开播前把当前实验参数写进日志，作为该组实验的起点横幅。
  static void logStart() {
    if (!enabled) return;
    DebugLog.log(
      'Experiment',
      '实验启动 runId=$runId $summary',
      flush: true,
    );
  }
}
