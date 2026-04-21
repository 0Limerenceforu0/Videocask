import 'package:flutter/material.dart';
import '../../config/constants.dart';

/// 倍速选择器组件
class SpeedSelector extends StatelessWidget {
  /// 当前播放速度
  final double currentSpeed;

  /// 选择回调
  final ValueChanged<double> onSelected;

  const SpeedSelector({
    super.key,
    required this.currentSpeed,
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
              '播放速度',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(height: 1),

          // 速度选项
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppConstants.speedOptions.map((speed) {
                final isSelected = speed == currentSpeed;
                return _buildSpeedChip(
                  context,
                  speed: speed,
                  isSelected: isSelected,
                  onTap: () => onSelected(speed),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildSpeedChip(
    BuildContext context, {
    required double speed,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final label = speed == 1.0 ? '正常' : '${speed}x';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? theme.colorScheme.onPrimary
                : theme.textTheme.bodyMedium?.color,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

/// 显示倍速选择器底部弹窗
Future<void> showSpeedSelector({
  required BuildContext context,
  required double currentSpeed,
  required ValueChanged<double> onSelected,
}) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => SpeedSelector(
      currentSpeed: currentSpeed,
      onSelected: (speed) {
        onSelected(speed);
        Navigator.of(context).pop();
      },
    ),
  );
}
