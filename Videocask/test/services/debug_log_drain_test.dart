import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/debug_log.dart';

/// DebugLog 同步落盘队列回归测试（2026-11-08）。
///
/// 真机事故：8103 装机后 21:31:33~21:33 共 17 次 `调用 addMagnet`，
/// 只落下 2 条同批次的「放行」——旧实现 `IOSink.writeln` + 并发
/// `unawaited(flush())` 会在高并发 / 进程被杀时静默吞行。
/// 修复后每行走 `drainPending` → `RandomAccessFile.writeFromSync`，
/// 写失败整批保留。这里锁死「不丢行、不乱序、失败可重试」三条。
void main() {
  group('DebugLog.drainPending', () {
    test('一次写出全部暂存行，顺序不变且清空队列', () {
      final pending = <String>['a', 'b', 'c'];
      final written = <String>[];

      final n = DebugLog.drainPending(pending, written.add);

      expect(n, 3);
      expect(written, <String>['a\nb\nc\n']);
      expect(pending, isEmpty);
    });

    test('空队列不触发写操作', () {
      final pending = <String>[];
      var calls = 0;

      final n = DebugLog.drainPending(pending, (_) => calls++);

      expect(n, 0);
      expect(calls, 0);
      expect(pending, isEmpty);
    });

    test('写失败时整批留在队列，重试后仍按原顺序落盘', () {
      final pending = <String>['放行 快速', '调用 addMagnet', '元数据就绪'];
      var failOnce = true;
      final written = <String>[];

      expect(
        () => DebugLog.drainPending(pending, (text) {
          if (failOnce) {
            failOnce = false;
            throw const FileSystemException('模拟磁盘写失败');
          }
          written.add(text);
        }),
        throwsA(isA<FileSystemException>()),
      );
      expect(pending, <String>['放行 快速', '调用 addMagnet', '元数据就绪']);

      final n = DebugLog.drainPending(pending, written.add);
      expect(n, 3);
      expect(pending, isEmpty);
      expect(written.single, '放行 快速\n调用 addMagnet\n元数据就绪\n');
    });

    test('写盘往返：同步落盘后文件里行数与内容完全一致', () {
      final base = Directory(
        Platform.environment['TEMP'] ??
            Platform.environment['TMP'] ??
            Directory.systemTemp.path,
      );
      final dir = base.createTempSync('videocask_debug_log_test_');
      final file = File('${dir.path}${Platform.pathSeparator}probe.log');
      try {
        final raf = file.openSync(mode: FileMode.write);
        final pending = <String>[
          '21:31:56.48 [SubtitleProbe] 放行 快速',
          '21:31:56.49 [SubtitleProbe] 调用 addMagnet',
          '21:32:03.86 [SubtitleProbe] 元数据就绪',
        ];
        // 逐行调用，模拟 log() 的高频写入。
        for (final line in pending) {
          DebugLog.drainPending(<String>[line], (text) {
            raf.writeFromSync(utf8.encode(text));
          });
        }
        raf.flushSync();
        raf.closeSync();

        final lines = file.readAsLinesSync();
        expect(lines, pending);
      } finally {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });

  group('DebugLog 完整性快照', () {
    test('快照包含三个计数，便于真机核对有没有静默丢行', () {
      final snapshot = DebugLog.logIntegritySnapshot();
      expect(snapshot, contains('logged='));
      expect(snapshot, contains('written='));
      expect(snapshot, contains('pending='));
    });
  });
}
