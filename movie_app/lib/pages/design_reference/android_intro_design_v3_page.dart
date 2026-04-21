import 'package:flutter/material.dart';
import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/pages/detail/detail_ui_tokens.dart';

/// 设计稿 `assets/design-v3-android-intro-collapsed-icons-only.png` 的可交互静态复刻页。
///
/// 路由：[AppRoutes.designAndroidIntroV3]，入口示例：`context.push(AppRoutes.designAndroidIntroV3)`。
class AndroidIntroDesignV3Page extends StatefulWidget {
  const AndroidIntroDesignV3Page({super.key});

  @override
  State<AndroidIntroDesignV3Page> createState() =>
      _AndroidIntroDesignV3PageState();
}

const Color _kDesignV3SubText = Color(0xFF8E8E93);
const Color _kDesignV3Card = Color(0xFF1C1C1E);

class _AndroidIntroDesignV3PageState extends State<AndroidIntroDesignV3Page> {
  static const Color _bg = Color(0xFF000000);

  bool _introExpanded = false;

  /// 为 true 时表示正在播放，控制条显示「暂停」图标。
  bool _isPlaying = true;
  int _upperTab = 0;
  int _lowerTab = 0;
  double _progress = 0.21;
  int _speedIndex = 1;

  static const List<double> _speedPresets = <double>[
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final topPad = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: topPad),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final playerH = w * 9 / 16;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: playerH,
                      width: w,
                      child: _DesignPlayer(
                        l10n: l10n,
                        isPlaying: _isPlaying,
                        progress: _progress,
                        speedLabel:
                            '${_speedPresets[_speedIndex].toStringAsFixed(1)}x',
                        onPlayPause: () =>
                            setState(() => _isPlaying = !_isPlaying),
                        onProgress: (v) => setState(() => _progress = v),
                        onSpeedTap: () {
                          setState(() {
                            _speedIndex =
                                (_speedIndex + 1) % _speedPresets.length;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TitleBlock(l10n: l10n),
                            const SizedBox(height: 12),
                            _IntroCollapsible(
                              l10n: l10n,
                              expanded: _introExpanded,
                              onToggle: () => setState(
                                () => _introExpanded = !_introExpanded,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _IconActionRow(l10n: l10n),
                            const SizedBox(height: 20),
                            _UnderlineTabs(
                              labels: [
                                l10n.detailDesktopEpisodes,
                                l10n.detailPlayRoutes,
                              ],
                              selectedIndex: _upperTab,
                              onSelect: (i) => setState(() => _upperTab = i),
                            ),
                            const SizedBox(height: 12),
                            if (_upperTab == 0)
                              _EpisodeChips(l10n: l10n)
                            else
                              _RouteLines(l10n: l10n),
                            const SizedBox(height: 20),
                            _UnderlineTabs(
                              labels: [
                                l10n.detailDesktopTabRecommend,
                                l10n.detailDesktopTabMagnet,
                              ],
                              selectedIndex: _lowerTab,
                              onSelect: (i) => setState(() => _lowerTab = i),
                            ),
                            const SizedBox(height: 12),
                            if (_lowerTab == 0)
                              _RelatedStrip(l10n: l10n)
                            else
                              _MagnetList(l10n: l10n),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const _HomeIndicatorBar(),
        ],
      ),
    );
  }
}

class _DesignPlayer extends StatelessWidget {
  const _DesignPlayer({
    required this.l10n,
    required this.isPlaying,
    required this.progress,
    required this.speedLabel,
    required this.onPlayPause,
    required this.onProgress,
    required this.onSpeedTap,
  });

  final AppLocalizations l10n;
  final bool isPlaying;
  final double progress;
  final String speedLabel;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onProgress;
  final VoidCallback onSpeedTap;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0A1628),
                  Color(0xFF050810),
                  Color(0xFF0D1B2A),
                ],
              ),
            ),
          ),
          Center(
            child: Icon(
              Icons.movie_creation_outlined,
              size: 56,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.designV3TimeDemo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 6),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: SliderComponentShape.noOverlay,
                        activeTrackColor: kDetailAccentColor,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: kDetailAccentColor,
                      ),
                      child: Slider(
                        value: progress.clamp(0.001, 0.999),
                        onChanged: onProgress,
                      ),
                    ),
                    Row(
                      children: [
                        Tooltip(
                          message: l10n.designV3TooltipPlayPause,
                          child: IconButton(
                            onPressed: onPlayPause,
                            icon: Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l10n.designV3BufferDemo,
                          style: const TextStyle(
                            color: kDetailAccentColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: l10n.designV3TooltipSpeed,
                          child: Material(
                            color: Colors.white.withValues(alpha: 0.12),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: onSpeedTap,
                              child: SizedBox(
                                width: 34,
                                height: 34,
                                child: Center(
                                  child: Text(
                                    speedLabel,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Tooltip(
                          message: l10n.designV3TooltipVolume,
                          child: IconButton(
                            onPressed: () {},
                            icon: const Icon(
                              Icons.volume_up_outlined,
                              color: Colors.white,
                              size: 22,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                          ),
                        ),
                        Tooltip(
                          message: l10n.designV3TooltipCast,
                          child: IconButton(
                            onPressed: () {},
                            icon: const Icon(
                              Icons.cast_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                          ),
                        ),
                        Tooltip(
                          message: l10n.designV3TooltipFullscreen,
                          child: IconButton(
                            onPressed: () {},
                            icon: const Icon(
                              Icons.fullscreen_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.designV3MovieTitle,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '${l10n.designV3DoubanLabel} 9.3',
              style: const TextStyle(
                color: kDetailAccentColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '|',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
            ),
            const SizedBox(width: 8),
            ...List.generate(
              4,
              (_) => const Icon(
                Icons.star_rounded,
                color: Color(0xFFFFB800),
                size: 18,
              ),
            ),
            const Icon(
              Icons.star_half_rounded,
              color: Color(0xFFFFB800),
              size: 18,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l10n.designV3MetaLine,
          style: const TextStyle(color: _kDesignV3SubText, fontSize: 13),
        ),
      ],
    );
  }
}

class _IntroCollapsible extends StatelessWidget {
  const _IntroCollapsible({
    required this.l10n,
    required this.expanded,
    required this.onToggle,
  });

  final AppLocalizations l10n;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final text =
        expanded ? l10n.designV3SynopsisFull : l10n.designV3SynopsisCollapsed;
    return Semantics(
      button: true,
      label: expanded ? l10n.designV3CollapseIntro : l10n.designV3ExpandIntro,
      child: InkWell(
        key: const Key('design_v3_intro_toggle'),
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.detailIntro,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      text,
                      maxLines: expanded ? null : 2,
                      overflow: expanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _kDesignV3SubText,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: kDetailAccentColor,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconActionRow extends StatelessWidget {
  const _IconActionRow({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    Widget circle(IconData icon, String tooltip) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {},
            customBorder: const CircleBorder(),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: kDetailAccentColor, width: 1.5),
              ),
              child: Icon(icon, color: kDetailAccentColor, size: 22),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        circle(Icons.download_outlined, l10n.designV3TooltipDownload),
        const SizedBox(width: 16),
        circle(Icons.star_border_rounded, l10n.designV3TooltipFavorite),
        const SizedBox(width: 16),
        circle(Icons.share_rounded, l10n.designV3TooltipShare),
      ],
    );
  }
}

class _UnderlineTabs extends StatelessWidget {
  const _UnderlineTabs({
    required this.labels,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(labels.length, (i) {
        final selected = i == selectedIndex;
        return Expanded(
          child: InkWell(
            onTap: () => onSelect(i),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: selected ? Colors.white : _subTextConst,
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: selected ? kDetailAccentColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

const Color _subTextConst = Color(0xFF8E8E93);

class _EpisodeChips extends StatelessWidget {
  const _EpisodeChips({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SoftChip(text: l10n.designV3EpisodeChip1, selected: true),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SoftChip(text: l10n.designV3EpisodeChip2, selected: false),
        ),
      ],
    );
  }
}

class _SoftChip extends StatelessWidget {
  const _SoftChip({required this.text, required this.selected});

  final String text;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? kDetailAccentColor.withValues(alpha: 0.22)
          : _kDesignV3Card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteLines extends StatelessWidget {
  const _RouteLines({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SoftChip(text: l10n.designV3RouteLine1, selected: true),
        const SizedBox(height: 8),
        _SoftChip(text: l10n.designV3RouteLine2, selected: false),
      ],
    );
  }
}

class _RelatedStrip extends StatelessWidget {
  const _RelatedStrip({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final items = <({String title, double rating})>[
      (title: l10n.designV3RelatedMartian, rating: 8.5),
      (title: l10n.designV3RelatedArrival, rating: 7.9),
      (title: l10n.designV3RelatedInception, rating: 9.3),
      (title: l10n.designV3RelatedGravity, rating: 7.7),
    ];

    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final it = items[i];
          return SizedBox(
            width: 108,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _cardGradientTop(i),
                          _cardGradientBottom(i),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.movie_filter_rounded,
                        color: Colors.white.withValues(alpha: 0.2),
                        size: 40,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  it.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFFFB800),
                      size: 14,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      it.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: _subTextConst,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        fontFeatures: [FontFeature.tabularFigures()],
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

  Color _cardGradientTop(int i) {
    const colors = <Color>[
      Color(0xFF2D3E50),
      Color(0xFF3D2C4A),
      Color(0xFF1E3A2F),
      Color(0xFF2A2D45),
    ];
    return colors[i % colors.length];
  }

  Color _cardGradientBottom(int i) {
    const colors = <Color>[
      Color(0xFF151920),
      Color(0xFF1A1520),
      Color(0xFF121A16),
      Color(0xFF151820),
    ];
    return colors[i % colors.length];
  }
}

class _MagnetList extends StatelessWidget {
  const _MagnetList({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: _kDesignV3Card,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.designV3MagnetRowTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.designV3MagnetRowMeta,
                          style: const TextStyle(
                            color: _subTextConst,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.link_rounded,
                    color: kDetailAccentColor,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeIndicatorBar extends StatelessWidget {
  const _HomeIndicatorBar();

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: bottom > 0 ? bottom : 10),
      child: Center(
        child: Container(
          width: 128,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
