import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 应用数据存放位置的统一入口。
///
/// **桌面端（Windows / Linux / macOS）一律使用「软件所在目录」**（可执行文件旁），
/// 目的是绿色便携：整个文件夹拷到 U 盘或换台电脑，模型与离线缓存跟着走，
/// 卸载时删掉文件夹就干净了，不会在「文档」「AppData」里留残骸。
///
/// 移动端 / Web 端不具备这个前提，仍走系统约定目录：
/// - Android / iOS：`getApplicationSupportDirectory()`
/// - Web：不支持本地文件，调用方需在入口处自行短路
abstract final class AppDataPaths {
  /// 缓存探测结果：设置页会频繁读取可用性与体积，不必每次都做磁盘探测。
  static Directory? _cachedRoot;

  /// 数据根目录。桌面端 = 软件所在目录；移动端 = 应用支持目录。
  ///
  /// 若软件所在目录不可写（例如装在 Program Files 又无管理员权限），
  /// 自动降级回系统目录，避免直接崩溃 —— 此时就不再「便携」了。
  static Future<Directory> root() async {
    final cached = _cachedRoot;
    if (cached != null) return cached;
    if (kIsWeb) return Directory('');
    if (Platform.isAndroid || Platform.isIOS) {
      return _cachedRoot = await getApplicationSupportDirectory();
    }
    final portable = _executableSiblingDir();
    if (portable != null && await _isWritable(portable)) {
      return _cachedRoot = portable;
    }
    debugPrint(
      'AppDataPaths: 软件所在目录不可写，已降级到应用支持目录。'
      '（建议把程序放在非 Program Files 的可写目录，以保持绿色便携）',
    );
    return _cachedRoot = await getApplicationSupportDirectory();
  }

  /// AI 离线字幕模型根目录：<root>/subtitle_ai_models
  static Future<Directory> modelsRoot() async {
    if (kIsWeb) return Directory('');
    final base = await root();
    return Directory('${base.path}${Platform.pathSeparator}subtitle_ai_models');
  }

  /// 离线影视缓存根目录：<root>/cache
  static Future<Directory> cacheRoot() async {
    if (kIsWeb) return Directory('');
    final base = await root();
    return Directory('${base.path}${Platform.pathSeparator}cache');
  }

  /// 可执行文件所在目录；取不到时返回 null。
  static Directory? _executableSiblingDir() {
    try {
      final exe = Platform.resolvedExecutable;
      if (exe.isEmpty) return null;
      final sep = Platform.pathSeparator;
      var path = File(exe).parent.path;
      // macOS：xxx.app/Contents/MacOS/xxx → 取 .app 的父目录。
      // 写进 Contents/MacOS 会把数据埋在 bundle 内部，还可能破坏签名。
      if (Platform.isMacOS) {
        final appIdx = path.lastIndexOf('.app$sep');
        if (appIdx > 0) {
          final parentSep = path.lastIndexOf(sep, appIdx - 1);
          path = parentSep < 0 ? path : path.substring(0, parentSep);
        }
      }
      return Directory(path);
    } catch (_) {
      return null;
    }
  }

  /// 目录是否可写（写一个探针文件再删掉）。
  static Future<bool> _isWritable(Directory dir) async {
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
      final probe = File(
        '${dir.path}${Platform.pathSeparator}.write_probe_'
        '${DateTime.now().millisecondsSinceEpoch}',
      );
      await probe.writeAsString('ok');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
