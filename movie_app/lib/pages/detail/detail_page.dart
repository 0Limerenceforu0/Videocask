import 'dart:async' show Timer, unawaited;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter/services.dart'
    show
        DeviceOrientation,
        HardwareKeyboard,
        KeyDownEvent,
        LogicalKeyboardKey,
        SystemChrome,
        SystemUiMode;
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/subtitle_service.dart';
// 图片缓存
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/cache_speed_formatter.dart';
import '../../config/constants.dart';
import '../../config/routes.dart';
import '../../models/movie.dart';
import '../../providers/history_provider.dart';
import '../../providers/movie_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/source_provider.dart';
import '../../services/dlna_service.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/error_widget.dart' as app_widgets;

import 'detail_player.dart';
import 'detail_torrent.dart';
import 'detail_cache.dart';
import 'detail_components.dart';
import 'detail_movie_info_section.dart';
import 'detail_desktop_layout.dart';
import 'detail_ui_tokens.dart';
import 'playback_error_type.dart';

/// Windows 桌面详情宽屏分栏断点（逻辑宽度）
const double _kDetailDesktopBreakpointWidth = 900;

/// 右侧信息 / 选集栏宽度
const double _kDetailDesktopSidebarWidth = 340;

/// 影片详情页（B站风格深色主题）
///
/// 上半部分：视频播放器（16:9自适应）
/// 下半部分：可滚动的影片信息 + 选集 + 相关推荐
class DetailPage extends StatefulWidget {
  /// 影片ID
  final String movieId;

  /// 源ID
  final String sourceId;

  /// 可选的影片对象（如果传入则直接使用，不再请求API）
  final Movie? movie;

  /// 进入页面后自动播放的磁力（由 [AppRoutes.toMagnetTorrentDetail] 等入口使用）
  final String initialMagnetUri;

  const DetailPage({
    super.key,
    required this.movieId,
    this.sourceId = '',
    this.movie,
    this.initialMagnetUri = '',
  });

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  /// 键盘焦点节点（复用，避免每次 build 重新创建）
  final FocusNode _keyboardFocusNode = FocusNode();

  /// 详情页主滚动（宽屏左栏 / 与右栏并发滚动检测）
  final ScrollController _detailLeftScrollController = ScrollController();

  /// 详情页右栏滚动（宽屏）
  final ScrollController _detailRightScrollController = ScrollController();

  /// 详情页单栏下方信息区滚动
  final ScrollController _detailMobileScrollController = ScrollController();
  bool _showDetailScrollToTop = false;

  /// Windows 宽屏分栏：当前选中的播放线路
  int _desktopRouteIndex = 0;

  /// 已对当前播放 URL 尝试过字幕自动匹配（避免重复请求）。
  String? _subtitleAutoMatchedForUrl;

  /// 长时间缓冲后尝试切换线路
  Timer? _routeFallbackTimer;

  final DlnaService _dlnaService = DlnaService();

  /// 首帧及换片首帧内避免在 [build] 期间 `notifyListeners`：先显示骨架屏，再在 [addPostFrameCallback] 里 [primeDetailLoad]。
  bool _deferDetailPrime = true;

  // ========== 模块实例 ==========

  /// 播放器模块
  final DetailPlayer _playerModule = DetailPlayer();

  /// 磁力搜索模块
  final DetailTorrent _torrentModule = DetailTorrent();

  /// 缓存管理模块
  final DetailCache _cacheModule = DetailCache();

