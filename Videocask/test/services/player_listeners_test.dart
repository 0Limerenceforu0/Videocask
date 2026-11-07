import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/player_listeners.dart';

/// 播放器事件通道（多播）的测试。
///
/// 核心命题：**外部订阅的是「服务」而不是「某个 Player 实例」**，
/// 因此播放器实例被回收重建后，订阅者不会失效、也不会重复收到事件。
///
/// 这组用例直接对应真实缺陷：此前 `PlayerProvider` 直接订阅
/// `player.stream.position`，播放器一旦被回收重建，订阅就挂在已 dispose
/// 的旧实例上，表现为「回收一次，进度条永久冻结」。
void main() {
  group('PlayerEventChannel 多播', () {
    test('多个消费者并存，互不覆盖', () {
      final channel = PlayerEventChannel<int>();
      final a = <int>[];
      final b = <int>[];
      channel.add(a.add);
      channel.add(b.add);

      channel.emit(7);

      expect(a, [7]);
      expect(b, [7]);
    });

    test('同一监听器重复注册只生效一次（幂等装配）', () {
      final channel = PlayerEventChannel<int>();
      var count = 0;
      void handler(int _) => count++;

      channel.add(handler);
      channel.add(handler);

      channel.emit(1);

      expect(count, 1, reason: '重复装配不得导致事件被处理多次');
    });

    test('注销后不再收到事件', () {
      final channel = PlayerEventChannel<int>();
      final seen = <int>[];
      void handler(int v) => seen.add(v);

      channel.add(handler);
      channel.emit(1);
      channel.remove(handler);
      channel.emit(2);

      expect(seen, [1]);
      expect(channel.listenerCount, 0);
    });

    test('清空后所有消费者都不再收到事件', () {
      final channel = PlayerEventChannel<int>();
      var count = 0;
      channel.add((_) => count++);
      channel.add((_) => count++);

      channel.clear();
      channel.emit(1);

      expect(count, 0);
      expect(channel.hasListeners, isFalse);
    });
  });

  group('ListenerList 通知期变更安全', () {
    test('通知过程中移除的监听器，本轮被跳过', () {
      final list = ListenerList<int>();
      final seen = <int>[];
      late void Function(int) second;
      second = (v) {
        seen.add(v);
        list.remove(second);
      };
      list.add(second);
      list.add((v) => seen.add(v * 100));

      list.emit(1);
      list.emit(2);

      expect(seen, [1, 100, 200],
          reason: '被移除的监听器本轮不再收到，但其后的监听器仍要收到');
    });

    test('通知过程中新增的监听器，本轮不触发', () {
      final list = ListenerList<int>();
      final seen = <int>[];
      list.add((_) {
        list.add((v) => seen.add(v * 1000));
      });

      list.emit(1);

      expect(seen, isEmpty, reason: '新增监听器应从下一轮开始生效');
      list.emit(2);
      expect(seen, [2000]);
    });

    test('单个监听器抛异常不影响其它监听器', () {
      final list = ListenerList<int>();
      final seen = <int>[];
      list.add((_) => throw StateError('炸了'));
      list.add((v) => seen.add(v));

      list.emit(1);

      expect(seen, [1], reason: '一个监听器出错不得吞掉其它监听器的事件');
    });

    test('isEmpty / isNotEmpty 反映真实状态', () {
      final list = ListenerList<int>();
      expect(list.isEmpty, isTrue);
      list.add((_) {});
      expect(list.isNotEmpty, isTrue);
      expect(list.length, 1);
    });
  });

  group('回收重建场景（真实缺陷回归）', () {
    test('模拟 Player 重建：订阅者持续收到事件，不冻结也不重复', () {
      // 模拟：服务持有通道 → 播放器实例 A 重建为实例 B → 通道不变。
      final channel = PlayerEventChannel<int>();
      final seen = <int>[];
      channel.add(seen.add);

      // 实例 A 的一轮事件
      channel.emit(1);
      // 重建：旧实例 dispose，通道**不**重建（这是修复的核心）
      // 实例 B 的一轮事件
      channel.emit(2);

      expect(seen, [1, 2],
          reason: '重建后订阅者必须继续收到事件，不能永久冻结');
    });

    test('重建后重新装配不会产生重复事件', () {
      final channel = PlayerEventChannel<int>();
      var count = 0;
      void handler(int _) => count++;

      // 首次装配
      channel.add(handler);
      channel.emit(1);
      // 重建后「重新装配」（幂等）
      channel.add(handler);
      channel.emit(2);

      expect(count, 2, reason: '每个事件只应被处理一次');
    });
  });

  group('异步与并发安全', () {
    test('通知是同步的，不产生未处理的异步错误', () async {
      final channel = PlayerEventChannel<int>();
      channel.add((v) async {
        throw StateError('异步错误');
      });

      // 同步 emit 不会 await 监听器返回的 Future；用 runZoned 捕获未处理错误。
      final errors = <Object>[];
      await runZonedGuarded(() {
        channel.emit(1);
      }, (e, s) => errors.add(e));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 断言：emit 本身不抛；异步错误被 zone 捕获（不静默丢失）。
      expect(errors.isNotEmpty, isTrue,
          reason: '监听器内的异步异常应可被观测，而不是彻底消失');
    });
  });
}
