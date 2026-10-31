part of 'detail_page.dart';

// 由 detail_page.dart 拆分而来：方法体逐字搬运，
// 通过 extension on _DetailPageState 直接访问原类的私有成员。

extension _DetailPageDownloadExt on _DetailPageState {
  bool _isMagnetPlaybackActive() {
    if (!_isMagnetDetailEntry) return false;
    return _playerModule.currentPlayUrl != null ||
        _playerModule.magnetSourcePreparing ||
        (_playerModule.torrentStep > 0 && _playerModule.torrentStep < 4) ||
        _playerModule.torrentStage > 0;
  }

  bool _showMagnetPrepIndicator() {
    if (!_isMagnetDetailEntry) return false;
    // 已经判定失败 → 让错误面板独占画面（它有「再试一次 / 换个资源」）。
    // 否则 handoverWithoutPeers 的 10 分钟时间戳会盖住错误面板。
    if (_playerModule.playbackErrorType == PlaybackErrorType.magnetFailed) {
      return false;
    }
    // 45s 内一个节点都没连上 → 继续保留这条指示器，让它把
    // 「这个资源连不上任何节点」明说出来，而不是交接后立刻消失、
    // 留用户对着黑屏猜（2026-10-27 真机实测：黑屏 120s 零提示）。
    if (_playerModule.torrentService.handoverWithoutPeers) return true;
    return _playerModule.magnetSourcePreparing ||
        (_playerModule.torrentStep > 0 && _playerModule.torrentStep < 4) ||
        _playerModule.torrentStage > 0;
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

  String _magnetUriForPlayback(Movie movie) {
    if (widget.initialMagnetUri.isNotEmpty) {
      return widget.initialMagnetUri;
    }
    final h = _resolveWatchHistory(movie);
    if (h != null && h.magnetUri.isNotEmpty) return h.magnetUri;
    return '';
  }

  Future<void> _runMagnetSearchForMovie(
    Movie movie, {
    required bool strict,
  }) async {
    final done = _torrentModule.searchForMovieDetail(movie, strict: strict);
    if (mounted) _setState(() {});
    await done;
    if (mounted) _setState(() {});
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

  DetailMagnetPlayback _buildMagnetPlayback() {
    final l10n = AppLocalizations.of(context)!;
    return DetailMagnetPlayback(
      player: _playerModule,
      torrent: _torrentModule,
      isMounted: () => mounted,
      onStateChanged: () {
        if (mounted) _setState(() {});
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
    if (mounted) _setState(() {});
  }

  Future<void> _enrichMagnetDetailMovie(Movie movie) async {
    final enriched = await MagnetDetailEnrichmentService.instance.enrich(
      movie,
      searchHint: widget.displayTitleHint,
      torrentImdbId: widget.torrentImdbId,
    );
    debugPrint(
      '磁力详情补全结果: ${movie.name} -> ${enriched?.name ?? "(无补全)"} '
      '导演=${enriched?.director ?? "-"} 演员=${enriched?.actors.length ?? 0} '
      '类型=${enriched?.genres.join("/") ?? "-"}',
    );
    if (!mounted || enriched == null) return;
    _pageMovie = enriched;
    context.read<MovieProvider>().completeDetailWithMovie(enriched);
    if (mounted) _setState(() {});
    unawaited(_runMagnetSearchForMovie(enriched, strict: false));
  }

  Future<void> _playMagnet(
    String magnetUri,
    Movie movie, {
    int episodeIndex = 0,
    int? fileIndex,
  }) async {
    // 这里**不能**用布尔锁把并发请求挡掉（曾经的写法：正在播放就直接 return）。
    // 磁力首集往往要等元数据 + 缓冲几十秒，用户在这个窗口内点第二集时，
    // 请求会被静默丢弃 —— 界面毫无反应，表现就是「第二集点不出来」。
    //
    // 防重入实际由 DetailMagnetPlayback 的 playVersion 机制保证：
    // 每次 play() 都会 ++magnetPlayVersion，旧流程在每个 await 点检测到
    // 版本不匹配便自行退出，因此并发调用是安全的，无需额外加锁。
    await _buildMagnetPlayback().play(
      magnetUri,
      movie,
      episodeIndex: episodeIndex,
      preferredFileIndex: fileIndex,
    );
  }
}
