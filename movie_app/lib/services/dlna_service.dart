import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';

/// DLNA设备信息
class DlnaDevice {
  final String name;
  final String location;
  final String uuid;
  final String model;
  final String manufacturer;

  /// 底层DLNA设备实例
  final DLNADevice nativeDevice;

  DlnaDevice({
    required this.name,
    required this.location,
    required this.uuid,
    this.model = '',
    this.manufacturer = '',
    required this.nativeDevice,
  });
}

/// DLNA投屏服务（Android 局域网 DLNA Push URL）
class DlnaService {
  DlnaService._();
  static final DlnaService _instance = DlnaService._();
  factory DlnaService() => _instance;

  final List<DlnaDevice> _devices = [];
  List<DlnaDevice> get devices => List.unmodifiable(_devices);

  DlnaDevice? _currentDevice;
  DlnaDevice? get currentDevice => _currentDevice;

  String? _castingUrl;
  String? get castingUrl => _castingUrl;

  bool _isSearching = false;
  bool get isSearching => _isSearching;

  bool _isCasting = false;
  bool get isCasting => _isCasting;

  DLNAManager? _manager;
  DeviceManager? _deviceManager;
  StreamSubscription<Map<String, DLNADevice>>? _deviceSub;

  /// 幂等守卫：dispose 可能被应用退出路径与测试析构多次调用。
  bool _released = false;

  /// 搜索超时定时器句柄：必须持有才能取消（旧实现丢弃句柄，stopSearch
  /// 取消不掉，面板每开合一次泄漏一个 12s 定时器 + 捕获单例的闭包）。
  Timer? _searchTimeoutTimer;

  /// 进行中的搜索对应的 Completer：stopSearch 时完成它，
  /// 防止旧调用方的 future 永久挂起（其唯一完成者就是那个定时器）。
  Completer<List<DlnaDevice>>? _searchCompleter;

  /// 设备管理器工厂：默认真实实现；测试注入假实现以避开 UDP 1900 绑定。
  DLNAManager Function() createManager = DLNAManager.new;

  static const int searchTimeoutSec = 12;

  Future<List<DlnaDevice>> searchDevices({
    Duration timeout = const Duration(seconds: searchTimeoutSec),
  }) async {
    // 已有搜索在进行：返回当前设备的**快照**（旧实现返回内部列表本体，
    // 调用方手里的列表会被后续 syncDevices 改写）。
    if (_isSearching) return List<DlnaDevice>.from(_devices);

    // 先停旧搜索：取消其定时器并完成其 completer（旧 caller 拿到旧快照），
    // 必须早于置 _isSearching，否则会被 stopSearch 复位。
    stopSearch();

    _isSearching = true;
    _devices.clear();

    final completer = Completer<List<DlnaDevice>>();
    _searchCompleter = completer;

    void finish(List<DlnaDevice> result) {
      _searchTimeoutTimer?.cancel();
      _searchTimeoutTimer = null;
      _searchCompleter = null;
      _isSearching = false;
      if (!completer.isCompleted) completer.complete(result);
    }

    try {
      _manager = createManager();
      _deviceManager = await _manager!.start();

      void syncDevices(Map<String, DLNADevice> map) {
        _devices
          ..clear()
          ..addAll(
            map.entries.map((entry) {
              final native = entry.value;
              final info = native.info;
              return DlnaDevice(
                name: info.friendlyName.trim().isNotEmpty
                    ? info.friendlyName
                    : 'DLNA 设备',
                location: info.URLBase,
                uuid: entry.key,
                model: info.deviceType,
                nativeDevice: native,
              );
            }),
          );
      }

      syncDevices(_deviceManager!.deviceList);

      _deviceSub = _deviceManager!.devices.stream.listen(syncDevices);

      _searchTimeoutTimer = Timer(timeout, () {
        _searchTimeoutTimer = null;
        finish(List<DlnaDevice>.from(_devices));
      });

      return completer.future;
    } catch (e) {
      debugPrint('搜索DLNA设备失败: $e');
      finish(_devices);
      return _devices;
    }
  }

