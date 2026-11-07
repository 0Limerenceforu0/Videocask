import 'package:flutter/material.dart';

import '../theme/hifi_theme_extension.dart';

/// 10套主题定义（Color Hunt 风格）
class AppThemes {
  AppThemes._();

  /// 主题名称（英文，可用于调试或导出）
  static const List<String> themeNames = [
    'Midnight Teal',
    'Coral Mint',
    'Royal Rose',
    'Neon Night',
    'Berry Cream',
    'Lavender Soft',
    'Amber Forest',
    'Sunset Peach',
    'Ocean Breeze',
    'Slate Gold',
  ];

  /// 主题名称（中文，与 [themeNames] 顺序一致）
  static const List<String> themeNamesZh = [
    '午夜青绿',
    '珊瑚薄荷',
    '皇家玫红',
    '霓虹夜色',
    '莓果奶油',
    '柔和薰衣草',
    '琥珀森林',
    '日落桃杏',
    '海风蓝绿',
    '板岩流金',
  ];

  /// 获取主题列表（缓存，避免重复构建）
  static final List<ThemeData> themes = [
    _buildTheme(
      brightness: Brightness.dark,
      primary: const Color(0xFF00ADB5),
      secondary: const Color(0xFFEEEEEE),
      background: const Color(0xFF222831),
      surface: const Color(0xFF393E46),
    ),
    _buildTheme(
      brightness: Brightness.light,
      primary: const Color(0xFFF38181),
      secondary: const Color(0xFF95E1D3),
      background: const Color(0xFFFCE38A),
      surface: const Color(0xFFEAFFD0),
    ),
    _buildTheme(
      brightness: Brightness.dark,
      primary: const Color(0xFFE84545),
      secondary: const Color(0xFF903749),
      background: const Color(0xFF2B2E4A),
      surface: const Color(0xFF53354A),
    ),
    _buildTheme(
      brightness: Brightness.dark,
      primary: const Color(0xFFFF2E63),
      secondary: const Color(0xFF08D9D6),
      background: const Color(0xFF252A34),
      surface: const Color(0xFF1D222B),
    ),
    _buildTheme(
      brightness: Brightness.light,
      primary: const Color(0xFFFC5185),
      secondary: const Color(0xFF3FC1C9),
      background: const Color(0xFFF5F5F5),
      surface: const Color(0xFFFFFFFF),
    ),
    _buildTheme(
      brightness: Brightness.light,
      primary: const Color(0xFFAA96DA),
      secondary: const Color(0xFFA8D8EA),
      background: const Color(0xFFFFF4E1),
      surface: const Color(0xFFFFD3B6),
    ),
    _buildTheme(
      brightness: Brightness.light,
      primary: const Color(0xFF4B8673),
      secondary: const Color(0xFFF7B267),
      background: const Color(0xFFF8F1E5),
      surface: const Color(0xFFDDE5B6),
    ),
    _buildTheme(
      brightness: Brightness.light,
      primary: const Color(0xFFFF6F61),
      secondary: const Color(0xFFFFB88C),
      background: const Color(0xFFFFF1E6),
      surface: const Color(0xFFFFD6BA),
    ),
    _buildTheme(
      brightness: Brightness.light,
      primary: const Color(0xFF256D85),
      secondary: const Color(0xFF8FE3CF),
      background: const Color(0xFFEAF6F6),
      surface: const Color(0xFFCBE4DE),
    ),
    _buildTheme(
      brightness: Brightness.dark,
      primary: const Color(0xFFE9C46A),
      secondary: const Color(0xFF2A9D8F),
      background: const Color(0xFF1F2933),
      surface: const Color(0xFF323F4B),
    ),
  ];

  /// 根据索引获取主题
  static ThemeData getTheme(int index) {
    if (index < 0 || index >= themes.length) {
      return themes.first;
    }
    return themes[index];
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color primary,
    required Color secondary,
    required Color background,
    required Color surface,
  }) {
    final isDark = brightness == Brightness.dark;
    final onPrimary = isDark ? Colors.black : Colors.white;
    final onSurface =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF1B1B1F);
    final muted = isDark ? const Color(0xFFB0BEC5) : const Color(0xFF6B7280);
    final card = isDark
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.06), surface)
        : Colors.white;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        primary: primary,
        secondary: secondary,
        surface: surface,
        error: isDark ? const Color(0xFFFF6B6B) : const Color(0xFFC62828),
      ),
      scaffoldBackgroundColor: background,
      cardColor: card,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: onSurface),
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: isDark ? 1 : 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textTheme: TextTheme(
        titleLarge: TextStyle(color: onSurface, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: onSurface),
        bodyMedium: TextStyle(color: onSurface),
        bodySmall: TextStyle(color: muted),
        labelLarge: TextStyle(color: onPrimary, fontWeight: FontWeight.w600),
      ),
      iconTheme: IconThemeData(color: onSurface),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: muted,
        type: BottomNavigationBarType.fixed,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white12 : Colors.black12,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        hintStyle: TextStyle(color: muted),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: primary.withValues(alpha: 0.2),
        labelStyle: TextStyle(color: onSurface),
        secondaryLabelStyle: TextStyle(color: onSurface),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      extensions: const <ThemeExtension<dynamic>>[
        HiFiUiTokens.standard,
      ],
    );
  }
}
