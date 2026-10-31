part of 'detail_page.dart';

// 由 detail_page.dart 拆分而来：方法体逐字搬运，
// 通过 extension on _DetailPageState 直接访问原类的私有成员。

extension _DetailPagePlayerUiExt on _DetailPageState {
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
                              onRouteSelected: _selectPlayRoute,
                              currentRouteIndex: _desktopRouteIndex,
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
                  isMagnetDetail: _isMagnetDetailEntry,
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
              child: Container(
                width: screenWidth,
                height: playerHeight,
                // 移动端：播放器底部一条半透明描边 + 柔和投影，作为「媒体卡片」与
                // 下方滚动详情区的分界（2026-10-18 用户要求：只保留下边框，
                // 其他方向不要描边）。
                decoration: _isMobilePlatform && !kIsWeb
                    ? BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.14),
                            width: 1,
                          ),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x40000000),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      )
                    : null,
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
              _setState(() => _playerModule.showShortcutHelp = false);
            } else if (_playerModule.showVolumePopover) {
              _setState(() => _playerModule.showVolumePopover = false);
            } else if (_playerModule.isFullScreen) {
              unawaited(_applyDetailFullscreen(false));
            }
            return;
          }
          // H / ?：快捷键帮助面板
          if (key == LogicalKeyboardKey.keyH ||
              (key == LogicalKeyboardKey.slash &&
                  !HardwareKeyboard.instance.isShiftPressed)) {
            _setState(
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
            _setState(() {
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
            _setState(
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
              _setState(() => _playerModule.showControls = true);
              _startHideTimer();
            },
            // 单击：隐藏控制栏时先显示；已显示时桌面/Web/iOS 可点按切播放，Android 仅双击切播放。
            onTap: () {
              if (_playerModule.showShortcutHelp) return;
              if (_playerModule.isScreenLocked) {
                if (_playerModule.showLockChrome) {
                  _setState(() => _playerModule.showLockChrome = false);
                  _playerModule.lockChromeHideTimer?.cancel();
                } else {
                  _setState(() => _playerModule.showLockChrome = true);
                  _startLockChromeHideTimer();
                }
                return;
              }
              if (_playerModule.showVolumePopover) {
                _setState(() => _playerModule.showVolumePopover = false);
              }
              if (!_playerModule.showControls) {
                _setState(() => _playerModule.showControls = true);
                _startHideTimer();
              } else if (_isMobilePlatform) {
                _setState(() => _playerModule.showControls = false);
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
                    _setState(() {
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
                        _setState(() => _playerModule.showGestureHint = false);
                      }
                    });
                    // 手势进度条1秒后淡出
                    _playerModule.gestureBarTimer?.cancel();
                    _playerModule.gestureBarTimer =
                        Timer(const Duration(seconds: 1), () {
                      if (mounted) {
                        _setState(() => _playerModule.showGestureBar = false);
                      }
                    });
                  },
            // 水平滑动：快进/快退（锁屏时禁用）
            // 手速增益：滑动越快同样距离跳过的时长越多、越慢越少
            // （慢拖精细 ↔ 快甩粗调），单次封顶 ±5 分钟（2026-10-19 方向修正）。
            onHorizontalDragStart: _playerModule.isScreenLocked
                ? null
                : (details) {
                    _setState(() {
                      _horizontalSeekDragSeconds = 0;
                      _seekDragVelocity = 0;
                      _lastSeekDragAt = DateTime.now();
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
                    // 瞬时手速 = |dx| / dt（dt 过小则沿用上次平滑值，
                    // 同时规避一帧巨大跳变的除零/抖动）
                    final now = DateTime.now();
                    final dtMs = _lastSeekDragAt == null
                        ? 0
                        : now.difference(_lastSeekDragAt!).inMilliseconds;
                    _lastSeekDragAt = now;
                    if (dtMs >= 5) {
                      _seekDragVelocity =
                          DetailVideoLayout.smoothSeekDragVelocity(
                        previous: _seekDragVelocity,
                        instant: details.delta.dx.abs() * 1000 / dtMs,
                      );
                    }
                    _horizontalSeekDragSeconds =
                        DetailVideoLayout.nextSeekDragSeconds(
                      dx: details.delta.dx,
                      smoothedVelocity: _seekDragVelocity,
                      screenWidth: screenWidth,
                      currentTotalSeconds: _horizontalSeekDragSeconds,
                      positionSeconds:
                          _playerModule.position.inSeconds.toDouble(),
                      durationSeconds: durationSec.toDouble(),
                    );
                    final previewSec = _horizontalSeekDragSeconds.round();
                    _setState(() {
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
                    _seekDragVelocity = 0;
                    _lastSeekDragAt = null;
                    if (delta != 0) {
                      _seekRelative(delta);
                    }
                    _playerModule.seekBubbleTimer?.cancel();
                    _playerModule.seekBubbleTimer =
                        Timer(const Duration(seconds: 1), () {
                      if (mounted) {
                        _setState(() => _playerModule.showSeekBubble = false);
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

                // 控制栏隐藏时保留返回；全屏时与底栏一并隐藏，按 Esc / 单击唤出。
                // 磁力准备/失败期间 videoController 还没建出来（或被释放），但用户
                // 同样需要退出 —— 判定逻辑见 shouldShowPersistentPlayerBackButton。
                if (shouldShowPersistentPlayerBackButton(
                  hasVideoController: _playerModule.videoController != null,
                  controlsVisible: _playerModule.showControls,
                  fullScreen: _playerModule.isFullScreen,
                  screenLocked: _playerModule.isScreenLocked,
                  magnetBusyOrFailed: _showMagnetPrepIndicator() ||
                      _playerModule.playbackErrorType !=
                          PlaybackErrorType.none,
                ))
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
                              valueListenable: _playerModule.openElapsedSeconds,
                              builder: (context, elapsed, _) {
                                // 5s 之内给一个基础圆环；之后切换到缓冲进度反馈。
                                if (elapsed < 5.0) {
                                  return const CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  );
                                }
                                return const CircularProgressIndicator(
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
                              .openElapsedSeconds.value.isFinite) ...[
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
                //
                // 磁力失败必须**立刻**显示（不再等 retryCount>=3）：
                // 磁力没有「自动重连计数」这条链路，等 3 次等于永远不显示，
                // 用户看到的就是「连不上直接断开、一句提示都没有」。
                if (_playerModule.playerErrorMessage.isNotEmpty &&
                    (_playerModule.retryCount >= 3 || _isMagnetError))
                  Center(
                    child: _isMagnetError
                        ? _buildMagnetErrorCard(l10n)
                        : _buildGenericErrorCard(l10n),
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
            key: ValueKey<int>(_playerModule.playerService.recycleEpoch),
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
        if (!kIsWeb && Platform.isAndroid)
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
            _setState(() => _playerModule.showVolumePopover = false);
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
                    if (!kIsWeb && Platform.isAndroid)
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
                                  _setState(() {
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
                _setState(() {
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
          _setState(() {
            _scrubbingProgress = true;
            _scrubPreviewPosition = newPos;
          });
          _scrubFastSeekThrottled(newPos);
        }

        void commitSeek(Duration newPos, {required bool precise}) {
          _scrubFastSeekTimer?.cancel();
          _scrubFastSeekTarget = null;
          if (_playerModule.currentPlayUrl == null) return;
          // 统一走 coordinator seek：先更新 authoritative 再真正 seek，
          // 避免 seek 后回跳被 PlayheadAuthority 误判为 discontinuity。
          unawaited(
            _playerModule.seek(newPos).then((_) {
              if (!mounted) return;
              _setState(() => _scrubbingProgress = false);
            }),
          );
          _setState(() {
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
              _setState(() {
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

  Widget _buildGestureIndicator() {
    return DetailComponents.buildGestureIndicator(
      _playerModule.gestureHintIcon,
      _playerModule.gestureHintValue,
    );
  }

  Widget _buildSpeedHintOverlay() {
    return DetailComponents.buildSpeedHintOverlay(2.0);
  }

  /// 磁力失败的错误面板与普通在线源失败是两套动作：
  /// 磁力要能「重新解析一次」或「直接回去换资源」，而不是重放一个空 URL。
  bool get _isMagnetError =>
      _playerModule.playbackErrorType == PlaybackErrorType.magnetFailed;

  Widget _buildErrorActionButton({
    required String label,
    required bool primary,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: primary ? Colors.blue : Colors.white24,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }

  /// 磁力失败卡片（紧凑版）。
  ///
  /// ⚠️ 必须比在线源那张卡矮：磁力播放器是详情页顶部的小窗（约 300dp 高），
  /// 大图标 + 大间距 + 三段文字会直接 `BOTTOM OVERFLOWED`
  /// （2026-10-28 真机实测溢出 45px，按钮被画到播放器外面去）。
  Widget _buildMagnetErrorCard(AppLocalizations l10n) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                // 「连不上」和「连上了读不出画面」是两件事，图标别再混用同一个断链。
                _playerModule.magnetNoFrameFailure
                    ? Icons.videocam_off_rounded
                    : Icons.link_off_rounded,
                color: const Color(0xFFFF8A80),
                size: 17,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.detailPlaybackErrorMagnet,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            _playerModule.playerErrorMessage,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              height: 1.35,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          // 「为什么失败 + 该怎么办」完整说清楚。
          //
          // 三种磁力失败要分开说：
          // * 交接后一直读不出画面/时长（0:00 黑屏）→ 多半是封装/编码不支持；
          // * 起播阶段彻底停下（stage=-1，例如种子里没有视频文件）；
          // * 播到一半断源（stage=0）。
          Text(
            _playerModule.magnetNoFrameFailure
                ? l10n.detailMagnetNoFrameHint
                : _playerModule.torrentStage == -1
                    ? l10n.detailMagnetExhaustedHint
                    : l10n.detailMagnetStreamLostHint,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          // 2026-10-28 用户明确要求：磁力连不上**不要「再试一次」按钮**，
          // 直接自动重试并给文字提示。重试由 DetailMagnetPlayback.play()
          // 无限循环承担，这里只保留失败结论，不再放置任何按钮；
          // 退出走左上角常驻返回键，换源走下方资源列表。
        ],
      ),
    );
  }

  /// 在线线路失败卡片（保持原有观感：大图标 + 重试）。
  Widget _buildGenericErrorCard(AppLocalizations l10n) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _playbackErrorLabel(),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _playerModule.playerErrorMessage,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          _buildErrorActionButton(
            label: l10n.detailRetry,
            primary: true,
            onTap: () {
              _setState(() {
                _playerModule.retryCount = 0;
                _clearPlaybackError();
              });
              if (_playerModule.currentPlayUrl != null) {
                final pos = _playbackPreservePosition();
                final retryUrl = _playerModule.currentOpenUrl ??
                    _playerModule.activeStreamUrl ??
                    _playerModule.currentPlayUrl!;
                unawaited(
                  _playerModule.playerService.play(retryUrl, startAt: pos),
                );
                if (pos != null) {
                  _playerModule.markResumeStartApplied(pos);
                }
              }
            },
          ),
        ],
      ),
    );
  }

  /// 磁力失败卡片不再提供任何按钮（用户 2026-10-28：直接自动重试，不要按钮）。
  /// 起播阶段由 DetailMagnetPlayback.play() 无限自动重试；只有在「重试也不会有救」
  /// （种子里没有视频文件）时才停下来说原因。断流同样是文字结论 + 返回键退出，
  /// 换源走详情页下方的磁力资源列表。

  /// 磁力阶段总数：启动引擎 → 解析元数据 → 连接节点 → 选定文件 → 缓冲 → 交接。
  static const int _magnetStageTotal = 6;

  /// 只返回**当前这一步**的提示（用户 2026-10-28：提示每次显示一行就够），
  /// 例如「第 2/6 步 · 解析种子元数据」。stage 越界时返回空串，由组件回退到
  /// 原来的 torrentMessage。
  ///
  /// 从第 2 轮起整轮都带「正在自动重试第 N 次」前缀：重试是自动的，用户必须
  /// 一直看得见它在动，而不是只在两次尝试之间的 1.5 秒里闪一下。
  String _magnetStageProgressLabel(AppLocalizations l10n) {
    // 交接完成、正在等第一帧：这时候显示「第 6/6 步 · 交给播放器」会让人
    // 以为已经播上了，而实际画面还是黑的。直接说「正在等画面」。
    if (_playerModule.magnetWaitingFirstFrame) {
      return l10n.detailMagnetWaitingFrame;
    }
    final stage = _playerModule.torrentStage;
    final labels = <String>[
      l10n.detailMagnetStageInit,
      l10n.detailMagnetStageMeta,
      l10n.detailMagnetStagePeers,
      l10n.detailMagnetStagePickFile,
      l10n.detailMagnetStageBuffer,
      l10n.detailMagnetStageHandoff,
    ];
    final stageLabel =
        (stage > 0 && stage <= _magnetStageTotal) ? labels[stage - 1] : '';
    if (_playerModule.magnetRetrying) {
      final attempt = '${_playerModule.torrentAttempt}';
      if (stageLabel.isEmpty) {
        return l10n.detailMagnetAutoRetry(attempt);
      }
      return l10n.detailMagnetAutoRetryStage(attempt, stageLabel);
    }
    if (stageLabel.isEmpty) return '';
    return l10n.detailMagnetStageProgress(
      '$stage',
      '$_magnetStageTotal',
      stageLabel,
    );
  }

  Widget _buildTorrentProgressBar() {
    final t = _playerModule.torrentService;
    final l10n = AppLocalizations.of(context)!;
    return DetailComponents.buildTorrentProgressBar(
      _playerModule.torrentStep,
      _playerModule.torrentMessage,
      downloadSpeed: t.downloadSpeed,
      peers: t.peers,
      seeds: t.seeds,
      activePeers: t.activePeers,
      bufferPct: t.bufferPct,
      etaFormatted: t.etaFormatted,
      metaWait: t.metaWaitFormatted,
      webFallback: kIsWeb,
      deadSwarm: t.handoverWithoutPeers,
      deadSwarmMessage: l10n.detailMagnetNoPeers,
      deadSwarmHint: l10n.detailMagnetNoPeersHint,
      torrentStage: _playerModule.torrentStage,
      stageTotal: _magnetStageTotal,
      stageProgressLabel: _magnetStageProgressLabel(l10n),
      attempt: _playerModule.torrentAttempt,
      // 重试等待期标题已经写了「正在自动重试（第 N 次）」，徽标再标一次是重复。
      attemptLabel: _playerModule.magnetRetrying
          ? ''
          : l10n.detailMagnetAttemptLabel('${_playerModule.torrentAttempt}'),
      onStop: _stopMagnetLoading,
    );
  }

  /// 用户主动停止磁力解析/起流。
  ///
  /// 磁力最长要等 45s，原先没有中途取消入口：用户只能干等，或整页退出
  /// （退出会把详情页一起关掉，历史进度也跟着丢界面）。停止后落到
  /// `magnetFailed` 错误面板，复用它已有的「再试一次 / 换个资源」，
  /// 而不是留一块黑屏让用户猜。
  void _stopMagnetLoading() {
    // 不需要等待完成：停止是「放弃这次加载」，立刻回到可操作界面更重要。
    unawaited(_playerModule.torrentService.stop());
    _setState(() {
      _playerModule.magnetSourcePreparing = false;
      _playerModule.magnetRetrying = false;
      _playerModule.magnetWaitingFirstFrame = false;
      _playerModule.isBuffering = false;
      _playerModule.torrentStep = -1;
      _playerModule.torrentStage = -1;
      const msg = '已停止加载';
      _playerModule.torrentMessage = msg;
      _playerModule.playerErrorMessage = msg;
      _playerModule.playbackErrorType = PlaybackErrorType.magnetFailed;
    });
    DebugLog.log('Magnet', '用户主动停止磁力加载', flush: true);
  }

  Widget _buildShortcutHelpPanel() {
    return DetailComponents.buildShortcutHelpPanel(
      _playerModule.showShortcutHelp,
      showLockShortcut: _supportsPlayerScreenLock,
      onClose: () {
        _setState(() => _playerModule.showShortcutHelp = false);
      },
    );
  }

  void _engagePlayerScreenLock() {
    if (!_supportsPlayerScreenLock) return;
    _setState(() {
      _playerModule.isScreenLocked = true;
      _playerModule.showLockChrome = true;
    });
    _startLockChromeHideTimer();
  }

  void _releasePlayerScreenLock() {
    _setState(() {
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

  /// [delta] 为相对变化量（如键盘 ±10）
  void _adjustVolume(double delta) {
    _setState(() {
      _playerModule.volume =
          (_playerModule.volume + delta).clamp(0.0, DetailPlayer.maxVolumeUi);
      unawaited(_playerModule.playerService.setVolume(_playerModule.volume));
      if (_playerModule.isMuted) {
        _playerModule.muteVolume = _playerModule.volume;
      }
    });
  }

  void _startLockChromeHideTimer() {
    _playerModule.lockChromeHideTimer?.cancel();
    if (!_playerModule.isScreenLocked) return;
    _playerModule.lockChromeHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playerModule.isScreenLocked) {
        _setState(() => _playerModule.showLockChrome = false);
      }
    });
  }
}
