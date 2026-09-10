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

  static const int searchTimeoutSec = 12;

  Future<List<DlnaDevice>> searchDevices({
    Duration timeout = const Duration(seconds: searchTimeoutSec),
  }) async {
    if (_isSearching) return _devices;

    _isSearching = true;
    _devices.clear();

    try {
      stopSearch();
      _manager = DLNAManager();
      _deviceManager = await _manager!.start();

      final completer = Completer<List<DlnaDevice>>();
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

      Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(List<DlnaDevice>.from(_devices));
        }
      });

      return completer.future;
    } catch (e) {
      debugPrint('搜索DLNA设备失败: $e');
      return _devices;
    } finally {
      _isSearching = false;
    }
  }

  void stopSearch() {
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
    stopSearch();
    unawaited(disconnectDevice());
  }
}
