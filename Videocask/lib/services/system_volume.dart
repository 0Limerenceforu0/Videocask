import 'dart:async';

import 'package:flutter/services.dart';

/// 系统音量（STREAM_MUSIC）读写与变化监听。
///
/// 让 App 内的音量手势 / 滑块与系统音量统一为同一个音量：
/// 实际响度由系统音量决定，播放器（mpv）保持 100% 直通，
/// 仅静音走播放器自身增益（0/100）。
class SystemVolume {
  SystemVolume._();

  static final SystemVolume instance = SystemVolume._();

  static const MethodChannel _channel = MethodChannel('videocask/volume');
  static const EventChannel _events = EventChannel('videocask/volumeEvents');

  Stream<double>? _stream;

  /// 硬件音量键 / 系统设置变化时的归一化音量流（0.0–1.0）。
  Stream<double> get onVolumeChanged {
    _stream ??= _events
        .receiveBroadcastStream()
        .map((e) => (e as num?)?.toDouble() ?? 0.0)
        .where((e) => e >= 0.0 && e <= 1.0);
    return _stream!;
  }

  /// 读取当前系统音量（归一化 0.0–1.0）。
  Future<double> getVolume() async {
    final v = await _channel.invokeMethod<double>('getVolume');
    return (v ?? 1.0).clamp(0.0, 1.0);
  }

  /// 设置系统音量；[level] 为归一化值（0.0–1.0）。
  Future<void> setVolume(double level) async {
    await _channel.invokeMethod<void>('setVolume', {
      'level': level.clamp(0.0, 1.0),
    });
  }
}
