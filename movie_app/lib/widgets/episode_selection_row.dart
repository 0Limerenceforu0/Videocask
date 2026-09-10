import 'package:flutter/material.dart';

import '../utils/episode_display_label.dart';

/// 选集列表行：一行一集，适合综艺等长标题。
class EpisodeSelectionRow extends StatelessWidget {
  const EpisodeSelectionRow({
    super.key,
    required this.display,
    required this.selected,
    required this.onTap,
    required this.backgroundColor,
    required this.selectedBackgroundColor,
    required this.textColor,
    required this.subTextColor,
    this.trailing,
    this.leading,
    this.dense = false,
    this.showFullSubtitle = false,
  });

  final EpisodeDisplayLabel display;
  final bool selected;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Color selectedBackgroundColor;
  final Color textColor;
  final Color subTextColor;
  final Widget? trailing;
  final Widget? leading;
  final bool dense;
  final bool showFullSubtitle;

  bool get _showSubtitle =>
      display.full != display.primary || display.secondary != null;

  String get _subtitleText =>
      showFullSubtitle ? display.full : (display.secondary ?? display.full);

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitleText;
    final verticalPadding = dense ? 8.0 : 10.0;

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: display.full,
      child: Material(
        color: selected ? selectedBackgroundColor : backgroundColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: verticalPadding,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        display.primary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: dense ? 13 : 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_showSubtitle) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: subTextColor,
                            fontSize: dense ? 11 : 12,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
