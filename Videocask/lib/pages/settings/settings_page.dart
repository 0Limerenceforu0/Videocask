import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:file_picker/file_picker.dart';
import 'dart:convert' show utf8;
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
import '../../services/subtitle_service.dart';
import '../../services/video_output_policy.dart';
import '../../widgets/ai_subtitle_settings_panel.dart';
import '../../widgets/app_about_dialog.dart';
import '../../widgets/webdav_config_sheet.dart';
import '../../services/data_export.dart';
import 'magnet_sources_page.dart';
import 'update_dialog.dart';
import '../../providers/theme_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/source_provider.dart';
import '../../providers/cache_provider.dart';
import '../../services/debug_log.dart';
import '../../services/log_export.dart';
import '../../services/hw_decode_policy.dart';
import '../../services/buffer_tier.dart';
import '../../services/hw_decode_platform.dart';

/// 设置中心页面
class SettingsPage extends StatelessWidget {
  /// 从「我的」页跳进来时指定要置顶的分组（例如 `webdav`）。
  /// 纯声明式重排，不需要滚动控制器，StatelessWidget 也不会泄漏资源。
  final String? anchor;

  const SettingsPage({super.key, this.anchor});

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

    Widget section(String title, List<Widget> children) =>
        _section(context, colors, title, children);

