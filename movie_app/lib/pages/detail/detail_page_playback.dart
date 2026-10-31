part of 'detail_page.dart';

// 由 detail_page.dart 拆分而来：方法体逐字搬运，
// 通过 extension on _DetailPageState 直接访问原类的私有成员。

extension _DetailPagePlaybackExt on _DetailPageState {
  Movie? _displayMovie(MovieProvider mp) {
    final cm = mp.currentMovie;
    // 只认领「本页本次加载会话」产生的 currentMovie，杜绝跨页/跨源串片；
    // 同时允许自动换源后身份（id/sourceId）变化仍被本页正常认领
    // （各 CMS 的 vod_id 仅在本站唯一，不能再靠 id 死绑）。
    if (cm != null && mp.detailSession == _expectedDetailSession) {
      _pageMovie = cm;
      return cm;
    }
    return _pageMovie;
  }

  bool _shouldShowDetailError(MovieProvider mp) {
    if (_displayMovie(mp) != null) return false;
    if (_shouldShowDetailShimmer(mp)) return false;
    return mp.errorMessage.isNotEmpty;
  }

  double _detailPlayerMaxHeight(double availableHeight) {
    return availableHeight *
        DetailVideoLayout.detailMaxHeightFactorForPlatform(
          isWeb: kIsWeb,
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
      portraitOrientations: _DetailPageState._mobilePortraitOrientations,
    );
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

  /// 设置项变化回调。
  ///
  /// 2026-10-22：详情页此前**从不**监听 SettingsProvider，导致用户在设置页
  /// 改完「硬解档位 / 视频输出后端」返回后，播放器仍是旧档位 —— 要等到切集
  /// 或重新加载详情才生效。现在设置一变就重新下发。
  void _onSettingsChanged() {
    if (!mounted) return;
    final settings = context.read<SettingsProvider>();
    final hw = settings.effectiveHwDecodeMode;
    final vo = settings.effectiveVideoOutputMode;
    if (hw == _appliedHwDecodeMode && vo == _appliedVideoOutputMode) return;
    unawaited(_applyPlayerPlaybackTuning());
  }

  Future<void> _applyPlayerPlaybackTuning() async {
    if (kIsWeb || !mounted) return;
    final settings = context.read<SettingsProvider>();
    final hw = settings.effectiveHwDecodeMode;
    final vo = settings.effectiveVideoOutputMode;
    _appliedHwDecodeMode = hw;
    _appliedVideoOutputMode = vo;
    await _playerModule.playerService.applyPlaybackStrategy(
      PlaybackStrategyConfig.fromKey(settings.playbackStrategy),
      hwDecodeMode: hw,
      videoOutputMode: vo,
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
      // 拖动期间只做 UI 预览，不真正 seek；松手后由 commitSeek 统一走
      // coordinator seek，避免频繁 seek 导致 PlayheadAuthority 误判。
      _scrubFastSeekTarget = null;
    });
  }

  WatchHistory? _resolveWatchHistory(Movie movie) {
    return DetailResumeCoordinator.resolveHistory(
      history: context.read<HistoryProvider>(),
      movieId: movie.id,
      sourceId: _detailSourceId(movie),
      magnetUri: widget.initialMagnetUri,
    );
  }

  String _historyOverlayLabel() {
    return DetailResumeCoordinator.historyOverlayLabel(
      AppLocalizations.of(context)!,
      _playerModule,
    );
  }

