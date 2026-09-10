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
    this.header,
  });

  /// CMS 大类名（如「电影」「剧集」），决定类型/地区候选项。
  final String category;

  final String selectedGenre;
  final String selectedRegion;
  final ValueChanged<String> onGenreSelected;
  final ValueChanged<String> onRegionSelected;

  /// 可选：例如首页「宽屏频道页」入口。
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final genres = CategoryFilterCatalog.genresFor(category);
    final regions = CategoryFilterCatalog.regionsFor(category);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null) header!,
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
  });

  final String label;
  final List<String> items;
  final String selected;
  final ValueChanged<String> onSelected;

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
                            item,
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