    final sections = <String, Widget>{
      // ===== 播放 =====
      'play': section('播放', [
        _buildBiliSettingItem(
          context,
          colors,
          icon: Icons.high_quality_outlined,
          iconBgColor: const Color(0xFF81C784),
          title: '默认清晰度',
          value: context
              .select<SettingsProvider, String>((s) => s.defaultQuality),
          onTap: () => _showQualitySetting(context),
        ),
        _buildBiliDivider(colors),
        _buildBiliSwitchItem(
          context,
          colors,
          icon: Icons.playlist_play_outlined,
          iconBgColor: const Color(0xFFCE93D8),
          title: '自动连播',
          subtitle: '播放完自动播放下一集',
          value: context
              .select<SettingsProvider, bool>((s) => s.autoPlayNext),
          onChanged: (value) =>
              context.read<SettingsProvider>().setAutoPlayNext(value),
        ),
        _buildBiliDivider(colors),
        _buildBiliSwitchItem(
          context,
          colors,
          icon: Icons.play_circle_outline,
          iconBgColor: const Color(0xFF64B5F6),
          title: l10n.settingsAutoPlayOnDetailEnter,
          subtitle: l10n.settingsAutoPlayOnDetailEnterSubtitle,
          value: context.select<SettingsProvider, bool>(
              (s) => s.autoPlayOnDetailEnter),
          onChanged: (value) => context
              .read<SettingsProvider>()
              .setAutoPlayOnDetailEnter(value),
        ),
        _buildBiliDivider(colors),
        _buildBiliSwitchItem(
          context,
          colors,
          icon: Icons.block_outlined,
          iconBgColor: const Color(0xFFEF9A9A),
          title: 'HLS 去广告',
          subtitle: '自动剔除 m3u8 里注入的广告分片；如遇跳剧情可关闭',
          value: context
              .select<SettingsProvider, bool>((s) => s.hlsAdFilter),
          onChanged: (value) =>
              context.read<SettingsProvider>().setHlsAdFilter(value),
        ),
        _buildBiliDivider(colors),
        _buildBiliSwitchItem(
          context,
          colors,
          icon: Icons.headphones_outlined,
          iconBgColor: const Color(0xFF9575CD),
          title: '后台播放',
          subtitle: '返回桌面或切到其它应用后继续播放（会显示一条常驻通知）',
          value: context.select<SettingsProvider, bool>(
              (s) => s.backgroundPlayback),
          onChanged: (value) => context
              .read<SettingsProvider>()
              .setBackgroundPlayback(value),
        ),
        _buildBiliDivider(colors),
        _buildBiliSwitchItem(
          context,
          colors,
          icon: Icons.skip_next_outlined,
          iconBgColor: const Color(0xFF4DB6AC),
          title: '提前加载下一集',
          subtitle: '播放到 80% 时解析并预拉下一集；关闭后不解析、不预热',
          value: context.select<SettingsProvider, bool>(
              (s) => s.preloadNextEpisode),
          onChanged: (value) => context
              .read<SettingsProvider>()
              .setPreloadNextEpisode(value),
        ),
      ]),

      // ===== 画面与性能 =====
      'video': section('画面与性能', [
        _buildBiliSettingItem(
          context,
          colors,
          icon: Icons.tune_outlined,
          iconBgColor: const Color(0xFF4DB6AC),
          title: l10n.settingsHwDecodeMode,
          value: _hwDecodeModeSummary(context),
          onTap: () => _showHwDecodeModeSheet(context),
        ),
        _buildBiliDivider(colors),
        _buildBiliSettingItem(
          context,
          colors,
          icon: Icons.monitor_outlined,
          iconBgColor: const Color(0xFF9575CD),
          title: l10n.settingsVideoOutputMode,
          value: _videoOutputModeSummary(context),
          onTap: () => _showVideoOutputModeSheet(context),
        ),
        _buildBiliDivider(colors),
        _buildBiliSettingItem(
          context,
          colors,
          icon: Icons.memory_outlined,
          iconBgColor: const Color(0xFF4DD0E1),
          title: '缓冲大小',
          value: context.select<SettingsProvider, String>((s) {
            final label = BufferTier.labelOf(
              s.bufferTier,
              autoBytes: s.autoBufferBytes,
            );
            if (s.bufferTier != BufferTier.autoKey) return label;
            // 桌面 / Web 的内存探测恒为 0，自动挡实际是固定 192MB，
            // 播放中不会升降档；UI 必须如实说明，不能叫「自动」了事。
            final canAutoTune = !kIsWeb &&
                defaultTargetPlatform == TargetPlatform.android;
            return canAutoTune ? label : '$label · 此平台固定，不自动调档';
          }),
          onTap: () => _showBufferTierSetting(context),
        ),
        _buildBiliDivider(colors),
        _buildBiliSettingItem(
          context,
          colors,
          icon: Icons.precision_manufacturing_outlined,
          iconBgColor: const Color(0xFFFF8A65),
          title: '拖动精度',
          value: context.select<SettingsProvider, String>(
            (s) => _hrSeekLabel(s.hrSeekMode),
          ),
          onTap: () => _showHrSeekSetting(context),
        ),
      ]),

      // ===== 字幕 =====
      'subtitle': section('字幕', [
        _buildBiliSettingItem(
          context,
          colors,
          icon: Icons.subtitles_outlined,
          iconBgColor: const Color(0xFF78909C),
          title: '在线字幕源',
          value: SubtitleService().lastError.isNotEmpty
              ? '免费源 · 上次失败（点开查看）'
              : '免费源 · 免配置',
          onTap: () => _showOnlineSubtitleStatusDialog(context),
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
      ]),

      // ===== 片源 =====
      'sources': section('片源', [
        _buildBiliSettingItem(
          context,
          colors,
          icon: Icons.source_outlined,
          iconBgColor: const Color(0xFF4FC3F7),
          title: '播放源管理',
          value:
              '${context.select<SourceProvider, int>((s) => s.sources.length)} 个源',
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
              '${context.select<SettingsProvider, int>((s) => s.enabledMagnetSourceCount)}/${context.select<SettingsProvider, int>((s) => s.visibleMagnetSources.length)} 已启用',
          onTap: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (ctx) => const MagnetSourcesPage(),
              ),
            );
          },
        ),
      ]),

      // ===== 数据 =====
      'data': section('数据', [
        _buildBiliSettingItem(
          context,
          colors,
          icon: Icons.download_outlined,
          iconBgColor: const Color(0xFF81C784),
          title: '缓存管理',
          value: context
              .select<CacheProvider, String>((s) => s.formattedTotalSize),
          onTap: () => AppRoutes.toCacheManager(context),
        ),
        _buildBiliDivider(colors),
        _buildBiliSwitchItem(
          context,
          colors,
          icon: Icons.wifi_outlined,
          iconBgColor: const Color(0xFF64B5F6),
          title: l10n.settingsOnlyWifiCache,
          subtitle: l10n.settingsOnlyWifiCacheSubtitle,
          value: context
              .select<SettingsProvider, bool>((s) => s.onlyWifiCache),
          onChanged: (value) {
            unawaited(() async {
              await context.read<SettingsProvider>().setOnlyWifiCache(value);
              if (!context.mounted) return;
              await context.read<CacheProvider>().setOnlyWifi(value);
            }());
          },
        ),
        _buildBiliDivider(colors),
        _buildBiliSettingItem(
          context,
          colors,
          icon: Icons.cloud_upload_outlined,
          iconBgColor: const Color(0xFF90CAF9),
          title: '导出数据',
          value: '保存到系统下载目录',
          onTap: () => _exportData(context),
        ),
        _buildBiliDivider(colors),
        _buildBiliSettingItem(
          context,
          colors,
          icon: Icons.cloud_download_outlined,
          iconBgColor: const Color(0xFFA5D6A7),
          title: '导入数据',
          value: '从备份文件恢复',
          onTap: () => _importData(context),
        ),
      ]),

      // ===== 云备份（WebDAV）=====
      'webdav': section('云备份（WebDAV）', [
        _buildBiliSettingItem(
          context,
          colors,
          icon: context.select<SettingsProvider, bool>(
                  (s) => s.webdavConnected)
              ? Icons.cloud_done_outlined
              : Icons.cloud_queue_outlined,
          iconBgColor: context.select<SettingsProvider, bool>(
                  (s) => s.webdavConnected)
              ? const Color(0xFF81C784)
              : const Color(0xFFBDBDBD),
          title: 'WebDAV配置',
          value: context.select<SettingsProvider, bool>(
                  (s) => s.webdavConnected)
              ? '已连接'
              : '未配置',
          onTap: () => unawaited(showWebDavConfigSheet(context)),
        ),
        if (context.select<SettingsProvider, bool>(
            (s) => s.webdavConnected)) ...[
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
              context.select<SettingsProvider, String>(
                  (s) => s.conflictStrategy),
            ),
            onTap: () => _showConflictStrategy(context),
          ),
        ],
      ]),

      // ===== 通用（原「外观」并入）=====
      'general': section('通用', [
        _buildBiliSettingItem(
          context,
          colors,
          icon: Icons.palette_outlined,
          iconBgColor: const Color(0xFFF48FB1),
          title: '主题切换',
          value: context.select<ThemeProvider, String>((s) => s.themeName),
          onTap: () => _showThemeSelector(context),
        ),
        _buildBiliDivider(colors),
        _buildBiliSettingItem(
          context,
          colors,
          icon: Icons.movie_filter_outlined,
          iconBgColor: const Color(0xFF7986CB),
          title: l10n.settingsTmdbApiKey,
          value: context.select<SettingsProvider, bool>(
                  (s) => s.tmdbApiKeyConfigured)
              ? l10n.settingsTmdbApiKeyConfigured
              : l10n.settingsTmdbApiKeyNotConfigured,
          onTap: () => _showTmdbApiKeyDialog(context),
        ),
      ]),

      // ===== 诊断：长说明已移到「关于 → 帮助与反馈」=====
      'diagnosis': section('诊断', [
        // Web 没有 Android MediaStore / 桌面下载目录通道，导出与清空都会抛
        // MissingPluginException，因此这两项只在原生端出现。
        if (!kIsWeb) ...[
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            kIsWeb
                ? '网页版暂不支持导出 / 清空诊断日志；遇到问题请截图反馈。'
                : '出问题先复现一次，再导出日志；用法见「关于 → 帮助与反馈」。',
            style: TextStyle(color: colors.subTextColor, fontSize: 12),
          ),
        ),
      ]),

      // ===== 关于 =====
      'about': section('关于', [
        _buildBiliSettingItem(
          context,
          colors,
          icon: Icons.info_outline,
          iconBgColor: const Color(0xFF4FC3F7),
          title: '关于与帮助',
          value: 'v${AppConstants.appVersion}',
          onTap: () => showAppAboutDialog(context),
        ),
        _buildBiliDivider(colors),
        _buildBiliSettingItem(
          context,
          colors,
          icon: Icons.system_update_outlined,
          iconBgColor: const Color(0xFF9575CD),
          title: '检查更新',
          value: '当前 v${AppConstants.appVersion}',
          onTap: () => checkUpdateManually(context),
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
      ]),
    };

    final order = <String>[
      'play',
      'video',
      'subtitle',
      'sources',
      'data',
      'webdav',
      'general',
      'diagnosis',
      'about',
    ];
    final targetAnchor = anchor;
    if (targetAnchor != null && sections.containsKey(targetAnchor)) {
      order.remove(targetAnchor);
      order.insert(0, targetAnchor);
    }

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
          for (final key in order) sections[key]!,
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 分组容器：标题 + 卡片 + 组间距。
  Widget _section(
    BuildContext context,
    _SettingsColors colors,
    String title,
    List<Widget> children,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBiliSectionHeader(colors, title),
          _buildBiliSectionCard(context, colors, children: children),
        ],
      ),
    );
  }

  String _hrSeekLabel(String mode) {
    if (mode == 'yes') return '精确';
    if (mode == 'no') return '快速';
    return '跟随默认';
  }

  /// 拖动精度（hr-seek）。从原「播放偏好三档」里拆出来单独成项。
  /// 统一的「设置项底部弹窗」范式。
  ///
  /// 三样必须同时具备，缺一个就会在档位多 / 说明长时把末尾内容裁掉且滑不动：
  /// 1. `isScrollControlled` —— 允许 sheet 超过默认约 9/16 屏高；
  /// 2. Container 高度上限 —— 防止内容把整屏顶满；
  /// 3. `Flexible` + `SingleChildScrollView` —— 标题固定，选项与说明可滚动。
  /// 「更新日志 / 缓冲大小 / 主题」弹窗用的是同一套写法，此处供其余设置项复用。
  void _showScrollableSettingSheet(
    BuildContext context, {
    required String title,
    Widget? description,
    required List<Widget> Function(BuildContext sheetContext) items,
    Widget? footer,
    double maxHeightFactor = 0.75,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final maxHeight =
            MediaQuery.of(sheetContext).size.height * maxHeightFactor;
        return Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (description != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: description,
                  ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...items(sheetContext),
                        if (footer != null) footer,
                        const SizedBox(height: 8),
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

  void _showHrSeekSetting(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    const options = [
      ('', '跟随默认', '由播放器按片源决定'),
      ('yes', '精确', '拖到哪帧从哪帧播，seek 稍慢'),
      ('no', '快速', '就近关键帧起播，更跟手'),
    ];
    _showScrollableSettingSheet(
      context,
      title: '拖动精度',
      items: (sheetContext) => [
        for (final option in options)
          RadioListTile<String>(
            value: option.$1,
            groupValue: settings.hrSeekMode,
            title: Text(option.$2),
            subtitle: Text(option.$3),
            onChanged: (value) {
              if (value == null) return;
              settings.setHrSeekMode(value);
              Navigator.pop(sheetContext);
            },
          ),
      ],
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
    _showScrollableSettingSheet(
      context,
      title: l10n.settingsHwDecodeMode,
      description: Text(
        l10n.settingsHwDecodeModeDesc,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      items: (sheetContext) => [
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
                context.read<SettingsProvider>().setHwDecodeMode(
                      hwDecodeModeFromKey(
                        value,
                        platform: detectHwDecodePlatform(),
                      ),
                    );
              }
              Navigator.pop(sheetContext);
            },
            title: Text(option.label),
          ),
      ],
    );
  }

  /// 视频输出后端选择（默认 gpu-next / 新版渲染）。
  /// fd 泄漏已在引擎层通过 SurfaceTexture 桥接统一修复，三种后端都不漏句柄；
  /// 该设置只影响画面兼容性与功能（字幕/滤镜/截图），出画异常时再手动切换。
  void _showVideoOutputModeSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final current = settings.effectiveVideoOutputMode;
    _showScrollableSettingSheet(
      context,
      title: l10n.settingsVideoOutputMode,
      description: Text(
        l10n.settingsVideoOutputModeDesc,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      items: (sheetContext) => [
        // 顺序即推荐顺序：新版渲染（推荐）→ 旧版渲染（兜底）→ 硬解直出。
        for (final option in [
          (
            value: VideoOutputMode.gpuNext,
            label: l10n.settingsVoGpuNext,
            desc: l10n.settingsVoGpuNextDesc
          ),
          (
            value: VideoOutputMode.gpu,
            label: l10n.settingsVoGpu,
            desc: l10n.settingsVoGpuDesc
          ),
          (
            value: VideoOutputMode.mediacodecEmbed,
            label: l10n.settingsVoEmbed,
            desc: l10n.settingsVoEmbedDesc
          ),
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
      ],
    );
  }

  String _videoOutputModeSummary(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (context.select<SettingsProvider, VideoOutputMode>(
        (s) => s.effectiveVideoOutputMode)) {
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
        key ==
            encodeHwDecodeMode(
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

  /// 显示清晰度设置
  void _showQualitySetting(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    _showScrollableSettingSheet(
      context,
      title: '默认清晰度',
      items: (sheetContext) => [
        for (final quality in AppConstants.qualityOptions)
          ListTile(
            title: Text(quality),
            trailing: quality == settings.defaultQuality
                ? Icon(
                    Icons.check,
                    color: Theme.of(sheetContext).colorScheme.primary,
                  )
                : null,
            selected: quality == settings.defaultQuality,
            onTap: () {
              settings.setDefaultQuality(quality);
              Navigator.of(sheetContext).pop();
            },
          ),
      ],
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Text(
          '优先选择片源里最接近该档位的清晰度；片源本身只有单一画质时无法改变。'
          '改动在下一次起播生效。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }

  /// 显示缓冲挡位选择。
  ///
  /// 「自动」按本机物理内存推算；手动挡位钉死 128~512MB。
  /// 改动只对之后 open 的媒体生效（mpv 的 demuxer 参数在 open 时绑定）。
  /// 弹窗必须 isScrollControlled + 高度上限 + 内部可滚动：6 个挡位加说明文字
  /// 会超出 bottomSheet 默认高度，否则末尾档位和说明被裁掉且滑不动。
  void _showBufferTierSetting(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final totalMem = settings.deviceTotalMemoryBytes;
    final availMem = settings.availableMemoryBytes;
    final autoBytes = settings.autoBufferBytes;
    final current = settings.bufferTier;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
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
                  '缓冲大小',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...BufferTier.allKeys.map((key) {
                        final isSelected = key == current;
                        return ListTile(
                          title: Text(
                            BufferTier.labelOf(
                              key,
                              autoBytes: key == BufferTier.autoKey
                                  ? autoBytes
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            BufferTier.describe(
                              tier: key,
                              totalMemoryBytes: totalMem,
                              availableMemoryBytes: availMem,
                              autoBytes: key == BufferTier.autoKey
                                  ? autoBytes
                                  : null,
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : null,
                          selected: isSelected,
                          onTap: () {
                            settings.setBufferTier(key);
                            Navigator.of(context).pop();
                          },
                        );
                      }),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Text(
                          '自动挡按本机内存定上限，播放时每 10 分钟看一次系统可用内存：'
                          '紧张就降档，宽裕就升档（字节与预读秒数一起调）。'
                          '缓冲越大越能扛住网络抖动，但占用内存也越多。'
                          '磁力/本地播放不受此项影响。改动在下一集或重新进入播放时生效；'
                          '播放中改挡位会立刻热更新播放器。'
                          '${(!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ? '' : '当前平台不支持内存探测：自动挡固定 192 MB、不会动态调档，需要不同大小请选手动挡位。'}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
    _showScrollableSettingSheet(
      context,
      title: '冲突解决策略',
      items: (sheetContext) => [
        for (final option in [
          ('local_win', '本地优先', '冲突时保留本地数据'),
          ('remote_win', '远程优先', '冲突时使用云端数据'),
          ('newest_win', '最新优先', '冲突时保留较新的数据'),
        ])
          ListTile(
            title: Text(option.$2),
            subtitle: Text(option.$3),
            trailing: settings.conflictStrategy == option.$1
                ? const Icon(Icons.check)
                : null,
            onTap: () {
              settings.setConflictStrategy(option.$1);
              Navigator.of(sheetContext).pop();
            },
          ),
      ],
    );
  }

  /// 导出数据：写成文件放进系统「下载」目录，不再塞进剪贴板。
  /// Web 端没有原生下载通道，降级到剪贴板。
  void _exportData(BuildContext context) async {
    final jsonData = await context.read<SettingsProvider>().exportData();
    if (jsonData.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出失败：无数据')),
        );
      }
      return;
    }
    try {
      final dest = await DataExport.exportText(
        name: DataExport.backupFileName(),
        content: jsonData,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出：$dest')),
        );
      }
    } catch (e) {
      // 原生通道不可用（Web / 老系统 / 权限异常）：至少不能丢数据。
      await Clipboard.setData(ClipboardData(text: jsonData));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(kIsWeb
                ? '数据已复制到剪贴板'
                : '写文件失败，已改为复制到剪贴板：$e'),
          ),
        );
      }
    }
  }

  /// 导入数据：走系统文件选择器，不再让用户粘贴一大段 JSON。
  void _importData(BuildContext context) async {
    String jsonText = '';
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final bytes = picked.files.first.bytes;
      if (bytes == null) return;
      jsonText = utf8.decode(bytes);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('读取文件失败：$e')),
        );
      }
      return;
    }
    if (jsonText.trim().isEmpty) return;
    final success = await context.read<SettingsProvider>().importData(jsonText);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? '导入成功' : '导入失败：格式不正确')),
      );
    }
  }

  /// 导出诊断日志：打包 videocask_logs 到系统下载目录。
  Future<void> _exportLogs(BuildContext context) async {
    // 兜底：即便 UI 入口被误开，Web 也不能走原生通道。
    if (kIsWeb) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网页版暂不支持导出诊断日志')),
        );
      }
      return;
    }
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
    // 兜底：即便 UI 入口被误开，Web 也不能走原生通道。
    if (kIsWeb) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网页版暂不支持清空诊断日志')),
        );
      }
      return;
    }
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

  /// 更新日志（底部弹窗：isScrollControlled + 高度上限 + ListView 懒构建）
  ///
  /// 🔴 必须用 `ListView.builder`：历史已有 37 个版本 / 134 条，原先
  /// `SingleChildScrollView + Column(for ...)` 会一次性构建上千个 Widget，
  /// 打开与滚动都要整表布局/光栅化，中低端机上明显掉帧（2026-11-07 反馈）。
  void _showChangelogSheet(BuildContext context) {
    // 先把「版本头 + 每条内容」摊平成扁平索引，交给 builder 按需构建。
    final rows = <_ChangelogRow>[
      for (final entry in AppChangelog.entries) ...[
        _ChangelogRow.version(entry),
        for (final item in entry.items) _ChangelogRow.item(item),
      ],
    ];
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
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: rows.length,
                    // 只构建视口内的行；滑出即回收，条目再多也不会拖慢打开速度。
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final entry = row.entry;
                      if (entry != null) {
                        return Padding(
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
                        );
                      }
                      return Padding(
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
                                row.text ?? '',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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

  /// 在线字幕源状态：S5 起改用免费无 Key 的源，这里只展示状态与最近一次
  /// 失败原因（失败可见但不打扰，不弹窗打断播放）。
  Future<void> _showOnlineSubtitleStatusDialog(BuildContext context) async {
    final svc = SubtitleService();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('在线字幕源'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                svc.providerLabel,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '自动匹配简体中文字幕，无需注册、无需 API Key。'
                '磁力资源会优先用片源内封 / 种子内字幕，在线源只是补充。',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (svc.lastError.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '最近一次失败：${svc.lastError}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
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

/// 更新日志弹窗的扁平行：要么是版本头，要么是一条内容。
///
/// 历史已有 37 个版本 / 134 条，必须摊平后交给 `ListView.builder` 懒构建；
/// 若直接 `Column(for ...)` 会一次性建出上千个 Widget，打开即掉帧。
class _ChangelogRow {
  const _ChangelogRow.version(this.entry) : text = null;

  const _ChangelogRow.item(this.text) : entry = null;

  /// 版本头（含版本号与日期）。
  final ChangelogEntry? entry;

  /// 单条更新内容。
  final String? text;
}
