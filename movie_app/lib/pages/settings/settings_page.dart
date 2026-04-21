import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/constants.dart';
import '../../config/routes.dart';
import '../../config/themes.dart';
import 'magnet_sources_page.dart';
import '../../providers/theme_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/source_provider.dart';
import '../../providers/cache_provider.dart';

/// 设置中心页面
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// B站风格颜色配置
  static _SettingsColors _getColors(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return _SettingsColors(
      bgColor: isDark ? const Color(0xFF17181A) : const Color(0xFFF4F4F4),
      cardColor: isDark ? const Color(0xFF222325) : Colors.white,
      dividerColor: isDark ? const Color(0xFF2E2F31) : const Color(0xFFEEEEEE),
      textColor: isDark ? const Color(0xFFE6E6E6) : const Color(0xFF212121),
      subTextColor: isDark ? const Color(0xFF999999) : const Color(0xFF999999),
      accentColor: theme.colorScheme.primary,
      sectionTitleColor:
          isDark ? const Color(0xFFE6E6E6) : const Color(0xFF212121),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _getColors(context);

    return Scaffold(
      backgroundColor: colors.bgColor,
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: colors.cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: () => context.pop(),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // 播放设置分组
          _buildBiliSectionHeader(colors, '播放设置'),
          _buildBiliSectionCard(
            context,
            colors,
            children: [
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.speed_outlined,
                iconBgColor: const Color(0xFF4FC3F7),
                title: '默认播放速度',
                value: context.watch<SettingsProvider>().defaultSpeed == 1.0
                    ? '正常'
                    : '${context.watch<SettingsProvider>().defaultSpeed}x',
                onTap: () => _showSpeedSetting(context),
              ),
              _buildBiliDivider(colors),
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.high_quality_outlined,
                iconBgColor: const Color(0xFF81C784),
                title: '默认清晰度',
                value: context.watch<SettingsProvider>().defaultQuality,
                onTap: () => _showQualitySetting(context),
              ),
              _buildBiliDivider(colors),
              _buildBiliSwitchItem(
                context,
                colors,
                icon: Icons.memory_outlined,
                iconBgColor: const Color(0xFFFFB74D),
                title: '硬件解码',
                subtitle: '开启后播放更流畅',
                value: context.watch<SettingsProvider>().hardwareDecode,
                onChanged: (value) =>
                    context.read<SettingsProvider>().setHardwareDecode(value),
              ),
              _buildBiliDivider(colors),
              _buildBiliSwitchItem(
                context,
                colors,
                icon: Icons.playlist_play_outlined,
                iconBgColor: const Color(0xFFCE93D8),
                title: '自动连播',
                subtitle: '播放完自动播放下一集',
                value: context.watch<SettingsProvider>().autoPlayNext,
                onChanged: (value) =>
                    context.read<SettingsProvider>().setAutoPlayNext(value),
              ),
              _buildBiliDivider(colors),
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.auto_awesome_outlined,
                iconBgColor: const Color(0xFFFF8A65),
                title: '播放偏好',
                value: _getPlaybackStrategyName(
                  context.watch<SettingsProvider>().playbackStrategy,
                ),
                onTap: () => _showPlaybackStrategySetting(context),
              ),
              _buildBiliDivider(colors),
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.subtitles_outlined,
                iconBgColor: const Color(0xFF78909C),
                title: 'OpenSubtitles API Key',
                value: context
                        .watch<SettingsProvider>()
                        .opensubtitlesApiKeyConfigured
                    ? '已配置'
                    : '未配置（在线字幕不可用）',
                onTap: () => _showOpensubtitlesApiKeyDialog(context),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 数据管理分组
          _buildBiliSectionHeader(colors, '数据管理'),
          _buildBiliSectionCard(
            context,
            colors,
            children: [
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.source_outlined,
                iconBgColor: const Color(0xFF4FC3F7),
                title: '播放源管理',
                value: '${context.watch<SourceProvider>().sources.length} 个源',
                onTap: () => AppRoutes.toSourceManager(context),
              ),
              _buildBiliDivider(colors),
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.nfc_outlined,
                iconBgColor: const Color(0xFF90A4AE),
                title: '磁力搜索源',
                value:
                    '${context.watch<SettingsProvider>().enabledMagnetSourceCount}/${context.watch<SettingsProvider>().magnetSources.length} 已启用',
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (ctx) => const MagnetSourcesPage(),
                    ),
                  );
                },
              ),
              _buildBiliDivider(colors),
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.download_outlined,
                iconBgColor: const Color(0xFF81C784),
                title: '缓存管理',
                value: context.watch<CacheProvider>().formattedTotalSize,
                onTap: () => AppRoutes.toCacheManager(context),
              ),
              _buildBiliDivider(colors),
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.cloud_upload_outlined,
                iconBgColor: const Color(0xFF90CAF9),
                title: '导出数据',
                value: '导出收藏、历史等数据',
                onTap: () => _exportData(context),
              ),
              _buildBiliDivider(colors),
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.cloud_download_outlined,
                iconBgColor: const Color(0xFFA5D6A7),
                title: '导入数据',
                value: '从文件导入数据',
                onTap: () => _importData(context),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // WebDAV同步分组
          _buildBiliSectionHeader(colors, 'WebDAV同步'),
          _buildBiliSectionCard(
            context,
            colors,
            children: [
              _buildBiliSettingItem(
                context,
                colors,
                icon: context.watch<SettingsProvider>().webdavConnected
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_queue_outlined,
                iconBgColor: context.watch<SettingsProvider>().webdavConnected
                    ? const Color(0xFF81C784)
                    : const Color(0xFFBDBDBD),
                title: 'WebDAV配置',
                value: context.watch<SettingsProvider>().webdavConnected
                    ? '已连接'
                    : '未配置',
                onTap: () => _showWebDavConfig(context),
              ),
              if (context.watch<SettingsProvider>().webdavConnected) ...[
                _buildBiliDivider(colors),
                _buildBiliSettingItem(
                  context,
                  colors,
                  icon: Icons.sync_outlined,
                  iconBgColor: const Color(0xFF4FC3F7),
                  title: '上传数据',
                  value: '将本地数据同步到云端',
                  onTap: () => _syncUpload(context),
                ),
                _buildBiliDivider(colors),
                _buildBiliSettingItem(
                  context,
                  colors,
                  icon: Icons.download_outlined,
                  iconBgColor: const Color(0xFF90CAF9),
                  title: '下载数据',
                  value: '从云端同步数据到本地',
                  onTap: () => _syncDownload(context),
                ),
                _buildBiliDivider(colors),
                _buildBiliSettingItem(
                  context,
                  colors,
                  icon: Icons.sync_alt_outlined,
                  iconBgColor: const Color(0xFFCE93D8),
                  title: '双向同步',
                  value: '合并本地和云端数据',
                  onTap: () => _syncBoth(context),
                ),
                _buildBiliDivider(colors),
                _buildBiliSettingItem(
                  context,
                  colors,
                  icon: Icons.settings_ethernet_outlined,
                  iconBgColor: const Color(0xFFFFB74D),
                  title: '冲突解决策略',
                  value: _getConflictStrategyName(
                    context.watch<SettingsProvider>().conflictStrategy,
                  ),
                  onTap: () => _showConflictStrategy(context),
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // 外观分组
          _buildBiliSectionHeader(colors, '外观'),
          _buildBiliSectionCard(
            context,
            colors,
            children: [
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.palette_outlined,
                iconBgColor: const Color(0xFFF48FB1),
                title: '主题切换',
                value: context.watch<ThemeProvider>().themeName,
                onTap: () => _showThemeSelector(context),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 关于分组
          _buildBiliSectionHeader(colors, '关于'),
          _buildBiliSectionCard(
            context,
            colors,
            children: [
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.info_outline,
                iconBgColor: const Color(0xFF4FC3F7),
                title: '版本信息',
                value: 'v${AppConstants.appVersion}',
                onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationName: AppConstants.appName,
                    applicationVersion: AppConstants.appVersion,
                    applicationLegalese: '纯客户端、零服务器、无广告',
                  );
                },
              ),
              _buildBiliDivider(colors),
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.code_outlined,
                iconBgColor: const Color(0xFF81C784),
                title: '开源许可',
                value: '查看第三方库许可',
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: AppConstants.appName,
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// B站风格分组标题
  Widget _buildBiliSectionHeader(_SettingsColors colors, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: colors.sectionTitleColor,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// B站风格分组卡片
  Widget _buildBiliSectionCard(
    BuildContext context,
    _SettingsColors colors, {
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }

  /// B站风格分隔线
  Widget _buildBiliDivider(_SettingsColors colors) {
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Divider(height: 1, color: colors.dividerColor, indent: 0),
    );
  }

  /// B站风格设置项
  Widget _buildBiliSettingItem(
    BuildContext context,
    _SettingsColors colors, {
    required IconData icon,
    required Color iconBgColor,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // 图标背景
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBgColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconBgColor, size: 20),
            ),
            const SizedBox(width: 14),
            // 标题
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: colors.textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // 值
            Text(
              value,
              style: TextStyle(
                color: colors.subTextColor,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: colors.subTextColor.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  /// B站风格开关设置项
  Widget _buildBiliSwitchItem(
    BuildContext context,
    _SettingsColors colors, {
    required IconData icon,
    required Color iconBgColor,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBgColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconBgColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.subTextColor,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: colors.accentColor,
          ),
        ],
      ),
    );
  }

  /// 显示速度设置
  void _showSpeedSetting(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '默认播放速度',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: AppConstants.speedOptions.length,
                  itemBuilder: (context, index) {
                    final speed = AppConstants.speedOptions[index];
                    final label = speed == 1.0 ? '正常' : '${speed}x';
                    final isSelected = speed == settings.defaultSpeed;

                    return ListTile(
                      title: Text(label),
                      trailing: isSelected
                          ? Icon(
                              Icons.check,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      selected: isSelected,
                      onTap: () {
                        settings.setDefaultSpeed(speed);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示清晰度设置
  void _showQualitySetting(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '默认清晰度',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: AppConstants.qualityOptions.length,
                  itemBuilder: (context, index) {
                    final quality = AppConstants.qualityOptions[index];
                    final isSelected = quality == settings.defaultQuality;

                    return ListTile(
                      title: Text(quality),
                      trailing: isSelected
                          ? Icon(
                              Icons.check,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      selected: isSelected,
                      onTap: () {
                        settings.setDefaultQuality(quality);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示播放策略设置
  void _showPlaybackStrategySetting(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    const options = ['smooth', 'balanced', 'quality'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '播放偏好',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const Divider(height: 1),
              ...options.map((strategy) {
                final isSelected = strategy == settings.playbackStrategy;
                return ListTile(
                  title: Text(_getPlaybackStrategyName(strategy)),
                  subtitle: Text(_getPlaybackStrategyDesc(strategy)),
                  trailing: isSelected
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  selected: isSelected,
                  onTap: () {
                    settings.setPlaybackStrategy(strategy);
                    Navigator.of(context).pop();
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示主题选择器（B站风格网格布局圆形色块预览）
  void _showThemeSelector(BuildContext context) {
    final themeProvider = context.read<ThemeProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.4,
        maxChildSize: 0.8,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // 标题栏 + 确认按钮
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Text(
                      '主题切换',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('确认'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 主题网格
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 16,
                  ),
                  // +1 for "跟随系统" option
                  itemCount: AppThemes.themeNames.length + 1,
                  itemBuilder: (context, index) {
                    // 第一项是"跟随系统"
                    if (index == 0) {
                      final isSelected = themeProvider.isSystemTheme;
                      return _buildThemeGridItem(
                        context,
                        name: '跟随系统',
                        color: null,
                        gradient: const LinearGradient(
                          colors: [Colors.grey, Colors.white],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        icon: Icons.brightness_auto,
                        isSelected: isSelected,
                        onTap: () {
                          themeProvider
                              .setTheme(ThemeProvider.systemThemeIndex);
                        },
                      );
                    }

                    // 其他主题项（索引偏移 -1）
                    final themeIndex = index - 1;
                    final theme = AppThemes.getTheme(themeIndex);
                    final isSelected = themeIndex == themeProvider.themeIndex;

                    return _buildThemeGridItem(
                      context,
                      name: AppThemes.themeNamesZh[themeIndex],
                      color: theme.colorScheme.primary,
                      isSelected: isSelected,
                      onTap: () {
                        themeProvider.setTheme(themeIndex);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建主题网格项（圆形色块）
  Widget _buildThemeGridItem(
    BuildContext context, {
    required String name,
    Color? color,
    LinearGradient? gradient,
    IconData? icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 圆形色块
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradient,
              color: gradient == null ? color : null,
              border: isSelected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: (color ?? Colors.grey).withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child:
                icon != null ? Icon(icon, color: Colors.white, size: 22) : null,
          ),
          const SizedBox(height: 8),
          // 主题名称
          Text(
            name,
            style: TextStyle(
              fontSize: 11,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).hintColor,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (isSelected)
            Icon(
              Icons.check_circle,
              size: 14,
              color: Theme.of(context).colorScheme.primary,
            ),
        ],
      ),
    );
  }

  /// 显示WebDAV配置（B站风格卡片式表单）
  void _showWebDavConfig(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final urlController = TextEditingController(
      text: settings.webdavConfig?.serverUrl ?? '',
    );
    final userController = TextEditingController(
      text: settings.webdavConfig?.username ?? '',
    );
    final passController = TextEditingController(
      text: settings.webdavConfig?.password ?? '',
    );
    final pathController = TextEditingController(
      text: settings.webdavConfig?.remotePath ?? '/movie_app/',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部把手
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 标题
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.cloud_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'WebDAV配置',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 预置服务商选择
            DropdownButtonFormField<String>(
              initialValue: settings.webdavConfig?.presetName ?? '自定义',
              decoration: InputDecoration(
                labelText: '服务商',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              items: AppConstants.webdavPresets.map((preset) {
                return DropdownMenuItem(
                  value: preset['name'],
                  child: Text(preset['name']!),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  final preset = AppConstants.webdavPresets.firstWhere(
                    (p) => p['name'] == value,
                  );
                  urlController.text = preset['url'] ?? '';
                }
              },
            ),
            const SizedBox(height: 12),

            TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: '服务器地址',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: userController,
              decoration: InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pathController,
              decoration: InputDecoration(
                labelText: '远程路径',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      settings.disconnectWebDav();
                      Navigator.of(context).pop();
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('断开连接'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final success = await settings.configureWebDav(
                        serverUrl: urlController.text.trim(),
                        username: userController.text.trim(),
                        password: passController.text.trim(),
                        remotePath: pathController.text.trim(),
                        presetName: '自定义',
                      );
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(success ? '连接成功' : '连接失败'),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('连接'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 同步上传
  void _syncUpload(BuildContext context) async {
    final message = await context.read<SettingsProvider>().uploadSync();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  /// 同步下载
  void _syncDownload(BuildContext context) async {
    final message = await context.read<SettingsProvider>().downloadSync();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  /// 双向同步
  void _syncBoth(BuildContext context) async {
    final message = await context.read<SettingsProvider>().syncBoth();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  /// 显示冲突策略选择
  void _showConflictStrategy(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '冲突解决策略',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('本地优先'),
                subtitle: const Text('冲突时保留本地数据'),
                trailing: settings.conflictStrategy == 'local_win'
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  settings.setConflictStrategy('local_win');
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                title: const Text('远程优先'),
                subtitle: const Text('冲突时使用云端数据'),
                trailing: settings.conflictStrategy == 'remote_win'
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  settings.setConflictStrategy('remote_win');
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                title: const Text('最新优先'),
                subtitle: const Text('冲突时保留较新的数据'),
                trailing: settings.conflictStrategy == 'newest_win'
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  settings.setConflictStrategy('newest_win');
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 导出数据
  void _exportData(BuildContext context) async {
    final jsonData = await context.read<SettingsProvider>().exportData();
    if (jsonData.isNotEmpty) {
      // 将导出的JSON数据复制到剪贴板
      await Clipboard.setData(ClipboardData(text: jsonData));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('数据已复制到剪贴板')),
        );
      }
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导出失败：无数据')),
      );
    }
  }

  /// 导入数据
  void _importData(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入数据'),
        content: TextField(
          controller: controller,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: '粘贴导出的数据JSON',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      // ignore: use_build_context_synchronously
      final success = await context.read<SettingsProvider>().importData(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? '导入成功' : '导入失败')),
        );
      }
    }
  }

  /// 获取冲突策略名称
  String _getConflictStrategyName(String strategy) {
    switch (strategy) {
      case 'local_win':
        return '本地优先';
      case 'remote_win':
        return '远程优先';
      case 'newest_win':
        return '最新优先';
      default:
        return '本地优先';
    }
  }

  String _getPlaybackStrategyName(String strategy) {
    switch (strategy) {
      case 'smooth':
        return '优先流畅';
      case 'quality':
        return '优先画质';
      default:
        return '均衡';
    }
  }

  String _getPlaybackStrategyDesc(String strategy) {
    switch (strategy) {
      case 'smooth':
        return '优先选择更稳定、起播更快的线路与源';
      case 'quality':
        return '优先选择线路更多、评分更高的资源';
      default:
        return '在流畅与画质之间自动平衡';
    }
  }

  void _showOpensubtitlesApiKeyDialog(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final controller =
        TextEditingController(text: settings.opensubtitlesApiKey);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('OpenSubtitles API Key'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '在 https://www.opensubtitles.com 注册后于用户面板创建 API Key。留空则禁用在线字幕搜索。',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await settings.setOpensubtitlesApiKey(controller.text);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已保存字幕 API 配置')),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

/// 设置页B站风格颜色配置
class _SettingsColors {
  final Color bgColor;
  final Color cardColor;
  final Color dividerColor;
  final Color textColor;
  final Color subTextColor;
  final Color accentColor;
  final Color sectionTitleColor;

  const _SettingsColors({
    required this.bgColor,
    required this.cardColor,
    required this.dividerColor,
    required this.textColor,
    required this.subTextColor,
    required this.accentColor,
    required this.sectionTitleColor,
  });
}
