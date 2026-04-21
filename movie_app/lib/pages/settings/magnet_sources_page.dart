import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/magnet_source_config.dart';
import '../../providers/settings_provider.dart';
import '../../services/torrent_search_service.dart';

String _driverTitle(MagnetSourceDriver d) {
  switch (d) {
    case MagnetSourceDriver.ytsMxApi:
      return 'YTS API（list_movies.json）';
    case MagnetSourceDriver.torrentioJson:
      return 'Torrentio JSON（streams）';
    case MagnetSourceDriver.html1337x:
      return '1337x 类 HTML';
    case MagnetSourceDriver.htmlBt4g:
      return 'BT4G 类 HTML';
    case MagnetSourceDriver.rssNyaa:
      return 'Nyaa RSS';
    case MagnetSourceDriver.apibay:
      return 'Apibay（PirateBay）';
    case MagnetSourceDriver.solidHtml:
      return 'SolidTorrents 类 HTML';
    case MagnetSourceDriver.jackettApi:
      return 'Jackett Results JSON';
  }
}

/// 磁力搜索源：启用/禁用、探测、自定义、恢复默认
class MagnetSourcesPage extends StatelessWidget {
  const MagnetSourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('磁力搜索源'),
        actions: [
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('恢复默认'),
                      content: const Text('将重置为内置源列表与开关状态，自定义源会被清除。确定吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('恢复'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
              if (!ok || !context.mounted) return;
              await context
                  .read<SettingsProvider>()
                  .resetMagnetSourcesToDefaults();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已恢复为内置默认')),
                );
              }
            },
            child: const Text('恢复默认'),
          ),
        ],
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          final list = settings.magnetSources;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
            children: [
              Text(
                '聚合搜索仅在详情页「磁力」等场景发起。请使用 {query} 占位关键词；部分驱动支持 {page}（如 Apibay）。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor, height: 1.35),
              ),
              const SizedBox(height: 12),
              ...list.asMap().entries.map((e) {
                final c = e.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          title: Text(c.displayName),
                          subtitle: Text(
                            c.urlTemplate,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          value: c.enabled,
                          onChanged: (v) => context
                              .read<SettingsProvider>()
                              .setMagnetSourceEnabled(c.id, v),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 6),
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              TextButton.icon(
                                onPressed: () async {
                                  final svc = TorrentSearchService();
                                  final probe = await svc.probeSource(c);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        probe.$1
                                            ? '可用：${probe.$2}'
                                            : '不可用：${probe.$2}',
                                      ),
                                    ),
                                  );
                                },
                                icon:
                                    const Icon(Icons.wifi_tethering, size: 18),
                                label: const Text('探测'),
                              ),
                              if (!c.isBuiltin)
                                TextButton.icon(
                                  onPressed: () async {
                                    final del = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('删除源'),
                                            content:
                                                Text('确定删除「${c.displayName}」？'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('取消'),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                child: const Text('删除'),
                                              ),
                                            ],
                                          ),
                                        ) ??
                                        false;
                                    if (!del || !context.mounted) return;
                                    await context
                                        .read<SettingsProvider>()
                                        .removeMagnetSource(c.id);
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  label: const Text('删除'),
                                ),
                              Chip(
                                label: Text(
                                  c.isBuiltin ? '内置' : '自定义',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              Chip(
                                label: Text(
                                  _driverTitle(c.driver),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('自定义源'),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final nameCtl = TextEditingController();
    final urlCtl = TextEditingController(
      text:
          'http://127.0.0.1:9117/api/v2.0/indexers/all/results?apikey=YOUR_KEY&Query={query}',
    );
    MagnetSourceDriver driver = MagnetSourceDriver.jackettApi;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('添加磁力搜索源'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameCtl,
                      decoration: const InputDecoration(
                        labelText: '显示名称',
                        hintText: '例如：我的 Jackett',
                      ),
                    ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: '解析方式',
                        border: OutlineInputBorder(),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<MagnetSourceDriver>(
                          isExpanded: true,
                          value: driver,
                          items: MagnetSourceDriver.values
                              .map(
                                (d) => DropdownMenuItem(
                                  value: d,
                                  child: Text(
                                    _driverTitle(d),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => driver = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlCtl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'URL 模板',
                        alignLabelWithHint: true,
                        hintText: '必须包含 {query}；需要分页可加 {page}',
                      ),
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
                    final name = nameCtl.text.trim();
                    final url = urlCtl.text.trim();
                    if (name.isEmpty || !url.contains('{query}')) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('请填写名称，且 URL 须包含 {query}'),
                        ),
                      );
                      return;
                    }
                    final id =
                        'custom_${DateTime.now().millisecondsSinceEpoch}';
                    final cfg = MagnetSourceConfig(
                      id: id,
                      displayName: name,
                      driver: driver,
                      urlTemplate: url,
                      enabled: true,
                      isBuiltin: false,
                    );
                    await ctx
                        .read<SettingsProvider>()
                        .addCustomMagnetSource(cfg);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    nameCtl.dispose();
    urlCtl.dispose();
  }
}
