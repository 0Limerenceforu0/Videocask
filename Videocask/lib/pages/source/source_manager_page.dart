import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/play_source.dart';
import '../../providers/source_provider.dart';
import '../../widgets/empty_widget.dart';

/// 播放源管理页面
class SourceManagerPage extends StatefulWidget {
  const SourceManagerPage({super.key});

  @override
  State<SourceManagerPage> createState() => _SourceManagerPageState();
}

class _SourceManagerPageState extends State<SourceManagerPage> {
  /// 是否显示添加对话框
  // ignore: unused_field
  bool _showAddDialog = false;

  /// 编辑中的源
  PlaySource? _editingSource;

  /// 名称输入控制器
  final _nameController = TextEditingController();

  /// 地址输入控制器
  final _urlController = TextEditingController();

  /// 类型选择
  String _selectedType = 'cms';

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  /// 显示添加/编辑对话框（B站风格底部Sheet）
  void _showSourceDialog({PlaySource? source}) {
    _editingSource = source;
    _nameController.text = source?.name ?? '';
    _urlController.text = source?.url ?? '';
    _selectedType = source?.type ?? 'cms';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setDialogState) {
          return Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
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
                        Icons.source_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _editingSource != null ? '编辑播放源' : '添加播放源',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: '源名称',
                    hintText: '例如：默认源',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: '源地址',
                    hintText: 'https://api.example.com/',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedType,
                  decoration: InputDecoration(
                    labelText: '源类型',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cms', child: Text('苹果CMS')),
                    DropdownMenuItem(value: 'json', child: Text('JSON')),
                    DropdownMenuItem(value: 'xml', child: Text('XML')),
                    DropdownMenuItem(value: 'html', child: Text('HTML')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        _selectedType = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _saveSource();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('确认'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 保存源
  void _saveSource() async {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();

    if (name.isEmpty || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写完整信息')),
      );
      return;
    }

    final sourceProvider = context.read<SourceProvider>();

    if (_editingSource != null) {
      // 编辑
      await sourceProvider.updateSource(
        _editingSource!.copyWith(
          name: name,
          url: url,
          type: _selectedType,
        ),
      );
    } else {
      // 添加
      await sourceProvider.addSource(
        name: name,
        url: url,
        type: _selectedType,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_editingSource != null ? '编辑成功' : '添加成功')),
      );
      // 保存成功后清除编辑状态
      _editingSource = null;
    }
  }

  /// 删除源
  void _deleteSource(PlaySource source) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除源"${source.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              context.read<SourceProvider>().deleteSource(source.id);
              Navigator.of(context).pop();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// 导入源
  void _importSources() async {
    // 简单的文本输入导入
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入播放源'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: '粘贴源配置JSON或文本',
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
      final count = await context.read<SourceProvider>().importSources(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功导入$count个源')),
        );
      }
    }
  }

  /// 导出源
  void _exportSources() async {
    context.read<SourceProvider>().exportSources();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('源配置已复制到剪贴板')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sourceProvider = context.watch<SourceProvider>();

    final bgColor = isDark ? const Color(0xFF17181A) : const Color(0xFFF4F4F4);
    final cardColor = isDark ? const Color(0xFF222325) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('播放源管理'),
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          // 检测所有源
          if (sourceProvider.sources.isNotEmpty)
            IconButton(
              icon: sourceProvider.isChecking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_find),
              onPressed: sourceProvider.isChecking
                  ? null
                  : () => sourceProvider.checkAllSources(),
              tooltip: '检测所有源',
            ),

          // 导入
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _importSources,
            tooltip: '导入',
          ),

          // 导出
          IconButton(
            icon: const Icon(Icons.file_upload),
            onPressed: _exportSources,
            tooltip: '导出',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSourceDialog(),
        backgroundColor: theme.colorScheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add),
      ),
      body: sourceProvider.sources.isEmpty
          ? EmptyWidget(
              message: '还没有添加播放源',
              icon: Icons.source,
              actionText: '添加源',
              onAction: () => _showSourceDialog(),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(
                bottom: 80,
                left: 12,
                right: 12,
                top: 8,
              ),
              itemCount: sourceProvider.sources.length,
              onReorder: (oldIndex, newIndex) {
                sourceProvider.reorderSources(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final source = sourceProvider.sources[index];
                return _buildBiliSourceCard(
                  context,
                  theme,
                  source,
                  sourceProvider,
                  cardColor: cardColor,
                );
              },
            ),
    );
  }

  /// 构建B站风格源卡片
  Widget _buildBiliSourceCard(
    BuildContext context,
    ThemeData theme,
    PlaySource source,
    SourceProvider provider, {
    required Color cardColor,
  }) {
    final isCurrent = provider.currentSource?.id == source.id;
    final isDark = theme.brightness == Brightness.dark;
    final textColor =
        isDark ? const Color(0xFFE6E6E6) : const Color(0xFF212121);
    final subTextColor =
        isDark ? const Color(0xFF999999) : const Color(0xFF999999);

    // 状态指示灯颜色
    final statusColor = source.enabled
        ? (source.isValid ? const Color(0xFF66BB6A) : const Color(0xFFFFA726))
        : const Color(0xFFBDBDBD);

    return Container(
      key: ValueKey(source.id),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: isCurrent
            ? Border.all(color: theme.colorScheme.primary, width: 1.5)
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 状态指示灯
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // 名称
                Expanded(
                  child: Text(
                    source.name,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isCurrent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '使用中',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                // 开关
                Switch(
                  value: source.enabled,
                  onChanged: (_) => provider.toggleSource(source.id),
                  activeThumbColor: theme.colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // URL
            Text(
              source.url,
              style: TextStyle(
                color: subTextColor,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isCurrent)
                  TextButton.icon(
                    onPressed: () => provider.selectSource(source.id),
                    icon: Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    label: Text(
                      '使用',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 13,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: Size.zero,
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => _showSourceDialog(source: source),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('编辑', style: TextStyle(fontSize: 13)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: Size.zero,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _deleteSource(source),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: Colors.red[400],
                  ),
                  label: Text(
                    '删除',
                    style: TextStyle(color: Colors.red[400], fontSize: 13),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 显示添加/编辑对话框
  // ignore: unused_element
  Widget _buildAddDialog() {
    // ignore: unused_local_variable
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(_editingSource != null ? '编辑播放源' : '添加播放源'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '源名称',
              hintText: '例如：默认源',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: '源地址',
              hintText: 'https://api.example.com/',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedType,
            decoration: const InputDecoration(
              labelText: '源类型',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'cms', child: Text('苹果CMS')),
              DropdownMenuItem(value: 'json', child: Text('JSON')),
              DropdownMenuItem(value: 'xml', child: Text('XML')),
              DropdownMenuItem(value: 'html', child: Text('HTML')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedType = value;
                });
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _showAddDialog = false;
            });
          },
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _saveSource,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
