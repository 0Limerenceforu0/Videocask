import 'package:media_kit/media_kit.dart';

/// mpv 专有能力的 Web 空实现。
///
/// 浏览器里没有 mpv 后端，这里全部降级为空操作，调用方会回退到通用 API。

/// Web 端无 mpv 属性可读，恒返回 null。
Future<String?> getMpvProperty(Player player, String name) async => null;

/// Web 端无 mpv 属性可写，恒不执行。
Future<void> setMpvProperty(Player player, String name, String value) async {}

/// Web 端无 mpv 命令，恒返回 false（调用方回退到 [Player.seek] 等通用接口）。
Future<bool> runMpvCommand(Player player, List<String> args) async => false;
