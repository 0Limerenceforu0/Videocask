import 'package:flutter/material.dart';
import '../config/themes.dart';
import '../theme/hifi_theme_extension.dart';
import '../config/constants.dart';
import '../services/storage_service.dart';

/// 主题状态管理
class ThemeProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();

  /// 跟随系统模式的特殊索引
  static const int systemThemeIndex = -1;

  /// 当前主题索引（-1 表示跟随系统）
  int _themeIndex = 0;

  /// 当前主题索引
  int get themeIndex => _themeIndex;

  /// 是否跟随系统
  bool get isSystemTheme => _themeIndex == systemThemeIndex;

  /// 当前主题
  ThemeData get currentTheme {
    if (_themeIndex == systemThemeIndex) {
      // 跟随系统：使用第一个主题的结构，但 brightness 跟随系统
      final platformBrightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      final baseTheme = AppThemes.themes.isNotEmpty
          ? AppThemes.themes[0]
          : AppThemes.getTheme(0);
      if (platformBrightness == Brightness.dark) {
        return baseTheme;
      } else {
        // 创建一个浅色版本
        return ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.light(
            primary: baseTheme.colorScheme.primary,
            surface: const Color(0xFFF5F5F5),
          ),
          extensions: const <ThemeExtension<dynamic>>[
            HiFiUiTokens.standard,
          ],
        );
      }
    }
    return AppThemes.getTheme(_themeIndex);
  }

  /// 主题名称（中文，用于提示与设置展示）
  String get themeName {
    if (_themeIndex == systemThemeIndex) return '跟随系统';
    return AppThemes.themeNamesZh[_themeIndex];
  }

  /// 主题名称列表（含"跟随系统"）
  List<String> get themeNames => ['跟随系统', ...AppThemes.themeNamesZh];

  /// 初始化
  Future<void> init() async {
    _themeIndex = _storage.getIntSetting(
      AppConstants.keyThemeIndex,
      defaultValue: 0,
    );
    // 确保索引在有效范围内（包含 -1 跟随系统）
    if (_themeIndex != systemThemeIndex &&
        (_themeIndex < 0 || _themeIndex >= AppThemes.themes.length)) {
      _themeIndex = 0;
    }
    notifyListeners();
  }

  /// 切换主题
  Future<void> setTheme(int index) async {
    if (index != systemThemeIndex &&
        (index < 0 || index >= AppThemes.themes.length)) {
      return;
    }
    _themeIndex = index;
    await _storage.saveIntSetting(AppConstants.keyThemeIndex, index);
    notifyListeners();
  }

  /// 下一个主题
  ///
  /// 槽位：0=跟随系统，1..N 对应主题 0..N-1。须在「当前槽位 +1」后再映射，否则会一直停在同一套主题。
  Future<void> nextTheme() async {
    final allCount = AppThemes.themes.length + 1;
    final currentSlot = _themeIndex == systemThemeIndex ? 0 : _themeIndex + 1;
    final nextSlot = (currentSlot + 1) % allCount;
    if (nextSlot == 0) {
      await setTheme(systemThemeIndex);
    } else {
      await setTheme(nextSlot - 1);
    }
  }

  /// 上一个主题
  Future<void> previousTheme() async {
    final allCount = AppThemes.themes.length + 1;
    final currentSlot = _themeIndex == systemThemeIndex ? 0 : _themeIndex + 1;
    final prevSlot = (currentSlot - 1 + allCount) % allCount;
    if (prevSlot == 0) {
      await setTheme(systemThemeIndex);
    } else {
      await setTheme(prevSlot - 1);
    }
  }
}
