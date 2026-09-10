// ignore_for_file: prefer_const_constructors

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/storage_service.dart';
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

  List<SubtitleAiBackendKind> _availableBackends() {
    if (kIsWeb) {
      return [SubtitleAiBackendKind.onlineApi, SubtitleAiBackendKind.transformersWeb];
    }
    return [SubtitleAiBackendKind.onlineApi, SubtitleAiBackendKind.sherpaNative];
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
    return SafeArea(
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
                Text(
                  'AI 字幕生成',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '本地离线方案基于 sherpa_onnx（Apache 2.0，零付费）；Web 浏览器端走 transformers.js。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
                fontSize: 11,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            // 后端切换
            _buildBackendSelector(theme),
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
    );
  }

  Widget _buildBackendSelector(ThemeData theme) {
    final options = _availableBackends();
    return SegmentedButton<SubtitleAiBackendKind>(
      segments: options
          .map(
            (b) => ButtonSegment<SubtitleAiBackendKind>(
              value: b,
              label: Text(
                b == SubtitleAiBackendKind.onlineApi ? '在线 API' : '本地离线',
                style: const TextStyle(fontSize: 12),
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
          Text(
            '${s.subtitleAiModel.isEmpty ? 'base' : s.subtitleAiModel} · ${s.subtitleAiLanguage.isEmpty ? 'zh' : s.subtitleAiLanguage}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
              fontSize: 11,
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
          _field(_urlCtrl, 'API URL', 'https://api.openai.com/v1/audio/transcriptions'),
          _field(_keyCtrl, 'API Key（可选）', 'sk-...'),
          Row(
            children: [
              Expanded(child: _field(_modelCtrl, '模型', 'whisper-1 / base / large-v3')),
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
            contentPadding: EdgeInsets.zero,
            title: const Text('JSON URL 模式', style: TextStyle(fontSize: 12)),
            subtitle: const Text(
              'faster-whisper-server 直接传 URL 不下载文件',
              style: TextStyle(fontSize: 10, color: Colors.black54),
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
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            '离线模型（首次使用需下载到本机，下载一次即可重复使用）',
            style: TextStyle(fontSize: 11, color: Colors.black54),
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
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
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
              color: Colors.black54,
            ),
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
            Text(
              _progressMsg,
              style: const TextStyle(fontSize: 10, color: Colors.black54),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
Future<void> showAiSubtitleSettings(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) => SingleChildScrollView(
        controller: scroll,
        child: const AiSubtitleSettingsPanel(),
      ),
    ),
  );
}