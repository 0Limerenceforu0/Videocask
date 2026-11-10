import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/download_export.dart';

void main() {
  group('导出通道选择（跨平台回归）', () {
    test('Web 端不写文件，无论平台标记如何都降级剪贴板', () {
      expect(
        resolveDownloadExportRoute(isWeb: true, isAndroid: false),
        DownloadExportRoute.unsupported,
      );
      expect(
        resolveDownloadExportRoute(isWeb: true, isAndroid: true),
        DownloadExportRoute.unsupported,
      );
    });

    test('Android 走 MediaStore 原生通道，避免私有目录取不出', () {
      expect(
        resolveDownloadExportRoute(isWeb: false, isAndroid: true),
        DownloadExportRoute.nativeMediaStore,
      );
    });

    test('桌面端没有原生通道，必须直接写文件（旧实现会抛 MissingPluginException）', () {
      expect(
        resolveDownloadExportRoute(isWeb: false, isAndroid: false),
        DownloadExportRoute.directFile,
      );
    });
  });

  group('桌面分支：文件确实被写到用户可见目录', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('videocask_download_export_');
    });

    tearDown(() async {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('目标目录不存在时自动创建，文本内容一致，返回绝对路径', () async {
      final src = File('${root.path}${Platform.pathSeparator}source.json');
      await src.writeAsString('{"hello":"world"}');
      final destDir = Directory('${root.path}${Platform.pathSeparator}Downloads');
      expect(destDir.existsSync(), isFalse);

      final result = await DownloadExport.copyIntoDirectory(
        sourcePath: src.path,
        name: 'videocask_backup_test.json',
        dir: destDir,
      );

      final dest = File(
        '${destDir.path}${Platform.pathSeparator}videocask_backup_test.json',
      );
      expect(destDir.existsSync(), isTrue);
      expect(dest.existsSync(), isTrue);
      expect(await dest.readAsString(), '{"hello":"world"}');
      expect(result, dest.path);
      // 临时源文件由调用方的 finally 负责删除，helper 不能顺手删掉。
      expect(src.existsSync(), isTrue);
    });

    test('二进制 zip 逐字节一致（诊断日志走这条）', () async {
      final bytes = <int>[0x50, 0x4B, 0x03, 0x04, 0x00, 0xFF, 0x10, 0x00];
      final src = File('${root.path}${Platform.pathSeparator}source.zip');
      await src.writeAsBytes(bytes);
      final destDir = Directory('${root.path}${Platform.pathSeparator}Downloads')
        ..createSync();

      final result = await DownloadExport.copyIntoDirectory(
        sourcePath: src.path,
        name: 'videocask_logs_test.zip',
        dir: destDir,
      );

      expect(await File(result).readAsBytes(), bytes);
    });

    test('同名文件重复导出会覆盖，不残留旧内容', () async {
      final src = File('${root.path}${Platform.pathSeparator}source.json');
      final destDir = Directory('${root.path}${Platform.pathSeparator}Downloads')
        ..createSync();
      await src.writeAsString('first');

      await DownloadExport.copyIntoDirectory(
        sourcePath: src.path,
        name: 'backup.json',
        dir: destDir,
      );
      await src.writeAsString('second-longer');
      final result = await DownloadExport.copyIntoDirectory(
        sourcePath: src.path,
        name: 'backup.json',
        dir: destDir,
      );

      expect(await File(result).readAsString(), 'second-longer');
      expect(
        destDir.listSync().whereType<File>().length,
        1,
        reason: '不应为每次导出堆一份副本',
      );
    });
  });

  group('write() 端到端：桌面分支在真实调用链下也能落盘', () {
    late Directory root;
    late Directory downloads;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      root = await Directory.systemTemp.createTemp('videocask_write_e2e_');
      downloads = Directory('${root.path}${Platform.pathSeparator}Downloads');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => switch (call.method) {
          'getDownloadsDirectory' => downloads.path,
          'getApplicationDocumentsDirectory' => root.path,
          'getTemporaryDirectory' => root.path,
          _ => null,
        },
      );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('导出后目标文件存在且内容一致，源文件仍由调用方清理', () async {
      final src = File('${root.path}${Platform.pathSeparator}backup.json');
      await src.writeAsString('{"a":1}');

      final dest = await DownloadExport.write(
        sourcePath: src.path,
        name: 'videocask_backup_e2e.json',
      );
      final f = File(dest);
      try {
        expect(f.existsSync(), isTrue);
        expect(await f.readAsString(), '{"a":1}');
        expect(src.existsSync(), isTrue);
      } finally {
        // 若平台插件走了真实下载目录（FFI 绕过 channel mock），也不能留垃圾。
        if (f.existsSync()) f.deleteSync();
      }
    });
  });
}
