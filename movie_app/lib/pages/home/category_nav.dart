import 'package:flutter/material.dart';
import '../../config/constants.dart';
import '../../providers/movie_provider.dart';
import '../../providers/source_provider.dart';
import 'package:provider/provider.dart';

/// 分类导航组件
class CategoryNav extends StatelessWidget {
  /// 当前选中的分类
  final String selectedCategory;

  /// 分类选择回调
  final ValueChanged<String>? onCategorySelected;

  const CategoryNav({
    super.key,
    this.selectedCategory = '',
    this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: AppConstants.categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = AppConstants.categories[index];
          final isSelected = category == selectedCategory;

          return GestureDetector(
            onTap: () {
              if (onCategorySelected != null) {
                onCategorySelected!(category);
              } else {
                // 默认行为：加载分类影片
                context.read<MovieProvider>().loadCategoryMovies(
                      category: category,
                      refresh: true,
                      mergeSources:
                          context.read<SourceProvider>().enabledSources,
                    );
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                border: isSelected
                    ? null
                    : Border.all(
                        color: theme.dividerColor,
                        width: 1,
                      ),
              ),
              child: Center(
                child: Text(
                  category,
                  style: TextStyle(
                    color: isSelected
                        ? theme.colorScheme.onPrimary
                        : theme.textTheme.bodyMedium?.color,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 筛选栏组件
class FilterBar extends StatelessWidget {
  final String selectedRegion;
  final String selectedYear;
  final String selectedSort;
  final ValueChanged<String>? onRegionChanged;
  final ValueChanged<String>? onYearChanged;
  final ValueChanged<String>? onSortChanged;

  const FilterBar({
    super.key,
    this.selectedRegion = '全部',
    this.selectedYear = '全部',
    this.selectedSort = '综合排序',
    this.onRegionChanged,
    this.onYearChanged,
    this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildFilterChip(
            context,
            label: selectedRegion,
            items: AppConstants.regions,
            onSelected: onRegionChanged,
            theme: theme,
          ),
          const SizedBox(width: 12),
          _buildFilterChip(
            context,
            label: selectedYear,
            items: AppConstants.years,
            onSelected: onYearChanged,
            theme: theme,
          ),
          const SizedBox(width: 12),
          _buildFilterChip(
            context,
            label: selectedSort,
            items: AppConstants.sortOptions,
            onSelected: onSortChanged,
            theme: theme,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    BuildContext context, {
    required String label,
    required List<String> items,
    required ValueChanged<String>? onSelected,
    required ThemeData theme,
  }) {
    return GestureDetector(
      onTap: () {
        _showFilterMenu(context, items, onSelected);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.arrow_drop_down,
            size: 16,
            color: theme.colorScheme.primary,
          ),
        ],
      ),
    );
  }

  void _showFilterMenu(
    BuildContext context,
    List<String> items,
    ValueChanged<String>? onSelected,
  ) {
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
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '选择筛选条件',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      title: Text(item),
                      onTap: () {
                        onSelected?.call(item);
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
}
