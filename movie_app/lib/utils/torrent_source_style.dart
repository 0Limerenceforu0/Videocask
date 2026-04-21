import 'package:flutter/material.dart';

/// 磁力结果列表中来源标签颜色（与设置里显示名称模糊匹配）
Color torrentSourceAccentColor(String source, Color fallback) {
  final s = source.toLowerCase();
  if (s.contains('yts')) return const Color(0xFF4CAF50);
  if (s.contains('pirate') || s.contains('apibay')) {
    return const Color(0xFFFF9800);
  }
  if (s.contains('torrentio')) return const Color(0xFF2196F3);
  if (s.contains('1337')) return const Color(0xFFE91E63);
  if (s.contains('bt4g')) return const Color(0xFF9C27B0);
  if (s.contains('nyaa')) return const Color(0xFFFF5722);
  if (s.contains('jackett')) return const Color(0xFF607D8B);
  if (s.contains('solid')) return const Color(0xFF795548);
  return fallback;
}
