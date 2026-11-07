import 'dart:async';

import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/dlna_service.dart';

/// DLNA 搜索生命周期回归测试（2026-10-20）。
///
/// 背景：`searchDevices` 旧实现把 `Timer(timeout, …)` 的句柄直接丢弃：
/// - `stopSearch()` 取消不掉它 → 面板每开合一次泄漏一个 12s 定时器
///   （闭包捕获 completer + 整个 DlnaService 单例）；
/// - `finally { _isSearching = false; }` 在返回 future 时同步执行，
///   12s 窗口内重入守卫失效，第二次搜索的 stopSearch 杀掉第一次的
///   `_deviceSub` 后，第一次的 completer 唯一完成者（那个定时器）
///   已被取消 → 旧 caller 的 future **永久挂起**；
/// - 旧定时器到点仍 complete，stopSearch 之后拿到的可能是
///   新一批设备的混合快照（陈旧完成）。
///
/// 用假 DeviceManager/DLNAManager 驱动真实 DlnaService
/// （经 `createManager` 工厂注入，避免绑定 UDP 1900）。
void main() {
  group('DlnaService 搜索生命周期', () {
    late DlnaService service;
    late _FakeManager fakeManager;

    setUp(() {
      service = DlnaService();
      service.stopSearch(); // 清掉上一个用例可能残留的状态
      fakeManager = _FakeManager();
      service.createManager = () => fakeManager;
    });

    tearDown(() {
      service.stopSearch();
    });

    test('超时后返回已发现的设备', () async {
      fakeManager.deviceManager.addDevice('客厅电视');

      final devices = await service.searchDevices(
        timeout: const Duration(milliseconds: 100),
      );

      expect(devices.length, 1);
      expect(devices.single.name, '客厅电视');
      expect(service.isSearching, isFalse, reason: '搜索结束后应复位');
    });

    test('stopSearch 提前完成挂起的搜索（旧 caller 不挂死）', () async {
      fakeManager.deviceManager.addDevice('电视');

      // 超时 10s：若 stopSearch 不完成 completer，这个 await 会挂到测试超时。
      final future = service.searchDevices(
        timeout: const Duration(seconds: 10),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      service.stopSearch();

      // 旧 caller 必须立即拿到快照；若挂起则本测试整体超时失败。
      final devices = await future.timeout(const Duration(seconds: 2));
      expect(devices.length, 1);
      expect(service.isSearching, isFalse);
    });

    test('搜索进行中重复调用：返回快照且不打断第一次搜索', () async {
      fakeManager.deviceManager.addDevice('第一批');

      final first = service.searchDevices(
        timeout: const Duration(milliseconds: 250),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // 第二次调用：旧实现会走完整流程并 stopSearch 杀掉第一次的订阅
      final second = await service.searchDevices().timeout(
        const Duration(seconds: 2),
      );
      expect(second.length, 1, reason: '快照应包含已发现的设备');

      // 第一次搜索不受影响，正常超时完成
      final firstResult = await first.timeout(const Duration(seconds: 2));
      expect(firstResult.length, 1);
    });

    test('stopSearch 之后旧定时器不再产生陈旧完成', () async {
      fakeManager.deviceManager.addDevice('旧设备');

      final future = service.searchDevices(
        timeout: const Duration(milliseconds: 120),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      service.stopSearch();
      await future; // 提前完成

      // 等过原超时点：旧定时器若未取消，到这里还会唤醒一次
      // （complete 被 isCompleted 挡住，但闭包会拖住单例）。
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // 之后发起新搜索：旧定时器不得把新搜索搅乱（挂起/提前完成）
      fakeManager.deviceManager.addDevice('新设备');
      final devices = await service.searchDevices(
        timeout: const Duration(milliseconds: 80),
      );
      expect(devices.map((d) => d.name), contains('新设备'));
    });

    test('manager.start 抛错：返回空列表且状态复位，可再次搜索', () async {
      fakeManager.failStart = true;

      final devices = await service.searchDevices(
        timeout: const Duration(milliseconds: 100),
      );
      expect(devices, isEmpty);
      expect(service.isSearching, isFalse, reason: '异常路径也必须复位');

      // 状态未卡死：恢复后可正常搜索
      fakeManager.failStart = false;
      fakeManager.deviceManager.addDevice('恢复后');
      final ok = await service.searchDevices(
        timeout: const Duration(milliseconds: 100),
      );
      expect(ok.length, 1);
    });

    test('dispose 收口：stopSearch + 断开设备，可安全重复调用', () {
      expect(() => service.dispose(), returnsNormally);
      expect(() => service.dispose(), returnsNormally);
      expect(service.isSearching, isFalse);
    });
  });
}

/// 假 DeviceManager：直接操作继承来的 `deviceList` map 与 `devices` 流。
class _FakeDeviceManager extends DeviceManager {
  void addDevice(String name) {
    final info = DeviceInfo(
      'http://127.0.0.1:12345/',
      'MediaRenderer',
      name,
      <dynamic>[],
    );
    deviceList[name] = DLNADevice(info);
    if (!devices.isClosed) devices.add(deviceList);
  }
}

/// 假 DLNAManager：不绑定 UDP，start 返回假 DeviceManager。
class _FakeManager extends DLNAManager {
  final _FakeDeviceManager deviceManager = _FakeDeviceManager();
  bool failStart = false;

  @override
  Future<DeviceManager> start({reusePort = false}) async {
    if (failStart) throw StateError('模拟启动失败');
    return deviceManager;
  }

  @override
  void stop() {}
}
