import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async' show unawaited;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/changelog.dart';
import '../../config/constants.dart';
import '../../config/routes.dart';
import '../../config/themes.dart';
import '../../l10n/app_localizations.dart';
import '../../services/storage_service.dart';
import '../../services/subtitle_ai_backend.dart';
import '../../services/video_output_policy.dart';
import '../../widgets/ai_subtitle_settings_panel.dart';
import 'magnet_sources_page.dart';
import '../../providers/theme_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/source_provider.dart';
import '../../providers/cache_provider.dart';
import '../../services/debug_log.dart';
import '../../services/log_export.dart';
import '../../services/hw_decode_policy.dart';
import '../../services/hw_decode_platform.dart';

/// 设置中心页面
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// 导出/清空日志操作的并发守卫（避免连点重复触发）。
  static bool _logBusy = false;

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
    final l10n = AppLocalizations.of(context)!;

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
                subtitle: '默认开启；档位不适配请手动改档（下方可手动选档）',
                value: context.watch<SettingsProvider>().hardwareDecode,
                onChanged: (value) =>
                    context.read<SettingsProvider>().setHardwareDecode(value),
              ),
              _buildBiliDivider(colors),
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.tune_outlined,
                iconBgColor: const Color(0xFF4DB6AC),
                title: AppLocalizations.of(context)!.settingsHwDecodeMode,
                value: _hwDecodeModeSummary(context),
                onTap: () => _showHwDecodeModeSheet(context),
              ),
              _buildBiliDivider(colors),
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.monitor_outlined,
                iconBgColor: const Color(0xFF9575CD),
                title: AppLocalizations.of(context)!.settingsVideoOutputMode,
                value: _videoOutputModeSummary(context),
                onTap: () => _showVideoOutputModeSheet(context),
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
              _buildBiliSwitchItem(
                context,
                colors,
                icon: Icons.block_outlined,
                iconBgColor: const Color(0xFFEF9A9A),
                title: 'HLS 去广告',
                subtitle: '自动剔除 m3u8 里注入的广告分片；如遇跳剧情可关闭',
                value: context.watch<SettingsProvider>().hlsAdFilter,
                onChanged: (value) =>
                    context.read<SettingsProvider>().setHlsAdFilter(value),
              ),
              _buildBiliDivider(colors),
              _buildBiliSwitchItem(
                context,
                colors,
                icon: Icons.play_circle_outline,
                iconBgColor: const Color(0xFF64B5F6),
                title: l10n.settingsAutoPlayOnDetailEnter,
                subtitle: l10n.settingsAutoPlayOnDetailEnterSubtitle,
                value: context.watch<SettingsProvider>().autoPlayOnDetailEnter,
                onChanged: (value) => context
                    .read<SettingsProvider>()
                    .setAutoPlayOnDetailEnter(value),
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
              _buildBiliSwitchItem(
                context,
                colors,
                icon: Icons.skip_next_outlined,
                iconBgColor: const Color(0xFF4DB6AC),
                title: l10n.settingsPreloadNextEpisode,
                subtitle: l10n.settingsPreloadNextEpisodeSubtitle,
                value: context.watch<SettingsProvider>().preloadNextEpisode,
                onChanged: (value) => context
                    .read<SettingsProvider>()
                    .setPreloadNextEpisode(value),
              ),
              _buildBiliDivider(colors),
              _buildBiliSwitchItem(
                context,
                colors,
                icon: Icons.cloud_download_outlined,
                iconBgColor: const Color(0xFF90A4AE),
                title: l10n.settingsPlaybackPrefetch,
                subtitle: l10n.settingsPlaybackPrefetchSubtitle,
                value: context.watch<SettingsProvider>().playbackPrefetch,
                onChanged: (value) =>
                    context.read<SettingsProvider>().setPlaybackPrefetch(value),
              ),
              _buildBiliDivider(colors),
              _buildBiliSwitchItem(
                context,
                colors,
                icon: Icons.wifi_outlined,
                iconBgColor: const Color(0xFF64B5F6),
                title: l10n.settingsOnlyWifiCache,
                subtitle: l10n.settingsOnlyWifiCacheSubtitle,
                value: context.watch<SettingsProvider>().onlyWifiCache,
                onChanged: (value) {
                  unawaited(() async {
                    await context
                        .read<SettingsProvider>()
                        .setOnlyWifiCache(value);
                    if (!context.mounted) return;
                    await context.read<CacheProvider>().setOnlyWifi(value);
                  }());
                },
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
              _buildBiliDivider(colors),
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.movie_filter_outlined,
                iconBgColor: const Color(0xFF7986CB),
                title: l10n.settingsTmdbApiKey,
                value: context.watch<SettingsProvider>().tmdbApiKeyConfigured
                    ? l10n.settingsTmdbApiKeyConfigured
                    : l10n.settingsTmdbApiKeyNotConfigured,
                onTap: () => _showTmdbApiKeyDialog(context),
              ),
              _buildBiliDivider(colors),
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.auto_awesome_outlined,
                iconBgColor: const Color(0xFF7E57C2),
                title: 'AI 字幕生成',
                value: _aiSubtitleStatusText(context),
                onTap: () => showAiSubtitleSettings(context),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 诊断分组
          _buildBiliSectionHeader(colors, '诊断'),
          _buildBiliSectionCard(
            context,
            colors,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  '遇到跳剧情 / 闪退 / 卡顿等问题时：先正常使用该功能复现一次，'
                  '再点下方「导出诊断日志」把整个 guanzi_logs（含 crash_*.txt 崩溃栈）'
                  '打包发给我即可——无需电脑、无需文件管理器权限。',
                  style: TextStyle(color: colors.subTextColor, fontSize: 12),
                ),
              ),
              _buildBiliDivider(colors),
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.upload_file_outlined,
                iconBgColor: const Color(0xFF42A5F5),
                title: '导出诊断日志',
                value: '打包到系统下载目录',
                onTap: () => _exportLogs(context),
              ),
              _buildBiliDivider(colors),
              _buildBiliSettingItem(
                context,
                colors,
                icon: Icons.delete_sweep_outlined,
                iconBgColor: const Color(0xFFEF9A9A),
                title: '清空诊断日志',
                value: '删除崩溃/日志文件',
                onTap: () => _clearLogs(context),
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
                icon: Icons.update_outlined,
                iconBgColor: const Color(0xFFFFB74D),
                title: '更新日志',
                value:
                    'v${AppChangelog.latest.version} 新增 ${AppChangelog.latest.items.length} 项',
                onTap: () => _showChangelogSheet(context),
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

  /// 硬件解码档位选择（底部弹窗）。
  ///
  /// 档位说明：
  /// - 自动：按平台选最稳的硬解档（Android 走拷贝式）；不适配需手动改档；
  /// - 兼容：MediaCodec 拷贝式，硬件解码 + 拷回 CPU 渲染，兼容性最好；
  /// - 高性能：MediaCodec 零拷贝，最省电，但个别机型会卡死/闪退；
  /// - 关闭：纯软件解码。
  void _showHwDecodeModeSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: Theme.of(sheetContext).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  l10n.settingsHwDecodeMode,
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l10n.settingsHwDecodeModeDesc,
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                        color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              for (final option in _hwDecodeModeOptions(l10n))
                RadioListTile<String>(
                  value: option.value,
                  groupValue: settings.hwDecodeModeKey.isEmpty
                      ? 'auto'
                      : settings.hwDecodeModeKey,
                  onChanged: (value) {
                    if (value == null) return;
                    if (value == 'auto') {
                      context.read<SettingsProvider>().setHwDecodeMode(
                            defaultHwDecodeMode(detectHwDecodePlatform()),
                          );
                    } else {
                      context
                          .read<SettingsProvider>()
                          .setHwDecodeMode(hwDecodeModeFromKey(
                            value,
                            platform: detectHwDecodePlatform(),
                          ));
                    }
                    Navigator.pop(sheetContext);
                  },
                  title: Text(option.label),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// 视频输出后端选择（默认 gpu-next / 新版渲染）。
  /// fd 泄漏已在引擎层通过 SurfaceTexture 桥接统一修复，三种后端都不漏句柄；
  /// 该设置只影响画面兼容性与功能（字幕/滤镜/截图），出画异常时再手动切换。
  void _showVideoOutputModeSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final current = settings.effectiveVideoOutputMode;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: Theme.of(sheetContext).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  l10n.settingsVideoOutputMode,
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l10n.settingsVideoOutputModeDesc,
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                        color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              // 顺序即推荐顺序：新版渲染（推荐）→ 旧版渲染（兜底）→ 硬解直出。
              for (final option in [
                (value: VideoOutputMode.gpuNext,
                 label: l10n.settingsVoGpuNext,
                 desc: l10n.settingsVoGpuNextDesc),
                (value: VideoOutputMode.gpu,
                 label: l10n.settingsVoGpu,
                 desc: l10n.settingsVoGpuDesc),
                (value: VideoOutputMode.mediacodecEmbed,
                 label: l10n.settingsVoEmbed,
                 desc: l10n.settingsVoEmbedDesc),
              ])
                RadioListTile<VideoOutputMode>(
                  value: option.value,
                  groupValue: current,
                  onChanged: (value) {
                    if (value == null) return;
                    unawaited(settings.setVideoOutputMode(value));
                    Navigator.pop(sheetContext);
                  },
                  title: Text(option.label),
                  subtitle: Text(option.desc),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  String _videoOutputModeSummary(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (context.watch<SettingsProvider>().effectiveVideoOutputMode) {
      case VideoOutputMode.gpuNext:
        return l10n.settingsVoGpuNext;
      case VideoOutputMode.gpu:
        return l10n.settingsVoGpu;
      case VideoOutputMode.mediacodecEmbed:
        return l10n.settingsVoEmbed;
    }
  }

  /// 硬解档位选项（label 走 l10n，value 为持久化键）。
  List<({String value, String label})> _hwDecodeModeOptions(
    AppLocalizations l10n,
  ) {
    final platform = detectHwDecodePlatform();
    final options = <({String value, String label})>[];
    if (platform == HwDecodePlatform.android) {
      options
        ..add((
          value: 'mediaCodecZeroCopy',
          label: l10n.settingsHwDecodeModeZeroCopy,
        ))
        ..add((
          value: 'mediaCodecCopy',
          label: l10n.settingsHwDecodeModeCopy,
        ));
    }
    options
      ..add((value: 'auto', label: l10n.settingsHwDecodeModeAuto))
      ..add((value: 'disabled', label: l10n.settingsHwDecodeModeOff));
    return options;
  }

  /// 当前硬解档位的摘要文案（设置项右侧显示）。
  String _hwDecodeModeSummary(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    if (!settings.hardwareDecode) return l10n.settingsHwDecodeModeOff;
    final key = settings.hwDecodeModeKey;
    if (key.isEmpty ||
        key == encodeHwDecodeMode(
            defaultHwDecodeMode(detectHwDecodePlatform()),
        )) {
      return l10n.settingsHwDecodeModeAuto;
    }
    final mode = hwDecodeModeFromKey(key, platform: detectHwDecodePlatform());
    switch (mode) {
      case HwDecodeMode.mediaCodecCopy:
        return l10n.settingsHwDecodeModeCopy;
      case HwDecodeMode.mediaCodecZeroCopy:
        return l10n.settingsHwDecodeModeZeroCopy;
      case HwDecodeMode.autoSafe:
        return l10n.settingsHwDecodeModeAuto;
      case HwDecodeMode.disabled:
        return l10n.settingsHwDecodeModeOff;
    }
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
  Future<void> _showWebDavConfig(BuildContext context) async {
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

    await showModalBottomSheet(
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
    // 弹窗关闭后释放 4 个输入控制器（否则每次打开 WebDAV 配置都泄漏一份）。
    urlController.dispose();
    userController.dispose();
    passController.dispose();
    pathController.dispose();
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
    controller.dispose();

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

  /// 导出诊断日志：打包 guanzi_logs 到系统下载目录。
  Future<void> _exportLogs(BuildContext context) async {
    if (SettingsPage._logBusy) return;
    SettingsPage._logBusy = true;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在导出诊断日志…')),
      );
    }
    try {
      final dest = await LogExport.exportToDownloads();
      DebugLog.log('LogExport', '导出成功: $dest');
      if (context.mounted) {
        // 老系统在无存储权限时会降级到应用外部目录，因此显示实际落盘路径而非写死「下载目录」。
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出：$dest')),
        );
      }
    } catch (e) {
      DebugLog.log('LogExport', '导出失败: $e', flush: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败：$e')),
        );
      }
    } finally {
      SettingsPage._logBusy = false;
    }
  }

  /// 清空诊断日志：删除崩溃/日志文件（应用对自身私有目录有删除权）。
  Future<void> _clearLogs(BuildContext context) async {
    if (SettingsPage._logBusy) return;
    SettingsPage._logBusy = true;
    try {
      final n = await LogExport.clearLogs();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(n > 0 ? '已清空 $n 个日志/崩溃文件' : '没有可清空的文件')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清空失败：$e')),
        );
      }
    } finally {
      SettingsPage._logBusy = false;
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

  /// 更新日志（底部弹窗：isScrollControlled + 高度上限 + 内部 SingleChildScrollView）
  void _showChangelogSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '更新日志',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '当前 v${AppConstants.appVersion}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final entry in AppChangelog.entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  'v${entry.version}',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  entry.date,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (final item in entry.items)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Container(
                                      width: 4,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      item,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showTmdbApiKeyDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final controller = TextEditingController(text: settings.tmdbApiKey);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsTmdbApiKey),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.settingsTmdbApiKeyDialogBody,
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
              await settings.setTmdbApiKey(controller.text);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.settingsTmdbApiKeySaved)),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  String _aiSubtitleStatusText(BuildContext context) {
    final s = StorageService();
    final minutes = s.subtitleAiMaxMinutes <= 0 ? 10 : s.subtitleAiMaxMinutes;
    switch (s.subtitleAiBackend) {
      case SubtitleAiBackendKind.onlineApi:
        if (s.subtitleAiApiUrl.trim().isEmpty) {
          return '在线 API 未配置 · $minutes 分钟';
        }
        final model = s.subtitleAiModel.isEmpty ? 'base' : s.subtitleAiModel;
        return '在线 API · $model · $minutes 分钟';
      case SubtitleAiBackendKind.sherpaNative:
        if (s.subtitleAiOfflineModel.isEmpty) {
          return '本地离线 · 未选模型 · $minutes 分钟';
        }
        return '本地离线 · $minutes 分钟';
      case SubtitleAiBackendKind.transformersWeb:
        return '浏览器 Whisper · $minutes 分钟';
    }
  }

  Future<void> _showOpensubtitlesApiKeyDialog(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final controller =
        TextEditingController(text: settings.opensubtitlesApiKey);
    await showDialog<void>(
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
    controller.dispose();
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
