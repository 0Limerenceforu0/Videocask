// ignore_for_file: prefer_const_constructors

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../services/subtitle_ai_availability_policy.dart';
import '../services/subtitle_ai_backend.dart';
import '../services/subtitle_ai_model_manager.dart';

/// AI 字幕设置面板（三种后端 + 模型管理）
///
/// 用 [showModalBottomSheet] 弹出。
class AiSubtitleSettingsPanel extends StatefulWidget {
  const AiSubtitleSettingsPanel({super.key});

  @override
  State<AiSubtitleSettingsPanel> createState() =>
      _AiSubtitleSettingsPanelState();
}

/// 根据明暗主题返回「次要文字」颜色。
///
/// 注意：**不要**在这里写死 `Colors.black54` —— 本项目默认主题是深色
/// （surface `#393E46`），黑色半透明文字在深灰面板上几乎看不见，
/// 视觉上等同于「文字没显示出来」。
Color _mutedColor(BuildContext context) {
  final theme = Theme.of(context);
  final base = theme.textTheme.bodySmall?.color ?? theme.colorScheme.onSurface;
  return base.withValues(
    alpha: theme.brightness == Brightness.dark ? 0.75 : 0.7,
  );
}

class _AiSubtitleSettingsPanelState extends State<AiSubtitleSettingsPanel> {
  SubtitleAiBackendKind _backend = SubtitleAiBackendKind.onlineApi;
  String _selectedModelId = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final s = StorageService();
    setState(() {
      _backend = _availableBackends().contains(s.subtitleAiBackend)
          ? s.subtitleAiBackend
          : _availableBackends().first;
      _selectedModelId = s.subtitleAiOfflineModel;
    });
  }

  /// 离线后端不可用时给用户的说明；可用则为 null。
  ///
  /// 离线识别 = 本地 ASR + **本地抽音**。抽音依赖平台能力：
  /// - 桌面端：spawn 系统/随包 ffmpeg（可用）
  /// - 移动端：需要 ffmpeg-kit，`subtitle_ai_audio_extractor_mobile.dart`
  ///   目前还是 stub，且 `registerMobileFfmpegRunner()` 从未被调用 → 点了必失败
  /// - Web 端：需要 transformers.js 的 JS bridge，同样是 stub
  ///
  /// 与其让用户点下去才报一句看不懂的错误，不如直接不给这个选项。
  String? get _offlineUnavailableReason {
    // 与播放页字幕面板共用同一份判据，避免两处各写一套、以后又对不上。
    final reason = offlineSubtitleUnavailableReason(offlineSubtitleSupport());
    return reason.isEmpty ? null : reason;
  }

  List<SubtitleAiBackendKind> _availableBackends() {
    if (_offlineUnavailableReason != null) {
      return [SubtitleAiBackendKind.onlineApi];
    }
    return kIsWeb
        ? [
            SubtitleAiBackendKind.onlineApi,
            SubtitleAiBackendKind.transformersWeb,
          ]
        : [
            SubtitleAiBackendKind.onlineApi,
            SubtitleAiBackendKind.sherpaNative,
          ];
  }

  Future<void> _setBackend(SubtitleAiBackendKind v) async {
    final s = StorageService();
    await s.setSubtitleAiBackend(v);
    setState(() => _backend = v);
  }

  Future<void> _setModel(String id) async {
    final s = StorageService();
    await s.setSubtitleAiOfflineModel(id);
    setState(() => _selectedModelId = id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _mutedColor(context);
    // 面板自己负责滚动：外层负责给高度上限，这里保证内容再多也能滚到底。
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部把手
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI 字幕生成',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '本地离线方案基于 sherpa_onnx（Apache 2.0，零付费）；Web 浏览器端走 transformers.js。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontSize: 11,
                  height: 1.35,
                ),
                softWrap: true,
              ),
              const SizedBox(height: 12),
              // 后端切换
              _buildBackendSelector(theme),
              if (_offlineUnavailableReason != null) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: muted),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '当前平台只有「在线 API」可用：${_offlineUnavailableReason!}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontSize: 11,
                          height: 1.35,
                        ),
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              // 公共设置
              _buildCommonSettings(theme),
              const SizedBox(height: 8),
              const Divider(),
              // 后端专属配置
              if (_backend == SubtitleAiBackendKind.onlineApi)
                _OnlineApiForm(onChanged: () => setState(() {}))
              else if (_backend == SubtitleAiBackendKind.sherpaNative)
                _NativeModelManager(
                  selectedModelId: _selectedModelId,
                  onSelected: _setModel,
                )
              else
                _WebModelManager(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackendSelector(ThemeData theme) {
    final options = _availableBackends();
    // 撑满宽度：否则窄窗口里分段按钮的文字会被挤成省略号。
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<SubtitleAiBackendKind>(
        showSelectedIcon: false,
        segments: options
            .map(
              (b) => ButtonSegment<SubtitleAiBackendKind>(
                value: b,
                label: Text(
                  b == SubtitleAiBackendKind.onlineApi ? '在线 API' : '本地离线',
                  style: const TextStyle(fontSize: 12),
                  softWrap: false,
                  overflow: TextOverflow.fade,
                ),
                icon: Icon(
                  b == SubtitleAiBackendKind.onlineApi
                      ? Icons.cloud_outlined
                      : Icons.memory,
                  size: 16,
                ),
              ),
            )
            .toList(),
        selected: {_backend},
        onSelectionChanged: (s) => _setBackend(s.first),
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }

  Widget _buildCommonSettings(ThemeData theme) {
    final s = StorageService();
    final minutes = s.subtitleAiMaxMinutes <= 0 ? 10 : s.subtitleAiMaxMinutes;
    return Row(
      children: [
        const Icon(Icons.timer_outlined, size: 16),
        const SizedBox(width: 6),
        const Text('识别前', style: TextStyle(fontSize: 12)),
        const SizedBox(width: 6),
        DropdownButton<int>(
          value: minutes,
          underline: const SizedBox.shrink(),
          isDense: true,
          style: const TextStyle(fontSize: 12),
          items: [3, 5, 10, 15, 20, 30, 45, 60]
              .map((m) => DropdownMenuItem(value: m, child: Text('$m 分钟')))
              .toList(),
          onChanged: (v) async {
            if (v != null) {
              await s.setSubtitleAiMaxMinutes(v);
              if (mounted) setState(() {});
            }
          },
        ),
        const Spacer(),
        if (_backend == SubtitleAiBackendKind.onlineApi)
          Flexible(
            child: Text(
              '${s.subtitleAiModel.isEmpty ? 'base' : s.subtitleAiModel} · ${s.subtitleAiLanguage.isEmpty ? 'zh' : s.subtitleAiLanguage}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _mutedColor(context),
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
      ],
    );
  }
}

/// 在线 API 表单（保留原所有字段）
class _OnlineApiForm extends StatefulWidget {
  const _OnlineApiForm({required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<_OnlineApiForm> createState() => _OnlineApiFormState();
}

class _OnlineApiFormState extends State<_OnlineApiForm> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _langCtrl;
  late final TextEditingController _promptCtrl;
  late bool _sendAsUrl;

  @override
  void initState() {
    super.initState();
    final s = StorageService();
    _urlCtrl = TextEditingController(text: s.subtitleAiApiUrl);
    _keyCtrl = TextEditingController(text: s.subtitleAiApiKey);
    _modelCtrl = TextEditingController(text: s.subtitleAiModel);
    _langCtrl = TextEditingController(text: s.subtitleAiLanguage);
    _promptCtrl = TextEditingController(text: s.subtitleAiInitialPrompt);
    _sendAsUrl = s.subtitleAiSendAsUrl;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _langCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = StorageService();
    await s.setSubtitleAiApiUrl(_urlCtrl.text);
    await s.setSubtitleAiApiKey(_keyCtrl.text);
    await s.setSubtitleAiModel(_modelCtrl.text);
    await s.setSubtitleAiLanguage(_langCtrl.text);
    await s.setSubtitleAiInitialPrompt(_promptCtrl.text);
    await s.setSubtitleAiSendAsUrl(_sendAsUrl);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(
            _urlCtrl,
            'API URL',
            'https://api.openai.com/v1/audio/transcriptions',
          ),
          _field(_keyCtrl, 'API Key（可选）', 'sk-...'),
          Row(
            children: [
              Expanded(
                child: _field(_modelCtrl, '模型', 'whisper-1 / base / large-v3'),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: _field(_langCtrl, '语种', 'zh / en'),
              ),
            ],
          ),
          _field(_promptCtrl, '提示词（可选）', '片名 / 领域术语'),
          SwitchListTile(
            dense: true,
            // 次标题较长，去掉默认 16 的左缩进，避免右侧文字被挤到换行/截断。
            contentPadding: EdgeInsets.zero,
            title: const Text('JSON URL 模式', style: TextStyle(fontSize: 12)),
            subtitle: Text(
              'faster-whisper-server 直接传 URL，不先把文件下载到本地',
              style: TextStyle(
                fontSize: 10,
                color: _mutedColor(context),
                height: 1.35,
              ),
              softWrap: true,
            ),
            value: _sendAsUrl,
            onChanged: (v) => setState(() => _sendAsUrl = v),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save, size: 16),
              label: const Text('保存'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

/// Native 端模型管理器
class _NativeModelManager extends StatelessWidget {
  const _NativeModelManager({
    required this.selectedModelId,
    required this.onSelected,
  });
  final String selectedModelId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final models = kSubtitleAiModelRegistry.all
        .where((m) => m.engineKind != 'whisper_web')
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            '离线模型（首次使用需下载到本机，下载一次即可重复使用）',
            style: TextStyle(
              fontSize: 11,
              color: _mutedColor(context),
              height: 1.35,
            ),
            softWrap: true,
          ),
        ),
        for (final m in models)
          _ModelTile(
            model: m,
            isSelected: m.id == selectedModelId,
            onTap: () => onSelected(m.id),
          ),
      ],
    );
  }
}

/// Web 端模型管理器（占位）
class _WebModelManager extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.public, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '浏览器内自动加载 Whisper base（首次 ~150MB，会缓存到浏览器 OPFS / IndexedDB）。无需手动管理。',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个模型行
class _ModelTile extends StatefulWidget {
  const _ModelTile({
    required this.model,
    required this.isSelected,
    required this.onTap,
  });
  final SubtitleAiModel model;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_ModelTile> createState() => _ModelTileState();
}

class _ModelTileState extends State<_ModelTile> {
  bool _downloading = false;
  double _progress = 0.0;
  String _progressMsg = '';
  bool? _installed;
  int _installedSize = 0;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final ok = await widget.model.isLocallyAvailable;
    final size = await widget.model.localSizeBytes;
    if (!mounted) return;
    setState(() {
      _installed = ok;
      _installedSize = size;
    });
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0.0;
      _progressMsg = '准备下载…';
    });
    try {
      await SubtitleAiModelInstaller().download(
        widget.model,
        onProgress: (p, msg) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            _progressMsg = msg;
          });
        },
      );
      if (!mounted) return;
      await _refreshStatus();
      widget.onTap();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已下载：${widget.model.displayName}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _progress = 0.0;
          _progressMsg = '';
        });
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除 ${widget.model.displayName}？'),
        content: Text(
          '将释放 ${(widget.model.approxSizeMb)}MB 磁盘空间。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await SubtitleAiModelInstaller().delete(widget.model);
    if (!mounted) return;
    await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installed = _installed == true;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: widget.isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.10)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(
          color: widget.isSelected
              ? theme.colorScheme.primary
              : theme.dividerColor,
          width: widget.isSelected ? 1.5 : 0.5,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                installed ? Icons.check_circle : Icons.download_outlined,
                size: 16,
                color: installed ? Colors.green : theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.model.displayName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                installed
                    ? '${(_installedSize / 1024 / 1024).toStringAsFixed(0)}MB'
                    : '~${widget.model.approxSizeMb}MB',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.model.description,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              height: 1.35,
              color: _mutedColor(context),
            ),
            softWrap: true,
          ),
          if (_downloading) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 4,
                backgroundColor: Colors.black12,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: Text(
                _progressMsg,
                style: TextStyle(fontSize: 10, color: _mutedColor(context)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (installed)
                  TextButton.icon(
                    onPressed: widget.isSelected ? null : () => widget.onTap(),
                    icon: const Icon(Icons.radio_button_checked, size: 14),
                    label: Text(
                      widget.isSelected ? '已选用' : '选用',
                      style: const TextStyle(fontSize: 11),
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: _download,
                    icon: const Icon(Icons.download, size: 14),
                    label: const Text('下载', style: TextStyle(fontSize: 11)),
                  ),
                const Spacer(),
                if (installed)
                  TextButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('删除', style: TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 弹出 AI 字幕设置面板
///
/// 面板内部自带滚动（见 [_AiSubtitleSettingsPanelState.build]），这里只需给
/// 高度上限。之前套 `DraggableScrollableSheet` 时，滚动手势会和拖拽抢事件，
/// 容易出现「滚不动、底部内容看不到」。
Future<void> showAiSubtitleSettings(BuildContext context) async {
  final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints(maxHeight: maxHeight),
    builder: (ctx) => const AiSubtitleSettingsPanel(),
  );
}