  @override
  void initState() {
    super.initState();
    _detailLeftScrollController.addListener(_onDetailScrollFab);
    _detailRightScrollController.addListener(_onDetailScrollFab);
    _detailMobileScrollController.addListener(_onDetailScrollFab);
    // 初始化模块
    _initModules();

    // primeDetailLoad 须在首帧之后调用，否则会触发「build 期间 notifyListeners」异常
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _keyboardFocusNode.requestFocus();
      context.read<MovieProvider>().primeDetailLoad(widget.movieId);
      setState(() => _deferDetailPrime = false);
      await _bootstrapDetailPage();
    });
  }

  @override
  void didUpdateWidget(covariant DetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final idChanged = oldWidget.movieId != widget.movieId;
    final sourceChanged = oldWidget.sourceId != widget.sourceId;
    if (!idChanged && !sourceChanged) return;

    _subtitleAutoMatchedForUrl = null;
    _desktopRouteIndex = 0;
    _deferDetailPrime = true;
    _torrentModule.resetForNewMovie();
    unawaited(_resetPlayerForDetailChange());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      context.read<MovieProvider>().primeDetailLoad(widget.movieId);
      setState(() => _deferDetailPrime = false);
      await _bootstrapDetailPage();
    });
  }

  /// 切源、写入路由传入的 [Movie]、拉取详情（供首次进入与 [didUpdateWidget] 复用）。
  Future<void> _bootstrapDetailPage() async {
    // 历史/收藏带有的 sourceId 与全局当前源不一致时，必须先切源再拉详情；
    // 各 CMS 的 vod_id 仅在本站唯一，换源用同一 id 会打开完全错误的片子。
    if (widget.sourceId.isNotEmpty) {
      final sourceProvider = context.read<SourceProvider>();
      final curId = sourceProvider.currentSource?.id ?? '';
      if (curId != widget.sourceId) {
        await sourceProvider.selectSource(widget.sourceId);
      }
      if (!mounted) return;
      final src = sourceProvider.currentSource;
      if (src != null) {
        context.read<MovieProvider>().setCurrentSource(src);
      }
    }

    if (widget.movie != null) {
      context.read<MovieProvider>().setCurrentMovie(widget.movie!);
    }
    if (!mounted) return;
    await _loadData();
    if (!mounted) return;
    _loadRecommendations();

    final loaded = context.read<MovieProvider>().currentMovie;
    if (loaded != null && loaded.id == widget.movieId) {
      if (mounted) {
        _syncWatchHistory(loaded);
        if (_playerModule.pendingResumePosition == null) {
          _applyPreferredRouteFromSettings(loaded);
        }
        setState(() {});
      }
      unawaited(_runMagnetSearchForMovie(loaded, strict: true));
    }
  }

  Future<void> _runMagnetSearchForMovie(
    Movie movie, {
    required bool strict,
  }) async {
    await _torrentModule.searchForMovieDetail(movie, strict: strict);
    if (mounted) setState(() {});
  }

  Future<void> _resetPlayerForDetailChange() async {
    if (_playerModule.isFullScreen) {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await _restoreSystemUiAfterFullScreen();
      }
      _playerModule.isFullScreen = false;
    }
    _stopProgressPersistTimer();
    _routeFallbackTimer?.cancel();
    await _playerModule.resetPlaybackForNewDetail();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stopProgressPersistTimer();
    _routeFallbackTimer?.cancel();

    // 释放模块资源
    _playerModule.dispose();
    _torrentModule.dispose();
    _cacheModule.dispose();

    // 退出全屏（还原系统栏与方向；应用内全屏不再使用 OS 窗口全屏）
    if (_playerModule.isFullScreen) {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        unawaited(_restoreSystemUiAfterFullScreen());
      }
      _playerModule.isFullScreen = false;
    }

    // 释放滚动控制器和焦点节点
    _detailLeftScrollController.removeListener(_onDetailScrollFab);
    _detailRightScrollController.removeListener(_onDetailScrollFab);
    _detailMobileScrollController.removeListener(_onDetailScrollFab);
    _detailLeftScrollController.dispose();
    _detailRightScrollController.dispose();
    _detailMobileScrollController.dispose();
    _keyboardFocusNode.dispose();
    _routeFallbackTimer?.cancel();

    if (!kIsWeb) {
      unawaited(ScreenBrightness().resetApplicationScreenBrightness());
    }

    super.dispose();
  }

  void _onDetailScrollFab() {
    if (!mounted) return;
    const threshold = 280.0;
    var show = false;
    for (final c in [
      _detailLeftScrollController,
      _detailRightScrollController,
      _detailMobileScrollController,
    ]) {
      if (c.hasClients && c.offset > threshold) {
        show = true;
        break;
      }
    }
    if (show != _showDetailScrollToTop) {
      setState(() => _showDetailScrollToTop = show);
    }
  }

  void _scrollDetailContentToTop() {
    const duration = Duration(milliseconds: 420);
    const curve = Curves.easeOutCubic;
    for (final c in [
      _detailLeftScrollController,
      _detailRightScrollController,
      _detailMobileScrollController,
    ]) {
      if (c.hasClients) {
        c.animateTo(0, duration: duration, curve: curve);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final movieProvider = context.watch<MovieProvider>();

    return Scaffold(
      backgroundColor: Colors.black,
      floatingActionButton: (movieProvider.currentMovie != null &&
              !_playerModule.isFullScreen &&
              _showDetailScrollToTop)
          ? FloatingActionButton.small(
              heroTag: 'detail_scroll_top',
              tooltip: '回到顶部',
              onPressed: _scrollDetailContentToTop,
              child: const Icon(Icons.vertical_align_top_rounded),
            )
          : null,
      body: _deferDetailPrime ||
              (movieProvider.isLoadingDetail &&
                  movieProvider.currentMovie == null)
          ? const DetailShimmer()
          : movieProvider.currentMovie == null
              ? Column(
                  children: [
                    // 返回按钮（错误页也能返回）
                    AppBar(
                      backgroundColor: Colors.black,
                      elevation: 0,
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () {
                          if (_playerModule.isFullScreen) {
                            unawaited(_toggleFullScreen());
                          } else {
                            context.pop();
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: app_widgets.ErrorWidget(
                        message: movieProvider.errorMessage.isEmpty
                            ? '无法加载影片信息，请检查网络或在「源管理」中切换采集源后重试。'
                            : movieProvider.errorMessage,
                        messageColor: Colors.white70,
                        iconColor: Theme.of(context).colorScheme.error,
                        onRetry: _loadData,
                      ),
                    ),
                  ],
                )
              : _buildMainLayout(movieProvider.currentMovie!),
    );
  }

  /// 应用内全屏：播放器独占 [Scaffold.body]（宽分栏下隐藏侧栏；移动端配合 [SystemChrome]）。
  Widget _buildDetailFullscreenPlayerShell(Movie movie) {
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          var h = constraints.maxHeight;
          if (!h.isFinite || h <= 0) {
            h = MediaQuery.sizeOf(context).height;
          }
          return _buildVideoPlayer(movie, h);
        },
      ),
    );
  }

  Widget _buildMainLayout(Movie movie) {
    final mq = MediaQuery.of(context);
    if (_playerModule.isFullScreen && !kIsWeb) {
      return _buildDetailFullscreenPlayerShell(movie);
    }

    final screenWidth = mq.size.width;
    final screenHeight = mq.size.height;
    final safeAreaPadding = mq.padding;
    final availableHeight =
        screenHeight - safeAreaPadding.top - safeAreaPadding.bottom;

    /// 播放器区域严格按宽度算 16:9；高度上限避免超出可用区域（必要时上下裁切画面，不留左右黑边）。
    double playerHeightForColumnWidth(double columnWidth, double maxHeight) {
      if (columnWidth <= 0 || !columnWidth.isFinite) return 200;
      return (columnWidth * 9 / 16).clamp(200.0, maxHeight);
    }

    /// Web / 桌面 OS 在宽度 ≥ 断点时走分栏；选集与播放线路在右栏顶部（见 `DetailDesktopRightSidebar`）。
    final useWideDetailSplit = screenWidth >= _kDetailDesktopBreakpointWidth &&
        (kIsWeb ||
            (!kIsWeb &&
                (Platform.isWindows || Platform.isLinux || Platform.isMacOS)));

    if (useWideDetailSplit) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, outer) {
                    final w = outer.maxWidth;
                    final ph = playerHeightForColumnWidth(
                      w,
                      outer.maxHeight * 0.92,
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: w,
                          height: ph,
                          child: _buildVideoPlayer(movie, ph),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _detailLeftScrollController,
                            child: DetailDesktopLeftSection(movie: movie),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              SizedBox(
                width: _kDetailDesktopSidebarWidth,
                child: DetailDesktopRightSidebar(
                  movie: movie,
                  scrollController: _detailRightScrollController,
                  selectedRouteIndex: _desktopRouteIndex,
                  onRouteSelected: (i) => _playEpisode(i, 0),
                  onEpisodeSelected: _playEpisode,
                  playingRouteIndex: movie.playRoutes.isEmpty
                      ? 0
                      : _desktopRouteIndex.clamp(
                          0,
                          movie.playRoutes.length - 1,
                        ),
                  playingEpisodeIndex: _playerModule.currentEpisodeIndex,
                  onOpenRelated: (related) {
                    AppRoutes.toDetail(
                      context,
                      id: related.id,
                      sourceId: related.sourceId,
                      movie: related,
                    );
                  },
                  magnetResults: _torrentModule.torrentSearchResults,
                  magnetLoading: _torrentModule.isSearching,
                  magnetMessage: _torrentModule.searchMessage,
                  onMagnetRefreshStrict: () =>
                      _runMagnetSearchForMovie(movie, strict: true),
                  onMagnetRefreshLoose: () =>
                      _runMagnetSearchForMovie(movie, strict: false),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final innerPlayerWidth = (screenWidth - 20).clamp(1.0, screenWidth);
    final playerHeight = playerHeightForColumnWidth(
      innerPlayerWidth,
      availableHeight * 0.92,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            SizedBox(
              height: playerHeight,
              child: _buildVideoPlayer(movie, playerHeight),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _detailMobileScrollController,
                child: DetailMovieInfoSection(
                  movie: movie,
                  onPlayRoute: (index) => _playEpisode(index, 0),
                  magnetResults: _torrentModule.torrentSearchResults,
                  magnetLoading: _torrentModule.isSearching,
                  magnetMessage: _torrentModule.searchMessage,
                  onMagnetRefreshStrict: () =>
                      _runMagnetSearchForMovie(movie, strict: true),
                  onMagnetRefreshLoose: () =>
                      _runMagnetSearchForMovie(movie, strict: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer(Movie movie, double playerHeight) {
    // Web端不支持 media_kit
    if (kIsWeb) {
      return SizedBox(
        height: playerHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: DetailComponents.buildPlayerCover(movie)),
            // Web端提示
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white54,
                    size: 36,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Web端暂不支持播放',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
            // 返回按钮
            DetailComponents.buildPlayerTopBar(
              context,
              onBack: () {
                if (_playerModule.isFullScreen) {
                  unawaited(_toggleFullScreen());
                } else {
                  context.pop();
                }
              },
              onFavorite: () {
                // 实现收藏功能
              },
              onShare: () {
                // 实现分享功能
              },
            ),
          ],
        ),
      );
    }

    // 已初始化播放器
    if (_playerModule.videoController != null) {
      final sw = MediaQuery.sizeOf(context).width;
      final useWideDetailSplit = sw >= _kDetailDesktopBreakpointWidth &&
          (kIsWeb ||
              (!kIsWeb &&
                  (Platform.isWindows ||
                      Platform.isLinux ||
                      Platform.isMacOS)));
      final showRoutePickerInPlayerChrome = !useWideDetailSplit;
      return SizedBox(
        height: playerHeight,
        width: double.infinity,
        child: KeyboardListener(
          focusNode: _keyboardFocusNode,
          onKeyEvent: (event) {
            if (event is! KeyDownEvent) return;

            final key = event.logicalKey;

            // ESC：退出全屏
            if (key == LogicalKeyboardKey.escape) {
              if (_playerModule.showShortcutHelp) {
                setState(() => _playerModule.showShortcutHelp = false);
              } else if (_playerModule.showVolumePopover) {
                setState(() => _playerModule.showVolumePopover = false);
              } else if (_playerModule.isFullScreen) {
                unawaited(_applyDetailFullscreen(false));
              }
              return;
            }
            // H / ?：快捷键帮助面板
            if (key == LogicalKeyboardKey.keyH ||
                (key == LogicalKeyboardKey.slash &&
                    !HardwareKeyboard.instance.isShiftPressed)) {
              setState(
                () => _playerModule.showShortcutHelp =
                    !_playerModule.showShortcutHelp,
              );
              if (_playerModule.showShortcutHelp) {
                _playerModule.hideTimer?.cancel();
              } else {
                _startHideTimer();
              }
              return;
            }
            // 当帮助面板显示时，忽略其他快捷键
            if (_playerModule.showShortcutHelp) return;
            // Space：播放/暂停
            if (key == LogicalKeyboardKey.space) {
              _togglePlayPause();
              _startHideTimer();
              return;
            }
            // F：全屏切换
            if (key == LogicalKeyboardKey.keyF) {
              unawaited(_applyDetailFullscreen(!_playerModule.isFullScreen));
              _startHideTimer();
              return;
            }
            // M：静音切换
            if (key == LogicalKeyboardKey.keyM) {
              _toggleMute();
              return;
            }
            // L：锁屏
            if (key == LogicalKeyboardKey.keyL) {
              setState(
                () => _playerModule.isScreenLocked =
                    !_playerModule.isScreenLocked,
              );
              return;
            }
            // 上方向键：音量 +10（0–200 标尺）
            if (key == LogicalKeyboardKey.arrowUp) {
              _adjustVolume(10);
              _startHideTimer();
              return;
            }
            // 下方向键：音量 -10
            if (key == LogicalKeyboardKey.arrowDown) {
              _adjustVolume(-10);
              _startHideTimer();
              return;
            }
            // 左方向键：快退 5s；Shift+左：10s
            if (key == LogicalKeyboardKey.arrowLeft) {
              _seekRelative(
                HardwareKeyboard.instance.isShiftPressed ? -10 : -5,
              );
              _startHideTimer();
              return;
            }
            // 右方向键：快进 5s；Shift+右：10s
            if (key == LogicalKeyboardKey.arrowRight) {
              _seekRelative(
                HardwareKeyboard.instance.isShiftPressed ? 10 : 5,
              );
              _startHideTimer();
              return;
            }
            // C：内嵌字幕开关
            if (key == LogicalKeyboardKey.keyC) {
              setState(
                () =>
                    _playerModule.showSubtitles = !_playerModule.showSubtitles,
              );
              _startHideTimer();
              return;
            }
            // [ / ]：减速 / 加速
            if (key == LogicalKeyboardKey.bracketLeft) {
              _cycleSpeed(-1);
              return;
            }
            if (key == LogicalKeyboardKey.bracketRight) {
              _cycleSpeed(1);
              return;
            }
            final digitSeek = <LogicalKeyboardKey, double>{
              LogicalKeyboardKey.digit0: 0.0,
              LogicalKeyboardKey.digit1: 0.1,
              LogicalKeyboardKey.digit2: 0.2,
              LogicalKeyboardKey.digit3: 0.3,
              LogicalKeyboardKey.digit4: 0.4,
              LogicalKeyboardKey.digit5: 0.5,
              LogicalKeyboardKey.digit6: 0.6,
              LogicalKeyboardKey.digit7: 0.7,
              LogicalKeyboardKey.digit8: 0.8,
              LogicalKeyboardKey.digit9: 0.9,
            };
            final seekFrac = digitSeek[key];
            if (seekFrac != null) {
              _seekToPercent(seekFrac);
              _startHideTimer();
              return;
            }
            // N：下一集
            if (key == LogicalKeyboardKey.keyN) {
              _playNextEpisode();
              _startHideTimer();
              return;
            }
            // P：上一集
            if (key == LogicalKeyboardKey.keyP) {
              _playPreviousEpisode();
              _startHideTimer();
              return;
            }
          },
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerMove: (_) => _onPlayerPointerActivity(),
            onPointerHover: (_) => _onPlayerPointerActivity(),
            child: GestureDetector(
              onDoubleTap: () {
                if (_playerModule.showShortcutHelp) return;
                if (_playerModule.isScreenLocked) return;
                if (_playerModule.currentPlayUrl == null) return;
                final wasPlaying = _playerModule.isPlaying;
                _togglePlayPause();
                setState(() {
                  _playerModule.playPauseIndicatorIcon =
                      wasPlaying ? Icons.pause : Icons.play_arrow;
                  _playerModule.showPlayPauseIndicator = true;
                });
                _playerModule.playPauseIndicatorTimer?.cancel();
                _playerModule.playPauseIndicatorTimer =
                    Timer(const Duration(seconds: 1), () {
                  if (mounted) {
                    setState(
                      () => _playerModule.showPlayPauseIndicator = false,
                    );
                  }
                });
                _startHideTimer();
              },
              // 单击：隐藏控制栏时先显示；已显示时桌面/Web/iOS 可点按切播放，Android 仅双击切播放。
              onTap: () {
                if (_playerModule.showShortcutHelp) return;
                if (_playerModule.isScreenLocked) return;
                if (_playerModule.showVolumePopover) {
                  setState(() => _playerModule.showVolumePopover = false);
                }
                if (!_playerModule.showControls) {
                  setState(() => _playerModule.showControls = true);
                  _startHideTimer();
                } else if (Platform.isAndroid) {
                  _startHideTimer();
                } else {
                  final wasPlaying = _playerModule.isPlaying;
                  _togglePlayPause();
                  setState(() {
                    _playerModule.playPauseIndicatorIcon =
                        wasPlaying ? Icons.pause : Icons.play_arrow;
                    _playerModule.showPlayPauseIndicator = true;
                  });
                  _playerModule.playPauseIndicatorTimer?.cancel();
                  _playerModule.playPauseIndicatorTimer =
                      Timer(const Duration(seconds: 1), () {
                    if (mounted) {
                      setState(
                        () => _playerModule.showPlayPauseIndicator = false,
                      );
                    }
                  });
                  _startHideTimer();
                }
              },
              // 垂直滑动：亮度/音量调节（锁屏时禁用）
              onVerticalDragStart: _playerModule.isScreenLocked
                  ? null
                  : (details) {
                      // 判断触摸点在左半屏还是右半屏
                      final screenWidth = MediaQuery.of(context).size.width;
                      final isLeftSide =
                          details.globalPosition.dx < screenWidth / 2;
                      // 初始化手势提示
                      setState(() {
                        _playerModule.verticalGestureIsLeftSide = isLeftSide;
                        if (isLeftSide) {
                          _playerModule.gestureHintIcon =
                              Icons.brightness_medium;
                          _playerModule.gestureHintValue =
                              _playerModule.brightness;
                          _playerModule.isBrightnessGesture = true;
                        } else {
                          _playerModule.gestureHintIcon = Icons.volume_up;
                          _playerModule.gestureHintValue =
                              _playerModule.volume / 200;
                          _playerModule.isBrightnessGesture = false;
                        }
                        _playerModule.showGestureHint = true;
                        _playerModule.gestureProgress = isLeftSide
                            ? _playerModule.brightness
                            : _playerModule.volume / 200;
                        _playerModule.showGestureBar = true;
                      });
                      if (isLeftSide && !kIsWeb) {
                        unawaited(_refreshBrightnessFromSystem());
                      }
                    },
              onVerticalDragUpdate: _playerModule.isScreenLocked
                  ? null
                  : (details) {
                      _handleVerticalGesture(details);
                    },
              onVerticalDragEnd: _playerModule.isScreenLocked
                  ? null
                  : (_) {
                      _playerModule.gestureHintTimer?.cancel();
                      _playerModule.gestureHintTimer =
                          Timer(const Duration(seconds: 2), () {
                        if (mounted) {
                          setState(() => _playerModule.showGestureHint = false);
                        }
                      });
                      // 手势进度条1秒后淡出
                      _playerModule.gestureBarTimer?.cancel();
                      _playerModule.gestureBarTimer =
                          Timer(const Duration(seconds: 1), () {
                        if (mounted) {
                          setState(() => _playerModule.showGestureBar = false);
                        }
                      });
                    },
              // 水平滑动：快进/快退（锁屏时禁用）
              onHorizontalDragStart: _playerModule.isScreenLocked
                  ? null
                  : (details) {
                      setState(() {
                        _playerModule.seekBubbleText = '';
                        _playerModule.showSeekBubble = true;
                      });
                    },
              onHorizontalDragUpdate: _playerModule.isScreenLocked
                  ? null
                  : (details) {
                      if (_playerModule.duration == Duration.zero) return;
                      final screenWidth = MediaQuery.of(context).size.width;
                      final seekDelta = (details.delta.dx / screenWidth) *
                          _playerModule.duration.inSeconds;
                      final currentSeek = int.tryParse(
                            _playerModule.seekBubbleText
                                .replaceAll(RegExp(r'[+-]'), ''),
                          ) ??
                          0;
                      final totalSeek = (currentSeek + seekDelta.round()).clamp(
                        -_playerModule.duration.inSeconds,
                        _playerModule.duration.inSeconds,
                      );
                      setState(() {
                        _playerModule.seekBubbleText =
                            totalSeek >= 0 ? '+${totalSeek}s' : '${totalSeek}s';
                      });
                    },
              onHorizontalDragEnd: _playerModule.isScreenLocked
                  ? null
                  : (_) {
                      // 执行快进/快退
                      final seekSeconds = int.tryParse(
                            _playerModule.seekBubbleText
                                .replaceAll(RegExp(r'[+-]'), ''),
                          ) ??
                          0;
                      final isForward =
                          _playerModule.seekBubbleText.startsWith('+');
                      if (seekSeconds != 0) {
                        _seekRelative(isForward ? seekSeconds : -seekSeconds);
                      }
                      // 气泡1秒后淡出
                      _playerModule.seekBubbleTimer?.cancel();
                      _playerModule.seekBubbleTimer =
                          Timer(const Duration(seconds: 1), () {
                        if (mounted) {
                          setState(() => _playerModule.showSeekBubble = false);
                        }
                      });
                    },
              onLongPressStart: _playerModule.isScreenLocked
                  ? null
                  : (_) => _onLongPressStart(),
              onLongPressEnd: _playerModule.isScreenLocked
                  ? null
                  : (_) => _onLongPressEnd(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black,
                      child: ClipRect(
                        child: Align(
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: double.infinity,
                            height: playerHeight,
                            child: _buildVideoWidget(playerHeight),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 顶部渐变遮罩（让按钮更清晰）
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 80,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black54, Colors.transparent],
                        ),
                      ),
                    ),
                  ),

                  // 已创建 VideoController 但尚未 open：封面 + 中心播放（避免 init 后误走「无控制器」分支）
                  if (_playerModule.currentPlayUrl == null &&
                      movie.playRoutes.isNotEmpty &&
                      !_playerModule.isScreenLocked)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _startPlay,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fill(child: _buildPlayerCover(movie)),
                            Positioned.fill(
                              child: ColoredBox(
                                color: Colors.black.withValues(alpha: 0.42),
                              ),
                            ),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 56,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 暂停时大号播放键（点击由外层 GestureDetector 处理，此处仅作提示）
                  if (_playerModule.currentPlayUrl != null &&
                      !_playerModule.isPlaying &&
                      !_playerModule.isScreenLocked &&
                      !_playerModule.showShortcutHelp &&
                      !_playerModule.showReplayOverlay)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.42),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 72,
                            ),
                          ),
                        ),
                      ),
                    ),

                  if (_playerModule.showReplayOverlay &&
                      _playerModule.currentPlayUrl != null &&
                      !_playerModule.showShortcutHelp)
                    Positioned.fill(
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.55),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                '本集已播放完毕',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 14),
                              FilledButton.icon(
                                onPressed: () {
                                  setState(
                                    () =>
                                        _playerModule.showReplayOverlay = false,
                                  );
                                  _seekToPercent(0);
                                  _playerModule.resume();
                                  _startHideTimer();
                                },
                                icon: const Icon(Icons.replay),
                                label: const Text('重播'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // 播放中控制栏自动隐藏时仍保留返回，避免全屏视频区无返回入口
                  if (_playerModule.videoController != null &&
                      !_playerModule.isScreenLocked &&
                      !_playerModule.showControls)
                    _buildPlayerPersistentBackButton(),

                  // 控制栏（带显示/隐藏，锁屏时隐藏）；未 open 片源时不显示底栏与锁钮，避免「空播放器」堆控件
                  if (_playerModule.showControls &&
                      !_playerModule.isScreenLocked) ...[
                    // 顶部栏（返回、收藏、分享）
                    _buildPlayerTopBar(),
                    if (_playerModule.currentPlayUrl != null) ...[
                      // 底部控制栏（进度条、播放/暂停、时间、倍速、全屏）
                      _buildPlayerControls(
                        movie,
                        showRoutePickerInChrome: showRoutePickerInPlayerChrome,
                      ),
                      // 左侧悬浮锁按钮（Android风格）
                      Positioned(
                        left: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _playerModule.isScreenLocked = true;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(
                                Icons.lock_open,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 右侧悬浮锁按钮（Android风格）
                      Positioned(
                        right: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _playerModule.isScreenLocked = true;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(
                                Icons.lock_open,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],

                  // 锁屏时显示解锁按钮
                  if (_playerModule.isScreenLocked)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _playerModule.isScreenLocked = false);
                        },
                        child: const Center(
                          child: Icon(
                            Icons.lock_outline,
                            color: Colors.white54,
                            size: 48,
                          ),
                        ),
                      ),
                    ),

                  // 磁力缓存进度条（底部小条，显示当前步骤）
                  if (_playerModule.torrentStep != 0)
                    _buildTorrentProgressBar(),

                  // 字幕叠加层
                  if (_playerModule.showSubtitles &&
                      _playerModule.currentSubtitleText.isNotEmpty)
                    _buildSubtitleOverlay(),

                  // 手势提示（亮度/音量）
                  if (_playerModule.showGestureHint) _buildGestureIndicator(),

                  // 长按加速提示
                  if (_playerModule.showSpeedHint) _buildSpeedHintOverlay(),

                  // 中央播放/暂停指示器（B站风格动画）
                  if (_playerModule.showPlayPauseIndicator)
                    Center(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.5, end: 1.0),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutBack,
                        builder: (context, scale, child) {
                          return Transform.scale(
                            scale: scale,
                            child: AnimatedOpacity(
                              opacity: _playerModule.showPlayPauseIndicator
                                  ? 1.0
                                  : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(115),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _playerModule.playPauseIndicatorIcon,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  // 快进/快退时间气泡
                  if (_playerModule.showSeekBubble &&
                      _playerModule.seekBubbleText.isNotEmpty)
                    Positioned(
                      top: MediaQuery.of(context).size.height * 0.3,
                      left: 0,
                      right: 0,
                      child: AnimatedOpacity(
                        opacity: _playerModule.showSeekBubble ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _playerModule.seekBubbleText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // 亮度/音量竖向进度条
                  if (_playerModule.showGestureBar)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: _playerModule.isBrightnessGesture ? 12 : null,
                      right: _playerModule.isBrightnessGesture ? null : 12,
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: _playerModule.showGestureBar ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: Container(
                            width: 4,
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: _playerModule.gestureProgress
                                    .clamp(0.0, 1.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // 缓冲 / 打开媒体：普通详情在磁力步骤时用右下角卡片；纯磁力详情页中央也要提示（否则黑屏无反馈）
                  if ((_playerModule.isBuffering ||
                          _playerModule.isOpeningMedia ||
                          (widget.sourceId ==
                                  AppConstants.magnetDetailSourceId &&
                              _playerModule.torrentStep == 0)) &&
                      !(_playerModule.torrentStep >= 1 &&
                          _playerModule.torrentStep <= 4 &&
                          widget.sourceId != AppConstants.magnetDetailSourceId))
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 36,
                              height: 36,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              widget.sourceId ==
                                          AppConstants.magnetDetailSourceId &&
                                      _playerModule.torrentStep == 0
                                  ? '正在加载磁力资源…'
                                  : (_playerModule.isOpeningMedia
                                      ? '正在连接播放资源…'
                                      : '正在缓冲…'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                            if (widget.sourceId ==
                                    AppConstants.magnetDetailSourceId &&
                                _playerModule.torrentMessage.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                _playerModule.torrentMessage,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withAlpha(217),
                                  fontSize: 12,
                                  height: 1.25,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                  // 错误提示
                  if (_playerModule.playerErrorMessage.isNotEmpty &&
                      _playerModule.retryCount >= 3)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.white54,
                              size: 40,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '播放失败',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _playbackErrorLabel(),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _playerModule.playerErrorMessage,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _playerModule.retryCount = 0;
                                  _clearPlaybackError();
                                });
                                if (_playerModule.currentPlayUrl != null) {
                                  _playerModule.playerService
                                      .play(_playerModule.currentPlayUrl!);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  '重试',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 快捷键帮助面板
                  _buildShortcutHelpPanel(),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 未播放时显示封面图 + B站风格播放按钮
    return SizedBox(
      height: _playerModule.isFullScreen
          ? MediaQuery.of(context).size.height
          : playerHeight,
      width: _playerModule.isFullScreen
          ? MediaQuery.of(context).size.width
          : double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _buildPlayerCover(movie)),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withAlpha(77),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 返回按钮
          _buildPlayerTopBar(),

          // 上次观看进度提示（有历史记录时显示）
          if (_playerModule.hasHistory && _playerModule.lastPlayDuration > 0)
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(179),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '上次看到 第${_playerModule.currentEpisodeIndex + 1}集 ${(_playerModule.progressPercent * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ),
            ),

          // B站风格播放按钮：半透明黑色圆形背景 + 白色三角形
          if (movie.playRoutes.isNotEmpty)
            Center(
              child: GestureDetector(
                onTap: () {
                  _startPlay();
                },
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(128),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoWidget(double playerHeight) {
    final h =
        playerHeight <= 0 || !playerHeight.isFinite ? 220.0 : playerHeight;
    BoxFit fit;
    if (_playerModule.aspectRatio == 999 / 999) {
      // 全屏裁剪
      fit = BoxFit.cover;
    } else if (_playerModule.aspectRatio == 0) {
      // 原始比例（完整可见，可能有黑边）
      fit = BoxFit.contain;
    } else {
      // 铺满宽度，上下裁切或留黑边（与 B 站网页端一致，避免左右黑边）
      fit = BoxFit.fitWidth;
    }

    final c = _playerModule.videoContrast.clamp(0.6, 1.4);
    final t = 0.5 * (1.0 - c);
    final contrastMatrix = <double>[
      c,
      0,
      0,
      0,
      t,
      0,
      c,
      0,
      0,
      t,
      0,
      0,
      c,
      0,
      t,
      0,
      0,
      0,
      1,
      0,
    ];

    return ClipRect(
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(contrastMatrix),
        child: Video(
          controller: _playerModule.videoController!,
          width: double.infinity,
          height: h,
          controls: null,
          fit: fit,
        ),
      ),
    );
  }

  Widget _buildPlayerCover(Movie movie) {
    final imageUrl = movie.backdrop.isNotEmpty ? movie.backdrop : movie.cover;
    if (imageUrl.isEmpty) {
      return const ColoredBox(color: Color(0xFF000000));
    }
    return Hero(
      tag: 'movie_${movie.id}',
      child: SizedBox.expand(
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) =>
              const ColoredBox(color: Color(0xFF000000)),
        ),
      ),
    );
  }

  Widget _buildPlayerTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // 返回按钮
            GestureDetector(
              onTap: () {
                if (_playerModule.isFullScreen) {
                  unawaited(_toggleFullScreen());
                } else {
                  context.pop();
                }
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const Spacer(),
            Tooltip(
              message: AppLocalizations.of(context)!.detailPlayerTooltipCache,
              child: GestureDetector(
                onTap: () {
                  unawaited(_cacheModule.loadCache(context));
                  _cacheModule.displayCachePanel(context);
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.download_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 收藏按钮
            GestureDetector(
              onTap: () {
                // 实现收藏功能
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.favorite_border,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 分享按钮
            GestureDetector(
              onTap: () {
                // 实现分享功能
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.share,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerPersistentBackButton() {
    return Positioned(
      top: 0,
      left: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () {
            if (_playerModule.isFullScreen) {
              unawaited(_toggleFullScreen());
            } else {
              context.pop();
            }
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.arrow_back,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerControls(
    Movie movie, {
    required bool showRoutePickerInChrome,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (_playerModule.showVolumePopover) {
            setState(() => _playerModule.showVolumePopover = false);
          }
          _startHideTimer();
        },
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildProgressBar(),
              Row(
                children: [
                  _playerChromeIconButton(
                    icon: Icons.skip_previous_rounded,
                    tooltip: l10n.detailPlayerPrevEpisode,
                    enabled: _canPlayPreviousEpisode(movie),
                    onPressed: _playPreviousEpisode,
                  ),
                  _playerChromeIconButton(
                    icon: _playerModule.isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_filled_rounded,
                    tooltip: l10n.designV3TooltipPlayPause,
                    onPressed: () {
                      _togglePlayPause();
                      _startHideTimer();
                    },
                    size: 40,
                  ),
                  _playerChromeIconButton(
                    icon: Icons.skip_next_rounded,
                    tooltip: l10n.detailPlayerNextEpisode,
                    enabled: _canPlayNextEpisode(movie),
                    onPressed: _playNextEpisode,
                  ),
                  Flexible(
                    flex: 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        '${_formatDuration(_playerModule.position)} / ${_formatDuration(_playerModule.duration)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (_playerModule.cacheSpeed > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: SizedBox(
                        width: 64,
                        child: Text(
                          CacheSpeedFormatter.format(_playerModule.cacheSpeed),
                          style: TextStyle(
                            color: kDetailAccentColor.withValues(alpha: 0.95),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  const Spacer(),
                  if (!kIsWeb)
                    _playerChromeIconButton(
                      icon: Icons.subtitles_outlined,
                      tooltip: l10n.detailPlayerSubtitleMenu,
                      onPressed: () =>
                          unawaited(_showSubtitleTrackSheet(movie)),
                    ),
                  Material(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: () {
                        _cycleSpeed(1);
                        _startHideTimer();
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          '${_playerModule.playbackSpeed}x',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (showRoutePickerInChrome)
                    _playerChromeIconButton(
                      icon: Icons.high_quality_rounded,
                      tooltip: '线路 / 清晰度',
                      onPressed: () => _showRouteQualitySheet(movie),
                    ),
                  _playerChromeIconButton(
                    icon: Icons.tune_rounded,
                    tooltip: '画面对比度',
                    onPressed: _showContrastSheet,
                  ),
                  _playerChromeIconButton(
                    icon: Icons.cast_rounded,
                    tooltip: 'DLNA 投屏',
                    onPressed: () => unawaited(_showDlnaSheet(movie)),
                  ),
                  _buildVolumePopoverControl(),
                  _playerChromeIconButton(
                    icon: _playerModule.isFullScreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    tooltip: _playerModule.isFullScreen
                        ? l10n.detailPlayerFullscreenExit
                        : l10n.detailPlayerFullscreenEnter,
                    onPressed: () {
                      unawaited(_toggleFullScreen());
                      _startHideTimer();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// B 站风格：点击喇叭展开/收起上方纵向音量条；弹层内可拖动滑块、点图标静音。
  Widget _buildVolumePopoverControl() {
    return Tooltip(
      message: '音量（点击展开）',
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          if (_playerModule.showVolumePopover)
            Positioned(
              bottom: 40,
              child: MouseRegion(
                onEnter: (_) => _onPlayerPointerActivity(),
                child: Material(
                  color: Colors.black.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_playerModule.volume.round()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 120,
                          height: 32,
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                activeTrackColor: kDetailAccentColor,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: SliderComponentShape.noOverlay,
                              ),
                              child: Slider(
                                value: _playerModule.volume
                                    .clamp(0, DetailPlayer.maxVolumeUi),
                                min: 0,
                                max: DetailPlayer.maxVolumeUi,
                                onChanged: (v) {
                                  setState(() {
                                    _playerModule.volume = v;
                                    _playerModule.isMuted = false;
                                  });
                                  unawaited(
                                    _playerModule.playerService.setVolume(v),
                                  );
                                  _startHideTimer();
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        TextButton(
                          onPressed: () {
                            _toggleMute();
                            _startHideTimer();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white60,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            _playerModule.isMuted ? '取消静音' : '静音',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                setState(() {
                  _playerModule.showVolumePopover =
                      !_playerModule.showVolumePopover;
                });
                _startHideTimer();
              },
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  _playerModule.isMuted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerChromeIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    double size = 28,
    bool enabled = true,
  }) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled
                ? () {
                    onPressed();
                    _startHideTimer();
                  }
                : null,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                icon,
                color: Colors.white,
                size: size,
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _timelineFraction() {
    final d = _playerModule.duration.inMilliseconds;
    if (d <= 0) return 0;
    return (_playerModule.position.inMilliseconds / d).clamp(0.0, 1.0);
  }

  double _bufferFraction() {
    final d = _playerModule.duration.inMilliseconds;
    if (d <= 0) return 0;
    return (_playerModule.bufferedPosition.inMilliseconds / d).clamp(0.0, 1.0);
  }

  Widget _buildProgressBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        void seekAt(Offset local) {
          final w = constraints.maxWidth;
          final dMs = _playerModule.duration.inMilliseconds;
          if (w <= 0 || dMs <= 0) return;
          final f = (local.dx / w).clamp(0.0, 1.0);
          final newPos = Duration(milliseconds: (dMs * f).round());
          _playerModule.playerService.seek(newPos);
          setState(() => _playerModule.position = newPos);
        }

        return SizedBox(
          height: 22,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) {
              _playerModule.hideTimer?.cancel();
              seekAt(d.localPosition);
            },
            onHorizontalDragUpdate: (d) => seekAt(d.localPosition),
            onHorizontalDragEnd: (_) => _startHideTimer(),
            onTapDown: (d) {
              _playerModule.hideTimer?.cancel();
              seekAt(d.localPosition);
              _startHideTimer();
            },
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: _bufferFraction(),
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white38,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: _timelineFraction(),
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: kDetailAccentColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment(_timelineFraction() * 2 - 1, 0),
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: kDetailAccentColor.withValues(alpha: 0.9),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubtitleOverlay() {
    return DetailComponents.buildSubtitleOverlay(
      _playerModule.currentSubtitleText,
      fontSize: _playerModule.subtitleFontSize,
      color: _playerModule.subtitleColor,
    );
  }

  Widget _buildGestureIndicator() {
    return DetailComponents.buildGestureIndicator(
      _playerModule.gestureHintIcon,
      _playerModule.gestureHintValue,
    );
  }

  Widget _buildSpeedHintOverlay() {
    return DetailComponents.buildSpeedHintOverlay(2.0);
  }

  Widget _buildTorrentProgressBar() {
    return DetailComponents.buildTorrentProgressBar(
      _playerModule.torrentStep,
      _playerModule.torrentMessage,
    );
  }

  Widget _buildShortcutHelpPanel() {
    return DetailComponents.buildShortcutHelpPanel(
      _playerModule.showShortcutHelp,
      onClose: () {
        setState(() => _playerModule.showShortcutHelp = false);
      },
    );
  }

  void _stopProgressPersistTimer() {
    _playerModule.progressPersistTimer?.cancel();
    _playerModule.progressPersistTimer = null;
  }

  void _startProgressPersistTimer() {
    _stopProgressPersistTimer();
    _playerModule.progressPersistTimer =
        Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      final m = context.read<MovieProvider>().currentMovie;
      if (m == null || _playerModule.currentPlayUrl == null) return;
      await _playerModule.saveProgress(
        context,
        m,
        routeIndex: _desktopRouteIndex,
      );
    });
  }

  void _syncWatchHistory(Movie movie) {
    final h = widget.initialMagnetUri.isNotEmpty
        ? context.read<HistoryProvider>().getHistory(
              movie.id,
              magnetUri: widget.initialMagnetUri,
            )
        : context.read<HistoryProvider>().getHistory(
              movie.id,
              sourceId: movie.sourceId,
            );
    if (h == null || (h.progress <= 0 && h.duration <= 0)) {
      _playerModule.hasHistory = false;
      _playerModule.lastPlayProgress = 0;
      _playerModule.lastPlayDuration = 0;
      _playerModule.pendingResumePosition = null;
      _playerModule.resumeTargetRouteIndex = null;
      _playerModule.resumeTargetEpisodeIndex = null;
      return;
    }
    _playerModule.hasHistory = true;
    _playerModule.lastPlayProgress = h.progress;
    _playerModule.lastPlayDuration = h.duration;
    final rc = movie.playRoutes.length;
    if (rc > 0) {
      _desktopRouteIndex = h.routeIndex.clamp(0, rc - 1);
    }
    final nearEnd = h.duration > 0 && h.progress >= h.duration - 3000;
    if (!h.isFinished && !nearEnd && h.progress > 0) {
      _playerModule.resumeTargetRouteIndex =
          h.routeIndex.clamp(0, rc > 0 ? rc - 1 : 0);
      _playerModule.resumeTargetEpisodeIndex = h.episodeIndex;
      _playerModule.pendingResumePosition = Duration(milliseconds: h.progress);
    } else {
      _playerModule.pendingResumePosition = null;
      _playerModule.resumeTargetRouteIndex = null;
      _playerModule.resumeTargetEpisodeIndex = null;
    }
  }

  void _applyPreferredRouteFromSettings(Movie movie) {
    if (movie.playRoutes.isEmpty) return;
    if (_playerModule.pendingResumePosition != null) return;
    final q = context.read<SettingsProvider>().defaultQuality;
    final idx = _routeIndexMatchingQuality(movie, q);
    if (idx != null) {
      _desktopRouteIndex = idx.clamp(0, movie.playRoutes.length - 1);
    }
  }

  int? _routeIndexMatchingQuality(Movie movie, String quality) {
    if (quality == '自动') return null;
    final keywords = <String, List<String>>{
      '标清': ['标', '流畅', '普清', '360', '480'],
      '高清': ['高清', 'hd', '720', '超清'],
      '1080P': ['1080', '蓝光', 'bd'],
      '4K': ['4k', '2160', 'uhd'],
    };
    final keys = keywords[quality];
    if (keys == null) return null;
    for (var i = 0; i < movie.playRoutes.length; i++) {
      final n = movie.playRoutes[i].name.toLowerCase();
      for (final k in keys) {
        if (n.contains(k.toLowerCase())) return i;
      }
    }
    return null;
  }

  void _handleDetailPlaybackEnded() {
    if (!mounted) return;
    final movie = context.read<MovieProvider>().currentMovie;
    if (movie != null && _playerModule.currentPlayUrl != null) {
      unawaited(
        _playerModule.saveProgress(
          context,
          movie,
          routeIndex: _desktopRouteIndex,
        ),
      );
    }
    if (_playerModule.isAutoPlayNext &&
        movie != null &&
        movie.playRoutes.isNotEmpty) {
      final ri = _desktopRouteIndex.clamp(0, movie.playRoutes.length - 1);
      final route = movie.playRoutes[ri];
      if (route.episodes.isEmpty) {
        setState(() => _playerModule.showReplayOverlay = true);
        return;
      }
      final next = _playerModule.currentEpisodeIndex + 1;
      if (next < route.episodes.length) {
        setState(() => _playerModule.showReplayOverlay = false);
        _playEpisode(ri, next);
        return;
      }
    }
    setState(() => _playerModule.showReplayOverlay = true);
  }

  void _onPlayerBufferingChanged(bool buffering) {
    _routeFallbackTimer?.cancel();
    if (!buffering) return;
    final movie = context.read<MovieProvider>().currentMovie;
    if (movie == null || movie.playRoutes.length < 2) return;
    if (_playerModule.currentPlayUrl == null) return;
    _routeFallbackTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || !_playerModule.isBuffering) return;
      _tryFallbackToNextRoute(movie);
    });
  }

  void _tryFallbackToNextRoute(Movie movie) {
    if (movie.playRoutes.length < 2) return;
    final next = (_desktopRouteIndex + 1) % movie.playRoutes.length;
    if (next == _desktopRouteIndex) return;
    final episodes = movie.playRoutes[next].episodes;
    if (episodes.isEmpty) return;
    final ei = _playerModule.currentEpisodeIndex.clamp(0, episodes.length - 1);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('缓冲较慢，已尝试切换线路')),
    );
    _playEpisode(next, ei);
  }

  void _showContrastSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '画面对比度',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: kDetailAccentColor,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: kDetailAccentColor,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: _playerModule.videoContrast,
                      min: 0.6,
                      max: 1.4,
                      divisions: 16,
                      label: _playerModule.videoContrast.toStringAsFixed(2),
                      onChanged: (x) {
                        setModal(() {});
                        setState(() => _playerModule.videoContrast = x);
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showRouteQualitySheet(Movie movie) {
    if (movie.playRoutes.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      builder: (ctx) {
        return ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < movie.playRoutes.length; i++)
              ListTile(
                title: Text(
                  movie.playRoutes[i].name.isEmpty
                      ? '线路 ${i + 1}'
                      : movie.playRoutes[i].name,
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: i == _desktopRouteIndex
                    ? const Icon(Icons.check, color: Colors.lightBlueAccent)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  final eps = movie.playRoutes[i].episodes;
                  if (eps.isEmpty) return;
                  final ei = _playerModule.currentEpisodeIndex
                      .clamp(0, eps.length - 1);
                  _playEpisode(i, ei);
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _showDlnaSheet(Movie movie) async {
    if (_playerModule.currentPlayUrl == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(content: Text('正在搜索局域网设备…')),
    );
    await _dlnaService.searchDevices();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dctx) {
        final list = _dlnaService.devices;
        return AlertDialog(
          title: const Text('DLNA 设备'),
          content: SizedBox(
            width: double.maxFinite,
            child: list.isEmpty
                ? const Text('未发现设备，请确认电视与电脑在同一网络')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final d = list[i];
                      return ListTile(
                        title: Text(d.name),
                        onTap: () async {
                          Navigator.pop(dctx);
                          await _dlnaService.connectDevice(d);
                          final ok = await _dlnaService.castPlay(
                            _playerModule.currentPlayUrl!,
                            title: movie.name,
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok ? '已推送播放地址到设备' : '投屏失败',
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadData() async {
    final movieProvider = context.read<MovieProvider>();
    await movieProvider.loadMovieDetail(widget.movieId);
  }

  void _loadRecommendations() {}

  void _startPlay() {
    final movie = context.read<MovieProvider>().currentMovie;
    if (movie == null || movie.playRoutes.isEmpty) return;
    if (_playerModule.currentPlayUrl != null) {
      _togglePlayPause();
      return;
    }
    final ri = _desktopRouteIndex.clamp(0, movie.playRoutes.length - 1);
    _playEpisode(ri, 0);
  }

  void _playEpisode(int routeIndex, int episodeIndex) {
    final movie = context.read<MovieProvider>().currentMovie;
    if (movie == null || routeIndex >= movie.playRoutes.length) return;

    final route = movie.playRoutes[routeIndex];
    if (route.episodes.isEmpty) return;
    if (episodeIndex < 0 || episodeIndex >= route.episodes.length) return;

    final episode = route.episodes[episodeIndex];
    if (_playerModule.currentPlayUrl != episode.url) {
      _subtitleAutoMatchedForUrl = null;
    }
    _playerModule.currentPlayUrl = episode.url;
    _playerModule.currentEpisodeIndex = episodeIndex;
    _playerModule.currentRouteIndex = routeIndex;
    _playerModule.cacheSpeed = 0;
    _playerModule.showReplayOverlay = false;

    final matchResume = _playerModule.resumeTargetRouteIndex == routeIndex &&
        _playerModule.resumeTargetEpisodeIndex == episodeIndex;
    if (!matchResume) {
      _playerModule.pendingResumePosition = null;
      _playerModule.resumeTargetRouteIndex = null;
      _playerModule.resumeTargetEpisodeIndex = null;
    }

    if (_playerModule.videoController == null) {
      _playerModule.initialize().then((_) async {
        if (!mounted) return;
        if (_playerModule.videoController != null) {
          setState(() {
            _desktopRouteIndex = routeIndex;
            _playerModule.isOpeningMedia = true;
          });
          await _playerModule.playerService.play(episode.url);
          if (mounted) {
            setState(() {});
            _startHideTimer();
            _startProgressPersistTimer();
            unawaited(_maybeAutoMatchSubtitlePlay(movie, episode.url));
          }
        }
      });
    } else {
      setState(() {
        _desktopRouteIndex = routeIndex;
        _playerModule.isOpeningMedia = true;
      });
      unawaited(
        _playerModule.playerService.play(episode.url).whenComplete(() {
          if (mounted) {
            setState(() {});
            _startHideTimer();
            _startProgressPersistTimer();
            final m = context.read<MovieProvider>().currentMovie;
            if (m != null) {
              unawaited(_maybeAutoMatchSubtitlePlay(m, episode.url));
            }
          }
        }),
      );
    }
  }

  bool _canPlayPreviousEpisode(Movie movie) {
    if (movie.playRoutes.isEmpty) return false;
    final ri = _playerModule.currentRouteIndex.clamp(
      0,
      movie.playRoutes.length - 1,
    );
    final route = movie.playRoutes[ri];
    if (route.episodes.isEmpty) return false;
    return _playerModule.currentEpisodeIndex > 0;
  }

  bool _canPlayNextEpisode(Movie movie) {
    if (movie.playRoutes.isEmpty) return false;
    final ri = _playerModule.currentRouteIndex.clamp(
      0,
      movie.playRoutes.length - 1,
    );
    final route = movie.playRoutes[ri];
    if (route.episodes.isEmpty) return false;
    return _playerModule.currentEpisodeIndex < route.episodes.length - 1;
  }

  bool _shouldTrySubtitleAutoMatch(Movie movie, String playUrl) {
    if (widget.sourceId == AppConstants.magnetDetailSourceId) return true;
    if (movie.sourceId == AppConstants.magnetDetailSourceId) return true;
    final u = playUrl.toLowerCase();
    if (u.startsWith('magnet:')) return true;
    if (u.contains('magnet')) return true;
    return false;
  }

  Future<void> _maybeAutoMatchSubtitlePlay(Movie movie, String playUrl) async {
    if (kIsWeb) return;
    if (!_shouldTrySubtitleAutoMatch(movie, playUrl)) return;
    if (_subtitleAutoMatchedForUrl == playUrl) return;
    _subtitleAutoMatchedForUrl = playUrl;
    if (!mounted) return;
    if (!context.read<SettingsProvider>().opensubtitlesApiKeyConfigured) {
      return;
    }
    final svc = SubtitleService();
    final ok = await svc.init();
    if (!ok || !mounted) return;
    final list = await svc.searchByName(movie.name);
    if (!mounted || list.isEmpty) return;
    SubtitleInfo pick = list.first;
    for (final s in list) {
      if (s.language.toLowerCase().contains('zh')) {
        pick = s;
        break;
      }
    }
    if (pick.fileId == null || pick.fileId! <= 0) return;
    final path = await svc.downloadSubtitle(pick.fileId!);
    if (!mounted || path == null) return;
    await _playerModule.playerService.setExternalSubtitleFromFile(path);
    if (!mounted) return;
    setState(() => _playerModule.showSubtitles = true);
  }

  Future<void> _showSubtitleTrackSheet(Movie movie) async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  l10n.detailPlayerSubtitleSheetTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(l10n.detailPlayerSubtitleAutoMatch),
                subtitle: Text(l10n.detailPlayerSubtitleAutoMatchSubtitle),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_runSubtitleAutoMatch(movie));
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: Text(l10n.detailPlayerSubtitlePickFile),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickAndLoadSubtitleFile();
                },
              ),
              ListTile(
                leading: const Icon(Icons.closed_caption_off_outlined),
                title: Text(l10n.detailPlayerSubtitleOff),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (!kIsWeb) {
                    await _playerModule.playerService
                        .clearExternalSubtitleTrack();
                  }
                  if (mounted) {
                    setState(() => _playerModule.showSubtitles = false);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.search),
                title: Text(l10n.detailPlayerSubtitleBrowseOnline),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_showSubtitleSearchPicker(movie));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _runSubtitleAutoMatch(Movie movie) async {
    if (kIsWeb) return;
    final l10n = AppLocalizations.of(context)!;
    if (!context.read<SettingsProvider>().opensubtitlesApiKeyConfigured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.detailPlayerSubtitleNoApiKey)),
      );
      return;
    }
    final svc = SubtitleService();
    final ok = await svc.init();
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.detailPlayerSubtitleApplyFailed)),
      );
      return;
    }
    if (!mounted) return;
    final list = await svc.searchByName(movie.name);
    if (!mounted) return;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.detailPlayerSubtitleNone)),
      );
      return;
    }
    SubtitleInfo pick = list.first;
    for (final s in list) {
      if (s.language.toLowerCase().contains('zh')) {
        pick = s;
        break;
      }
    }
    if (pick.fileId == null || pick.fileId! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.detailPlayerSubtitleApplyFailed)),
      );
      return;
    }
    final path = await svc.downloadSubtitle(pick.fileId!);
    if (!mounted) return;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.detailPlayerSubtitleApplyFailed)),
      );
      return;
    }
    await _playerModule.playerService.setExternalSubtitleFromFile(path);
    if (!mounted) return;
    setState(() => _playerModule.showSubtitles = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.detailPlayerSubtitleApplied)),
    );
  }

  Future<void> _pickAndLoadSubtitleFile() async {
    if (kIsWeb) return;
    final l10n = AppLocalizations.of(context)!;
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['srt', 'vtt', 'ass', 'ssa'],
    );
    if (!mounted) return;
    final p = r?.files.single.path;
    if (p == null || p.isEmpty) return;
    try {
      await _playerModule.playerService.setExternalSubtitleFromFile(p);
      if (!mounted) return;
      setState(() => _playerModule.showSubtitles = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.detailPlayerSubtitleApplied)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.detailPlayerSubtitleApplyFailed)),
      );
    }
  }

  Future<void> _showSubtitleSearchPicker(Movie movie) async {
    if (kIsWeb) return;
    final l10n = AppLocalizations.of(context)!;
    if (!context.read<SettingsProvider>().opensubtitlesApiKeyConfigured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.detailPlayerSubtitleNoApiKey)),
      );
      return;
    }
    final svc = SubtitleService();
    final ok = await svc.init();
    if (!ok || !mounted) return;
    final list = await svc.searchByName(movie.name);
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.55,
            child: list.isEmpty
                ? Center(child: Text(l10n.detailPlayerSubtitleNone))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final s = list[i];
                      return ListTile(
                        title: Text(
                          s.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${s.language} · DL ${s.downloadsCount}',
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          if (!mounted) return;
                          if (s.fileId == null || s.fileId! <= 0) return;
                          final path = await svc.downloadSubtitle(s.fileId!);
                          if (!mounted) return;
                          if (path == null) {
                            if (!mounted) return;
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content:
                                    Text(l10n.detailPlayerSubtitleApplyFailed),
                              ),
                            );
                            return;
                          }
                          await _playerModule.playerService
                              .setExternalSubtitleFromFile(path);
                          if (!mounted) return;
                          setState(() => _playerModule.showSubtitles = true);
                          if (!mounted) return;
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(l10n.detailPlayerSubtitleApplied),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  Future<void> _restoreSystemUiAfterFullScreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _applyDetailFullscreen(bool enter) async {
    if (_playerModule.isFullScreen == enter) return;
    setState(() {
      _playerModule.isFullScreen = enter;
    });
    if (kIsWeb) return;
    final mobile = Platform.isAndroid || Platform.isIOS;
    if (mobile) {
      if (enter) {
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
        );
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await _restoreSystemUiAfterFullScreen();
      }
      if (!mounted) return;
    }
  }

  Future<void> _toggleFullScreen() async {
    await _applyDetailFullscreen(!_playerModule.isFullScreen);
  }

  void _togglePlayPause() {
    if (_playerModule.playerService.player == null) return;
    if (_playerModule.currentPlayUrl == null) return;
    if (_playerModule.isPlaying) {
      _playerModule.pause();
    } else {
      _playerModule.resume();
    }
  }

  void _toggleMute() {
    setState(() {
      _playerModule.isMuted = !_playerModule.isMuted;
      if (_playerModule.isMuted) {
        _playerModule.muteVolume = _playerModule.volume;
        _playerModule.playerService.setVolume(0);
      } else {
        _playerModule.playerService.setVolume(_playerModule.muteVolume);
        _playerModule.volume = _playerModule.muteVolume;
      }
    });
  }

  /// [delta] 为相对变化量（如键盘 ±10）
  void _adjustVolume(double delta) {
    setState(() {
      _playerModule.volume =
          (_playerModule.volume + delta).clamp(0.0, DetailPlayer.maxVolumeUi);
      unawaited(_playerModule.playerService.setVolume(_playerModule.volume));
      if (_playerModule.isMuted) {
        _playerModule.muteVolume = _playerModule.volume;
      }
    });
  }

  void _seekRelative(int seconds) {
    final d = _playerModule.duration;
    if (d <= Duration.zero) return;
    var newMs = _playerModule.position.inMilliseconds + seconds * 1000;
    newMs = newMs.clamp(0, d.inMilliseconds);
    final newPosition = Duration(milliseconds: newMs);
    _playerModule.playerService.seek(newPosition);
    setState(() => _playerModule.position = newPosition);
  }

  void _seekToPercent(double percent) {
    final dMs = _playerModule.duration.inMilliseconds;
    if (dMs <= 0) return;
    final newPosition =
        Duration(milliseconds: (dMs * percent.clamp(0.0, 1.0)).round());
    _playerModule.playerService.seek(newPosition);
    setState(() => _playerModule.position = newPosition);
  }

  void _playNextEpisode() {
    final movie = context.read<MovieProvider>().currentMovie;
    if (movie == null || movie.playRoutes.isEmpty) return;
    final ri =
        _playerModule.currentRouteIndex.clamp(0, movie.playRoutes.length - 1);
    final route = movie.playRoutes[ri];
    if (route.episodes.isEmpty) return;
    final next = _playerModule.currentEpisodeIndex + 1;
    if (next >= route.episodes.length) return;
    _playEpisode(ri, next);
  }

  void _playPreviousEpisode() {
    final movie = context.read<MovieProvider>().currentMovie;
    if (movie == null || movie.playRoutes.isEmpty) return;
    final ri =
        _playerModule.currentRouteIndex.clamp(0, movie.playRoutes.length - 1);
    final route = movie.playRoutes[ri];
    if (route.episodes.isEmpty) return;
    final prev = _playerModule.currentEpisodeIndex - 1;
    if (prev < 0) return;
    _playEpisode(ri, prev);
  }

  static const List<double> _kSpeedSteps = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  void _cycleSpeed(int direction) {
    var idx = _kSpeedSteps.indexWhere(
      (s) => (s - _playerModule.playbackSpeed).abs() < 0.02,
    );
    if (idx < 0) {
      idx = _kSpeedSteps.indexOf(1.0);
    }
    idx = (idx + direction) % _kSpeedSteps.length;
    final sp = _kSpeedSteps[idx];
    unawaited(_playerModule.setPlaybackSpeed(sp));
    setState(() => _playerModule.playbackSpeed = sp);
    _startHideTimer();
  }

  Future<void> _refreshBrightnessFromSystem() async {
    if (kIsWeb) return;
    try {
      final b = await ScreenBrightness().application;
      if (!mounted) return;
      setState(() => _playerModule.brightness = b.clamp(0.0, 1.0));
    } catch (_) {}
  }

  void _handleVerticalGesture(DragUpdateDetails details) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _playerModule.lastGestureUpdateMs <
        DetailPlayer.gestureThrottleMs) {
      return;
    }
    _playerModule.lastGestureUpdateMs = now;

    final left = _playerModule.verticalGestureIsLeftSide;
    final delta = -details.delta.dy / 220;

    setState(() {
      if (left) {
        _playerModule.brightness =
            (_playerModule.brightness + delta).clamp(0.0, 1.0);
        _playerModule.gestureHintValue = _playerModule.brightness;
        _playerModule.gestureProgress = _playerModule.brightness;
        if (!kIsWeb) {
          unawaited(
            ScreenBrightness().setApplicationScreenBrightness(
              _playerModule.brightness,
            ),
          );
        }
      } else {
        _playerModule.volume = (_playerModule.volume + delta * 200)
            .clamp(0.0, DetailPlayer.maxVolumeUi);
        unawaited(_playerModule.playerService.setVolume(_playerModule.volume));
        _playerModule.gestureHintValue =
            _playerModule.volume / DetailPlayer.maxVolumeUi;
        _playerModule.gestureProgress =
            _playerModule.volume / DetailPlayer.maxVolumeUi;
      }
    });
  }

  void _onLongPressStart() {
    if (_playerModule.currentPlayUrl == null) return;
    _playerModule.normalSpeed = _playerModule.playbackSpeed;
    unawaited(_playerModule.setPlaybackSpeed(2.0));
    setState(() => _playerModule.showSpeedHint = true);
  }

  void _onLongPressEnd() {
    if (_playerModule.currentPlayUrl == null) return;
    unawaited(_playerModule.setPlaybackSpeed(_playerModule.normalSpeed));
    setState(() => _playerModule.showSpeedHint = false);
  }

  /// 鼠标在播放器上移动：显示控制栏与进度条，并重置 3 秒隐藏计时。
  void _onPlayerPointerActivity() {
    if (!mounted) return;
    if (_playerModule.showShortcutHelp || _playerModule.isScreenLocked) {
      return;
    }
    if (!_playerModule.showControls) {
      setState(() => _playerModule.showControls = true);
    }
    _startHideTimer();
  }

  void _startHideTimer() {
    _playerModule.hideTimer?.cancel();
    if (!_playerModule.showControls || _playerModule.showShortcutHelp) return;
    _playerModule.hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          _playerModule.showControls &&
          !_playerModule.showShortcutHelp) {
        setState(() {
          _playerModule.showControls = false;
          _playerModule.showVolumePopover = false;
        });
      }
    });
  }

  void _clearPlaybackError() {
    _playerModule.playerErrorMessage = '';
    _playerModule.playbackErrorType = PlaybackErrorType.none;
  }

  String _playbackErrorLabel() {
    switch (_playerModule.playbackErrorType) {
      case PlaybackErrorType.noPlayableEpisode:
        return '无可播放地址';
      case PlaybackErrorType.parseFailed:
        return '解析失败';
      case PlaybackErrorType.routeFallback:
        return '已切换线路';
      case PlaybackErrorType.sourceFallbackFailed:
        return '多源回退失败';
      case PlaybackErrorType.networkOrPlayer:
        return '网络或播放器错误';
      case PlaybackErrorType.magnetFailed:
        return '磁力播放失败';
      case PlaybackErrorType.none:
        return '';
    }
  }

  // void _saveProgress() {
  //   final movie = context.read<MovieProvider>().currentMovie;
  //   if (movie == null || movie.id.isEmpty) return;

  //   final historyProvider = context.read<HistoryProvider>();
  //   // 保存磁力链接，无论sourceId是什么
  //   String? magnetUri;
  //   if (_playerModule.lastMagnetUri.isNotEmpty) {
  //     magnetUri = _playerModule.lastMagnetUri;
  //   }

  //   historyProvider.saveOrUpdateHistory(
  //     movieId: movie.id,
  //     movieName: movie.name,
  //     movieCover: movie.cover,
  //     episodeIndex: _playerModule.currentEpisodeIndex,
  //     episodeName: _playerModule.lastMagnetUri.isNotEmpty
  //         ? '磁力'
  //         : '第${_playerModule.currentEpisodeIndex + 1}集',
  //     progress: _playerModule.position.inMilliseconds,
  //     duration: _playerModule.duration.inMilliseconds,
  //     sourceId: widget.sourceId,
  //     routeIndex: 0,
  //     magnetUri: magnetUri,
  //   );
  // }

  /// 初始化模块
  Future<void> _initModules() async {
    _playerModule.onUiChanged = () {
      if (mounted) setState(() {});
    };
    _playerModule.onPlaybackEnded = _handleDetailPlaybackEnded;
    _playerModule.onBufferingChangedUi = _onPlayerBufferingChanged;
    await _playerModule.initialize();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
