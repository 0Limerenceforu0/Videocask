import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../services/player_service.dart';
import '../services/storage_service.dart';
import '../services/video_output_policy.dart';

/// FD 泄漏矩阵测试的配置 deeplink（仅 debug 构建生效）。
///
/// 用法（adb）：
/// ```bash
/// adb shell am start -a android.intent.action.VIEW \
///   -d "movieapp://testcfg?vo=gpu&hwdec=no&sp=true&gpuapi=vulkan"
/// ```
///
/// 参数：
/// - `vo`：`gpu` | `gpuNext` | `mediacodecEmbed`（写 Hive，重启后由
///   SettingsProvider.init 读取，与设置页手动切换等价）；
///   `default` = 删键回默认档（gpu-next）
/// - `hwdec`：`no`（软解，hardware_decode=false）| `mediacodec`（硬解）；
///   `default` = 删键回默认（开）
/// - `sp`：`true` | `false`（SurfaceProducer 开关，写 Hive debug key，
///   PlayerService.init 读取；**必须落盘**——内存 override 会被重启冲掉，
///   2026-10-23 实测因此白跑一整批）；`default` = 删键
/// - `gpuapi`：`vulkan` | `opengl`（mpv gpu-api，同样落 Hive debug key）；
///   `default` = 删键
///
/// 🔴 每次真机验证（尤其磁力首播）前，先发一次全 `default` 清场：
/// ```bash
/// adb shell am start -a android.intent.action.VIEW \
///   -d "movieapp://testcfg?vo=default&hwdec=default&sp=default&gpuapi=default"
/// ```
/// 2026-10-24 实测教训：矩阵残留的 `debug_gpu_api=opengl` + `vo=mediacodecEmbed`
/// 会让磁力首播流程在 addMagnet 后中途切视频后端、重建播放器，污染验证结果。
///
/// 设计约束：
/// - **仅 kDebugMode**：release 构建直接忽略，正式包无此入口。
/// - vo/hwdec 走 Hive 持久化（复用设置页的同一存储键，不改数据格式）；
///   sp/gpuapi 是内存态 override，不落盘——避免测试通道污染真实设置。
/// - 下发后需要**重启进程**才完整生效（SettingsProvider 启动时读盘），
///   所以测试脚本的顺序固定为：testcfg → force-stop → 冷启 → 播放。

import 'package:flutter/foundation.dart';
/// 处理 `movieapp://testcfg?...`，返回人类可读的结果摘要（调试用）。
///
/// 非 debug 构建返回 null（调用方应忽略）。
Future<String?> applyTestConfigDeeplink(Uri uri) async {
  if (!kDebugMode) return null;

  final params = uri.queryParameters;
  final storage = StorageService();
  final applied = <String>[];

  // --- vo / hwdec：写 Hive（与设置页同一存储键）---
  // `default` = 删键，回到「未设置」= 代码默认档（vo→gpu-next，hwdec→开）。
  final vo = params['vo'];
  if (vo != null && vo.isNotEmpty) {
    if (vo == 'default') {
      await storage.deleteSetting(AppConstants.keyVideoOutputMode);
      applied.add('vo=default(删键)');
    } else {
      VideoOutputMode mode;
      switch (vo) {
        case 'gpu':
          mode = VideoOutputMode.gpu;
          break;
        case 'gpuNext':
          mode = VideoOutputMode.gpuNext;
          break;
        case 'mediacodecEmbed':
          mode = VideoOutputMode.mediacodecEmbed;
          break;
        default:
          return 'testcfg: 未知 vo=$vo'
              '（合法值 gpu|gpuNext|mediacodecEmbed|default）';
      }
      await storage.saveSetting(
        AppConstants.keyVideoOutputMode,
        encodeVideoOutputMode(mode),
      );
      applied.add('vo=${encodeVideoOutputMode(mode)}');
    }
  }

  final hwdec = params['hwdec'];
  if (hwdec != null && hwdec.isNotEmpty) {
    if (hwdec == 'no') {
      // 软解 = 硬件解码总开关关闭（档位置空，跟随平台默认）。
      await storage.saveBoolSetting(AppConstants.keyHardwareDecode, false);
      applied.add('hwdec=no(总开关关)');
    } else if (hwdec == 'mediacodec') {
      await storage.saveBoolSetting(AppConstants.keyHardwareDecode, true);
      applied.add('hwdec=mediacodec(总开关开)');
    } else if (hwdec == 'default') {
      await storage.deleteSetting(AppConstants.keyHardwareDecode);
      applied.add('hwdec=default(删键)');
    } else {
      return 'testcfg: 未知 hwdec=$hwdec（合法值 no|mediacodec|default）';
    }
  }

  // --- sp / gpuapi：写 Hive debug key（PlayerService.init 读；必须落盘）---
  final sp = params['sp'];
  if (sp != null && sp.isNotEmpty) {
    if (sp == 'default') {
      await storage.deleteSetting('debug_surface_producer');
      applied.add('sp=default(删键)');
    } else {
      if (sp != 'true' && sp != 'false') {
        return 'testcfg: 未知 sp=$sp（合法值 true|false|default）';
      }
      await storage.saveSetting('debug_surface_producer', sp);
      applied.add('sp=$sp');
    }
  }

  final gpuapi = params['gpuapi'];
  if (gpuapi != null && gpuapi.isNotEmpty) {
    if (gpuapi == 'default') {
      await storage.deleteSetting('debug_gpu_api');
      applied.add('gpuapi=default(删键)');
    } else {
      if (gpuapi != 'vulkan' && gpuapi != 'opengl') {
        return 'testcfg: 未知 gpuapi=$gpuapi（合法值 vulkan|opengl|default）';
      }
      await storage.saveSetting('debug_gpu_api', gpuapi);
      applied.add('gpuapi=$gpuapi');
    }
  }

  if (applied.isEmpty) return 'testcfg: 无参数';
  return 'testcfg 已下发: ${applied.join(' ')}（重启后完整生效）';
}
