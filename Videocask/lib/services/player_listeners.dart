/// 播放事件的多播通道。
///
/// ## 为什么需要多播，而不是单值回调
///
/// 播放器实例会被**回收重建**（切换视频输出后端时会重建）。如果外部
/// 直接订阅 `player.stream.position`，这个订阅会挂在**已被 dispose 的旧 Player
/// 实例**上：重建后旧流不再发事件，外部拿到的进度/时长/缓冲会**永久冻结**，
/// 而外部甚至不知道自己失效了。
///
/// 正确做法是让外部订阅**服务**（[PlayerService]）而不是某个 Player 实例：
/// 服务在重建后会重新接上 mpv 的流，事件通道随之恢复，订阅者完全无感。
///
/// 附带好处：多个消费者可以并存（详情页 + 迷你播放器），互不覆盖。
library;

/// 多播监听器集合：持有 `void Function(T)` 监听器，广播 `T` 事件。
///
/// 语义：
/// - 通知过程中增删监听器是安全的（新增者本轮不通知，删除者本轮跳过）；
/// - 单个监听器抛异常不影响其余监听器；
/// - 同一监听器重复 [add] 不会重复注册（配合「幂等装配」）。
class ListenerList<T> {
  final List<void Function(T)> _listeners = <void Function(T)>[];

  /// 通知过程中发生的删除，延迟到本轮结束后生效。
  final List<void Function(T)> _deferredRemovals = <void Function(T)>[];

  bool _notifying = false;

  /// 监听器数量。
  int get length => _listeners.length;

  /// 是否没有监听器。
  bool get isEmpty => _listeners.isEmpty;

  /// 是否存在监听器。
  bool get isNotEmpty => _listeners.isNotEmpty;

  /// 注册监听器（重复注册同一实例会被忽略）。
  void add(void Function(T) listener) {
    if (_listeners.contains(listener)) return;
    _listeners.add(listener);
  }

  /// 注销监听器。
  void remove(void Function(T) listener) {
    if (_notifying) {
      if (!_deferredRemovals.contains(listener)) {
        _deferredRemovals.add(listener);
      }
      return;
    }
    _listeners.remove(listener);
  }

  /// 清空全部监听器。
  void clear() {
    _listeners.clear();
    _deferredRemovals.clear();
  }

  /// 广播一个事件给全部监听器。
  void emit(T value) {
    _notifying = true;
    try {
      final snapshot = List<void Function(T)>.of(_listeners, growable: false);
      for (final listener in snapshot) {
        if (_deferredRemovals.contains(listener)) continue;
        try {
          listener(value);
        } catch (_) {
          // 单个监听器出错不得影响其余监听器。
        }
      }
    } finally {
      _notifying = false;
      if (_deferredRemovals.isNotEmpty) {
        _listeners.removeWhere(_deferredRemovals.contains);
        _deferredRemovals.clear();
      }
    }
  }
}

/// 播放器事件通道（多播）。
///
/// 用法：
/// ```dart
/// playerService.positionChanged.add(myHandler);
/// playerService.positionChanged.remove(myHandler);
/// ```
class PlayerEventChannel<T> {
  final ListenerList<T> _listeners = ListenerList<T>();

  /// 注册监听器。
  void add(void Function(T) listener) => _listeners.add(listener);

  /// 注销监听器。
  void remove(void Function(T) listener) => _listeners.remove(listener);

  /// 清空全部监听器（服务销毁时用）。
  void clear() => _listeners.clear();

  /// 当前监听器数量（诊断用）。
  int get listenerCount => _listeners.length;

  /// 是否存在监听器。
  bool get hasListeners => _listeners.isNotEmpty;

  /// 广播一个事件。
  void emit(T value) => _listeners.emit(value);
}
