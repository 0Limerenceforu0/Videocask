// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';

/// 字幕轨选择器（仅做列出/切换，不做 AI 生成）。
///
/// 用法：[showSubtitleSelector] 弹出底部弹窗，[onSelected] 返回选择的轨索引，
/// -1 表示关闭。
class SubtitleSelector extends StatelessWidget {
  final int currentIndex;
  final List<String> subtitleTracks;
  final ValueChanged<int> onSelected;

  const SubtitleSelector({
    super.key,
    required this.currentIndex,
    required this.subtitleTracks,
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '字幕选择',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(height: 1),
          _buildOption(
            context,
            title: '关闭字幕',
            isSelected: currentIndex == -1,
            onTap: () => onSelected(-1),
          ),
          ...List.generate(subtitleTracks.length, (index) {
            final track = subtitleTracks[index];
            final name = track.split('/').last;
            return _buildOption(
              context,
              title: name,
              subtitle: track,
              isSelected: currentIndex == index,
              onTap: () => onSelected(index),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required String title,
    String? subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
}

/// 弹出字幕选择底部弹窗。
Future<void> showSubtitleSelector({
  required BuildContext context,
  required int currentIndex,
  required List<String> subtitleTracks,
  required ValueChanged<int> onSelected,
}) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => SubtitleSelector(
      currentIndex: currentIndex,
      subtitleTracks: subtitleTracks,
      onSelected: (index) {
        onSelected(index);
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      },
    ),
  );
}
