import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 读取设备内存信息（字节）。
///
/// 为什么不用 `dart:io`：`ProcessInfo` 只给当前进程的 RSS，
/// 拿不到「整机内存」；而 Android 10+ 已限制普通应用读 `/proc/meminfo`
/// （返回 0 或受限值）。唯一可靠来源是 `ActivityManager.MemoryInfo`，
/// 因此走原生通道。
///
/// 非 Android 平台（Windows/Web/iOS 未实现）直接返回 0，调用方按
/// [BufferTier.fallbackBytes] 的保守值处理——不会因为探测失败崩掉。
class DeviceMemoryProbe {
  DeviceMemoryProbe._();

  static const MethodChannel _channel = MethodChannel('guanzi/device');

  /// 物理内存探测结果缓存：一次运行内不会变，避免每次读设置都过通道。
  static int? _cached;

  static int get cachedTotalMemoryBytes => _cached ?? 0;

  static Future<int> readTotalMemoryBytes() async {
    if (_cached != null) return _cached!;
    if (kIsWeb) {
      _cached = 0;
      return 0;
    }
    try {
      final value = await _channel.invokeMethod<int>('getTotalMemory');
      _cached = (value ?? 0).clamp(0, 1 << 62);
    } catch (_) {
      // MissingPluginException（桌面/Web 未实现）或通道异常：退回保守默认。
      _cached = 0;
    }
    return _cached!;
  }

  /// 系统「当前可用」内存（字节）。**不缓存**——它每时每刻都在变，
  /// 自动缓冲挡位就是靠它每 10 分钟评估一次升降档。
  ///
  /// 失败（桌面/Web/通道异常）返回 0，调用方应保持现有挡位不动，
  /// 绝不能因为一次探测失败就把缓冲降到最低。
  static Future<int> readAvailableMemoryBytes() async {
    if (kIsWeb) return 0;
    try {
      final value = await _channel.invokeMethod<int>('getAvailableMemory');
      return (value ?? 0).clamp(0, 1 << 62);
    } catch (_) {
      return 0;
    }
  }
}
