import 'dart:async' show Timer, unawaited;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter/services.dart'
    show
        DeviceOrientation,
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        KeyRepeatEvent,
        MethodChannel,
        SystemChrome,
        SystemUiMode;
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart' show SubtitleTrack;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';
import '../../services/subtitle_service.dart';
import '../../widgets/subtitle_selector.dart' show runSubtitleAiGeneration;
// 图片缓存
import 'package:cached_network_image/cached_network_image.dart';

import '../../utils/web_http_stub.dart'
    if (dart.library.html) '../../utils/web_http.dart' as web_http;
import '../../utils/cache_speed_formatter.dart';
import '../../utils/episode_display_label.dart';
import '../../utils/magnet_episode_parser.dart';
import '../../config/constants.dart';
import '../../config/routes.dart';
import '../../services/debug_log.dart';
import '../../services/storage_service.dart';
import '../../models/movie.dart';
import '../../models/torrent_info.dart';
import '../../models/watch_history.dart';
import '../../providers/history_provider.dart';
import '../../providers/cache_provider.dart';
import '../../providers/movie_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/source_provider.dart';
import '../../services/dlna_service.dart';
import '../../services/dlna_playback_url_resolver.dart';
import '../../services/imdb_lookup_service.dart';
import '../../services/magnet_subtitle_service.dart';
import '../../services/player_mpv.dart';
import '../../services/playback_route_selector.dart';
import '../../services/subtitle/subtitle_track_parser.dart';
import '../../services/playback_strategy.dart';
import '../../services/playback_start_seek_exception.dart';
import '../../services/playback_url_resolver.dart';
import '../../services/hw_decode_policy.dart';
import '../../services/video_output_policy.dart';
import '../../services/magnet_detail_enrichment_service.dart';
import '../../services/background_playback_service.dart';
import '../../services/torrent_player_models.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/speed_selector.dart';
import '../../widgets/error_widget.dart' as app_widgets;

import 'detail_player.dart';
import 'detail_torrent.dart';
import 'detail_cache.dart';
import 'detail_components.dart';
import 'detail_movie_info_section.dart';
import 'detail_desktop_layout.dart';
import 'detail_ui_tokens.dart';
import 'detail_video_layout.dart';
import 'detail_resume_coordinator.dart';
import 'episode_download_coordinator.dart';
import 'detail_fullscreen_orientation.dart';
import 'detail_dlna_sheet.dart';
import 'detail_player_side_panel.dart';
import 'detail_player_cache_fab.dart';
import 'player_overlay_button.dart';
import 'detail_magnet_playback.dart';
import 'playback/subtitle_timing_policy.dart';
import 'playback/subtitle_format_policy.dart';
import 'playback_error_type.dart';
import 'playback/playback_lifecycle.dart';
import 'playback/player_chrome_policy.dart';
import 'playback/keyboard_shortcut_policy.dart';
import 'playback/subtitle_language_policy.dart';
import 'playback/subtitle_simplified_policy.dart';
import 'playback/magnet_prep_progress_policy.dart';
import 'playback/background_playback_policy.dart';
import 'playback/player_fit_policy.dart';

part 'detail_page_data.dart';
part 'detail_page_dlna.dart';
part 'detail_page_download.dart';
part 'detail_page_episode.dart';
part 'detail_page_misc.dart';
part 'detail_page_playback.dart';
part 'detail_page_player_ui.dart';
part 'detail_page_player_controls_ui.dart';
part 'detail_page_subtitle.dart';

/// Windows 桌面详情宽屏分栏断点（逻辑宽度）
const double _kDetailDesktopBreakpointWidth = 900;

/// 右侧信息 / 选集栏宽度
const double _kDetailDesktopSidebarWidth = 340;

