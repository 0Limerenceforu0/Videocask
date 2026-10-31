import 'dart:async';

import 'package:flutter/foundation.dart';

import 'debug_log.dart';

/// 资源释放失败回调（生产走 [DebugLog]，测试可注入自己的实现）。
typedef ResourceReleaseFailureHandler = void Function(
  String scopeName,
  String label,
  Object error,
  StackTrace? stack,
);

/// 一条待释放的资源。
class _ScopedRelease {
  _ScopedRelease(this.label, this.action);

  /// 人类可读标签（诊断里显示，如 `subscription:position`）。
  final String label;

  /// 释放动作。抛异常会被捕获并隔离，不影响其余资源。
  final FutureOr<void> Function() action;
}

/// 资源作用域：把「谁持有、谁释放」从散落各处的 `dispose()` 显式化为一个容器。
///
/// ## 为什么需要它
///
/// 释放资源这件事，零散手写极易漏：本次审计在 `lib/` 下发现 18 个泄漏点，
/// 典型形态是「A 类释放了，B 类忘了」——比如 `DetailPlayer` 写了
/// `disposeLifecycleListener()` 却从未调用；`PlayerProvider` 自己维护了一份
/// 订阅列表，而真正会重建播放器的 `PlayerService` 并不知道它的存在。
///
/// ## 三条纪律
///
/// 1. **逆序释放（LIFO）**：后注册的资源先释放。依赖方向天然是
///    「订阅 → 播放器 → 底层句柄」，逆序释放才能保证被依赖方先于依赖方死亡。
///    正序释放会在订阅仍活着时销毁播放器，触发回调打到已死对象。
/// 2. **单项失败隔离**：某一项释放抛异常，不得阻断其余资源的释放。
///    释放失败必须**可见**（记入 [_failures] 并写诊断日志），否则"没释放"
///    就变成了黑盒，无法排查。
/// 3. **幂等**：重复 [dispose] 安全。页面重建、异常路径、应用退出都可能
///    重复触发释放，第二次必须是空操作而不是二次释放。
///
/// ## 用法
///
/// ```dart
/// final scope = ResourceScope(name: 'player');
/// scope.addSubscription(player.stream.position.listen(onPos));
/// scope.addNotifier(valueNotifier);
/// await scope.dispose();   // 逆序释放全部
/// ```
class ResourceScope {
  ResourceScope({this.name = 'scope'});

  /// 作用域名（诊断里区分不同来源，如 `player` / `detail-page`）。
  final String name;

  final List<_ScopedRelease> _releases = [];

  int _registeredCount = 0;
  int _releasedCount = 0;
  final List<String> _failures = [];

  bool _disposed = false;

  /// 释放失败回调；默认写诊断日志。
  static ResourceReleaseFailureHandler failureHandler = (
    String scopeName,
    String label,
    Object error,
    StackTrace? stack,
  ) {
    DebugLog.log(
      'Resource',
      '释放失败 scope=$scopeName label=$label error=$error',
      flush: true,
    );
  };

  /// 本作用域是否已释放。
  bool get isDisposed => _disposed;

  /// 累计注册过的资源数。
  int get registeredCount => _registeredCount;

  /// 累计成功释放的资源数。
  int get releasedCount => _releasedCount;

  /// 释放失败的资源标签。
  List<String> get failures => List.unmodifiable(_failures);

  /// 尚未释放的资源数（已释放后恒为 0）。
  int get pendingCount => _disposed ? 0 : _releases.length;

  /// 是否存在释放失败（用于诊断告警）。
  bool get hasFailures => _failures.isNotEmpty;

  /// 注册一个自定义释放动作。
  ///
  /// [action] 可以是同步或异步函数；返回的 Future 会被 await。
  void add(String label, FutureOr<void> Function() action) {
    if (_disposed) {
      // 作用域已释放后再注册，说明调用顺序有问题：立刻释放，避免资源泄漏。
      _safeRun(label, action);
      return;
    }
    _releases.add(_ScopedRelease(label, action));
    _registeredCount++;
  }

  /// 注册一个 Stream 订阅。
  void addSubscription(
    StreamSubscription<dynamic> subscription, {
    String label = 'subscription',
  }) {
    add(label, () => subscription.cancel());
  }

  /// 注册一个 [ChangeNotifier]（含 [ValueNotifier]）。
  void addNotifier(ChangeNotifier notifier, {String label = 'notifier'}) {
    add(label, notifier.dispose);
  }

  /// 注册一个定时器。
  void addTimer(Timer timer, {String label = 'timer'}) {
    add(label, timer.cancel);
  }

  /// 释放全部资源（逆序）。可重复调用。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // 逆序释放：后注册的先释放（依赖方先死，被依赖方后死）。
    for (final entry in _releases.reversed.toList(growable: false)) {
      await _safeRun(entry.label, entry.action);
    }
    _releases.clear();
    ResourceScopeRegistry.untrack(this);
  }

  /// 执行单个释放动作，捕获并隔离异常。
  Future<void> _safeRun(String label, FutureOr<void> Function() action) async {
    try {
      await action();
      _releasedCount++;
    } catch (e, stack) {
      _failures.add(label);
      try {
        failureHandler(name, label, e, stack);
      } catch (_) {
        // 失败回调自身出错不能影响释放流程。
      }
    }
  }

  @override
  String toString() =>
      'ResourceScope($name, registered=$_registeredCount, released=$_releasedCount, '
      'pending=$pendingCount, failures=${_failures.length})';
}

/// 存活资源作用域登记表：供「设置 → 诊断」查看还有哪些作用域没释放。
///
/// 目的不是"回收"（作用域由各自持有者负责释放），而是**可观测**：
/// 一旦某个作用域长期挂在登记表里，说明它的持有者漏了 dispose。
class ResourceScopeRegistry {
  ResourceScopeRegistry._();

  static final Map<String, ResourceScope> _live = {};

  /// 登记一个作用域。
  static void track(ResourceScope scope) {
    _live[scope.name] = scope;
  }

  /// 注销一个作用域。
  static void untrack(ResourceScope scope) {
    if (_live[scope.name] == scope) {
      _live.remove(scope.name);
    }
  }

  /// 当前存活的作用域。
  static List<ResourceScope> get live => _live.values.toList(growable: false);

  /// 存活作用域数量。
  static int get liveCount => _live.length;

  /// 诊断摘要。
  static String describe() {
    if (_live.isEmpty) return '无存活资源作用域';
    final parts = _live.values.map((s) => s.toString()).toList()..sort();
    return parts.join('；');
  }

  /// 清空登记表（仅测试用）。
  static void reset() => _live.clear();
}
