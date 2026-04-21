import 'package:flutter/material.dart';
import '../../config/constants.dart';

/// 清晰度选择器组件
class QualitySelector extends StatelessWidget {
  /// 当前选中的清晰度
  final String currentQuality;

  /// 选择回调
  final ValueChanged<String> onSelected;

  const QualitySelector({
    super.key,
    required this.currentQuality,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '清晰度选择',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(height: 1),

          // 清晰度选项
          ...AppConstants.qualityOptions.map((quality) {
            return _buildOption(
              context,
              quality: quality,
              description: _getQualityDescription(quality),
              isSelected: quality == currentQuality,
              onTap: () => onSelected(quality),
            );
          }),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required String quality,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected ? theme.colorScheme.primary : theme.hintColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quality,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check,
                color: theme.colorScheme.primary,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }

  /// 获取清晰度描述
  String _getQualityDescription(String quality) {
    switch (quality) {
      case '自动':
        return '根据网络状况自动选择';
      case '标清':
        return '480P，节省流量';
      case '高清':
        return '720P，清晰流畅';
      case '1080P':
        return '1080P，高清体验';
      case '4K':
        return '2160P，极致画质';
      default:
        return '';
    }
  }
}

/// 显示清晰度选择器底部弹窗
Future<void> showQualitySelector({
  required BuildContext context,
  required String currentQuality,
  required ValueChanged<String> onSelected,
}) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => QualitySelector(
      currentQuality: currentQuality,
      onSelected: (quality) {
        onSelected(quality);
        Navigator.of(context).pop();
      },
    ),
  );
}