  Future<void> _resetPlayerForDetailChange() async {
    _torrentModule.magnetPlayVersion++;
    _horizontalSeekDragSeconds = 0;
    _seekDragVelocity = 0;
    _lastSeekDragAt = null;
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
    if (mounted) _setState(() {});
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

  void _stopProgressPersistTimer() {
    _playerModule.progressPersistTimer?.cancel();
    _playerModule.progressPersistTimer = null;
  }

  void _startProgressPersistTimer() {
    _stopProgressPersistTimer();
    _playerModule.progressPersistTimer =
        Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      final m = _displayMovie(context.read<MovieProvider>());
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

  void _applyPreferredRouteFromSettings(Movie movie) {
    if (movie.playRoutes.isEmpty) return;
    if (_playerModule.pendingResumePosition != null) return;
    if (_playerModule.resumeTargetRouteIndex != null) return;
    if (_playerModule.hasHistory) return;
    unawaited(() async {
      final idx = await _resolvePlayRouteIndex(movie, 0);
      if (!mounted) return;
      _setState(() => _desktopRouteIndex = idx);
    }());
  }

  void _handleDetailPlaybackEnded() {
    if (!mounted) return;
    final movie = _displayMovie(context.read<MovieProvider>());
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
    final movie = _displayMovie(context.read<MovieProvider>());
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

  void _startPlay() {
    final movieProvider = context.read<MovieProvider>();
    final movie = _displayMovie(movieProvider) ?? _pageMovie;
    if (movie == null) return;

    final magnetUri = _magnetUriForPlayback(movie);
    if (_isMagnetDetailEntry && magnetUri.isNotEmpty) {
      if (_playerModule.currentPlayUrl != null) {
        _togglePlayPause();
        return;
      }
      // 2026-10-28 用户实测：「加载的时候点一下屏幕，就重新读秒加载了」。
      //
      // 起播期间（解析元数据 / 连节点 / 缓冲）画面上盖着「封面 + 中心播放键」
      // 的整屏点击层，点任何位置都会落到 _startPlay → _playMagnet → play()；
      // play() 是「完整重开」（stop → addMagnet → 重新等元数据），于是
      // 「解析 1s」被清零重新数。这里在**准备中**直接忽略重复点击；
      // 失败后 magnetSourcePreparing 已被 _fail 置回 false，重试不受影响。
      if (_playerModule.magnetSourcePreparing ||
          _playerModule.magnetRetrying ||
          (_playerModule.torrentStage > 0 && _playerModule.torrentStage < 7) ||
          _playerModule.torrentStep == 1 ||
          _playerModule.torrentStep == 2 ||
          _playerModule.torrentStep == 3) {
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
    // 在线片源同理：解析/打开中重复点击不应重开（会重新走一遍 URL 解析）。
    if (_playerModule.isOpeningMedia) return;
    final ri = _desktopRouteIndex.clamp(0, movie.playRoutes.length - 1);
    _playEpisode(ri, _episodeIndexForResume(movie, ri));
  }

  /// 切换播放线路；已是当前线路时不重新加载。
  void _selectPlayRoute(int routeIndex) {
    if (routeIndex == _playerModule.currentRouteIndex &&
        _playerModule.currentPlayUrl != null) {
      if (_desktopRouteIndex != routeIndex) {
        _setState(() => _desktopRouteIndex = routeIndex);
      }
      return;
    }
    final movie = _displayMovie(context.read<MovieProvider>());
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

  Future<void> _restoreSystemUiAfterFullScreen() async {
    _fullscreenOrientation.resetAndroidLock();
    _fullscreenOrientation.cancelScheduledSync();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await _applyMobileNonFullscreenOrientations();
  }

  Future<void> _applyDetailFullscreen(bool enter) async {
    if (_playerModule.isFullScreen == enter) return;
    _setState(() {
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
    _setState(() {
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

  void _seekRelative(int seconds) {
    if (_playerModule.currentPlayUrl == null) return;
    final d = _playerModule.duration;
    if (d <= Duration.zero) return;
    var newMs = _playerModule.position.inMilliseconds + seconds * 1000;
    newMs = newMs.clamp(0, d.inMilliseconds);
    final newPosition = Duration(milliseconds: newMs);
    // 通过 coordinator seek，确保 PlayheadAuthority 先更新 authoritative，
    // 避免 seek 后回跳被误判为 discontinuity 而 recovery 回去。
    unawaited(_playerModule.seek(newPosition));
    _setState(() {});
  }

  void _seekToPercent(double percent) {
    if (_playerModule.currentPlayUrl == null) return;
    final dMs = _playerModule.duration.inMilliseconds;
    if (dMs <= 0) return;
    final newPosition =
        Duration(milliseconds: (dMs * percent.clamp(0.0, 1.0)).round());
    unawaited(_playerModule.seek(newPosition));
    _setState(() {});
  }

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
            _setState(() => _playerModule.playbackSpeed = speed);
          }
          _startHideTimer();
        },
      ),
    );
  }

  void _cycleSpeed(int direction) {
    var idx = _DetailPageState._kSpeedSteps.indexWhere(
      (s) => (s - _playerModule.playbackSpeed).abs() < 0.02,
    );
    if (idx < 0) {
      idx = _DetailPageState._kSpeedSteps.indexOf(1.0);
    }
    idx = (idx + direction) % _DetailPageState._kSpeedSteps.length;
    final sp = _DetailPageState._kSpeedSteps[idx];
    unawaited(_playerModule.setPlaybackSpeed(sp));
    _setState(() => _playerModule.playbackSpeed = sp);
    _startHideTimer();
  }

  Future<void> _refreshBrightnessFromSystem() async {
    if (kIsWeb) return;
    try {
      final b = await ScreenBrightness().application;
      if (!mounted) return;
      _setState(() => _playerModule.brightness = b.clamp(0.0, 1.0));
    } catch (_) {}
  }

  void _onLongPressStart() {
    if (_playerModule.currentPlayUrl == null) return;
    _playerModule.normalSpeed = _playerModule.playbackSpeed;
    unawaited(_playerModule.setPlaybackSpeed(2.0));
    _setState(() => _playerModule.showSpeedHint = true);
  }

  void _onLongPressEnd() {
    if (_playerModule.currentPlayUrl == null) return;
    unawaited(_playerModule.setPlaybackSpeed(_playerModule.normalSpeed));
    _setState(() => _playerModule.showSpeedHint = false);
  }

  /// 鼠标在播放器上移动：显示控制栏与进度条，并重置 3 秒隐藏计时。
  void _onPlayerPointerActivity() {
    if (!mounted) return;
    if (_playerModule.showShortcutHelp || _playerModule.isScreenLocked) {
      return;
    }
    if (!_playerModule.showControls) {
      _setState(() => _playerModule.showControls = true);
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
        _setState(() {
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
}
