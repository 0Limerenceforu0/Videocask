import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/debug_log.dart';

/// fd 分类规则回归测试（2026-10-22）。
///
/// 背景：fd 泄漏的排查完全依赖「哪一类在涨」。2026-10-21/22 两次真机排查
/// 都栽在分类规则上：
/// - 最初只认 `anon_inode:[eventfd]` 的**方括号**形态 →
///   `anon_inode:sync_file`（无方括号）被归成 `anon:?`，而它正是
///   media-kit#1391 每帧泄漏的 GPU fence 对象 —— 分类一旦吞掉它，
///   泄漏类型就永远定位不到；
/// - `/dmabuf:0123` 以 `/` 开头，默认被算进 `file` → 「file 数稳定」
///   会给人"没有图形 buffer 泄漏"的错觉。
///
/// 另：2026-10-22 真机日志还暴露出**采样窗口**缺陷（`maxScan: 3000`
/// 只扫前 3000 个 fd，泄漏的 fd 永远在窗口外）。该缺陷无法在单测里复现
/// （依赖真机 /proc），只能靠真机复测验证；但分类规则本身是纯函数，
/// 必须锁死。
void main() {
  group('DebugLog.classifyFdTarget', () {
    test('匿名 inode：无方括号形态（GPU fence sync_file）', () {
      // 关键回归点：只认方括号形态时，这里会退化成 anon:?
      expect(
        DebugLog.classifyFdTarget('anon_inode:sync_file'),
        'anon:sync_file',
      );
    });

    test('匿名 inode：方括号形态（eventfd / epoll / timerfd）', () {
      expect(
        DebugLog.classifyFdTarget('anon_inode:[eventfd]'),
        'anon:eventfd',
      );
      expect(
        DebugLog.classifyFdTarget('anon_inode:[eventpoll]'),
        'anon:eventpoll',
      );
      expect(
        DebugLog.classifyFdTarget('anon_inode:[timerfd]'),
        'anon:timerfd',
      );
    });

    test('匿名 inode：带后缀只保留主类型，避免分类被拆散', () {
      expect(
        DebugLog.classifyFdTarget('anon_inode:dmabuf:0123'),
        'anon:dmabuf',
      );
    });

    test('dmabuf：以 / 开头但不能算成 file', () {
      // 关键回归点：默认按 '/' 判断会归成 file，掩盖图形 buffer 泄漏
      expect(
        DebugLog.classifyFdTarget('/dmabuf:0123'),
        'dmabuf',
      );
    });

    test('ashmem / gpu 设备节点单列', () {
      expect(
        DebugLog.classifyFdTarget('/dev/ashmem/dalvik'),
        'ashmem',
      );
      expect(
        DebugLog.classifyFdTarget('/dev/kgsl-3d0'),
        'gpu',
      );
      expect(
        DebugLog.classifyFdTarget('/dev/mali0'),
        'gpu',
      );
    });

    test('socket / pipe 各自成类', () {
      expect(DebugLog.classifyFdTarget('socket:[12345]'), 'socket');
      expect(DebugLog.classifyFdTarget('pipe:[999]'), 'pipe');
    });

    test('普通路径算 file', () {
      expect(
        DebugLog.classifyFdTarget('/data/app/com.example.movie_app/x.db'),
        'file',
      );
    });

    test('无法识别的目标归 other（不抛异常）', () {
      expect(DebugLog.classifyFdTarget('???'), 'other');
      expect(DebugLog.classifyFdTarget(''), 'other');
    });
  });
}
