part of 'detail_page.dart';

// 由 detail_page.dart 拆分而来：方法体逐字搬运，
// 通过 extension on _DetailPageState 直接访问原类的私有成员。

extension _DetailPageDataExt on _DetailPageState {
  bool _shouldShowDetailShimmer(MovieProvider mp) {
    if (_deferDetailPrime) return true;
    if (_displayMovie(mp) != null) return false;
    return mp.isLoadingDetail;
  }

  /// 切源、写入路由传入的 [Movie]、拉取详情（供首次进入与 [didUpdateWidget] 复用）。
  Future<void> _bootstrapDetailPage() async {
    // 每次进入/换片都是一个新的加载会话，传给 loadMovieDetail 与之绑定，
    // 详情页按 _expectedDetailSession 认领属于自己的 currentMovie。
    _expectedDetailSession++;
    final isLocalDetail = _isLocalDetailEntry;

    // 历史/收藏带有的 sourceId 与全局当前源不一致时，必须先切源再拉详情；
    // 各 CMS 的 vod_id 仅在本站唯一，换源用同一 id 会打开完全错误的片子。
    // 磁力占位详情 / B 站平台源无对应 CMS 源，跳过切源。
    if (widget.sourceId.isNotEmpty && !isLocalDetail) {
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

    if (isLocalDetail) {
      final movie = widget.movie ?? _pageMovie;
      if (movie != null) {
        _pageMovie = movie;
        context.read<MovieProvider>().completeDetailWithMovie(movie);
      }
      if (!mounted) return;
      if (movie != null) {
        _syncWatchHistory(movie);
        if (mounted) _setState(() {});
        // 磁力补全（种子名 / 文件列表）只对磁力占位条目有意义，B 站源不适用。
        if (_isMagnetDetailEntry) {
          unawaited(_enrichMagnetDetailMovie(movie));
        }
        unawaited(_tryAutoPlayOnEnter(movie));
      }
      return;
    }

    if (!mounted) return;
    await _loadData();
    if (!mounted) return;
    _loadRecommendations();

    // 用本页加载会话认领，而非死绑 widget.movieId：自动换源后身份会变化，
    // 但仍应执行历史同步/自动起播等（否则换源后整页不自动播放）。
    final loaded = _displayMovie(context.read<MovieProvider>());
    if (loaded != null) {
      _pageMovie = loaded;
      if (mounted) {
        _syncWatchHistory(loaded);
        _applyInitialEpisodeFromRoute(loaded);
        if (_playerModule.pendingResumePosition == null) {
          _applyPreferredRouteFromSettings(loaded);
        }
        _setState(() {});
      }
      // 磁力搜索对磁力占位条目与 B 站平台源都没有意义，跳过。
      final isLocalSource = _isLocalSourceId(widget.sourceId) ||
          _isLocalSourceId(loaded.sourceId);
      if (!isLocalSource) {
        unawaited(_scheduleDeferredMagnetSearch(loaded));
      }
      unawaited(_tryAutoPlayOnEnter(loaded));
    }
  }

  String _detailSourceId(Movie movie) {
    if (widget.sourceId.isNotEmpty) return widget.sourceId;
    if (movie.sourceId.isNotEmpty) return movie.sourceId;
    return '';
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
      _setState(() => _showDetailScrollToTop = show);
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

  /// 停止播放并离开详情（返回、系统返回键等统一入口）。
  Future<void> _leaveDetailPage() async {
    _stopProgressPersistTimer();
    final movie = _displayMovie(context.read<MovieProvider>());
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
    if (_isLocalDetailEntry) {
      context.read<MovieProvider>().popDetailSnapshot();
    }
    if (!mounted) return;
    context.pop();
  }

  Future<void> _loadData() async {
    if (_isLocalDetailEntry) return;
    final movieProvider = context.read<MovieProvider>();
    await movieProvider.loadMovieDetail(
      widget.movieId,
      session: _expectedDetailSession,
      titleHint: widget.movie?.name,
      yearHint: widget.movie?.year,
    );
  }

  void _loadRecommendations() {
    final movie = _displayMovie(context.read<MovieProvider>());
    if (movie == null) return;
    unawaited(_fetchAndApplyRecommendations(movie));
  }

  Future<void> _fetchAndApplyRecommendations(Movie movie) async {
    final related = await ApiService().getDetailSideRecommendations(movie);
    if (!mounted) return;
    final provider = context.read<MovieProvider>();
    // 推荐回来时本页必须仍处于同一加载会话，否则丢弃（防串片/防错源同 id）。
    if (provider.detailSession != _expectedDetailSession) return;
    final current = provider.currentMovie;
    if (current == null) return;
    provider.setCurrentMovie(current.copyWith(relatedMovies: related));
    if (mounted) _setState(() {});
  }

  /// 初始化模块
  Future<void> _initModules() async {
    _playerModule.onUiChanged = () {
      if (mounted) _setState(() {});
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
        if (mounted) _setState(() {});
        return;
      }
      _scheduleMobileFullscreenOrientationSync();
      if (mounted) _setState(() {});
    };
    _clearUnsupportedPlayerScreenLock();
    await _playerModule.initialize();
    await _applyPlayerPlaybackTuning();
  }
}
