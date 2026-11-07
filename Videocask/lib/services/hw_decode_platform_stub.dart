import 'hw_decode_policy.dart';

/// Web 端没有 mpv 原生后端，只能软解。
HwDecodePlatform detectHwDecodePlatform() => HwDecodePlatform.web;
