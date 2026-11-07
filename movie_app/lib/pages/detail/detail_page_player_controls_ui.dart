part of 'detail_page.dart';

// 由 detail_page_player_ui.dart 拆分而来：控制栏 / 进度条 / 手势 / 错误面板 / 锁屏。
// 同为 extension on _DetailPageState，可直接访问原类私有成员。

extension _DetailPagePlayerControlsUiExt on _DetailPageState {
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
                          '${(_playerModule.volume * 100).round()}',
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
                                  final wasMuted = _playerModule.isMuted;
                                  _setState(() {
                                    _playerModule.volume = v;
                                    _playerModule.isMuted = false;
                                  });
                                  // 静音是「mpv 增益 0」，拖滑块解除静音时必须把增益
                                  // 恢复到 100，否则界面显示未静音、实际仍然没有声音。
                                  if (wasMuted) {
                                    unawaited(
                                      _playerModule.playerService
                                          .setVolume(100),
                                    );
                                  }
                                  unawaited(_playerModule.setVolume(v));
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
    // 只订阅播放位置的高频通知：避免每 200ms 把整页 setState 一遍。
    return ValueListenableBuilder<Duration>(
      valueListenable: _playerModule.positionListenable,
      builder: (context, _, __) => LayoutBuilder(
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
      ),
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
    // 2026-11-03：进度条取值不再交给组件自己按「第 N/6 步」线性推。
    // 阶段号不代表完成度（卡在第 5 步时它一直画 71% 不动，看着像马上就好），
    // 改由 [MagnetPrepProgressPolicy] 决定：有真实缓冲百分比用真实数据，
    // 卡在同一阶段太久或已交给播放器 → 返回 null 走不确定态。
    final stageProgressLabel = _magnetStageProgressLabel(l10n);
    final showStages = MagnetPrepProgressPolicy.showStages(
      stageTotal: _magnetStageTotal,
      torrentStage: _playerModule.torrentStage,
      stageProgressLabel: stageProgressLabel,
      deadSwarm: t.handoverWithoutPeers,
    );
    return MagnetPrepStageWatcher(
      stage: _playerModule.torrentStage,
      builder: (context, stageElapsed) {
        final value = MagnetPrepProgressPolicy.progressValue(
          torrentStep: _playerModule.torrentStep,
          torrentStage: _playerModule.torrentStage,
          stageTotal: _magnetStageTotal,
          bufferPct: t.bufferPct,
          stageElapsed: stageElapsed,
          showStages: showStages,
        );
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
          stageProgressLabel: stageProgressLabel,
          attempt: _playerModule.torrentAttempt,
          // 重试等待期标题已经写了「正在自动重试（第 N 次）」，徽标再标一次是重复。
          attemptLabel: _playerModule.magnetRetrying
              ? ''
              : l10n.detailMagnetAttemptLabel('${_playerModule.torrentAttempt}'),
          onStop: _stopMagnetLoading,
          progressValue: value,
          indeterminate: value == null,
        );
      },
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
        child: PlayerOverlayIconButton(
          icon: locked ? Icons.lock_outline : Icons.lock_open,
          tooltip: semanticsLabel,
          onTap: onTap,
          iconSize: 20,
          padding: 8,
          color: Colors.white70,
        ),
      ),
    );
  }

  /// [delta] 为相对变化量（如键盘 ±10）
  void _adjustVolume(double delta) {
    final v =
        (_playerModule.volume + delta).clamp(0.0, DetailPlayer.maxVolumeUi);
    _setState(() {
      _playerModule.volume = v;
    });
    unawaited(_playerModule.setVolume(v));
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
