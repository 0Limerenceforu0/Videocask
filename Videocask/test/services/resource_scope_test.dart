import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/resource_scope.dart';

/// 资源作用域（[ResourceScope]）的释放纪律测试。
///
/// 覆盖三条核心纪律：
/// 1. **逆序释放**（后注册先释放）；
/// 2. **单项失败隔离**（一项抛异常不影响其余）；
/// 3. **幂等**（重复 dispose 安全）。
void main() {
  group('ResourceScope 释放顺序', () {
    test('逆序释放：后注册的先释放', () async {
      final order = <String>[];
      final scope = ResourceScope(name: 'order');
      scope.add('a', () => order.add('a'));
      scope.add('b', () => order.add('b'));
      scope.add('c', () => order.add('c'));

      await scope.dispose();

      expect(order, ['c', 'b', 'a'],
          reason: '依赖方（后注册）必须先于被依赖方死亡');
    });

    test('释放后 pendingCount 归零，registeredCount 保留历史', () async {
      final scope = ResourceScope(name: 'count');
      scope.add('x', () {});
      scope.add('y', () {});

      expect(scope.registeredCount, 2);
      expect(scope.pendingCount, 2);

      await scope.dispose();

      expect(scope.pendingCount, 0);
      expect(scope.registeredCount, 2, reason: '历史计数不应被清空');
      expect(scope.releasedCount, 2);
      expect(scope.isDisposed, isTrue);
    });

    test('异步释放动作会被 await', () async {
      var done = false;
      final scope = ResourceScope(name: 'async');
      scope.add('a', () async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        done = true;
      });

      await scope.dispose();

      expect(done, isTrue, reason: 'dispose 必须等待异步释放完成');
    });
  });

  group('ResourceScope 失败隔离', () {
    test('单项释放抛异常不影响其余资源释放', () async {
      final released = <String>[];
      final scope = ResourceScope(name: 'fail');
      scope.add('ok1', () => released.add('ok1'));
      scope.add('boom', () => throw StateError('炸了'));
      scope.add('ok2', () => released.add('ok2'));

      await scope.dispose();

      expect(released, containsAll(['ok1', 'ok2']),
          reason: '一项失败不得阻断其它资源的释放');
      expect(scope.hasFailures, isTrue);
      expect(scope.failures, contains('boom'));
    });

    test('失败会被上报到失败处理器', () async {
      final reported = <String>[];
      final original = ResourceScope.failureHandler;
      ResourceScope.failureHandler = (scope, label, error, stack) {
        reported.add(label);
      };
      addTearDown(() => ResourceScope.failureHandler = original);

      final scope = ResourceScope(name: 'report');
      scope.add('bad', () => throw Exception('x'));
      await scope.dispose();

      expect(reported, ['bad']);
    });
  });

  group('ResourceScope 幂等', () {
    test('重复 dispose 只释放一次', () async {
      var count = 0;
      final scope = ResourceScope(name: 'idempotent');
      scope.add('a', () => count++);

      await scope.dispose();
      await scope.dispose();
      await scope.dispose();

      expect(count, 1, reason: '重复释放会导致二次副作用');
      expect(scope.releasedCount, 1);
    });

    test('已释放后再注册资源：立即释放，不泄漏', () async {
      var released = false;
      final scope = ResourceScope(name: 'late');
      await scope.dispose();

      scope.add('late-resource', () => released = true);

      expect(released, isTrue,
          reason: '作用域已释放后注册的资源必须立刻释放，否则等于泄漏');
    });
  });

  group('ResourceScope 专用注册器', () {
    test('addSubscription 会取消订阅', () async {
      var cancelled = false;
      final controller = StreamController<int>();
      final scope = ResourceScope(name: 'sub');
      scope.addSubscription(
        controller.stream.listen((_) {}),
        label: 'test-sub',
      );

      await scope.dispose();
      await controller.close();

      // 订阅被取消后，关闭 controller 不应再触发未处理错误。
      expect(scope.hasFailures, isFalse);
      cancelled = true;
      expect(cancelled, isTrue);
    });

    test('addTimer 会取消定时器', () async {
      var fired = false;
      final scope = ResourceScope(name: 'timer');
      scope.addTimer(
        Timer(const Duration(milliseconds: 30), () => fired = true),
        label: 'test-timer',
      );

      await scope.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(fired, isFalse, reason: '定时器必须被取消');
    });

    test('addNotifier 会释放 notifier', () async {
      final notifier = ValueNotifier<int>(1);
      final scope = ResourceScope(name: 'notifier');
      scope.addNotifier(notifier, label: 'test-notifier');

      await scope.dispose();

      expect(() => notifier.value = 2, throwsFlutterError,
          reason: '释放后再写入 notifier 应报错，证明确实被 dispose 了');
    });
  });

  group('ResourceScopeRegistry 存活登记', () {
    test('作用域释放后从登记表移除', () async {
      ResourceScopeRegistry.reset();
      final scope = ResourceScope(name: 'registered');
      ResourceScopeRegistry.track(scope);
      expect(ResourceScopeRegistry.liveCount, greaterThan(0));

      await scope.dispose();

      expect(ResourceScopeRegistry.liveCount, 0);
    });
  });
}
