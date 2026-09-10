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
        LogicalKeyboardKey,
        SystemChrome,
        SystemUiMode;
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';
import '../../services/subtitle_service.dart';
// 图片缓存
import 'package:cached_network_image/cached_network_image.dart';

import '../../utils/web_http_stub.dart'
    if (dart.library.html) '../../utils/web_http.dart' as web_http;
import '../../utils/cache_speed_formatter.dart';
import '../../utils/episode_display_label.dart';
import '../../utils/magnet_episode_parser.dart';
import '../../config/constants.dart';
import '../../config/routes.dart';
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
import '../../services/playback_route_selector.dart';
import '../../services/playback_strategy.dart';
import '../../services/playback_start_seek_exception.dart';
import '../../services/playback_url_resolver.dart';
import '../../services/magnet_detail_enrichment_service.dart';
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
import 'detail_magnet_playback.dart';
import 'playback_error_type.dart';

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

class _DetailPageState extends State<DetailPage> with RouteAware {
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

  /// 未配置 OpenSubtitles Key 的提示是否已在本次会话弹过（避免反复打扰）。
  bool _subtitleNoKeyHintShown = false;

  /// 水平滑动快进/快退：累计秒数（松手时应用，避免从文案解析）。
  double _horizontalSeekDragSeconds = 0;

  /// 长时间缓冲后尝试切换线路
  Timer? _routeFallbackTimer;

  final DetailFullscreenOrientationController _fullscreenOrientation =
      DetailFullscreenOrientationController();

  final GlobalKey _speedButtonKey = GlobalKey();

  final DlnaService _dlnaService = DlnaService();
  final DlnaPlaybackUrlResolver _dlnaUrlResolver = DlnaPlaybackUrlResolver();

  /// 磁力播放进行中（防止自动播放与手动点击并发触发原生层崩溃）
  bool _magnetPlayRunning = false;

  /// 递增序号，避免并发 [_playEpisodeAsync] 后发起播覆盖断点续播。
  int _episodePlaySeq = 0;

  /// 首帧及换片首帧内避免在 [build] 期间 `notifyListeners`：先显示骨架屏，再在 [addPostFrameCallback] 里 [primeDetailLoad]。
  bool _deferDetailPrime = true;

  /// 本路由已加载的影片（叠层磁力详情改写全局 Provider 时仍用于展示）。
  Movie? _pageMovie;

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

  bool _isMagnetPlaybackActive() {
    if (!_isMagnetDetailEntry) return false;
    return _playerModule.currentPlayUrl != null ||
        _playerModule.magnetSourcePreparing ||
        (_playerModule.torrentStep > 0 && _playerModule.torrentStep < 4);
  }

  bool _showMagnetPrepIndicator() {
    if (!_isMagnetDetailEntry) return false;
    return _playerModule.magnetSourcePreparing ||
        (_playerModule.torrentStep > 0 && _playerModule.torrentStep < 4);
  }

  Movie? _displayMovie(MovieProvider mp) {
    final cm = mp.currentMovie;
    if (cm != null && cm.id == widget.movieId) {
      _pageMovie = cm;
      return cm;
    }
    return _pageMovie;
  }

  bool _shouldShowDetailShimmer(MovieProvider mp) {
    if (_deferDetailPrime) return true;
    if (_displayMovie(mp) != null) return false;
    final cm = mp.currentMovie;
    if (cm != null && cm.id != widget.movieId) return false;
    return mp.isLoadingDetail;
  }