  void stopSearch() {
    _searchTimeoutTimer?.cancel();
    _searchTimeoutTimer = null;
    // 完成挂起的搜索：旧调用方立即拿到当前设备快照，不会永久挂起。
    final pending = _searchCompleter;
    _searchCompleter = null;
    _isSearching = false;
    if (pending != null && !pending.isCompleted) {
      pending.complete(List<DlnaDevice>.from(_devices));
    }
    _deviceSub?.cancel();
    _deviceSub = null;
    _manager?.stop();
    _manager = null;
    _deviceManager = null;
  }

  Future<bool> connectDevice(DlnaDevice device) async {
    try {
      _currentDevice = device;
      return true;
    } catch (e) {
      debugPrint('连接DLNA设备失败: $e');
      return false;
    }
  }

  Future<bool> castPlay(String url, {String title = ''}) async {
    if (_currentDevice == null) {
      debugPrint('未连接DLNA设备');
      return false;
    }

    try {
      if (_isCasting) {
        await _currentDevice!.nativeDevice.stop();
      }
      await _currentDevice!.nativeDevice.setUrl(
        url,
        title: title.isNotEmpty ? title : url,
        type: VideoMime.any,
      );
      await _currentDevice!.nativeDevice.play();
      final started = await _waitForCastPlayback();
      if (!started) {
        debugPrint('投屏未进入播放状态: $url');
        await _currentDevice!.nativeDevice.stop();
        _isCasting = false;
        _castingUrl = null;
        return false;
      }
      _isCasting = true;
      _castingUrl = url;
      debugPrint('投屏播放成功: $url');
      return true;
    } catch (e) {
      debugPrint('投屏播放失败: $e');
      _isCasting = false;
      _castingUrl = null;
      return false;
    }
  }

  Future<bool> _waitForCastPlayback() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      try {
        final raw = await _currentDevice!.nativeDevice.getTransportInfo();
        if (raw.contains('CurrentTransportState>PLAYING') ||
            raw.contains('CurrentTransportState>TRANSITIONING')) {
          return true;
        }
        if (raw.contains('CurrentTransportState>PAUSED_PLAYBACK')) {
          await _currentDevice!.nativeDevice.play();
          return true;
        }
      } catch (e) {
        debugPrint('读取投屏状态失败: $e');
      }
    }
    return false;
  }

  Future<bool> castPause() async {
    if (_currentDevice == null) return false;
    try {
      await _currentDevice!.nativeDevice.pause();
      return true;
    } catch (e) {
      debugPrint('投屏暂停失败: $e');
      return false;
    }
  }

  Future<bool> castResume() async {
    if (_currentDevice == null) return false;
    try {
      await _currentDevice!.nativeDevice.play();
      return true;
    } catch (e) {
      debugPrint('投屏继续播放失败: $e');
      return false;
    }
  }

  Future<bool> castStop() async {
    if (_currentDevice == null) return false;
    try {
      await _currentDevice!.nativeDevice.stop();
      _isCasting = false;
      _castingUrl = null;
      return true;
    } catch (e) {
      debugPrint('投屏停止失败: $e');
      return false;
    }
  }

  Future<bool> castSeek(Duration position) async {
    if (_currentDevice == null) return false;
    try {
      final hours = position.inHours;
      final minutes = position.inMinutes.remainder(60);
      final seconds = position.inSeconds.remainder(60);
      final target =
          '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      await _currentDevice!.nativeDevice.seek(target);
      return true;
    } catch (e) {
      debugPrint('投屏跳转失败: $e');
      return false;
    }
  }

  Future<bool> castSetVolume(int volume) async {
    if (_currentDevice == null) return false;
    try {
      await _currentDevice!.nativeDevice.volume(volume.clamp(0, 100));
      return true;
    } catch (e) {
      debugPrint('设置投屏音量失败: $e');
      return false;
    }
  }

  Future<void> disconnectDevice() async {
    if (_isCasting) {
      await castStop();
    }
    _currentDevice = null;
    _isCasting = false;
    _castingUrl = null;
  }

  void dispose() {
    // 幂等：单例可能被应用退出路径与测试析构多次调用。
    if (_released) return;
    _released = true;
    stopSearch();
    unawaited(disconnectDevice());
  }
}
