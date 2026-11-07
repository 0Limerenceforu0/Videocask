import 'package:flutter/material.dart';

import '../config/category_filter_catalog.dart';
import '../l10n/app_localizations.dart';

/// 分类列表用的「类型 + 地区」横向 Chip 筛选（与 `MovieProvider.loadCategoryMovies` 参数一致）。
class CategoryGenreRegionFilterBand extends StatelessWidget {
  const CategoryGenreRegionFilterBand({
    super.key,
    required this.category,
    required this.selectedGenre,
    required this.selectedRegion,
    required this.onGenreSelected,
    required this.onRegionSelected,
    this.genreOptions,
    this.regionOptions,
    this.header,
    this.subClassItems,
    this.selectedSubClass,
    this.onSubClassSelected,
  });

  /// CMS 大类名（如「电影」「剧集」），决定类型/地区候选项。
  final String category;

  final String selectedGenre;
  final String selectedRegion;
  final ValueChanged<String> onGenreSelected;
  final ValueChanged<String> onRegionSelected;

  /// 类型候选词；为空则用 [CategoryFilterCatalog] 的静态词表。
  ///
  /// 传入动态词表（从源站真实 `vod_class` 聚合）可让每个选项都有结果 ——
  /// 静态词表里的「热血/校园」等词在多数采集站并不存在，必然 0 命中。
  final List<String>? genreOptions;

  /// 地区候选词；为空则用静态词表。规则同 [genreOptions]。
  final List<String>? regionOptions;

  /// 可选：例如首页「宽屏频道页」入口。
  final Widget? header;

  /// 「小分类」chip 行（源站子类名，如「动作片」「喜剧片」）。
  ///
  /// 2026-10-21 起 Tab 首屏只拉前 N 个子类（见 `ApiService.defaultSubClassCount`），
  /// 这一行就是「按需传参」的入口：点某个子类只请求该子类，不再一次展开全部。
  /// 为空（树未缓存）时整行隐藏。
  final List<String>? subClassItems;

  /// 当前选中的小分类：`_kSubClassFeatured`（精选）、`_kSubClassAll`（全部）
  /// 或某个子类名。
  final String? selectedSubClass;

  /// 点小分类 chip 回调，参数为 [selectedSubClass] 的三种取值之一。
  final ValueChanged<String>? onSubClassSelected;

  /// 「精选」chip 的值：首屏默认只拉前 N 个子类。
  static const String kSubClassFeatured = '__featured__';

  /// 「全部」chip 的值：显式展开全部子类（请求量大）。
  static const String kSubClassAll = '__all__';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final genres = genreOptions ?? CategoryFilterCatalog.genresFor(category);
    final regions = regionOptions ?? CategoryFilterCatalog.regionsFor(category);
    final subItems = subClassItems;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null) header!,
          if (subItems != null && subItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FilterChipLabeledRow(
                label: l10n.filterLabelSubClass,
                items: <String>[
                  kSubClassFeatured,
                  ...subItems,
                  kSubClassAll,
                ],
                selected: selectedSubClass ?? kSubClassFeatured,
                onSelected: onSubClassSelected ?? (_) {},
                labelOverrides: const {
                  kSubClassFeatured: '精选',
                  kSubClassAll: '全部',
                },
              ),
            ),
          _FilterChipLabeledRow(
            label: l10n.filterLabelGenre,
            items: genres,
            selected: selectedGenre,
            onSelected: onGenreSelected,
          ),
          const SizedBox(height: 8),
          _FilterChipLabeledRow(
            label: l10n.filterLabelRegion,
            items: regions,
            selected: selectedRegion,
            onSelected: onRegionSelected,
          ),
        ],
      ),
    );
  }
}

class _FilterChipLabeledRow extends StatelessWidget {
  const _FilterChipLabeledRow({
    required this.label,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.labelOverrides = const {},
  });

  final String label;
  final List<String> items;
  final String selected;
  final ValueChanged<String> onSelected;

  /// chip 内部值 → 显示文案（用于「精选 / 全部」这类哨兵值）。
  final Map<String, String> labelOverrides;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, right: 6),
          child: Text(
            '$label:',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.hintColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onSelected(item),
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: item == selected
                                ? theme.colorScheme.primary
                                    .withValues(alpha: 0.12)
                                : theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: item == selected
                                  ? theme.colorScheme.primary
                                  : theme.dividerColor.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            labelOverrides[item] ?? item,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: item == selected
                                  ? theme.colorScheme.primary
                                  : theme.textTheme.bodyMedium?.color,
                              fontWeight: item == selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
