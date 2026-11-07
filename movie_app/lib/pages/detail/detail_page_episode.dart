part of 'detail_page.dart';

// 由 detail_page.dart 拆分而来：方法体逐字搬运，
// 通过 extension on _DetailPageState 直接访问原类的私有成员。

extension _DetailPageEpisodeExt on _DetailPageState {
  void _maybePreloadNextEpisode(Duration position, Duration duration) {
    if (duration <= Duration.zero) return;
    if (position.inMilliseconds / duration.inMilliseconds < 0.8) return;
    if (!context.read<SettingsProvider>().preloadNextEpisode) return;

    final movie = _displayMovie(context.read<MovieProvider>());
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
        prefetchEnabled: settings.preloadNextEpisode,
      ),
    );
  }

  int _episodeIndexForResume(Movie movie, int routeIndex) {
    return DetailResumeCoordinator.episodeIndexForResume(
      movie,
      routeIndex,
      _playerModule,
    );
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

  Future<void> _playEpisodeAsync(
    int routeIndex,
    int episodeIndex, {
    Duration? preservePosition,
  }) async {
    final playSeq = ++_episodePlaySeq;
    final movie = _displayMovie(context.read<MovieProvider>());
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
      final switchingEpisode =
          episodeIndex != _playerModule.currentEpisodeIndex ||
              routeIndex != _playerModule.currentRouteIndex;
      if (switchingEpisode) {
        // 旧集的纠偏/片尾恢复预约一律作废，否则会在新集起播后 fire。
        _playerModule.cancelPendingRecovery();
        // 2026-10-28 用户实测：「换集以后进度条还是不对，过一会才反应过来」。
        //
        // 磁力换集走的是 `_playMagnet`（stop → addMagnet → 重新等元数据），
        // **不经过** `playback.prepareOpen`，于是权威进度仍停在上一集的
        // 38:40、时长也还是上一集的 2:13:59；要等新文件起播上报位置，
        // 播放器才把进度「纠正」回来 —— 中间这段时间进度条是错的。
        //
        // 换集是确定的新媒体：立刻按「新集起播」重置进度权威，并把 UI 用的
        // 位置/时长/缓冲一起清零，进度条当帧就归零。
        _playerModule.playback.prepareOpen(isNewEpisode: true);
        _playerModule.position = Duration.zero;
        _playerModule.duration = Duration.zero;
        _playerModule.bufferedPosition = Duration.zero;
        _playerModule.cacheSpeed = 0;
      }
      _setState(() {
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
        !_playerModule.isOpeningMedia &&
        // 缓冲区已耗尽且不再推进（断网耗尽缓冲后 mpv 放弃读流）：点当前集应当
        // 唤醒播放器（内部按当前进度软重载），而不是静默返回卡住不动。
        // 生命周期 error/ended 时同样不能走捷径——否则源失败后点同一集永远
        // 无响应（2026-10-21 模拟器实测），要落到下方完整重开路径。
        (_playerModule.playback.lifecycle.isActive ||
            _playerModule.isStalledExhausted)) {
      if (_desktopRouteIndex != routeIndex) {
        _setState(() => _desktopRouteIndex = routeIndex);
      }
      if (_playerModule.isStalledExhausted) {
        await _playerModule.resume();
        return;
      }
      final resumeAt = _playerModule.takePendingResumeStart(
        routeIndex: routeIndex,
        episodeIndex: episodeIndex,
      );
      if (resumeAt != null) {
        // 统一走 coordinator seek，保持 authoritative 与生命周期一致。
        await _playerModule.seek(resumeAt);
        _playerModule.markResumeStartApplied(resumeAt);
        if (mounted) _setState(() {});
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
    // 每次 open（换集或换线）都是新的一次媒体加载：上一集遗留的纠偏预约 /
    // 片尾恢复定时器必须在这里作废，不能再对新媒体生效。
    _playerModule.cancelPendingRecovery();
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

    // 换集当帧必须把上一集的时长/位置/缓冲清掉。
    //
    // 2026-11-03 真机抓到：点第 7 集后第一帧显示 `2:59 / 47:04` —— 位置已经是
    // 新集的续播点 2:59，时长却还是上一集的 47:04，进度条按旧时长算比例会画错
    // 一段（若位置上报再晚一点，就是「22:24 / 47:04」，滑块停在上一集的 47%）。
    // [prepareOpen] 只重置进度权威（playhead），`duration` 是独立字段，原本要等
    // 新集 durationChanged 才更新；磁力换集分支早已清零，普通分支漏了这一步。
    //
    // 2026-11-04 加日志（不改行为）：真机复现出「切集后 pos 钉在上一集位置不动、
    // 同时 discontinuity 每 0.2s 刷一条」，需要看清 prepareOpen 到底有没有把
    // 进度权威清零、以及 isNewEpisode 是否被算成 false。
    DebugLog.log(
      'Playhead',
      '换集 open: isNewEpisode=$isNewEpisode '
          'preserve=${openPlan.preservePlayhead?.inSeconds ?? 'null'} '
          'authoritative=${_playerModule.playback.authoritativePosition.inSeconds}s '
          'position=${_playerModule.position.inSeconds}s',
      flush: true,
    );
    if (isNewEpisode && openPlan.preservePlayhead == null) {
      _playerModule.position = Duration.zero;
      _playerModule.duration = Duration.zero;
      _playerModule.bufferedPosition = Duration.zero;
    }

    if (!matchResume && preservePosition == null) {
      _playerModule.pendingResumePosition = null;
      _playerModule.resumeTargetRouteIndex = null;
      _playerModule.resumeTargetEpisodeIndex = null;
    }

    _setState(() {
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
    final isProxy = openUrl.contains('/adfree/') || openUrl.contains('/hls/');
    final proxyKind =
        isProxy ? (openUrl.contains('/hls/') ? '全量加密代理' : '列表代理') : '直连';
    DebugLog.log('Resume', '最终播放地址: $proxyKind $openUrl');

    Future<void> openMedia() async {
      if (!mounted || playSeq != _episodePlaySeq) return;
      if (openGeneration != _playerModule.playback.openGeneration) return;
      final resumeAt = openPlan.startAt ??
          _playerModule.takePendingResumeStart(
            routeIndex: routeIndex,
            episodeIndex: episodeIndex,
          );
      DebugLog.log(
        'Resume',
        'openMedia resumeAt=${resumeAt?.inSeconds ?? -1}s '
            'openPlan.startAt=${openPlan.startAt?.inSeconds ?? -1}s',
      );
      // 普通采集站源不需要额外请求头。
      try {
        await _playerModule.playerService.play(
          openUrl,
          startAt: resumeAt,
        );
      } on PlaybackStartSeekException catch (e) {
        debugPrint('Open seek failed, retry resume: $e');
        DebugLog.log(
          'Resume',
          '续播 seek 失败，进入重试路径: $e',
          flush: true,
        );
        if (resumeAt != null && resumeAt > Duration.zero) {
          // 重试前记下进度：本地代理首开 seek 失败 → 从 0 重播 → 用户可能已拖到
          // 别处（如拖到 27:00 看广告位）。此时若仍无条件 seek 回续播点，会把
          // 用户瞬间拽走（表现为「从27分跳到36分」）。用户已拖动则放弃续播
          // seek，尊重用户当前进度（2026-10-19 用户实测反馈：关过滤直连不复现）。
          final positionBeforeRetry = _playerModule.effectivePlaybackPosition;
          await _playerModule.playerService.play(
            openUrl,
            startAt: null,
          );
          // 等流就绪再走 coordinator seek，先更新 authoritative 再真正 seek，
          // 避免 open 初期的 0 位置报告被误判为 discontinuity、且网络流 0 位 seek 落空。
          await _playerModule.playerService.waitUntilSeekable(resumeAt);
          final drifted =
              (_playerModule.effectivePlaybackPosition - positionBeforeRetry)
                  .abs();
          if (drifted <= const Duration(seconds: 10)) {
            DebugLog.log(
              'Resume',
              '重试成功：拽回续播点 resumeAt=${resumeAt.inSeconds}s '
                  '(drift=${drifted.inSeconds}s)',
              flush: true,
            );
            await _playerModule.seek(resumeAt);
          } else {
            debugPrint(
              'Resume seek skipped: user took over '
              '(drift=${drifted.inSeconds}s)',
            );
            DebugLog.log(
              'Resume',
              '重试放弃拽回：用户已接管进度 '
                  '(drift=${drifted.inSeconds}s >= 10s)',
              flush: true,
            );
            // 续播点已失效而从头播时，权威进度不能继续钉在旧续播点上，
            // 否则进度条长期显示错误位置（实测 2944s vs 实际 167s）。
            if (_playerModule.playback.adoptPlayerPosition(
              _playerModule.playback.lastPlayerReport,
            )) {
              DebugLog.log(
                'Resume',
                '权威进度已对齐实际播放位置 '
                    '${_playerModule.playback.authoritativePosition.inSeconds}s',
                flush: true,
              );
            }
          }
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
      _setState(() {});
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

  void _playNextEpisode() {
    final movie = _displayMovie(context.read<MovieProvider>());
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
    final movie = _displayMovie(context.read<MovieProvider>());
    if (movie == null || movie.playRoutes.isEmpty) return;
    final ri =
        _playerModule.currentRouteIndex.clamp(0, movie.playRoutes.length - 1);
    final route = movie.playRoutes[ri];
    if (route.episodes.isEmpty) return;
    final prev = _playerModule.currentEpisodeIndex - 1;
    if (prev < 0) return;
    _playEpisode(ri, prev);
  }
}
