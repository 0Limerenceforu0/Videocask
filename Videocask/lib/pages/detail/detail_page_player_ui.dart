part of 'detail_page.dart';

// 由 detail_page.dart 拆分而来：方法体逐字搬运，
// 通过 extension on _DetailPageState 直接访问原类的私有成员。

extension _DetailPagePlayerUiExt on _DetailPageState {
  /// 焦点是否落在文本输入框里（此时空格 / 方向键属于文本编辑，不能抢）。
  bool _isTextInputFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// 页面级按键处理，由 initState 注册到 [HardwareKeyboard]。
  ///
  /// 🔴 2026-11-07：旧实现把 `KeyboardListener` 放在播放器子树里，而
  /// `KeyboardListener.autofocus` 默认 false、唯一的 requestFocus 又在
  /// videoController 尚未创建时执行；更致命的是切全屏会整棵换掉播放器子树
  /// → 焦点丢失 → ESC 退不出全屏、空格不暂停。全局 handler 不依赖焦点树，
  /// 页面级 Focus 只负责让窗口保持键盘焦点。
  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final isRepeat = event is KeyRepeatEvent;

    final shortcut = resolvePlayerShortcut(
      key: event.logicalKey,
      isShiftPressed: HardwareKeyboard.instance.isShiftPressed,
      isRepeat: isRepeat,
      helpVisible: _playerModule.showShortcutHelp,
      textInputFocused: _isTextInputFocused(),
      routeIsCurrent: ModalRoute.of(context)?.isCurrent ?? true,
      playerActive: _playerModule.currentPlayUrl != null,
      supportsScreenLock: _supportsPlayerScreenLock,
    );
    if (shortcut.isNone) return false;