/// 移动端详情信息区（播放器下方）左右留白
const double _kDetailMobileContentHorizontalInset = 10;

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

  /// 用户搜索中文片名（磁力详情元数据补全）
  final String? displayTitleHint;

  /// 磁力结果自带的 IMDb ID
  final String? torrentImdbId;

  /// 当前磁力条目（资源大小/做种等展示）
  final TorrentInfo? torrent;

  /// 从缓存列表进入时指定起播集数。
  final int? initialEpisodeIndex;

  const DetailPage({
    super.key,
    required this.movieId,
    this.sourceId = '',
    this.movie,
    this.initialMagnetUri = '',
    this.displayTitleHint,
    this.torrentImdbId,
    this.torrent,
    this.initialEpisodeIndex,
  });

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage>
    with RouteAware, WidgetsBindingObserver {
  /// 供拆分出去的 extension 间接调用：在 extension 内直接调用 [setState] 会被
  /// 分析器按 @protected 判定为越权（setState 只能由 State 子类成员调用），
  /// 这里做一层同名转发，语义完全一致。
  void _setState(void Function() fn) => setState(fn);

  /// 页面级键盘焦点锚点。
  ///
  /// 快捷键本体不再挂在播放器子树里的 `KeyboardListener` 上：切全屏时整棵
  /// 播放器子树会换父节点，FocusNode 随之失焦，ESC / 空格就全失灵。这个节点
  /// 放在 [build] 最外层、不随全屏切换卸载，配合 `autofocus` 保住窗口焦点。
  final FocusNode _keyboardFocusNode = FocusNode();

  /// 页面级按键处理器（保存 tear-off，dispose 时用同一引用注销）。
  late final bool Function(KeyEvent) _globalKeyHandler;

  /// 是否因为「进入后台且不允许后台播放」而被本页暂停过。
  /// 回前台只恢复这一类暂停——用户自己按的暂停不该被我们抢着播。
  bool _pausedByBackground = false;

  /// 详情页主滚动（宽屏左栏 / 与右栏并发滚动检测）
  final ScrollController _detailLeftScrollController = ScrollController();

  /// 详情页右栏滚动（宽屏）
  final ScrollController _detailRightScrollController = ScrollController();

  /// 详情页单栏下方信息区滚动
  final ScrollController _detailMobileScrollController = ScrollController();
  bool _showDetailScrollToTop = false;

  /// Windows 宽屏分栏：当前选中的播放线路
  int _desktopRouteIndex = 0;

  /// 详情页进度条拖动：仅更新 UI，不触发 mpv seek。
  bool _scrubbingProgress = false;
  Duration _scrubPreviewPosition = Duration.zero;

  Timer? _scrubFastSeekTimer;
  Duration? _scrubFastSeekTarget;

  final PlaybackUrlResolver _playbackUrlResolver = PlaybackUrlResolver();
  final PlaybackRouteSelector _playbackRouteSelector = PlaybackRouteSelector();
  String? _preloadTriggeredKey;

  /// 已对当前播放 URL 尝试过字幕自动匹配（避免重复请求）。
  String? _subtitleAutoMatchedForUrl;

  /// 水平滑动快进/快退：累计秒数（松手时应用，避免从文案解析）。
  double _horizontalSeekDragSeconds = 0;

  /// 水平滑动快进/快退：平滑后的手指速度（px/s）。
  ///
  /// 按手速衰减每像素对应的时长——慢拖精细、快扫粗调，防止一甩手指
  /// 就跳过几分钟（2026-10-18 用户反馈修复）。
  double _seekDragVelocity = 0;

  /// 上一次水平滑动 update 的时间戳（算瞬时手速用）。
  DateTime? _lastSeekDragAt;

  /// 长时间缓冲后尝试切换线路
  Timer? _routeFallbackTimer;

  final DetailFullscreenOrientationController _fullscreenOrientation =
      DetailFullscreenOrientationController();

  final GlobalKey _speedButtonKey = GlobalKey();

  final DlnaService _dlnaService = DlnaService();
  final DlnaPlaybackUrlResolver _dlnaUrlResolver = DlnaPlaybackUrlResolver();

  /// 递增序号，避免并发 [_playEpisodeAsync] 后发起播覆盖断点续播。
  int _episodePlaySeq = 0;

  /// 首帧及换片首帧内避免在 [build] 期间 `notifyListeners`：先显示骨架屏，再在 [addPostFrameCallback] 里 [primeDetailLoad]。
  bool _deferDetailPrime = true;

  /// 本路由已加载的影片（叠层磁力详情改写全局 Provider 时仍用于展示）。
  Movie? _pageMovie;

  /// 本页「加载会话」序号：每次进入/换片自增，传给 [MovieProvider.loadMovieDetail]
  /// 并与之绑定的 [_detailSession] 比对，详情页据此认领属于自己的 currentMovie，
  /// 既防跨页/跨源串片，又允许自动换源后身份（id/sourceId）变化仍被本页采纳。
  int _expectedDetailSession = 0;

  static const List<DeviceOrientation> _mobilePortraitOrientations =
      DetailVideoLayout.portraitOrientations;

  // ========== 模块实例 ==========

  /// 播放器模块
  final DetailPlayer _playerModule = DetailPlayer();

  /// 磁力搜索模块
  final DetailTorrent _torrentModule = DetailTorrent();

  /// 缓存管理模块
  final DetailCache _cacheModule = DetailCache();

  bool get _isMagnetDetailEntry =>
      widget.sourceId == AppConstants.magnetDetailSourceId ||
      widget.movie?.sourceId == AppConstants.magnetDetailSourceId;

  /// 无对应 CMS 源的 sourceId（磁力占位条目）。
  ///
  /// 刻意声明为**实例方法**而非 `static`：本类的 part 全是
  /// `extension on _DetailPageState`，在 extension 里引用 static 成员必须写成
  /// `_DetailPageState.xxx`，否则报 UNQUALIFIED_REFERENCE_TO_STATIC_MEMBER_OF_EXTENDED_TYPE。
  bool _isLocalSourceId(String id) => id == AppConstants.magnetDetailSourceId;

  /// **本地条目**：片源与详情都已由上层构造好（磁力占位条目），
  /// 没有对应的 CMS 源可查，因此跳过切源与 `loadMovieDetail`。
  bool get _isLocalDetailEntry =>
      _isLocalSourceId(widget.sourceId) ||
      _isLocalSourceId(widget.movie?.sourceId ?? '');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      AppRoutes.detailRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    _routeFallbackTimer?.cancel();
    unawaited(_playerModule.pause());
  }

  @override
  void didPopNext() {
    final mp = context.read<MovieProvider>();
    // 用加载会话而非 id 判断：自动换源后身份会变化，但只要仍是本页会话产生的
    // currentMovie 就保留（不会误覆盖成旧占位片）。
    if (mp.detailSession != _expectedDetailSession && _pageMovie != null) {
      mp.completeDetailWithMovie(_pageMovie!);
    }
  }

  bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get _isAndroidPlatform => !kIsWeb && Platform.isAndroid;

  /// 仅 Android / iOS 播放器内锁屏；Windows 等桌面端不提供。
  bool get _supportsPlayerScreenLock => _isMobilePlatform;

  /// Android 全屏时左右各一锁钮，便于横屏拇指操作。
  bool get _playerLockButtonsOnBothSides => _isAndroidPlatform;

  bool get _isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// 设置提供者（用于监听硬解档位 / 视频输出后端的变化）。
  SettingsProvider? _settingsProvider;

  /// 上次已下发给播放器的硬解档位与视频输出后端。
  ///
  /// 用来判断「设置真的变了」——SettingsProvider 任何一次 notifyListeners
  /// 都会触发监听回调，不能每次都重下参数。
  ///
  /// ⚠️ 必须声明在 State 类里：detail_page_playback.dart 等 part 文件是
  /// `extension on _DetailPageState`，**扩展不能声明实例字段**（编译期报错）。
  HwDecodeMode? _appliedHwDecodeMode;
  VideoOutputMode? _appliedVideoOutputMode;

  /// 上次应用的缓冲字节数（挡位变了要热更新 mpv 的 demuxer 上限）。
  int? _appliedBufferBytes;

  @override
  void initState() {
    super.initState();
    // 前后台：本页是「后台播放」的唯一决策点（media_kit 自带的
    // pauseUponEnteringBackgroundMode 已在 Video 里关掉）。
    WidgetsBinding.instance.addObserver(this);
    // 全局 HardwareKeyboard handler 不依赖焦点树：切全屏 / 播放器重建后
    // 仍能把 ESC、空格送到本页（旧的 KeyboardListener 会随子树卸载失焦）。
    _globalKeyHandler = _handleGlobalKeyEvent;
    HardwareKeyboard.instance.addHandler(_globalKeyHandler);
    _detailLeftScrollController.addListener(_onDetailScrollFab);
    _detailRightScrollController.addListener(_onDetailScrollFab);
    _detailMobileScrollController.addListener(_onDetailScrollFab);
    // 监听设置变化：用户改完「硬解档位 / 视频输出后端」返回后立即生效
    // （此前详情页从不监听 SettingsProvider，改了要等切集才生效）。
    _settingsProvider = context.read<SettingsProvider>();
    _settingsProvider!.addListener(_onSettingsChanged);
    // 初始化模块
    _initModules();
    // 播放活跃度 → 自动缓冲挡位的 10 分钟评估定时器。
    _playerModule.onPlaybackActiveChanged = _onPlaybackActiveChanged;

    // primeDetailLoad 须在首帧之后调用，否则会触发「build 期间 notifyListeners」异常
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_isLocalDetailEntry) {
        if (widget.movie != null) {
          _pageMovie = widget.movie;
          context.read<MovieProvider>().completeDetailWithMovie(widget.movie!);
        }
      } else {
        context.read<MovieProvider>().primeDetailLoad(widget.movieId);
      }
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
    _pageMovie = widget.movie;
    _torrentModule.resetForNewMovie();
    unawaited(_resetPlayerForDetailChange());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_isLocalDetailEntry) {
        if (widget.movie != null) {
          _pageMovie = widget.movie;
          context.read<MovieProvider>().completeDetailWithMovie(widget.movie!);
        }
      } else {
        context.read<MovieProvider>().primeDetailLoad(widget.movieId);
      }
      setState(() => _deferDetailPrime = false);
      await _bootstrapDetailPage();
    });
  }

  /// 前后台切换：本页是「后台播放」的唯一决策点。
  ///
  /// media_kit 自带的 `pauseUponEnteringBackgroundMode` 已在 Video 组件里关掉
  /// （它的默认行为是「切后台自动暂停 + 回前台不恢复」，实测 3/3 复现），
  /// 这里按用户设置决定：
  /// - 开了后台播放 → 不暂停，并拉起前台服务防止进程被系统 freeze；
  /// - 关了后台播放 → 暂停，回到前台自动恢复。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final allowBackground = _settingsProvider?.backgroundPlayback ?? true;
    final isPlaying = _playerModule.isPlaying;

    final action = decideBackgroundPlaybackAction(
      state: state,
      backgroundPlaybackAllowed: allowBackground,
      isPlaying: isPlaying,
      pausedByBackground: _pausedByBackground,
    );

    switch (action) {
      case BackgroundPlaybackAction.pause:
        _pausedByBackground = true;
        DebugLog.log(
          'Lifecycle',
          '进入后台且后台播放关闭 → 暂停（pos=${_playerModule.position.inSeconds}s）',
          flush: true,
        );
        unawaited(_playerModule.pause());
        break;
      case BackgroundPlaybackAction.resume:
        _pausedByBackground = false;
        DebugLog.log(
          'Lifecycle',
          '回到前台 → 恢复播放（pos=${_playerModule.position.inSeconds}s）',
          flush: true,
        );
        unawaited(_playerModule.resume());
        break;
      case BackgroundPlaybackAction.none:
        break;
    }

    // 前台服务：只有「要后台播放 + 真的在播」才需要。
    if (shouldHoldForegroundService(
      state: state,
      backgroundPlaybackAllowed: allowBackground,
      isPlaying: isPlaying,
    )) {
      final title = widget.movie?.name ?? widget.displayTitleHint ?? '';
      DebugLog.log('Lifecycle', '启动后台播放前台服务 title=$title', flush: true);
      unawaited(BackgroundPlaybackService.start(
        title: title.isEmpty ? null : title,
        text: '正在后台播放',
      ));
    } else if (state == AppLifecycleState.resumed) {
      unawaited(BackgroundPlaybackService.stop());
    }
  }

  /// 播放活跃度变化：自动缓冲挡位只在「有媒体在跑」时每 10 分钟评估一次。
  void _onPlaybackActiveChanged(bool active) {
    final settings = _settingsProvider;
    if (settings == null) return;
    if (active) {
      unawaited(settings.startBufferAutoTune());
    } else {
      settings.stopBufferAutoTune();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 页面销毁 = 播放结束：自动缓冲挡位评估和前台服务一起收掉。
    _playerModule.onPlaybackActiveChanged = null;
    _settingsProvider?.stopBufferAutoTune();
    // 页面销毁 = 播放结束，前台服务必须一起收掉，否则会留下一条
    // 点不掉的「正在后台播放」幽灵通知。
    unawaited(BackgroundPlaybackService.stop());
    AppRoutes.detailRouteObserver.unsubscribe(this);
    _settingsProvider?.removeListener(_onSettingsChanged);
    _stopProgressPersistTimer();
    _routeFallbackTimer?.cancel();
    _fullscreenOrientation.dispose();
    _scrubFastSeekTimer?.cancel();

    final wasFullScreen = _playerModule.isFullScreen;
    if (_isDesktopPlatform && wasFullScreen) {
      unawaited(windowManager.setFullScreen(false));
    }
    if (wasFullScreen && _isMobilePlatform) {
      // 兜底：全屏时直接退出页面（系统返回/路由 pop）不会走 _applyDetailFullscreen，
      // 这里必须把挖孔绘制模式一并复原，否则退出后其它页面会被挖孔遮挡。
      unawaited(_applyCutoutFullscreen(false));
      unawaited(_restoreSystemUiAfterFullScreen());
    }

    _playerModule.onUiChanged = null;
    _playerModule.onPlaybackEnded = null;
    _playerModule.onBufferingChangedUi = null;
    _playerModule.onSeekLandedUi = null;
    _playerModule.onPlaybackProgress = null;
    _playerModule.onVideoDimensionsChanged = null;
    unawaited(_dlnaService.disconnectDevice());
    _playerModule.dispose();
    _torrentModule.dispose();
    _cacheModule.dispose();

    // 释放滚动控制器和焦点节点
    _detailLeftScrollController.removeListener(_onDetailScrollFab);
    _detailRightScrollController.removeListener(_onDetailScrollFab);
    _detailMobileScrollController.removeListener(_onDetailScrollFab);
    _detailLeftScrollController.dispose();
    _detailRightScrollController.dispose();
    _detailMobileScrollController.dispose();
    HardwareKeyboard.instance.removeHandler(_globalKeyHandler);
    _keyboardFocusNode.dispose();
    _routeFallbackTimer?.cancel();

    if (!kIsWeb) {
      unawaited(ScreenBrightness().resetApplicationScreenBrightness());
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final movieProvider = context.watch<MovieProvider>();
    final displayMovie = _displayMovie(movieProvider);
    final showShimmer = _shouldShowDetailShimmer(movieProvider);
    final showError = _shouldShowDetailError(movieProvider);
    final l10n = AppLocalizations.of(context)!;

    // 焦点锚点放在最外层：全屏切换只换 body 子树，这个 Focus 一直挂载。
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_playerModule.isFullScreen) {
          unawaited(_toggleFullScreen());
          return;
        }
        unawaited(_leaveDetailPage());
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        floatingActionButton: (displayMovie != null && !_playerModule.isFullScreen)
            ? Padding(
                // 用 Scaffold FAB 系统承载，天然避让 SnackBar / 底部弹层；
                // 底部加安全区内边距，等价于原来的 safeAreaBottom + 16。
                // 「回到顶部」与「下载」包在同一个盒子里，作为一个整体同步移动。
                padding:
                    EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_showDetailScrollToTop)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: PlayerOverlayIconButton(
                          icon: Icons.vertical_align_top_rounded,
                          tooltip: l10n.homeScrollToTopTooltip,
                          onTap: _scrollDetailContentToTop,
                          iconSize: 22,
                          padding: 12,
                        ),
                      ),
                    if (!kIsWeb && !_isMagnetDetailEntry)
                      DetailPlayerCacheFab(
                        movieId: displayMovie!.id,
                        sourceId: _detailSourceId(displayMovie),
                        episodeIndex: _playerModule.currentEpisodeIndex,
                        placement: DetailCacheFabPlacement.pageCorner,
                        isFullScreen: false,
                        bottomOffset: 0,
                        onTap: () {
                          _openCachePanel(displayMovie);
                        },
                      ),
                  ],
                ),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        body: showShimmer
            ? const DetailShimmer()
            : showError
                ? Column(
                    children: [
                      // 返回按钮（错误页也能返回）
                      AppBar(
                        backgroundColor:
                            Theme.of(context).scaffoldBackgroundColor,
                        elevation: 0,
                        leading: IconButton(
                          icon: Icon(
                            Icons.arrow_back,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          onPressed: () {
                            if (_playerModule.isFullScreen) {
                              unawaited(_toggleFullScreen());
                            } else {
                              unawaited(_leaveDetailPage());
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: app_widgets.ErrorWidget(
                          message: movieProvider.errorMessage.isEmpty
                              ? l10n.detailLoadError
                              : movieProvider.errorMessage,
                          messageColor: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withValues(alpha: 0.75),
                          iconColor: Theme.of(context).colorScheme.error,
                          onRetry: _loadData,
                        ),
                      ),
                    ],
                  )
                : _buildMainLayout(displayMovie!),
        ),
      ),
    );
  }

  static const List<double> _kSpeedSteps = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];
}
