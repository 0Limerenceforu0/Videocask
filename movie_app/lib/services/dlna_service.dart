import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dlna_dart/dlna.dart';

/// DLNA设备信息
class DlnaDevice {
  final String name;
  final String location;
  final String uuid;
  final String model;
  final String manufacturer;

  /// 底层DLNA设备实例
  final dynamic nativeDevice;

  DlnaDevice({
    required this.name,
    required this.location,
    required this.uuid,
    this.model = '',
    this.manufacturer = '',
    this.nativeDevice,
  });
}

/// DLNA投屏服务
/// 使用 dlna_dart 包实现设备发现与控制
class DlnaService {
  DlnaService._();
  static final DlnaService _instance = DlnaService._();
  factory DlnaService() => _instance;

  /// 发现的设备列表
  final List<DlnaDevice> _devices = [];

  /// 发现的设备列表（只读）
  List<DlnaDevice> get devices => List.unmodifiable(_devices);

  /// 当前连接的设备
  DlnaDevice? _currentDevice;

  /// 当前连接的设备
  DlnaDevice? get currentDevice => _currentDevice;

  /// 是否正在搜索
  bool _isSearching = false;

  /// 是否正在搜索
  bool get isSearching => _isSearching;

  /// 是否正在投屏
  bool _isCasting = false;

  /// 是否正在投屏
  bool get isCasting => _isCasting;

  /// DLNA管理器
  DLNAManager? _manager;

  /// 设备管理器
  dynamic _deviceManager;

  /// 搜索超时时间（秒）
  static const int searchTimeout = 10;

  /// 搜索DLNA设备
  Future<List<DlnaDevice>> searchDevices() async {
    if (_isSearching) return _devices;

    _isSearching = true;
    _devices.clear();

    try {
      _manager = DLNAManager();
      _deviceManager = await _manager!.start();

      // 等待设备发现
      final completer = Completer<List<DlnaDevice>>();

      // 设置超时
      Timer(const Duration(seconds: searchTimeout), () {
        if (!completer.isCompleted) {
          _isSearching = false;
          completer.complete(_devices);
        }
      });

      // 从DeviceManager中获取已发现的设备
      if (_deviceManager != null) {
        final deviceMap = _deviceManager.deviceList as Map<String, dynamic>;
        for (final entry in deviceMap.entries) {
          final nativeDevice = entry.value;
          final deviceInfo = nativeDevice.info;
          final dlnaDevice = DlnaDevice(
            name: deviceInfo?.friendlyName?.toString() ?? '未知设备',
            location: deviceInfo?.URLBase?.toString() ?? '',
            uuid: entry.key,
            model: deviceInfo?.deviceType?.toString() ?? '',
            manufacturer: '',
            nativeDevice: nativeDevice,
          );
          if (!_devices.any((d) => d.uuid == dlnaDevice.uuid)) {
            _devices.add(dlnaDevice);
          }
        }
      }

      if (!completer.isCompleted) {
        completer.complete(_devices);
      }

      return completer.future;
    } catch (e) {
      debugPrint('搜索DLNA设备失败: $e');
      return _devices;
    } finally {
      _isSearching = false;
    }
  }

  /// 停止搜索
  void stopSearch() {
    _manager?.stop();
    _isSearching = false;
  }

  /// 连接设备
  Future<bool> connectDevice(DlnaDevice device) async {
    try {
      _currentDevice = device;
      debugPrint('已连接DLNA设备: ${device.name}');
      return true;
    } catch (e) {
      debugPrint('连接DLNA设备失败: $e');
      return false;
    }
  }

  /// 投屏播放
  Future<bool> castPlay(String url, {String title = ''}) async {
    if (_currentDevice == null) {
      debugPrint('未连接DLNA设备');
      return false;
    }

    try {
      _isCasting = true;
      final nativeDevice = _currentDevice!.nativeDevice;
      if (nativeDevice != null) {
        await nativeDevice.setUrl(url, title: title);
        await nativeDevice.play();
      }
      debugPrint('投屏播放成功: $url');
      return true;
    } catch (e) {
      debugPrint('投屏播放失败: $e');
      return false;
    }
  }

  /// 投屏暂停
  Future<bool> castPause() async {
    if (_currentDevice == null) return false;

    try {
      final nativeDevice = _currentDevice!.nativeDevice;
      if (nativeDevice != null) {
        await nativeDevice.pause();
      }
      return true;
    } catch (e) {
      debugPrint('投屏暂停失败: $e');
      return false;
    }
  }

  /// 投屏继续播放
  Future<bool> castResume() async {
    if (_currentDevice == null) return false;

    try {
      final nativeDevice = _currentDevice!.nativeDevice;
      if (nativeDevice != null) {
        await nativeDevice.play();
      }
      return true;
    } catch (e) {
      debugPrint('投屏继续播放失败: $e');
      return false;
    }
  }

  /// 投屏停止
  Future<bool> castStop() async {
    if (_currentDevice == null) return false;

    try {
      final nativeDevice = _currentDevice!.nativeDevice;
      if (nativeDevice != null) {
        await nativeDevice.stop();
      }
      _isCasting = false;
      return true;
    } catch (e) {
      debugPrint('投屏停止失败: $e');
      return false;
    }
  }

  /// 投屏 seek
  Future<bool> castSeek(Duration position) async {
    if (_currentDevice == null) return false;

    try {
      final nativeDevice = _currentDevice!.nativeDevice;
      if (nativeDevice != null) {
        // 格式化时间为HH:MM:SS
        final hours = position.inHours;
        final minutes = position.inMinutes.remainder(60);
        final seconds = position.inSeconds.remainder(60);
        final target =
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        await nativeDevice.seek(target);
      }
      return true;
    } catch (e) {
      debugPrint('投屏跳转失败: $e');
      return false;
    }
  }

  /// 设置音量
  Future<bool> castSetVolume(int volume) async {
    if (_currentDevice == null) return false;

    try {
      final nativeDevice = _currentDevice!.nativeDevice;
      if (nativeDevice != null) {
        await nativeDevice.volume(volume.clamp(0, 100));
      }
      return true;
    } catch (e) {
      debugPrint('设置投屏音量失败: $e');
      return false;
    }
  }

  /// 断开设备
  void disconnectDevice() {
    castStop();
    _currentDevice = null;
    _isCasting = false;
  }

  /// 释放资源
  void dispose() {
    stopSearch();
    disconnectDevice();
  }
}