    switch (shortcut.action) {
      case PlayerShortcutAction.none:
        return false;
      case PlayerShortcutAction.escape:
        if (_playerModule.showShortcutHelp) {
          _setState(() => _playerModule.showShortcutHelp = false);
        } else if (_playerModule.showVolumePopover) {
          _setState(() => _playerModule.showVolumePopover = false);
        } else if (_playerModule.isFullScreen) {
          unawaited(_applyDetailFullscreen(false));
        }
        return true;
      case PlayerShortcutAction.toggleHelp:
        _setState(
          () => _playerModule.showShortcutHelp =
              !_playerModule.showShortcutHelp,
        );
        if (_playerModule.showShortcutHelp) {
          _playerModule.hideTimer?.cancel();
        } else {
          _startHideTimer();
        }
        return true;
      case PlayerShortcutAction.togglePlayPause:
        _togglePlayPause();
        _startHideTimer();
        return true;
      case PlayerShortcutAction.toggleFullscreen:
        unawaited(_applyDetailFullscreen(!_playerModule.isFullScreen));
        _startHideTimer();
        return true;
      case PlayerShortcutAction.toggleMute:
        _toggleMute();
        return true;
      case PlayerShortcutAction.toggleLock:
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
        return true;
      case PlayerShortcutAction.volumeUp:
        _adjustVolume(0.1);
        _startHideTimer();
        return true;
      case PlayerShortcutAction.volumeDown:
        _adjustVolume(-0.1);
        _startHideTimer();
        return true;
      case PlayerShortcutAction.seekBack5:
      case PlayerShortcutAction.seekBack10:
        _seekRelative(shortcut.action == PlayerShortcutAction.seekBack10
            ? -10
            : -5);
        _startHideTimer();
        return true;
      case PlayerShortcutAction.seekForward5:
      case PlayerShortcutAction.seekForward10:
        _seekRelative(shortcut.action == PlayerShortcutAction.seekForward10
            ? 10
            : 5);
        _startHideTimer();
        return true;
      case PlayerShortcutAction.toggleSubtitles:
        _setState(
          () => _playerModule.showSubtitles = !_playerModule.showSubtitles,
        );
        _startHideTimer();
        return true;
      case PlayerShortcutAction.speedDown:
        _cycleSpeed(-1);
        return true;
      case PlayerShortcutAction.speedUp:
        _cycleSpeed(1);
        return true;
      case PlayerShortcutAction.seekToFraction:
        final fraction = shortcut.fraction;
        if (fraction != null) _seekToPercent(fraction);
        _startHideTimer();
        return true;
      case PlayerShortcutAction.nextEpisode:
        _playNextEpisode();
        _startHideTimer();
        return true;
      case PlayerShortcutAction.prevEpisode:
        _playPreviousEpisode();
        _startHideTimer();
        return true;
    }
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
      ],
    );
  }

  Widget _buildVideoPlayer(Movie movie, double playerHeight) {
    final l10n = AppLocalizations.of(context)!;
    // 已初始化播放器
    if (_playerModule.videoController != null) {
      final showRoutePickerInPlayerChrome =
          _showRoutePickerInPlayerChrome(context, movie);
      // 快捷键不再挂在这里：切全屏时本子树会整体换父节点，FocusNode 必然失焦。
      // 见 _handleGlobalKeyEvent（注册在页面级 HardwareKeyboard 上）。
      final playerSurface = Listener(
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
                    // 新一次手势：清掉上一次残留的累计位移，否则首帧会跳一下。
                    _playerModule.pendingGestureDy = 0;
                    _playerModule.verticalGestureActive = true;
                    _setState(() {
                      _playerModule.verticalGestureIsLeftSide = isLeftSide;
                      if (isLeftSide) {
                        _playerModule.gestureHintIcon = Icons.brightness_medium;
                        _playerModule.gestureHintValue =
                            _playerModule.brightness;
                        _playerModule.isBrightnessGesture = true;
                      } else {
                        _playerModule.gestureHintIcon = Icons.volume_up;
                        // volume 已是 0.0–1.0 归一化值，不能再除 200（旧 mpv 量程残留）。
                        _playerModule.gestureHintValue = _playerModule.volume;
                        _playerModule.isBrightnessGesture = false;
                      }
                      _playerModule.showGestureHint = true;
                      _playerModule.gestureProgress = isLeftSide
                          ? _playerModule.brightness
                          : _playerModule.volume;
                      _playerModule.showGestureBar = true;
                    });
                    if (isLeftSide && !kIsWeb) {
                      unawaited(_refreshBrightnessFromSystem());
                    } else if (!isLeftSide) {
                      // 用系统真实音量当起点：App 内 volume 可能因错过广播而陈旧，
                      // 不拉齐会导致「系统 67% 时一上滑先跳到 0」。
                      unawaited(_playerModule.syncSystemVolume(force: true));
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
                    // 手势结束时把最后一段还没到节流窗口的位移补上，否则每次拖动
                    // 都会丢掉末尾 ~50ms 的量，短促滑动尤其明显。
                    _flushVerticalGesture();
                    _playerModule.verticalGestureActive = false;
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
                      _playerModule.playbackErrorType != PlaybackErrorType.none,
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

                // 字幕叠加层：只在 mpv 画不了字幕时兜底
                // （Android vo=mediacodec_embed / Web）。
                // 常态下字幕由 mpv/libass 画进视频帧，这里再叠一层就会出现
                // 「同一句台词上下两份 + 半透明黑底」，且投屏/截图与手机屏不一致。
                if (shouldShowFlutterOverlay(
                  showSubtitles: _playerModule.showSubtitles,
                  renderer: _playerModule.subtitleRenderer,
                  subtitleText: _playerModule.currentSubtitleText,
                ))
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

        // 画面比例模式：cropFill（旧的「全屏裁剪」选项）与用户手动切的「铺满」
        // 都走 cover；其余一律 contain（原始比例、对称留边，绝不变形/裁切）。
        // 旧逻辑非全屏无条件 fitWidth：当片源比槽「高」（4:3/方图/竖屏进宽槽）
        // 时会纵向溢出裁切，且片源比槽「宽」时也无法保证水平居中 —— 这就是
        // 之前出现「右边单边黑带」的根。统一 contain 后，所有留边自动对称。
        final fit = resolvePlayerFit(
          cropFill: cropFill,
          fitCover: _playerModule.fitCover,
        );

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
            // 前后台行为由 BackgroundPlaybackPolicy 统一接管：
            // media_kit 的默认值是「切后台自动暂停 + 回前台不恢复」，
            // 实测导致切出去 60 秒回来还停在原地（playing=false）。
            // 关掉它，改由详情页的 didChangeAppLifecycleState 按用户设置决定。
            pauseUponEnteringBackgroundMode: false,
          ),
        );

        // 全屏、或用户选了「铺满」：让视频填充满整个播放槽（cover 会裁掉溢出部分）。
        // 否则走原始比例居中（contain 的 letterbox/pillarbox 由 media_kit 内部 FittedBox 居中）。
        if (_playerModule.isFullScreen || _playerModule.fitCover) {
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

  /// 切换画面铺满/原始，并持久化选择。
  void _toggleFitCover() {
    _setState(() => _playerModule.fitCover = !_playerModule.fitCover);
    unawaited(
      StorageService().saveBoolSetting(
        AppConstants.keyPlayerFitCover,
        _playerModule.fitCover,
      ),
    );
    _startHideTimer();
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
      // 画面比例（留边 / 铺满）：放进顶栏而不是画面中部悬浮，避免与垂直居中的
      // 锁钮撞到同一水平带、也避免遮挡画面；顶栏在控制栏显示时全屏/非全屏都可达。
      _buildPlayerTopBarIcon(
        icon: _playerModule.fitCover
            ? Icons.aspect_ratio_rounded
            : Icons.fit_screen_rounded,
        tooltip: _playerModule.fitCover
            ? l10n.detailPlayerFitToContainHint
            : l10n.detailPlayerFitToCoverHint,
        compact: compact,
        onTap: _toggleFitCover,
      ),
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
    final l10n = AppLocalizations.of(context)!;
    final compact = _isMobilePlatform && !kIsWeb && !_playerModule.isFullScreen;
    final (pad, iconSize) = _playerTopBarButtonMetrics(compact: compact);
    return PlayerOverlayIconButton(
      icon: Icons.arrow_back,
      tooltip: l10n.detailPlayerTooltipBack ?? '',
      onTap: () {
        if (_playerModule.isFullScreen) {
          unawaited(_toggleFullScreen());
        } else {
          unawaited(_leaveDetailPage());
        }
      },
      iconSize: iconSize,
      padding: pad,
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
      child: PlayerOverlayIconButton(
        icon: icon,
        tooltip: tooltip,
        onTap: onTap,
        iconSize: iconSize,
        padding: pad,
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
                          ValueListenableBuilder<Duration>(
                            valueListenable: _playerModule.positionListenable,
                            builder: (context, _, __) => Text(
                              // 时长没解析出来（磁力起播、直播）时右侧显示
                              // `--:--`，别再出现 `0:01 / 0:00` 的倒挂。
                              DetailVideoLayout.formatPlaybackClock(
                                _controlsDisplayPosition(),
                                _playerModule.duration,
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
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
}