  bool _shouldShowDetailError(MovieProvider mp) {
    if (_displayMovie(mp) != null) return false;
    if (_shouldShowDetailShimmer(mp)) return false;
    return mp.errorMessage.isNotEmpty;
  }

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
    if (mp.currentMovie?.id != widget.movieId && _pageMovie != null) {
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

  double _detailPlayerMaxHeight(double availableHeight) {
    return availableHeight *
        DetailVideoLayout.detailMaxHeightFactorForPlatform(
          isWeb: kIsWeb,
          videoWidth: _playerModule.videoWidth,
          videoHeight: _playerModule.videoHeight,
        );
  }

  double _detailPlayerSlotHeight(double columnWidth, double maxHeight) {
    if (_isAndroidPlatform && !_playerModule.isFullScreen) {
      final portraitHeight =
          DetailVideoLayout.androidPortraitDetailPlayerHeight(
        screenHeight: MediaQuery.sizeOf(context).height,
        videoWidth: _playerModule.videoWidth,
        videoHeight: _playerModule.videoHeight,
      );
      if (portraitHeight != null) return portraitHeight;
    }
    return DetailVideoLayout.detailPlayerSlotHeight(
      columnWidth: columnWidth,
      maxHeight: maxHeight,
      videoWidth: _playerModule.videoWidth,
      videoHeight: _playerModule.videoHeight,
    );
  }

  /// 全屏时按片源横竖屏允许旋转：横屏片源 Android 仅锁左右横屏，避免先横后竖。
  Future<void> _applyMobileFullscreenOrientations() async {
    await _fullscreenOrientation.applyMobileFullscreen(
      isMobilePlatform: _isMobilePlatform,
      isAndroidPlatform: _isAndroidPlatform,
      player: _playerModule,
      isMounted: () => mounted,
    );
  }

  void _scheduleMobileFullscreenOrientationSync() {
    _fullscreenOrientation.scheduleMobileSync(
      isMobilePlatform: _isMobilePlatform,
      isAndroidPlatform: _isAndroidPlatform,
      player: _playerModule,
      isMounted: () => mounted,
    );
  }

  Future<void> _applyMobileNonFullscreenOrientations() async {
    await _fullscreenOrientation.applyMobileNonFullscreen(
      isMobilePlatform: _isMobilePlatform,
      portraitOrientations: _mobilePortraitOrientations,
    );
  }

  /// 窄屏：多线路时常显线路按钮；单线路仍仅在全屏播放器 chrome 显示（详情 Tab 可切换）。
  bool _showRoutePickerInPlayerChrome(BuildContext context, Movie movie) {
    final sw = MediaQuery.sizeOf(context).width;
    final useWideDetailSplit = sw >= _kDetailDesktopBreakpointWidth &&
        (kIsWeb ||
            (!kIsWeb &&
                (Platform.isWindows || Platform.isLinux || Platform.isMacOS)));
    if (useWideDetailSplit) return false;
    if (movie.playRoutes.length > 1) return true;
    return _playerModule.isFullScreen;
  }

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
      if (_isMagnetDetailEntry) {
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
      if (_isMagnetDetailEntry) {
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

  /// 切源、写入路由传入的 [Movie]、拉取详情（供首次进入与 [didUpdateWidget] 复用）。
  Future<void> _bootstrapDetailPage() async {
    final isMagnetDetail = _isMagnetDetailEntry;

    // 历史/收藏带有的 sourceId 与全局当前源不一致时，必须先切源再拉详情；
    // 各 CMS 的 vod_id 仅在本站唯一，换源用同一 id 会打开完全错误的片子。
    // 磁力占位详情无 CMS 源，跳过切源。
    if (widget.sourceId.isNotEmpty && !isMagnetDetail) {
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
      _pageMovie = widget.movie;
      context.read<MovieProvider>().setCurrentMovie(widget.movie!);
    }

    if (isMagnetDetail) {
      final movie = widget.movie ?? _pageMovie;
      if (movie != null) {
        _pageMovie = movie;
        context.read<MovieProvider>().completeDetailWithMovie(movie);
      }
      if (!mounted) return;
      if (movie != null) {
        _syncWatchHistory(movie);
        if (mounted) setState(() {});
        unawaited(_enrichMagnetDetailMovie(movie));
        unawaited(_tryAutoPlayOnEnter(movie));
      }
      return;
    }

    if (!mounted) return;
    await _loadData();
    if (!mounted) return;
    _loadRecommendations();

    final loaded = context.read<MovieProvider>().currentMovie;
    if (loaded != null && loaded.id == widget.movieId) {
      _pageMovie = loaded;
      if (mounted) {
        _syncWatchHistory(loaded);
        _applyInitialEpisodeFromRoute(loaded);
        if (_playerModule.pendingResumePosition == null) {
          _applyPreferredRouteFromSettings(loaded);
        }
        setState(() {});
      }
      final isMagnetDetail =
          widget.sourceId == AppConstants.magnetDetailSourceId ||
              loaded.sourceId == AppConstants.magnetDetailSourceId;
      if (!isMagnetDetail) {
        unawaited(_scheduleDeferredMagnetSearch(loaded));
      }
      unawaited(_tryAutoPlayOnEnter(loaded));
    }
  }

  /// 详情加载完成后自动起播：有历史则断点续播，否则从当前线路第 1 集开始。
  Future<void> _tryAutoPlayOnEnter(Movie movie) async {
    if (kIsWeb) return;
    if (!mounted) return;
    if (!context.read<SettingsProvider>().autoPlayOnDetailEnter) return;
    if (_playerModule.currentPlayUrl != null) return;
    if (_playerModule.isOpeningMedia) return;

    final magnetUri = _magnetUriForPlayback(movie);
    if (_isMagnetDetailEntry && magnetUri.isNotEmpty) {
      const ri = 0;
      final ei = _episodeIndexForResume(movie, ri);
      await _playMagnet(
        magnetUri,
        movie,
        episodeIndex: ei,
      );
      return;
    }

    if (movie.playRoutes.isEmpty) return;

    final preferredRoute =
        (_playerModule.resumeTargetRouteIndex ?? _desktopRouteIndex)
            .clamp(0, movie.playRoutes.length - 1);
    final ei = _episodeIndexForResume(movie, preferredRoute);
    final ri =
        await _resolvePlayRouteIndex(movie, ei, preferred: preferredRoute);
    if (!mounted) return;
    _playEpisode(ri, ei);
  }

  Future<int> _resolvePlayRouteIndex(
    Movie movie,
    int episodeIndex, {
    int? preferred,
  }) async {
    if (movie.playRoutes.isEmpty) return 0;
    final fallback =
        (preferred ?? _desktopRouteIndex).clamp(0, movie.playRoutes.length - 1);

    final resumeRoute = _playerModule.resumeTargetRouteIndex;
    final resumeEpisode = _playerModule.resumeTargetEpisodeIndex;
    if (resumeRoute != null &&
        resumeEpisode != null &&
        episodeIndex == resumeEpisode) {
      final rr = resumeRoute.clamp(0, movie.playRoutes.length - 1);
      final eps = movie.playRoutes[rr].episodes;
      if (resumeEpisode >= 0 && resumeEpisode < eps.length) {
        return rr;
      }
    }

    if (movie.playRoutes.length < 2) return fallback;

    final settings = context.read<SettingsProvider>();
    return _playbackRouteSelector.selectBestRoute(
      movie: movie,
      episodeIndex: episodeIndex,
      strategy: settings.playbackStrategy,
      defaultQuality: settings.defaultQuality,
      fallbackIndex: fallback,
    );
  }

  void _maybePreloadNextEpisode(Duration position, Duration duration) {
    if (duration <= Duration.zero) return;
    if (position.inMilliseconds / duration.inMilliseconds < 0.8) return;
    if (!context.read<SettingsProvider>().preloadNextEpisode) return;

    final movie = context.read<MovieProvider>().currentMovie;
    if (movie == null || movie.playRoutes.isEmpty) return;

    final ri = _desktopRouteIndex.clamp(0, movie.playRoutes.length - 1);
    final route = movie.playRoutes[ri];
    final next = _playerModule.currentEpisodeIndex + 1;
    if (next >= route.episodes.length) return;

    final key = '${movie.id}_${ri}_$next';
    if (_preloadTriggeredKey == key) return;
    _preloadTriggeredKey = key;

    final settings = context.read<SettingsProvider>();
    unawaited(
      _playbackUrlResolver.prefetchEpisodeUrl(
        episodeUrl: route.episodes[next].url,
        movieId: movie.id,
        episodeIndex: next,
        sourceId: _detailSourceId(movie),
        strategy: settings.playbackStrategy,
        prefetchEnabled: settings.playbackPrefetch,
      ),
    );
  }

  Future<void> _applyPlayerPlaybackTuning() async {
    if (kIsWeb || !mounted) return;
    final settings = context.read<SettingsProvider>();
    await _playerModule.playerService.applyPlaybackStrategy(
      PlaybackStrategyConfig.fromKey(settings.playbackStrategy),
      hardwareDecode: settings.hardwareDecode,
    );
  }

  void _scrubFastSeekThrottled(Duration target) {
    _scrubFastSeekTarget = target;
    if (_scrubFastSeekTimer?.isActive == true) return;
    final throttleMs =
        _playerModule.playerService.strategyConfig.scrubSeekThrottleMs;
    _scrubFastSeekTimer = Timer(Duration(milliseconds: throttleMs), () {
      final t = _scrubFastSeekTarget;
      if (!mounted || t == null || _playerModule.currentPlayUrl == null) {
        return;
      }
      unawaited(_playerModule.playerService.seekFast(t));
      _scrubFastSeekTarget = null;
    });
  }

  String _detailSourceId(Movie movie) {
    if (widget.sourceId.isNotEmpty) return widget.sourceId;
    if (movie.sourceId.isNotEmpty) return movie.sourceId;
    return '';
  }

  void _showCacheSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _openCachePanel(Movie movie) {
    var episodeName = '';
    var episodeIndex = _playerModule.currentEpisodeIndex;
    var episodes = const <Episode>[];
    if (movie.playRoutes.isNotEmpty) {
      final ri = _playerModule.currentRouteIndex.clamp(
        0,
        movie.playRoutes.length - 1,
      );
      final route = movie.playRoutes[ri];
      episodes = route.episodes;
      if (route.episodes.isNotEmpty) {
        episodeIndex = _playerModule.currentEpisodeIndex.clamp(
          0,
          route.episodes.length - 1,
        );
        episodeName = route.episodes[episodeIndex].name;
      }
    }

    final scope = DetailCacheMovieScope(
      movieId: movie.id,
      sourceId: _detailSourceId(movie),
      movieName: movie.name,
      movieCover: movie.cover,
      episodeIndex: episodeIndex,
      episodeName: episodeName,
      episodes: episodes,
      isMagnetDetail: _isMagnetDetailEntry,
      onDownloadEpisode: (ei) => _downloadEpisode(movie, ei),
      onDownloadEpisodes: (indices) => _downloadEpisodes(movie, indices),
    );
    unawaited(_cacheModule.loadCache(context));
    _cacheModule.displayCachePanel(
      context,
      scope,
      belowTopInset: _cachePanelBelowPlayerTop(),
    );
  }

  /// 非全屏移动端：缓存面板从播放器下缘开始，不遮挡画面。
  double? _cachePanelBelowPlayerTop() {
    if (kIsWeb || _playerModule.isFullScreen || !_isMobilePlatform) {
      return null;
    }
    final mq = MediaQuery.of(context);
    final availableHeight = mq.size.height - mq.padding.top - mq.padding.bottom;
    final playerHeight = _detailPlayerSlotHeight(
      mq.size.width,
      _detailPlayerMaxHeight(availableHeight),
    );
    return mq.padding.top + playerHeight;
  }

  Future<void> _downloadEpisode(Movie movie, int ei) async {
    final outcome = await _enqueueEpisodeDownload(
      movie,
      ei,
      showFeedback: true,
    );
    if (!mounted) return;
    _showSnackForDownloadOutcome(outcome);
  }

  Future<void> _downloadEpisodes(Movie movie, List<int> indices) async {
    if (indices.isEmpty) return;
    final outcomes = <EpisodeDownloadOutcome>[];
    for (final ei in indices) {
      final outcome = await _enqueueEpisodeDownload(
        movie,
        ei,
        showFeedback: false,
      );
      outcomes.add(outcome);
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final added = EpisodeDownloadCoordinator.countBatchAdded(outcomes);
    if (added > 0) {
      _showCacheSnack(l10n.detailCacheBatchQueued(added));
    } else {
      _showCacheSnack(l10n.detailCacheBatchNone);
    }
  }

  void _showSnackForDownloadOutcome(EpisodeDownloadOutcome outcome) {
    final l10n = AppLocalizations.of(context)!;
    switch (outcome) {
      case EpisodeDownloadOutcome.queued:
        _showCacheSnack(l10n.detailCacheQueued);
      case EpisodeDownloadOutcome.resumed:
        _showCacheSnack(l10n.detailCacheDownloadStarted);
      case EpisodeDownloadOutcome.alreadyCompleted:
        _showCacheSnack(l10n.detailCacheAlreadyCompleted);
      case EpisodeDownloadOutcome.alreadyActive:
        _showCacheSnack(l10n.detailCacheAlreadyDownloading);
      case EpisodeDownloadOutcome.skipped:
        break;
    }
  }

  Future<EpisodeDownloadOutcome> _enqueueEpisodeDownload(
    Movie movie,
    int ei, {
    required bool showFeedback,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    void feedback(EpisodeDownloadSkipReason reason) {
      if (showFeedback) {
        _showCacheSnack(
          EpisodeDownloadCoordinator.skipMessage(l10n, reason),
        );
      }
    }

    final preflight = EpisodeDownloadCoordinator.preflightSkipReason(
      isMagnetDetail: _isMagnetDetailEntry,
      movie: movie,
      routeIndex: _playerModule.currentRouteIndex,
      episodeIndex: ei,
    );
    if (preflight != null) {
      feedback(preflight);
      return EpisodeDownloadOutcome.skipped;
    }

    final ri = _playerModule.currentRouteIndex.clamp(
      0,
      movie.playRoutes.length - 1,
    );
    final route = movie.playRoutes[ri];
    final episode = route.episodes[ei];
    final sourceId = _detailSourceId(movie);
    final cacheProvider = context.read<CacheProvider>();
    final existing = cacheProvider.findTaskForEpisode(
      movieId: movie.id,
      episodeIndex: ei,
      sourceId: sourceId,
    );
    final existingOutcome =
        EpisodeDownloadCoordinator.outcomeForExistingTask(existing);
    if (existingOutcome == EpisodeDownloadOutcome.alreadyCompleted ||
        existingOutcome == EpisodeDownloadOutcome.alreadyActive) {
      return existingOutcome!;
    }
    if (existingOutcome == EpisodeDownloadOutcome.resumed) {
      await cacheProvider.resumeDownload(existing!.id);
      await cacheProvider.scheduleWaitingDownloads();
      return EpisodeDownloadOutcome.resumed;
    }

    String downloadUrl;
    try {
      downloadUrl = await _playbackUrlResolver.resolveForDownload(
        episode.url,
      );
    } catch (_) {
      if (!context.mounted) return EpisodeDownloadOutcome.skipped;
      feedback(EpisodeDownloadSkipReason.noEpisode);
      return EpisodeDownloadOutcome.skipped;
    }
    if (!context.mounted) return EpisodeDownloadOutcome.skipped;

    final urlSkip = EpisodeDownloadCoordinator.validateResolvedUrl(
      episodePageUrl: episode.url,
      downloadUrl: downloadUrl,
    );
    if (urlSkip != null) {
      feedback(urlSkip);
      return EpisodeDownloadOutcome.skipped;
    }

    await cacheProvider.enqueueEpisodeDownload(
      movieId: movie.id,
      movieName: movie.name,
      movieCover: movie.cover,
      episodeIndex: ei,
      episodeName: episode.name,
      url: downloadUrl,
      pageUrl: episode.url,
      sourceId: sourceId,
    );
    return EpisodeDownloadOutcome.queued;
  }

  WatchHistory? _resolveWatchHistory(Movie movie) {
    return DetailResumeCoordinator.resolveHistory(
      history: context.read<HistoryProvider>(),
      movieId: movie.id,
      sourceId: _detailSourceId(movie),
      magnetUri: widget.initialMagnetUri,
    );
  }

  String _magnetUriForPlayback(Movie movie) {
    if (widget.initialMagnetUri.isNotEmpty) {
      return widget.initialMagnetUri;
    }
    final h = _resolveWatchHistory(movie);
    if (h != null && h.magnetUri.isNotEmpty) return h.magnetUri;
    return '';
  }

  int _episodeIndexForResume(Movie movie, int routeIndex) {
    return DetailResumeCoordinator.episodeIndexForResume(
      movie,
      routeIndex,
      _playerModule,
    );
  }

  String _historyOverlayLabel() {
    return DetailResumeCoordinator.historyOverlayLabel(
      AppLocalizations.of(context)!,
      _playerModule,
    );
  }

  Future<void> _runMagnetSearchForMovie(
    Movie movie, {
    required bool strict,
  }) async {
    final done = _torrentModule.searchForMovieDetail(movie, strict: strict);
    if (mounted) setState(() {});
    await done;
    if (mounted) setState(() {});
  }

  void _maybeAutoMagnetSearch(Movie movie) {
    if (_torrentModule.isSearching || _torrentModule.torrentAutoSearched) {
      return;
    }
    unawaited(_runMagnetSearchForMovie(movie, strict: false));
  }

  /// 详情首屏渲染完成后再搜磁力，避免与海量选集布局争抢主线程。
  Future<void> _scheduleDeferredMagnetSearch(Movie movie) async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    _maybeAutoMagnetSearch(movie);
  }

  Future<void> _resetPlayerForDetailChange() async {
    _torrentModule.magnetPlayVersion++;
    _horizontalSeekDragSeconds = 0;
    if (_playerModule.isFullScreen) {
      if (_isMobilePlatform) {
        await _restoreSystemUiAfterFullScreen();
      } else if (_isDesktopPlatform) {
        await windowManager.setFullScreen(false);
      }
      _playerModule.isFullScreen = false;
    }
    _stopProgressPersistTimer();
    _routeFallbackTimer?.cancel();
    _scrubFastSeekTimer?.cancel();
    _preloadTriggeredKey = null;
    _playbackUrlResolver.clearParsedCache();
    _episodePlaySeq++;
    await _playerModule.resetPlaybackForNewDetail();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppRoutes.detailRouteObserver.unsubscribe(this);
    _stopProgressPersistTimer();
    _routeFallbackTimer?.cancel();
    _fullscreenOrientation.dispose();
    _scrubFastSeekTimer?.cancel();

    final wasFullScreen = _playerModule.isFullScreen;
    if (_isDesktopPlatform && wasFullScreen) {
      unawaited(windowManager.setFullScreen(false));
    }
    if (wasFullScreen && _isMobilePlatform) {
      unawaited(_restoreSystemUiAfterFullScreen());
    }

    _playerModule.onUiChanged = null;
    _playerModule.onPlaybackEnded = null;
    _playerModule.onBufferingChangedUi = null;
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
    final displayMovie = _displayMovie(movieProvider);
    final showShimmer = _shouldShowDetailShimmer(movieProvider);
    final showError = _shouldShowDetailError(movieProvider);
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
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
        floatingActionButton: (displayMovie != null &&
                !_playerModule.isFullScreen &&
                _showDetailScrollToTop)
            ? FloatingActionButton.small(
                heroTag: 'detail_scroll_top',
                tooltip: l10n.homeScrollToTopTooltip,
                onPressed: _scrollDetailContentToTop,
                child: const Icon(Icons.vertical_align_top_rounded),
              )
            : null,
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
    );
  }

  /// 停止播放并离开详情（返回、系统返回键等统一入口）。
  Future<void> _leaveDetailPage() async {
    _stopProgressPersistTimer();
    final movie = context.read<MovieProvider>().currentMovie;
    if (movie != null &&
        _playerModule.currentPlayUrl != null &&
        !_playerModule.isApplyingResume) {
      await _playerModule.saveProgress(
        context,
        movie,
        sourceId: _detailSourceId(movie),
        routeIndex: _playerModule.currentRouteIndex,
      );
    }
    await _playerModule.stopActivePlayback();
    await _dlnaService.disconnectDevice();
    if (!mounted) return;
    if (_playerModule.isFullScreen) {
      await _applyDetailFullscreen(false);
    }
    if (!mounted) return;
    if (_isMagnetDetailEntry) {
      context.read<MovieProvider>().popDetailSnapshot();
    }
    if (!mounted) return;
    context.pop();
  }

  /// 应用内全屏：播放器独占 [Scaffold.body]（宽分栏下隐藏侧栏；移动端配合 [SystemChrome]）。
  Widget _buildDetailFullscreenPlayerShell(Movie movie) {
    return OrientationBuilder(
      builder: (context, orientation) {
        return ColoredBox(
          color: Colors.black,
          child: SizedBox.expand(
            child: _buildVideoPlayer(movie, 0),
          ),
        );
      },
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

    /// 播放器区域：横屏片源 16:9；竖屏片源按真实比例加高（上限见 [_detailPlayerMaxHeight]）。
    final maxPlayerHeight = _detailPlayerMaxHeight(availableHeight);

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
                    final ph = _detailPlayerSlotHeight(
                      w,
                      _detailPlayerMaxHeight(outer.maxHeight),
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
                            child: DetailDesktopLeftSection(
                              movie: movie,
                              isMagnetDetail: _isMagnetDetailEntry,
                              torrent: widget.torrent,
                              isMagnetPlaying: _isMagnetPlaybackActive(),
                            ),
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
                  onRouteSelected: _selectPlayRoute,
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

    final playerHeight = _detailPlayerSlotHeight(screenWidth, maxPlayerHeight);
    final pageFabBottom = MediaQuery.paddingOf(context).bottom +
        (_showDetailScrollToTop ? 72.0 : 16.0);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              bottom: false,
              left: false,
              right: false,
              child: SizedBox(
                width: screenWidth,
                height: playerHeight,
                child: _buildVideoPlayer(movie, playerHeight),
              ),
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  controller: _detailMobileScrollController,
                  padding: EdgeInsets.fromLTRB(
                    _kDetailMobileContentHorizontalInset,
                    0,
                    _kDetailMobileContentHorizontalInset,
                    _showDetailScrollToTop ? 72 : 64,
                  ),
                  child: RepaintBoundary(
                    child: DetailMovieInfoSection(
                      movie: movie,
                      isMagnetDetail: _isMagnetDetailEntry,
                      torrent: widget.torrent,
                      isMagnetPlaying: _isMagnetPlaybackActive(),
                      selectedRouteIndex: movie.playRoutes.isEmpty
                          ? 0
                          : _playerModule.currentRouteIndex.clamp(
                              0,
                              movie.playRoutes.length - 1,
                            ),
                      playingRouteIndex: movie.playRoutes.isEmpty
                          ? 0
                          : _playerModule.currentRouteIndex.clamp(
                              0,
                              movie.playRoutes.length - 1,
                            ),
                      playingEpisodeIndex: _playerModule.currentEpisodeIndex,
                      onEpisodeSelected: _playEpisode,
                      onRouteSelected: _selectPlayRoute,
                      magnetResults: _torrentModule.torrentSearchResults,
                      magnetLoading: _torrentModule.isSearching,
                      magnetMessage: _torrentModule.searchMessage,
                      onMagnetRefreshStrict: () =>
                          _runMagnetSearchForMovie(movie, strict: true),
                      onMagnetRefreshLoose: () =>
                          _runMagnetSearchForMovie(movie, strict: false),
                      onMagnetTabSelected: () => _maybeAutoMagnetSearch(movie),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (!kIsWeb && !_isMagnetDetailEntry)
          Positioned(
            right: 16,
            bottom: pageFabBottom,
            child: DetailPlayerCacheFab(
              movieId: movie.id,
              sourceId: _detailSourceId(movie),
              episodeIndex: _playerModule.currentEpisodeIndex,
              placement: DetailCacheFabPlacement.pageCorner,
              isFullScreen: false,
              bottomOffset: 0,
              onTap: () => _openCachePanel(movie),
            ),
          ),
      ],
    );
  }

  Widget _buildVideoPlayer(Movie movie, double playerHeight) {
    final l10n = AppLocalizations.of(context)!;
    // 已初始化播放器
    if (_playerModule.videoController != null) {
      final showRoutePickerInPlayerChrome =
          _showRoutePickerInPlayerChrome(context, movie);
      final playerSurface = KeyboardListener(
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
          // L：锁屏（仅 Android / iOS）
          if (_supportsPlayerScreenLock && key == LogicalKeyboardKey.keyL) {
            setState(() {
              if (_playerModule.isScreenLocked) {
                _playerModule.isScreenLocked = false;
                _playerModule.showLockChrome = false;
                _playerModule.lockChromeHideTimer?.cancel();
              } else {
                _playerModule.isScreenLocked = true;
                _playerModule.showLockChrome = true;
              }
            });
            if (_playerModule.isScreenLocked) {
              _startLockChromeHideTimer();
            } else {
              _startHideTimer();
            }
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
              () => _playerModule.showSubtitles = !_playerModule.showSubtitles,
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
          // 移动端触摸会产生 pointer move，若在 onTap 前把控制栏设为显示，onTap 会立刻走「已显示→隐藏」分支。
          onPointerMove:
              _isDesktopPlatform ? (_) => _onPlayerPointerActivity() : null,
          onPointerHover:
              _isDesktopPlatform ? (_) => _onPlayerPointerActivity() : null,
          child: GestureDetector(
            onDoubleTap: () {
              if (_playerModule.showShortcutHelp) return;
              if (_playerModule.isScreenLocked) return;
              if (_playerModule.currentPlayUrl == null) return;
              _togglePlayPause();
              setState(() => _playerModule.showControls = true);
              _startHideTimer();
            },
            // 单击：隐藏控制栏时先显示；已显示时桌面/Web/iOS 可点按切播放，Android 仅双击切播放。
            onTap: () {
              if (_playerModule.showShortcutHelp) return;
              if (_playerModule.isScreenLocked) {
                if (_playerModule.showLockChrome) {
                  setState(() => _playerModule.showLockChrome = false);
                  _playerModule.lockChromeHideTimer?.cancel();
                } else {
                  setState(() => _playerModule.showLockChrome = true);
                  _startLockChromeHideTimer();
                }
                return;
              }
              if (_playerModule.showVolumePopover) {
                setState(() => _playerModule.showVolumePopover = false);
              }
              if (!_playerModule.showControls) {
                setState(() => _playerModule.showControls = true);
                _startHideTimer();
              } else if (_isMobilePlatform) {
                setState(() => _playerModule.showControls = false);
                _playerModule.hideTimer?.cancel();
              } else {
                _togglePlayPause();
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
                        _playerModule.gestureHintIcon = Icons.brightness_medium;
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
                      _horizontalSeekDragSeconds = 0;
                      _playerModule.seekBubbleText = '';
                      _playerModule.showSeekBubble = true;
                    });
                  },
            onHorizontalDragUpdate: _playerModule.isScreenLocked
                ? null
                : (details) {
                    final durationSec = _playerModule.duration.inSeconds;
                    if (durationSec <= 0) return;
                    final screenWidth = MediaQuery.sizeOf(context).width;
                    if (screenWidth <= 0) return;
                    final seekDelta =
                        details.delta.dx / screenWidth * durationSec;
                    _horizontalSeekDragSeconds =
                        (_horizontalSeekDragSeconds + seekDelta).clamp(
                      -durationSec.toDouble(),
                      durationSec.toDouble(),
                    );
                    final previewSec = _horizontalSeekDragSeconds.round();
                    setState(() {
                      _playerModule.seekBubbleText =
                          DetailVideoLayout.formatSeekBubbleSeconds(
                        previewSec,
                      );
                    });
                  },
            onHorizontalDragEnd: _playerModule.isScreenLocked
                ? null
                : (_) {
                    final delta = _horizontalSeekDragSeconds.round();
                    _horizontalSeekDragSeconds = 0;
                    if (delta != 0) {
                      _seekRelative(delta);
                    }
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
            onLongPressEnd:
                _playerModule.isScreenLocked ? null : (_) => _onLongPressEnd(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black,
                    child: _playerModule.isFullScreen
                        ? _buildVideoWidget(0)
                        : ClipRect(
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

                // 顶部渐变遮罩（随控制栏显示/隐藏，避免全屏时顶栏常驻发暗）
                if (_playerModule.showControls && !_playerModule.isScreenLocked)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: _playerModule.isFullScreen
                        ? 88
                        : (_isMobilePlatform && !kIsWeb ? 72 : 80),
                    child: IgnorePointer(
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
                  ),

                // 已创建 VideoController 但尚未 open：封面 + 中心播放（避免 init 后误走「无控制器」分支）
                if (_playerModule.currentPlayUrl == null &&
                    !_playerModule.isScreenLocked &&
                    (movie.playRoutes.isNotEmpty ||
                        (_isMagnetDetailEntry &&
                            _magnetUriForPlayback(movie).isNotEmpty)))
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

                // 控制栏隐藏时保留返回；全屏时与底栏一并隐藏，按 Esc / 单击唤出
                if (_playerModule.videoController != null &&
                    !_playerModule.isScreenLocked &&
                    !_playerModule.showControls &&
                    !_playerModule.isFullScreen)
                  _buildPlayerPersistentBackButton(),

                // 控制栏（带显示/隐藏，锁屏时隐藏）；未 open 片源时不显示底栏与锁钮，避免「空播放器」堆控件
                if (_playerModule.showControls &&
                    !_playerModule.isScreenLocked) ...[
                  // 顶部栏（返回、收藏、分享）
                  _buildPlayerTopBar(
                    movie,
                    showRoutePickerInChrome: showRoutePickerInPlayerChrome,
                  ),
                  if (_playerModule.isFullScreen &&
                      !kIsWeb &&
                      !_isMagnetDetailEntry)
                    DetailPlayerCacheFab(
                      movieId: movie.id,
                      sourceId: _detailSourceId(movie),
                      episodeIndex: _playerModule.currentEpisodeIndex,
                      placement: DetailCacheFabPlacement.playerOverlay,
                      isFullScreen: true,
                      bottomOffset: _playerCacheFabBottomOffset(playerHeight),
                      onTap: () {
                        _openCachePanel(movie);
                        _startHideTimer();
                      },
                    ),
                  if (_playerModule.currentPlayUrl != null) ...[
                    // 底部控制栏（进度条、播放/暂停、时间、倍速、全屏）
                    _buildPlayerControls(
                      movie,
                      showRoutePickerInChrome: showRoutePickerInPlayerChrome,
                      playerHeight: playerHeight,
                    ),
                    // 左侧悬浮锁按钮（Android 左右各一）
                    ..._buildPlayerLockEngageButtons(),
                  ],
                ],

                // 锁屏：侧边解锁按钮（可单击屏幕唤出/隐藏）
                ..._buildPlayerLockReleaseButtons(),

                // 磁力 P2P 准备：仅底部进度条 + 单行文案（避免与中心 loading 叠加）
                if (_showMagnetPrepIndicator()) _buildTorrentProgressBar(),

                // 字幕叠加层
                if (_playerModule.showSubtitles &&
                    _playerModule.currentSubtitleText.isNotEmpty)
                  _buildSubtitleOverlay(),

                // 手势提示（亮度/音量）
                if (_playerModule.showGestureHint) _buildGestureIndicator(),

                // 长按加速提示
                if (_playerModule.showSpeedHint) _buildSpeedHintOverlay(),

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
                              heightFactor:
                                  _playerModule.gestureProgress.clamp(0.0, 1.0),
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

                // 缓冲 / 打开媒体（CMS 线路；磁力走底部进度条，不在此叠中心 loading）
                if (!_isMagnetDetailEntry &&
                    (_playerModule.isBuffering ||
                        _playerModule.isOpeningMedia ||
                        _playerModule.magnetSourcePreparing))
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 36,
                            height: 36,
                            child: ValueListenableBuilder<double>(
                              valueListenable:
                                  _playerModule.openElapsedSeconds,
                              builder: (context, elapsed, _) {
                                // 5s 之内给一个基础圆环；之后切换到缓冲进度反馈。
                                if (elapsed < 5.0) {
                                  return const CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  );
                                }
                                return CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                  value: 0.66,
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _playerModule.isOpeningMedia
                                ? l10n.detailBufferingConnect
                                : l10n.detailBuffering,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_playerModule
                              .openElapsedSeconds.value
                              .isFinite) ...[
                            const SizedBox(height: 4),
                            Text(
                              '已等待 ${_playerModule.openElapsedSeconds.value.toStringAsFixed(0)}s',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
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
                          Text(
                            l10n.detailPlaybackFailed,
                            style: const TextStyle(
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
                                final pos = _playbackPreservePosition();
                                unawaited(
                                  _playerModule.playerService.play(
                                    _playerModule.currentOpenUrl ??
                                        _playerModule.activeStreamUrl ??
                                        _playerModule.currentPlayUrl!,
                                    startAt: pos,
                                  ),
                                );
                                if (pos != null) {
                                  _playerModule.markResumeStartApplied(pos);
                                }
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
                              child: Text(
                                l10n.detailRetry,
                                style: const TextStyle(
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
      );
      if (_playerModule.isFullScreen) {
        return SizedBox.expand(child: playerSurface);
      }
      return SizedBox(
        height: playerHeight,
        width: double.infinity,
        child: playerSurface,
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
          _buildPlayerTopBar(
            movie,
            showRoutePickerInChrome:
                _showRoutePickerInPlayerChrome(context, movie),
          ),

          // 上次观看进度提示（有历史记录时显示）
          if (_playerModule.hasHistory &&
              (_playerModule.lastPlayDuration > 0 ||
                  _playerModule.resumeTargetEpisodeIndex != null))
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
                  _historyOverlayLabel(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ),
            ),

          // B站风格播放按钮：CMS 线路或磁力详情均可手动起播
          if (movie.playRoutes.isNotEmpty ||
              (_isMagnetDetailEntry && _magnetUriForPlayback(movie).isNotEmpty))
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

  Widget _buildVideoWidget(double fallbackHeight) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : (fallbackHeight <= 0 || !fallbackHeight.isFinite
                ? 220.0
                : fallbackHeight);

        final cropFill =
            _playerModule.aspectRatio == DetailVideoLayout.cropFillMarker;
        final letterbox = DetailVideoLayout.shouldLetterbox(
          isFullScreen: _playerModule.isFullScreen,
          aspectRatioMode: _playerModule.aspectRatio,
          cropFill: cropFill,
          videoWidth: _playerModule.videoWidth,
          videoHeight: _playerModule.videoHeight,
          rotate: _playerModule.videoRotate,
        );

        final fit = cropFill
            ? BoxFit.cover
            : (_playerModule.isFullScreen
                ? BoxFit.contain
                : (letterbox ? BoxFit.contain : BoxFit.fitWidth));

        // 关键：Flutter Web 上 media_kit 的 Video 用 HtmlElementView(平台视图)
        // 承载 <video>。平台视图在 Web 上无法正确测量 double.infinity 尺寸，
        // 会导致宿主槽 <flt-platform-view> 塌缩到几像素高，画面露出背景（灰屏）。
        // 这里改为传入有限尺寸，保证平台视图拿到确定的高宽。
        final finiteW = maxW.isFinite && maxW > 0 ? maxW : 640.0;
        final finiteH = maxH.isFinite && maxH > 0 ? maxH : 360.0;
        Widget video = ClipRect(
          child: Video(
            controller: _playerModule.videoController!,
            width: finiteW,
            height: finiteH,
            controls: null,
            fit: fit,
          ),
        );

        if (_playerModule.isFullScreen && !cropFill) {
          video = SizedBox(
            width: maxW,
            height: maxH,
            child: video,
          );
        } else if (letterbox) {
          final ar = DetailVideoLayout.layoutAspectRatio(
            viewportWidth: maxW,
            viewportHeight: maxH,
            videoWidth: _playerModule.videoWidth,
            videoHeight: _playerModule.videoHeight,
            aspectRatioMode: _playerModule.aspectRatio,
            isFullScreen: _playerModule.isFullScreen,
            rotate: _playerModule.videoRotate,
          );
          video = SizedBox(
            width: maxW,
            height: maxH,
            child: Center(
              child: AspectRatio(
                aspectRatio: ar,
                child: video,
              ),
            ),
          );
        } else {
          video = SizedBox(width: maxW, height: maxH, child: video);
        }

        return video;
      },
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
          imageUrl: web_http.webProxiedImageUrl(imageUrl),
          fit: BoxFit.cover,
          errorWidget: (context, url, error) =>
              const ColoredBox(color: Color(0xFF000000)),
        ),
      ),
    );
  }

  Widget _buildPlayerTopBar(
    Movie movie, {
    required bool showRoutePickerInChrome,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final safeTop = MediaQuery.paddingOf(context).top;
    final topInset = _playerModule.isFullScreen ? safeTop : 0.0;
    final compact = _isMobilePlatform && !kIsWeb && !_playerModule.isFullScreen;
    final actionIcons = <Widget>[
      if (_isMobilePlatform && !kIsWeb) ...[
        _buildPlayerTopBarIcon(
          icon: Icons.playlist_play_rounded,
          tooltip: l10n.detailDesktopEpisodes,
          compact: compact,
          onTap: () {
            _showEpisodePickerSheet(movie);
            _startHideTimer();
          },
        ),
        if (showRoutePickerInChrome)
          _buildPlayerTopBarIcon(
            icon: Icons.high_quality_rounded,
            tooltip: l10n.detailPlayerTooltipRouteQuality,
            compact: compact,
            onTap: () {
              _showRouteQualitySheet(movie);
              _startHideTimer();
            },
          ),
        if (Platform.isAndroid)
          _buildPlayerTopBarIcon(
            icon: Icons.cast_rounded,
            tooltip: l10n.designV3TooltipCast,
            compact: compact,
            onTap: () {
              unawaited(_showDlnaSheet(movie));
              _startHideTimer();
            },
          ),
      ],
      if (_dlnaService.isCasting) _buildDlnaCastingChip(l10n),
      _buildPlayerTopBarIcon(
        icon: Icons.favorite_border,
        tooltip: l10n.designV3TooltipFavorite,
        compact: compact,
        onTap: () {
          // 实现收藏功能
          _startHideTimer();
        },
      ),
      _buildPlayerTopBarIcon(
        icon: Icons.share,
        tooltip: l10n.designV3TooltipShare,
        compact: compact,
        onTap: () {
          // 实现分享功能
          _startHideTimer();
        },
      ),
    ];
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, topInset + 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildPlayerTopBarBackButton(),
              ],
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: actionIcons,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  (double pad, double iconSize) _playerTopBarButtonMetrics({
    bool compact = false,
  }) {
    final isFullScreen = _playerModule.isFullScreen;
    if (isFullScreen) return (10.0, 24.0);
    if (compact) return (6.0, 18.0);
    return (8.0, 20.0);
  }

  Widget _buildPlayerTopBarBackButton() {
    final compact = _isMobilePlatform && !kIsWeb && !_playerModule.isFullScreen;
    final (pad, iconSize) = _playerTopBarButtonMetrics(compact: compact);
    return GestureDetector(
      onTap: () {
        if (_playerModule.isFullScreen) {
          unawaited(_toggleFullScreen());
        } else {
          unawaited(_leaveDetailPage());
        }
      },
      child: Container(
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          Icons.arrow_back,
          color: Colors.white,
          size: iconSize,
        ),
      ),
    );
  }

  Widget _buildPlayerTopBarIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    final (pad, iconSize) = _playerTopBarButtonMetrics(compact: compact);
    final outerPad = _playerModule.isFullScreen ? 6.0 : (compact ? 4.0 : 8.0);
    return Padding(
      padding: EdgeInsets.only(left: outerPad),
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.all(pad),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: iconSize,
            ),
          ),
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
              unawaited(_leaveDetailPage());
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

  /// 下载悬浮钮：位于底栏上方，与左右锁屏钮错开。
  double _playerCacheFabBottomOffset(double playerHeight) {
    const controlBarHeight = 76.0;
    const gap = 10.0;
    final mq = MediaQuery.of(context);
    if (!_playerModule.isFullScreen) {
      return controlBarHeight + gap;
    }
    final viewportHeight = mq.size.height;
    final chromeBottom = _playerChromeBottomInset(
      viewportWidth: mq.size.width,
      viewportHeight: viewportHeight,
      isFullScreen: true,
    );
    return chromeBottom + mq.padding.bottom + controlBarHeight + gap;
  }

  /// 根据片源在视口内的实际渲染高度，计算底部操作栏应上移的距离（避免落在黑边里）。
  double _playerChromeBottomInset({
    required double viewportWidth,
    required double viewportHeight,
    required bool isFullScreen,
  }) {
    if (viewportWidth <= 0 || viewportHeight <= 0) {
      return 0;
    }
    if (_playerModule.aspectRatio == DetailVideoLayout.cropFillMarker) {
      return 0;
    }

    final ar = DetailVideoLayout.layoutAspectRatio(
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      videoWidth: _playerModule.videoWidth,
      videoHeight: _playerModule.videoHeight,
      aspectRatioMode: _playerModule.aspectRatio,
      isFullScreen: isFullScreen,
      rotate: _playerModule.videoRotate,
    );
    if (ar <= 0) return 0;

    final boxAspect = viewportWidth / viewportHeight;
    final renderedHeight = boxAspect > ar ? viewportHeight : viewportWidth / ar;
    if (renderedHeight >= viewportHeight - 1) return 0;
    return (viewportHeight - renderedHeight) / 2;
  }

  Widget _buildPlayerControls(
    Movie movie, {
    required bool showRoutePickerInChrome,
    required double playerHeight,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final isMobile = _isMobilePlatform;
    final mq = MediaQuery.of(context);
    final viewportWidth = mq.size.width;
    final viewportHeight =
        _playerModule.isFullScreen ? mq.size.height : playerHeight;
    final chromeBottom = _playerModule.isFullScreen
        ? _playerChromeBottomInset(
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            isFullScreen: true,
          )
        : 0.0;
    return Positioned(
      bottom: chromeBottom,
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
          padding: EdgeInsets.fromLTRB(
            10,
            6,
            10,
            (_playerModule.isFullScreen ? mq.padding.bottom : 0) + 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildProgressBar(),
              Row(
                children: [
                  if (!isMobile) ...[
                    _playerChromeIconButton(
                      icon: Icons.skip_previous_rounded,
                      tooltip: l10n.detailPlayerPrevEpisode,
                      enabled: _canPlayPreviousEpisode(movie),
                      onPressed: _playPreviousEpisode,
                    ),
                  ],
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
                  if (!isMobile)
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${DetailVideoLayout.formatPlaybackDuration(_controlsDisplayPosition())} / ${DetailVideoLayout.formatPlaybackDuration(_playerModule.duration)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_playerModule.cacheSpeed > 0) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.downloading_outlined,
                              color: detailAccentColor(context)
                                  .withValues(alpha: 0.95),
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              CacheSpeedFormatter.format(
                                _playerModule.cacheSpeed,
                              ),
                              style: TextStyle(
                                color: detailAccentColor(context)
                                    .withValues(alpha: 0.95),
                                fontSize: isMobile ? 11 : 10,
                                fontWeight: FontWeight.w500,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ],
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
                  Tooltip(
                    message: l10n.designV3TooltipSpeed,
                    child: Material(
                      key: _speedButtonKey,
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: _showSpeedSelector,
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
                  ),
                  if (!isMobile) ...[
                    if (showRoutePickerInChrome)
                      _playerChromeIconButton(
                        icon: Icons.high_quality_rounded,
                        tooltip: l10n.detailPlayerTooltipRouteQuality,
                        onPressed: () => _showRouteQualitySheet(movie),
                      ),
                    if (Platform.isAndroid)
                      _playerChromeIconButton(
                        icon: Icons.cast_rounded,
                        tooltip: l10n.designV3TooltipCast,
                        onPressed: () => unawaited(_showDlnaSheet(movie)),
                      ),
                    _buildVolumePopoverControl(),
                  ],
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
    final l10n = AppLocalizations.of(context)!;
    return Tooltip(
      message: l10n.detailVolumeTooltip,
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
                                activeTrackColor: detailAccentColor(context),
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
                            _playerModule.isMuted
                                ? l10n.detailUnmute
                                : l10n.detailMute,
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

  Duration _controlsDisplayPosition() {
    if (_scrubbingProgress) return _scrubPreviewPosition;
    final d = _playerModule.duration;
    final p = _playerModule.position;
    if (!_playerModule.isPlaying &&
        d > Duration.zero &&
        p >= d - const Duration(seconds: 2)) {
      return d;
    }
    return p;
  }

  double _timelineFraction() {
    final d = _playerModule.duration.inMilliseconds;
    if (d <= 0) return 0;
    final posMs = _scrubbingProgress
        ? _scrubPreviewPosition.inMilliseconds
        : _controlsDisplayPosition().inMilliseconds;
    if (!_playerModule.isPlaying &&
        _playerModule.currentPlayUrl != null &&
        posMs >= d - 1500) {
      return 1.0;
    }
    return (posMs / d).clamp(0.0, 1.0);
  }

  double _bufferFraction() {
    final d = _playerModule.duration.inMilliseconds;
    if (d <= 0) return 0;
    return (_playerModule.bufferedPosition.inMilliseconds / d).clamp(0.0, 1.0);
  }

  Widget _buildProgressBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        Duration positionFromLocal(Offset local) {
          final w = constraints.maxWidth;
          final dMs = _playerModule.duration.inMilliseconds;
          if (w <= 0 || dMs <= 0) return Duration.zero;
          final f = (local.dx / w).clamp(0.0, 1.0);
          return Duration(milliseconds: (dMs * f).round());
        }

        void previewAt(Offset local) {
          final newPos = positionFromLocal(local);
          setState(() {
            _scrubbingProgress = true;
            _scrubPreviewPosition = newPos;
          });
          _scrubFastSeekThrottled(newPos);
        }

        void commitSeek(Duration newPos, {required bool precise}) {
          _scrubFastSeekTimer?.cancel();
          _scrubFastSeekTarget = null;
          if (_playerModule.currentPlayUrl == null) return;
          final seekFuture = precise
              ? _playerModule.playerService.seekPrecise(newPos)
              : _playerModule.playerService.seekFast(newPos);
          unawaited(
            seekFuture.then((_) {
              if (!mounted) return;
              setState(() {
                _playerModule.position = newPos;
                _scrubbingProgress = false;
              });
            }),
          );
          setState(() {
            _playerModule.position = newPos;
            if (precise) _scrubbingProgress = false;
          });
        }

        return SizedBox(
          height: 22,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) {
              _playerModule.hideTimer?.cancel();
              previewAt(d.localPosition);
            },
            onHorizontalDragUpdate: (d) => previewAt(d.localPosition),
            onHorizontalDragEnd: (_) {
              commitSeek(_scrubPreviewPosition, precise: true);
              _startHideTimer();
            },
            onTapDown: (d) {
              _playerModule.hideTimer?.cancel();
              final target = positionFromLocal(d.localPosition);
              setState(() {
                _scrubbingProgress = true;
                _scrubPreviewPosition = target;
              });
              commitSeek(target, precise: true);
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
                      color: detailAccentColor(context),
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
                        color:
                            detailAccentColor(context).withValues(alpha: 0.9),
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
    final safe = MediaQuery.paddingOf(context);
    final controlsVisible = _playerModule.showControls &&
        !_playerModule.isScreenLocked &&
        _playerModule.currentPlayUrl != null;
    const controlBarHeight = 118.0;
    final bottom = _playerModule.isFullScreen
        ? safe.bottom + (controlsVisible ? controlBarHeight : 20)
        : (controlsVisible ? 88.0 : 40.0);
    return DetailComponents.buildSubtitleOverlay(
      _playerModule.currentSubtitleText,
      fontSize: _playerModule.subtitleFontSize,
      color: _playerModule.subtitleColor,
      bottom: bottom,
      padding: _playerModule.isFullScreen
          ? EdgeInsets.only(left: safe.left, right: safe.right)
          : EdgeInsets.zero,
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
    final t = _playerModule.torrentService;
    return DetailComponents.buildTorrentProgressBar(
      _playerModule.torrentStep,
      _playerModule.torrentMessage,
      downloadSpeed: t.downloadSpeed,
      peers: t.peers,
      seeds: t.seeds,
      bufferPct: t.bufferPct,
      etaFormatted: t.etaFormatted,
      metaWait: t.metaWaitFormatted,
      webFallback: kIsWeb,
    );
  }

  Widget _buildShortcutHelpPanel() {
    return DetailComponents.buildShortcutHelpPanel(
      _playerModule.showShortcutHelp,
      showLockShortcut: _supportsPlayerScreenLock,
      onClose: () {
        setState(() => _playerModule.showShortcutHelp = false);
      },
    );
  }

  void _engagePlayerScreenLock() {
    if (!_supportsPlayerScreenLock) return;
    setState(() {
      _playerModule.isScreenLocked = true;
      _playerModule.showLockChrome = true;
    });
    _startLockChromeHideTimer();
  }

  void _releasePlayerScreenLock() {
    setState(() {
      _playerModule.isScreenLocked = false;
      _playerModule.showLockChrome = false;
    });
    _playerModule.lockChromeHideTimer?.cancel();
    _startHideTimer();
  }

  void _clearUnsupportedPlayerScreenLock() {
    if (_supportsPlayerScreenLock || !_playerModule.isScreenLocked) return;
    _playerModule.isScreenLocked = false;
    _playerModule.showLockChrome = false;
    _playerModule.lockChromeHideTimer?.cancel();
  }

  List<Widget> _buildPlayerLockEngageButtons() {
    if (!_supportsPlayerScreenLock) return const [];
    final l10n = AppLocalizations.of(context)!;
    return [
      _buildPlayerSideLockButton(
        onLeft: true,
        locked: false,
        semanticsLabel: l10n.detailPlayerLockControls,
        onTap: _engagePlayerScreenLock,
      ),
      if (_playerLockButtonsOnBothSides)
        _buildPlayerSideLockButton(
          onLeft: false,
          locked: false,
          semanticsLabel: l10n.detailPlayerLockControls,
          onTap: _engagePlayerScreenLock,
        ),
    ];
  }

  List<Widget> _buildPlayerLockReleaseButtons() {
    if (!_supportsPlayerScreenLock ||
        !_playerModule.isScreenLocked ||
        !_playerModule.showLockChrome) {
      return const [];
    }
    final l10n = AppLocalizations.of(context)!;
    return [
      _buildPlayerSideLockButton(
        onLeft: true,
        locked: true,
        semanticsLabel: l10n.detailPlayerUnlockControls,
        onTap: _releasePlayerScreenLock,
      ),
      if (_playerLockButtonsOnBothSides)
        _buildPlayerSideLockButton(
          onLeft: false,
          locked: true,
          semanticsLabel: l10n.detailPlayerUnlockControls,
          onTap: _releasePlayerScreenLock,
        ),
    ];
  }

  Widget _buildPlayerSideLockButton({
    required bool onLeft,
    required bool locked,
    required String semanticsLabel,
    required VoidCallback onTap,
  }) {
    return Positioned(
      left: onLeft ? 8 : null,
      right: onLeft ? null : 8,
      top: 0,
      bottom: 0,
      child: Center(
        child: Semantics(
          button: true,
          label: semanticsLabel,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                locked ? Icons.lock_outline : Icons.lock_open,
                color: Colors.white70,
                size: 20,
              ),
            ),
          ),
        ),
      ),
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
        sourceId: _detailSourceId(m),
        routeIndex: _playerModule.currentRouteIndex,
      );
    });
  }

  void _syncWatchHistory(Movie movie) {
    final applied = DetailResumeCoordinator.applyHistory(
      _resolveWatchHistory(movie),
      movie,
      _playerModule,
      _desktopRouteIndex,
    );
    _desktopRouteIndex = applied.desktopRouteIndex;
  }

  void _applyInitialEpisodeFromRoute(Movie movie) {
    final ei = widget.initialEpisodeIndex;
    if (ei == null) return;
    if (movie.playRoutes.isEmpty) {
      _playerModule.resumeTargetEpisodeIndex = ei;
      _playerModule.currentEpisodeIndex = ei;
      return;
    }
    final ri = _desktopRouteIndex.clamp(0, movie.playRoutes.length - 1);
    final episodes = movie.playRoutes[ri].episodes;
    if (episodes.isEmpty) return;
    final clamped = ei.clamp(0, episodes.length - 1);
    if (_playerModule.pendingResumePosition != null &&
        _playerModule.resumeTargetEpisodeIndex != null &&
        _playerModule.resumeTargetEpisodeIndex != clamped) {
      return;
    }
    _playerModule.resumeTargetRouteIndex = ri;
    _playerModule.resumeTargetEpisodeIndex = clamped;
    _playerModule.currentEpisodeIndex = clamped;
    _desktopRouteIndex = ri;
  }

  Widget _buildDlnaCastingChip(AppLocalizations l10n) {
    final name = _dlnaService.currentDevice?.name ?? l10n.detailDlnaTitle;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InputChip(
        avatar: const Icon(Icons.cast_connected, size: 18, color: Colors.white),
        label: Text(
          l10n.detailDlnaCastingNamed(name),
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
        deleteIcon: const Icon(Icons.close, size: 16, color: Colors.white70),
        onDeleted: () => unawaited(_stopDlnaCast()),
        backgroundColor: detailAccentColor(context).withValues(alpha: 0.35),
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  void _applyPreferredRouteFromSettings(Movie movie) {
    if (movie.playRoutes.isEmpty) return;
    if (_playerModule.pendingResumePosition != null) return;
    if (_playerModule.resumeTargetRouteIndex != null) return;
    if (_playerModule.hasHistory) return;
    unawaited(() async {
      final idx = await _resolvePlayRouteIndex(movie, 0);
      if (!mounted) return;
      setState(() => _desktopRouteIndex = idx);
    }());
  }

  void _handleDetailPlaybackEnded() {
    if (!mounted) return;
    final movie = context.read<MovieProvider>().currentMovie;
    if (movie != null && _playerModule.currentPlayUrl != null) {
      unawaited(
        _playerModule.saveProgress(
          context,
          movie,
          sourceId: _detailSourceId(movie),
          routeIndex: _playerModule.currentRouteIndex,
        ),
      );
    }
    if (_playerModule.isAutoPlayNext &&
        movie != null &&
        movie.playRoutes.isNotEmpty) {
      final ri = _desktopRouteIndex.clamp(0, movie.playRoutes.length - 1);
      final route = movie.playRoutes[ri];
      if (route.episodes.isEmpty) return;
      final next = _playerModule.currentEpisodeIndex + 1;
      if (next < route.episodes.length) {
        _playEpisode(ri, next);
      }
    }
  }

  void _onPlayerBufferingChanged(bool buffering) {
    _routeFallbackTimer?.cancel();
    if (!buffering) return;
    if (!_playerModule.playback.shouldAllowRouteFallback(
      isMagnet: _playerModule.lastMagnetUri.isNotEmpty ||
          _playerModule.magnetSourcePreparing,
      isApplyingResume: _playerModule.isApplyingResume,
      hasPendingResume: _playerModule.pendingResumePosition != null,
    )) {
      return;
    }
    final movie = context.read<MovieProvider>().currentMovie;
    if (movie == null || movie.playRoutes.length < 2) return;
    if (_playerModule.currentPlayUrl == null) return;
    final fallbackSec = PlaybackStrategyConfig.fromKey(
      context.read<SettingsProvider>().playbackStrategy,
    ).routeFallbackSec;
    _routeFallbackTimer = Timer(Duration(seconds: fallbackSec), () {
      if (!mounted || !_playerModule.isBuffering) return;
      unawaited(_tryFallbackToNextRoute(movie));
    });
  }

  Future<void> _tryFallbackToNextRoute(Movie movie) async {
    if (movie.playRoutes.length < 2) return;
    final ei = _playerModule.currentEpisodeIndex;
    final episodes = movie.playRoutes[_desktopRouteIndex].episodes;
    if (episodes.isEmpty) return;
    final clampedEi = ei.clamp(0, episodes.length - 1);
    final settings = context.read<SettingsProvider>();
    final next = await _playbackRouteSelector.selectBestRoute(
      movie: movie,
      episodeIndex: clampedEi,
      strategy: settings.playbackStrategy,
      defaultQuality: settings.defaultQuality,
      fallbackIndex: (_desktopRouteIndex + 1) % movie.playRoutes.length,
      excludeRouteIndices: {_desktopRouteIndex},
    );
    if (next == _desktopRouteIndex) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(l10n.detailRouteFallbackSnack)),
    );
    _playEpisode(
      next,
      clampedEi,
      preservePosition: _playbackPreservePosition(),
    );
  }

  /// 换线/重试时保留的播放进度（接近片尾则不 seek）。
  Duration? _playbackPreservePosition() {
    return _playerModule.playbackPositionToPreserve();
  }

  void _showRouteQualitySheet(Movie movie) {
    if (movie.playRoutes.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final currentRoute = _playerModule.currentRouteIndex.clamp(
      0,
      movie.playRoutes.length - 1,
    );

    Widget buildRouteList(BuildContext listContext) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        children: [
          for (var i = 0; i < movie.playRoutes.length; i++)
            ListTile(
              title: Text(
                movie.playRoutes[i].name.isEmpty
                    ? l10n.detailRouteLabel(i + 1)
                    : movie.playRoutes[i].name,
                style: const TextStyle(color: Colors.white),
              ),
              trailing: i == currentRoute
                  ? Icon(Icons.check, color: detailAccentColor(listContext))
                  : null,
              onTap: () {
                Navigator.pop(listContext);
                if (i == currentRoute) return;
                _selectPlayRoute(i);
              },
            ),
        ],
      );
    }

    if (_playerModule.isFullScreen) {
      unawaited(
        DetailPlayerSidePanel.show<void>(
          context: context,
          title: l10n.detailPlayerTooltipRouteQuality,
          child: Builder(builder: buildRouteList),
        ),
      );
      _startHideTimer();
      return;
    }

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
                      ? l10n.detailRouteLabel(i + 1)
                      : movie.playRoutes[i].name,
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: i == currentRoute
                    ? const Icon(Icons.check, color: Colors.lightBlueAccent)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  if (i == currentRoute) return;
                  _selectPlayRoute(i);
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildEpisodePickerContent({
    required BuildContext ctx,
    required Movie movie,
    required AppLocalizations l10n,
    required int pickedRoute,
    required ValueChanged<int> onRouteChanged,
    ScrollController? scrollController,
    required bool showTitle,
  }) {
    final episodes = movie.playRoutes[pickedRoute].episodes;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, showTitle ? 12 : 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle)
            Text(
              l10n.detailDesktopEpisodes,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (movie.playRoutes.length > 1) ...[
            SizedBox(height: showTitle ? 10 : 4),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: movie.playRoutes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final selected = i == pickedRoute;
                  final name = movie.playRoutes[i].name.isEmpty
                      ? '${l10n.detailPlayRoutes} ${i + 1}'
                      : movie.playRoutes[i].name;
                  return ChoiceChip(
                    label: Text(name),
                    selected: selected,
                    onSelected: (_) => onRouteChanged(i),
                    selectedColor: detailAccentColor(context),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontSize: 12,
                    ),
                    backgroundColor: Colors.white12,
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  );
                },
              ),
            ),
          ],
          SizedBox(height: showTitle ? 12 : 8),
          Expanded(
            child: episodes.isEmpty
                ? Center(
                    child: Text(
                      l10n.detailDesktopNoEpisodes,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    itemCount: episodes.length,
                    itemBuilder: (context, ei) {
                      final playing =
                          pickedRoute == _playerModule.currentRouteIndex &&
                              ei == _playerModule.currentEpisodeIndex;
                      final ep = episodes[ei];
                      final display = EpisodeDisplayLabel.forEpisode(
                        name: ep.name,
                        index: ei,
                      );
                      return ListTile(
                        dense: true,
                        title: Text(
                          display.primary,
                          style: TextStyle(
                            color: playing
                                ? detailAccentColor(context)
                                : Colors.white,
                            fontWeight:
                                playing ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        subtitle: display.full != display.primary
                            ? Text(
                                display.full,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: playing
                                      ? detailAccentColor(context)
                                          .withValues(alpha: 0.75)
                                      : Colors.white54,
                                  fontSize: 12,
                                ),
                              )
                            : null,
                        trailing: playing
                            ? Icon(
                                Icons.play_arrow_rounded,
                                color: detailAccentColor(context),
                              )
                            : null,
                        onTap: () {
                          Navigator.pop(ctx);
                          _playEpisode(pickedRoute, ei);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showEpisodePickerSheet(Movie movie) {
    if (movie.playRoutes.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    var pickedRoute = _playerModule.currentRouteIndex.clamp(
      0,
      movie.playRoutes.length - 1,
    );

    if (_playerModule.isFullScreen) {
      unawaited(
        DetailPlayerSidePanel.show<void>(
          context: context,
          title: l10n.detailDesktopEpisodes,
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              return _buildEpisodePickerContent(
                ctx: ctx,
                movie: movie,
                l10n: l10n,
                pickedRoute: pickedRoute,
                onRouteChanged: (i) => setModal(() => pickedRoute = i),
                showTitle: false,
              );
            },
          ),
        ),
      );
      _startHideTimer();
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.55,
              minChildSize: 0.35,
              maxChildSize: 0.9,
              builder: (context, scrollController) {
                return _buildEpisodePickerContent(
                  ctx: ctx,
                  movie: movie,
                  l10n: l10n,
                  pickedRoute: pickedRoute,
                  onRouteChanged: (i) => setModal(() => pickedRoute = i),
                  scrollController: scrollController,
                  showTitle: true,
                );
              },
            );
          },
        );
      },
    );
  }

  DetailMagnetPlayback _buildMagnetPlayback() {
    final l10n = AppLocalizations.of(context)!;
    return DetailMagnetPlayback(
      player: _playerModule,
      torrent: _torrentModule,
      isMounted: () => mounted,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
      cancelRouteFallback: () => _routeFallbackTimer?.cancel(),
      applyPlayerTuning: _applyPlayerPlaybackTuning,
      startHideTimer: _startHideTimer,
      startProgressPersistTimer: _startProgressPersistTimer,
      scheduleSubtitleMatch: _maybeAutoMatchSubtitlePlay,
      l10n: l10n,
      onStreamReady: (movie) => _syncDlnaAfterEpisodeChange(movie),
      onTorrentFilesReady: (files) {
        final m = _pageMovie ?? context.read<MovieProvider>().currentMovie;
        if (m != null) _applyMagnetEpisodesFromFiles(m, files);
      },
    );
  }

  void _applyMagnetEpisodesFromFiles(Movie movie, List<TorrentFileItem> files) {
    if (!_isMagnetDetailEntry || files.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final route = MagnetEpisodeParser.buildPlayRoute(
      files,
      routeName: l10n.detailDesktopTabMagnet,
    );
    if (route == null) return;
    final current = _pageMovie ?? movie;
    if (current.playRoutes.isNotEmpty &&
        current.playRoutes.first.episodes.length == route.episodes.length) {
      return;
    }
    final updated = current.copyWith(playRoutes: [route]);
    _pageMovie = updated;
    context.read<MovieProvider>().completeDetailWithMovie(updated);
    if (mounted) setState(() {});
  }

  Future<void> _showDlnaSheet(Movie movie) async {
    if (!Platform.isAndroid || kIsWeb) return;
    final l10n = AppLocalizations.of(context)!;
    if (_playerModule.currentPlayUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.detailDlnaNeedPlayback)),
      );
      return;
    }

    String? episodeUrl;
    if (movie.playRoutes.isNotEmpty) {
      final ri = _playerModule.currentRouteIndex.clamp(
        0,
        movie.playRoutes.length - 1,
      );
      final eps = movie.playRoutes[ri].episodes;
      final ei = _playerModule.currentEpisodeIndex;
      if (ei >= 0 && ei < eps.length) {
        episodeUrl = eps[ei].url;
      }
    }

    if (_playerModule.isFullScreen && _playerModule.isPlaying) {
      await _playerModule.pause();
      if (mounted) setState(() {});
    }
    if (!mounted) return;

    await DetailDlnaSheet.show(
      context: context,
      dlnaService: _dlnaService,
      urlResolver: _dlnaUrlResolver,
      movie: movie,
      currentPlayUrl: _playerModule.currentPlayUrl!,
      activeStreamUrl: _playerModule.activeStreamUrl ??
          _playerModule.torrentService.streamUrl,
      episodeUrl: episodeUrl,
      episodeIndex: _playerModule.currentEpisodeIndex,
      sourceId: _detailSourceId(movie),
      onCast: (device, castUrl) => _startDlnaCast(movie, device, castUrl),
      presentation: _playerModule.isFullScreen
          ? DetailDlnaPresentation.sidePanel
          : DetailDlnaPresentation.compactBottomSheet,
    );
    if (mounted) setState(() {});
  }

  Future<bool> _startDlnaCast(
    Movie movie,
    DlnaDevice device,
    String castUrl,
  ) async {
    await _dlnaService.connectDevice(device);
    final ok = await _dlnaService.castPlay(castUrl, title: movie.name);
    if (ok) {
      await _playerModule.pause();
      if (mounted) setState(() {});
    }
    return ok;
  }

  Future<void> _stopDlnaCast() async {
    await _dlnaService.disconnectDevice();
    if (mounted) setState(() {});
  }

  Future<void> _syncDlnaAfterEpisodeChange(Movie movie) async {
    if (!_dlnaService.isCasting) return;
    String? episodeUrl;
    if (movie.playRoutes.isNotEmpty) {
      final ri = _playerModule.currentRouteIndex.clamp(
        0,
        movie.playRoutes.length - 1,
      );
      final eps = movie.playRoutes[ri].episodes;
      final ei = _playerModule.currentEpisodeIndex;
      if (ei >= 0 && ei < eps.length) {
        episodeUrl = eps[ei].url;
      }
    }
    final result = await _dlnaUrlResolver.resolve(
      currentPlayUrl: _playerModule.currentPlayUrl ?? '',
      activeStreamUrl: _playerModule.activeStreamUrl ??
          _playerModule.torrentService.streamUrl,
      episodeUrl: episodeUrl,
      movieId: movie.id,
      episodeIndex: _playerModule.currentEpisodeIndex,
      sourceId: _detailSourceId(movie),
    );
    if (!result.isSuccess || !mounted) return;
    await _dlnaService.castPlay(result.url!, title: movie.name);
  }

  Future<void> _enrichMagnetDetailMovie(Movie movie) async {
    final enriched = await MagnetDetailEnrichmentService.instance.enrich(
      movie,
      searchHint: widget.displayTitleHint,
      torrentImdbId: widget.torrentImdbId,
    );
    if (!mounted || enriched == null) return;
    _pageMovie = enriched;
    context.read<MovieProvider>().completeDetailWithMovie(enriched);
    if (mounted) setState(() {});
    unawaited(_runMagnetSearchForMovie(enriched, strict: false));
  }

  Future<void> _loadData() async {
    if (_isMagnetDetailEntry) return;
    final movieProvider = context.read<MovieProvider>();
    await movieProvider.loadMovieDetail(widget.movieId);
  }

  void _loadRecommendations() {
    final movie = context.read<MovieProvider>().currentMovie;
    if (movie == null || movie.id != widget.movieId) return;
    unawaited(_fetchAndApplyRecommendations(movie));
  }

  Future<void> _fetchAndApplyRecommendations(Movie movie) async {
    final related = await ApiService().getDetailSideRecommendations(movie);
    if (!mounted) return;
    final provider = context.read<MovieProvider>();
    final current = provider.currentMovie;
    if (current == null || current.id != movie.id) return;
    provider.setCurrentMovie(current.copyWith(relatedMovies: related));
    if (mounted) setState(() {});
  }

  void _startPlay() {
    final movieProvider = context.read<MovieProvider>();
    final movie = _displayMovie(movieProvider) ?? movieProvider.currentMovie;
    if (movie == null) return;

    final magnetUri = _magnetUriForPlayback(movie);
    if (_isMagnetDetailEntry && magnetUri.isNotEmpty) {
      if (_playerModule.currentPlayUrl != null) {
        _togglePlayPause();
        return;
      }
      unawaited(
        _playMagnet(
          magnetUri,
          movie,
          episodeIndex: _episodeIndexForResume(movie, 0),
        ),
      );
      return;
    }

    if (movie.playRoutes.isEmpty) return;
    if (_playerModule.currentPlayUrl != null) {
      _togglePlayPause();
      return;
    }
    final ri = _desktopRouteIndex.clamp(0, movie.playRoutes.length - 1);
    _playEpisode(ri, _episodeIndexForResume(movie, ri));
  }

  Future<void> _playMagnet(
    String magnetUri,
    Movie movie, {
    int episodeIndex = 0,
    int? fileIndex,
  }) async {
    if (_magnetPlayRunning) return;
    _magnetPlayRunning = true;
    try {
      await _buildMagnetPlayback().play(
        magnetUri,
        movie,
        episodeIndex: episodeIndex,
        preferredFileIndex: fileIndex,
      );
    } finally {
      _magnetPlayRunning = false;
    }
  }

  void _playEpisode(
    int routeIndex,
    int episodeIndex, {
    Duration? preservePosition,
  }) {
    unawaited(
      _playEpisodeAsync(
        routeIndex,
        episodeIndex,
        preservePosition: preservePosition,
      ),
    );
  }

  /// 切换播放线路；已是当前线路时不重新加载。
  void _selectPlayRoute(int routeIndex) {
    if (routeIndex == _playerModule.currentRouteIndex &&
        _playerModule.currentPlayUrl != null) {
      if (_desktopRouteIndex != routeIndex) {
        setState(() => _desktopRouteIndex = routeIndex);
      }
      return;
    }
    final movie = context.read<MovieProvider>().currentMovie;
    if (movie == null || routeIndex >= movie.playRoutes.length) return;
    final route = movie.playRoutes[routeIndex];
    if (route.episodes.isEmpty) return;
    final ei = _playerModule.currentEpisodeIndex.clamp(
      0,
      route.episodes.length - 1,
    );
    final pos = _playerModule.effectivePlaybackPosition;
    final preserve =
        _playerModule.currentPlayUrl != null && pos > const Duration(seconds: 2)
            ? pos
            : null;
    _playEpisode(routeIndex, ei, preservePosition: preserve);
  }

  Future<void> _playEpisodeAsync(
    int routeIndex,
    int episodeIndex, {
    Duration? preservePosition,
  }) async {
    final playSeq = ++_episodePlaySeq;
    final movie = context.read<MovieProvider>().currentMovie;
    if (movie == null || routeIndex >= movie.playRoutes.length) return;

    final route = movie.playRoutes[routeIndex];
    if (route.episodes.isEmpty) return;
    if (episodeIndex < 0 || episodeIndex >= route.episodes.length) return;

    final episode = route.episodes[episodeIndex];
    if (_isMagnetDetailEntry &&
        MagnetEpisodeParser.isMagnetFileUrl(episode.url)) {
      final magnetUri = _magnetUriForPlayback(movie);
      if (magnetUri.isEmpty) return;
      final fileIdx = MagnetEpisodeParser.fileIndexFromUrl(episode.url);
      if (fileIdx == null) return;
      if (playSeq != _episodePlaySeq) return;
      setState(() {
        _desktopRouteIndex = routeIndex;
        _playerModule.currentEpisodeIndex = episodeIndex;
        _playerModule.currentRouteIndex = routeIndex;
      });
      await _playMagnet(
        magnetUri,
        movie,
        episodeIndex: episodeIndex,
        fileIndex: fileIdx,
      );
      return;
    }

    if (routeIndex == _playerModule.currentRouteIndex &&
        episodeIndex == _playerModule.currentEpisodeIndex &&
        _playerModule.currentPlayUrl != null &&
        !_playerModule.isOpeningMedia) {
      if (_desktopRouteIndex != routeIndex) {
        setState(() => _desktopRouteIndex = routeIndex);
      }
      final resumeAt = _playerModule.takePendingResumeStart(
        routeIndex: routeIndex,
        episodeIndex: episodeIndex,
      );
      if (resumeAt != null) {
        await _playerModule.playerService.seekPrecise(resumeAt);
        _playerModule.markResumeStartApplied(resumeAt);
        if (mounted) setState(() {});
      }
      return;
    }

    if (playSeq != _episodePlaySeq) return;

    final isNewEpisode = routeIndex != _playerModule.currentRouteIndex ||
        episodeIndex != _playerModule.currentEpisodeIndex ||
        _playerModule.currentPlayUrl == null;

    final matchResume = preservePosition == null &&
        _playerModule.resumeTargetRouteIndex == routeIndex &&
        _playerModule.resumeTargetEpisodeIndex == episodeIndex;

    final knownDuration =
        _playerModule.duration > Duration.zero ? _playerModule.duration : null;
    final openPlan = _playerModule.playback.prepareOpen(
      isNewEpisode: isNewEpisode,
      explicitPreserve: preservePosition,
      pendingResume: _playerModule.pendingResumePosition,
      resumeTargetMatches: matchResume,
      knownDuration: knownDuration,
    );
    final openGeneration = openPlan.generation;

    _playerModule.resetResumeConsumeForNewOpen(
      preservePeak: openPlan.preservePlayhead,
    );

    if (_playerModule.currentPlayUrl != episode.url) {
      _subtitleAutoMatchedForUrl = null;
      _preloadTriggeredKey = null;
    }
    // 非磁力片源不带 release 名，清掉上一个磁力文件残留，避免字幕匹配串味。
    if (!episode.url.toLowerCase().startsWith('magnet:')) {
      _playerModule.currentMagnetFileName = '';
    }
    _playerModule.currentPlayUrl = episode.url;
    _playerModule.currentEpisodeIndex = episodeIndex;
    _playerModule.currentRouteIndex = routeIndex;
    _playerModule.cacheSpeed = 0;
    _playerModule.showReplayOverlay = false;

    if (!matchResume && preservePosition == null) {
      _playerModule.pendingResumePosition = null;
      _playerModule.resumeTargetRouteIndex = null;
      _playerModule.resumeTargetEpisodeIndex = null;
    }

    setState(() {
      _desktopRouteIndex = routeIndex;
    });

    final resolvedUrl = await _playbackUrlResolver.resolveForPlayback(
      episodeUrl: episode.url,
      movieId: movie.id,
      episodeIndex: episodeIndex,
      sourceId: _detailSourceId(movie),
    );
    if (!mounted || playSeq != _episodePlaySeq) return;
    if (openGeneration != _playerModule.playback.openGeneration) return;
    _playerModule.activeStreamUrl = resolvedUrl;

    // 尝试把远端 m3u8 换成本地去广告地址（无广告/失败时原样返回）。
    final openUrl = await _playbackUrlResolver.openUrlForPlayer(resolvedUrl);
    if (!mounted || playSeq != _episodePlaySeq) return;
    if (openGeneration != _playerModule.playback.openGeneration) return;
    _playerModule.currentOpenUrl = openUrl;

    Future<void> openMedia() async {
      if (!mounted || playSeq != _episodePlaySeq) return;
      if (openGeneration != _playerModule.playback.openGeneration) return;
      final resumeAt = openPlan.startAt ??
          _playerModule.takePendingResumeStart(
            routeIndex: routeIndex,
            episodeIndex: episodeIndex,
          );
      try {
        await _playerModule.playerService.play(
          openUrl,
          startAt: resumeAt,
        );
      } on PlaybackStartSeekException catch (e) {
        debugPrint('Open seek failed, retry resume: $e');
        if (resumeAt != null && resumeAt > Duration.zero) {
          await _playerModule.playerService.play(openUrl, startAt: null);
          await _playerModule.playerService.seekPrecise(resumeAt);
          _playerModule.playback.confirmExplicitPosition(
            resumeAt,
            duration: _playerModule.duration,
          );
        } else {
          rethrow;
        }
      }
      if (playSeq != _episodePlaySeq) return;
      if (openGeneration != _playerModule.playback.openGeneration) return;
      _playerModule.playback.onOpenSucceeded();
      if (resumeAt != null) {
        _playerModule.markResumeStartApplied(resumeAt);
      }
      if (!mounted) return;
      setState(() {});
      unawaited(_syncDlnaAfterEpisodeChange(movie));
      _startHideTimer();
      _startProgressPersistTimer();
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (!mounted) return;
        unawaited(_maybeAutoMatchSubtitlePlay(movie, episode.url));
      });
    }

    if (_playerModule.videoController == null) {
      await _playerModule.initialize();
      if (!mounted || playSeq != _episodePlaySeq) return;
      await _applyPlayerPlaybackTuning();
      if (!mounted || playSeq != _episodePlaySeq) return;
      if (_playerModule.videoController != null) {
        await openMedia();
      }
    } else {
      await openMedia();
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

  /// 组装字幕查询参数：优先用种子内视频文件名（release 名）。
  ({
    String title,
    String? releaseName,
    String? imdbId,
    int? year,
  }) _subtitleQueryOf(Movie movie) {
    final release = _playerModule.currentMagnetFileName.trim();
    final year = int.tryParse(movie.year.trim());
    return (
      title: movie.name.trim(),
      releaseName: release.isEmpty ? null : release,
      imdbId: null,
      year: year,
    );
  }

  /// 未配置 Key 时给一次明确引导（自动匹配是后台触发，静默失败用户无从得知）。
  void _hintSubtitleApiKeyIfNeeded() {
    if (_subtitleNoKeyHintShown || !mounted) return;
    _subtitleNoKeyHintShown = true;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.detailPlayerSubtitleNoApiKeyHint),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _maybeAutoMatchSubtitlePlay(Movie movie, String playUrl) async {
    if (kIsWeb) return;
    if (!_shouldTrySubtitleAutoMatch(movie, playUrl)) return;
    if (_subtitleAutoMatchedForUrl == playUrl) return;
    _subtitleAutoMatchedForUrl = playUrl;
    if (!mounted) return;
    if (!context.read<SettingsProvider>().opensubtitlesApiKeyConfigured) {
      _hintSubtitleApiKeyIfNeeded();
      return;
    }
    final svc = SubtitleService();
    final ok = await svc.init();
    if (!ok || !mounted) return;
    final q = _subtitleQueryOf(movie);
    final list = await svc.searchBest(
      title: q.title,
      releaseName: q.releaseName,
      imdbId: q.imdbId,
      year: q.year,
    );
    if (!mounted || list.isEmpty) return;
    // searchBest 已按得分排序，只接受中文且得分及格的结果，避免自动挂上错位的字幕。
    final pick = list.first;
    final isChinese = pick.language.toLowerCase().contains('zh');
    if (!isChinese || pick.score < 60) {
      debugPrint(
        '字幕自动匹配: 放弃（lang=${pick.language} score=${pick.score}）',
      );
      return;
    }
    if (pick.fileId == null || pick.fileId! <= 0) return;
    final path = await svc.downloadSubtitle(pick.fileId!);
    if (!mounted || path == null) return;
    await _playerModule.playerService.setExternalSubtitleFromFile(path);
    if (!mounted) return;
    setState(() {
      _playerModule.showSubtitles = true;
      _playerModule.subtitleFileName = pick.fileName;
    });
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
              const Divider(height: 1),
              StatefulBuilder(
                builder: (ctx, setSheetState) {
                  final delay = _playerModule.subtitleDelaySeconds;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.tune, size: 20),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(l10n.detailPlayerSubtitleDelay),
                        ),
                        IconButton(
                          tooltip: '-0.5s',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () async {
                            await _adjustSubtitleDelay(-0.5);
                            if (ctx.mounted) setSheetState(() {});
                          },
                        ),
                        SizedBox(
                          width: 56,
                          child: Text(
                            '${delay >= 0 ? '+' : ''}${delay.toStringAsFixed(1)}s',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        IconButton(
                          tooltip: '+0.5s',
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () async {
                            await _adjustSubtitleDelay(0.5);
                            if (ctx.mounted) setSheetState(() {});
                          },
                        ),
                        IconButton(
                          tooltip: l10n.detailPlayerSubtitleDelayReset,
                          icon: const Icon(Icons.restart_alt),
                          onPressed: () async {
                            await _resetSubtitleDelay();
                            if (ctx.mounted) setSheetState(() {});
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 调整外挂字幕时间轴（秒），正数表示字幕延后出现。
  Future<void> _adjustSubtitleDelay(double delta) async {
    if (kIsWeb) return;
    final v =
        await _playerModule.playerService.adjustSubtitleDelaySeconds(delta);
    if (!mounted) return;
    setState(() => _playerModule.subtitleDelaySeconds = v);
  }

  /// 重置外挂字幕时间轴偏移。
  Future<void> _resetSubtitleDelay() async {
    if (kIsWeb) return;
    await _playerModule.playerService.setSubtitleDelaySeconds(0);
    if (!mounted) return;
    setState(() => _playerModule.subtitleDelaySeconds = 0);
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
    final q = _subtitleQueryOf(movie);
    final list = await svc.searchBest(
      title: q.title,
      releaseName: q.releaseName,
      imdbId: q.imdbId,
      year: q.year,
    );
    if (!mounted) return;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.detailPlayerSubtitleNone)),
      );
      return;
    }
    // 已按得分排序：中文优先取最高分，非中文结果排在后面。
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
    final q = _subtitleQueryOf(movie);
    final list = await svc.searchBest(
      title: q.title,
      releaseName: q.releaseName,
      imdbId: q.imdbId,
      year: q.year,
    );
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
                          '${s.language} · DL ${s.downloadsCount}'
                          '${s.episode > 0 ? ' · S${s.season}E${s.episode}' : ''}',
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
    _fullscreenOrientation.resetAndroidLock();
    _fullscreenOrientation.cancelScheduledSync();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await _applyMobileNonFullscreenOrientations();
  }

  Future<void> _applyDetailFullscreen(bool enter) async {
    if (_playerModule.isFullScreen == enter) return;
    setState(() {
      _playerModule.isFullScreen = enter;
    });
    if (kIsWeb) return;
    if (_isMobilePlatform) {
      if (enter) {
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
        );
        await _applyMobileFullscreenOrientations();
      } else {
        await _restoreSystemUiAfterFullScreen();
      }
      if (!mounted) return;
    } else if (_isDesktopPlatform) {
      await windowManager.setFullScreen(enter);
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
    if (_playerModule.currentPlayUrl == null) return;
    final d = _playerModule.duration;
    if (d <= Duration.zero) return;
    var newMs = _playerModule.position.inMilliseconds + seconds * 1000;
    newMs = newMs.clamp(0, d.inMilliseconds);
    final newPosition = Duration(milliseconds: newMs);
    unawaited(
      _playerModule.playerService.seekPrecise(newPosition).then((_) {
        if (!mounted) return;
        setState(() => _playerModule.position = newPosition);
      }),
    );
    setState(() => _playerModule.position = newPosition);
  }

  void _seekToPercent(double percent) {
    if (_playerModule.currentPlayUrl == null) return;
    final dMs = _playerModule.duration.inMilliseconds;
    if (dMs <= 0) return;
    final newPosition =
        Duration(milliseconds: (dMs * percent.clamp(0.0, 1.0)).round());
    unawaited(
      _playerModule.playerService.seekPrecise(newPosition).then((_) {
        if (!mounted) return;
        setState(() => _playerModule.position = newPosition);
      }),
    );
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

  void _showSpeedSelector() {
    _playerModule.hideTimer?.cancel();
    unawaited(
      showSpeedSelector(
        context: context,
        currentSpeed: _playerModule.playbackSpeed,
        presentation: _playerModule.isFullScreen
            ? SpeedSelectorPresentation.detailFullscreen
            : SpeedSelectorPresentation.detailEmbedded,
        anchorKey: _speedButtonKey,
        onSelected: (speed) {
          unawaited(_playerModule.setPlaybackSpeed(speed));
          if (mounted) {
            setState(() => _playerModule.playbackSpeed = speed);
          }
          _startHideTimer();
        },
      ),
    );
  }

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

  void _startLockChromeHideTimer() {
    _playerModule.lockChromeHideTimer?.cancel();
    if (!_playerModule.isScreenLocked) return;
    _playerModule.lockChromeHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playerModule.isScreenLocked) {
        setState(() => _playerModule.showLockChrome = false);
      }
    });
  }

  void _clearPlaybackError() {
    _playerModule.playerErrorMessage = '';
    _playerModule.playbackErrorType = PlaybackErrorType.none;
  }

  String _playbackErrorLabel() {
    final l10n = AppLocalizations.of(context)!;
    switch (_playerModule.playbackErrorType) {
      case PlaybackErrorType.noPlayableEpisode:
        return l10n.detailPlaybackErrorNoUrl;
      case PlaybackErrorType.parseFailed:
        return l10n.detailPlaybackErrorParseFailed;
      case PlaybackErrorType.routeFallback:
        return l10n.detailPlaybackErrorRouteSwitched;
      case PlaybackErrorType.sourceFallbackFailed:
        return l10n.detailPlaybackErrorMultiSourceFailed;
      case PlaybackErrorType.networkOrPlayer:
        return l10n.detailPlaybackErrorNetwork;
      case PlaybackErrorType.magnetFailed:
        return l10n.detailPlaybackErrorMagnet;
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
    _playerModule.onPlaybackProgress = _maybePreloadNextEpisode;
    _playerModule.onVideoDimensionsChanged = (_, __) {
      if (!_playerModule.isFullScreen) return;
      // Android 横屏片源已锁 landscape 时，忽略尺寸抖动触发的竖屏误判
      if (_isAndroidPlatform &&
          _fullscreenOrientation.androidLandscapeLocked &&
          !DetailVideoLayout.isConfidentPortraitVideo(
            videoWidth: _playerModule.videoWidth,
            videoHeight: _playerModule.videoHeight,
            rotate: _playerModule.videoRotate,
          )) {
        if (mounted) setState(() {});
        return;
      }
      _scheduleMobileFullscreenOrientationSync();
      if (mounted) setState(() {});
    };
    _clearUnsupportedPlayerScreenLock();
    await _playerModule.initialize();
    await _applyPlayerPlaybackTuning();
  }
}
