import 'package:media_kit/media_kit.dart';

/// mpv 专有能力的桌面/移动端实现（[Player] 的 platform 为 [NativePlayer] 时生效）。
///
/// 非 mpv 后端（如 Web）一律返回空值/不执行，调用方按返回值降级。

/// 读取 mpv 属性，非 NativePlayer 时返回 null。
Future<String?> getMpvProperty(Player player, String name) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return null;
  return platform.getProperty(name);
}

/// 设置 mpv 属性，非 NativePlayer 时静默跳过。
Future<void> setMpvProperty(Player player, String name, String value) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  await platform.setProperty(name, value);
}

/// 执行 mpv 命令，成功返回 true；非 NativePlayer 或失败返回 false。
Future<bool> runMpvCommand(Player player, List<String> args) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return false;
  await platform.command(args);
  return true;
}
