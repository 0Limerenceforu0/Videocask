part of 'detail_page.dart';

// 由 detail_page.dart 拆分而来：方法体逐字搬运，
// 通过 extension on _DetailPageState 直接访问原类的私有成员。

extension _DetailPageSubtitleExt on _DetailPageState {
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
    int? season,
    int? episode,
  }) _subtitleQueryOf(Movie movie) {
    final release = _playerModule.currentMagnetFileName.trim();
    final year = int.tryParse(movie.year.trim());
    // 片名/别名/简介/种子文件名里带 tt-id 时直接用；否则由调用方走免费的
    // IMDb 联想接口按片名+年份解析（2026-11-06 实测无 Key 可用）。
    // 之前这里写死 null，免费源永远查不到，是在线字幕链路断电的原因之一。
    final imdbId = ImdbLookupService.parseImdbIdFromText(
      '${movie.name} ${movie.alias} ${movie.description} $release',
    );
    // S5：剧集季集号从 seed release 名 / 片名解析，供免费源走
    // `/subtitles/series/tt:S:E.json`；电影名里的年份不会被误判成季集。
    final se = parseSubtitleSeasonEpisode(
      release,
      '${movie.name} ${movie.alias}',
    );
    return (
      title: movie.name.trim(),
      releaseName: release.isEmpty ? null : release,
      imdbId: imdbId,
      year: year,
      season: se.season,
      episode: se.episode,
    );
  }

  /// 自动匹配与手动浏览共用的 IMDb 解析：先用文本里的 tt-id，否则走
  /// 免费的 IMDb 联想接口。失败返回 null，调用方按「未找到」处理。
  Future<String?> _resolveSubtitleImdbId(Movie movie) async {
    final q = _subtitleQueryOf(movie);
    if (q.imdbId != null && q.imdbId!.isNotEmpty) return q.imdbId;
    try {
      return await ImdbLookupService.instance.resolveForVideoTitle(
        q.title,
        year: movie.year.trim().isEmpty ? null : movie.year.trim(),
        alias: movie.alias.trim().isEmpty ? null : movie.alias.trim(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 「能直接拿到就直接用」：先读片源内封中文轨（零原生改动、简体优先），
  /// 没有再走免费在线中文源。整条链路无 Key、无配置、无点击。
  Future<void> _maybeAutoMatchSubtitlePlay(Movie movie, String playUrl) async {
    if (kIsWeb) return;
    if (!_shouldTrySubtitleAutoMatch(movie, playUrl)) return;
    if (_subtitleAutoMatchedForUrl == playUrl) return;
    _subtitleAutoMatchedForUrl = playUrl;
    // 换集必定作废旧的字幕任务，避免上一集的字幕串到新一集
    //（即便本集有内封中文轨而不再走种子内字幕层）。
    MagnetSubtitleService().cancel();
    if (!mounted) return;

    // ① 片源自带中文轨优先，简体在前。
    if (await _applyEmbeddedChineseSubtitle()) return;

    // ①.5 种子内独立中文字幕（S3）：只有内封轨没有时才额外建短命磁力任务。
    if (await _applyTorrentChineseSubtitle()) return;

    // ② 内封与种子内都没有，再查免费在线源（失败静默降级、不弹窗）。
    await _applyFreeOnlineChineseSubtitle(movie);
  }

  /// 内封字幕状态回读：把 mpv 侧的可见性/轨道/文本一起落盘，
  /// 用于区分「轨没选中」与「选中了但没渲染（libass / 可见性 / hwdec）」。
  Future<void> _dumpEmbeddedSubtitleState(int expectedSid) async {
    // 等字幕真正进入渲染阶段再读，避免拿到空文本误判。
    await Future<void>.delayed(const Duration(seconds: 6));
    final player = _playerModule.playerService.player;
    if (player == null) return;
    try {
      final sid = await getMpvProperty(player, 'sid');
      final visibility = await getMpvProperty(player, 'sub-visibility');
      final subAss = await getMpvProperty(player, 'sub-ass');
      final current = await getMpvProperty(player, 'current-tracks/sub');
      final subText = await getMpvProperty(player, 'sub-text') ?? '';
      final rawTracks = await getMpvProperty(player, 'track-list') ?? '';
      final head = subText.length > 60
          ? '${subText.substring(0, 60)}…'
          : subText;
      DebugLog.log(
        'Subtitle',
        '内封轨回读: 期望sid=$expectedSid 实际sid=$sid '
        'visibility=$visibility sub-ass=$subAss '
        'current-track=${current ?? '-'} sub-text=$head '
        'tracks=${rawTracks.length > 900 ? rawTracks.substring(0, 900) : rawTracks}',
      );
    } catch (e) {
      DebugLog.log('Subtitle', '内封轨回读失败: $e');
    }
  }

  /// 从种子里独立的 `.srt/.ass` 取中文字幕并挂载。
  /// 返回 false 表示没有可用字幕，调用方继续走在线层。
  Future<bool> _applyTorrentChineseSubtitle() async {
    final uri = _playerModule.lastMagnetUri;
    if (uri.isEmpty) return false;
    String? path;
    try {
      path = await MagnetSubtitleService().fetchChineseSubtitle(
        magnetUri: uri,
      );
    } catch (e) {
      debugPrint('字幕自动匹配: 种子内字幕异常: $e');
      return false;
    }
    if (!mounted || path == null) return false;
    await _playerModule.playerService.setExternalSubtitleFromFile(path);
    if (!mounted) return true;
    _setState(() {
      _playerModule.showSubtitles = true;
      _playerModule.subtitleFileName = '种子内中文字幕';
    });
    debugPrint('字幕自动匹配: 已挂种子内中文字幕 $path');
    // S4：时轴体检只做诊断，不阻塞字幕挂载结果。
    unawaited(
      _inspectSubtitleTiming(
        label: '种子内',
        subtitlePath: path,
        subtitleName: path,
      ),
    );
    return true;
  }

  /// 读 mpv `track-list`，挑一条简体优先的中文字幕轨并选中。
  /// 返回 false 表示没有可用中文轨，调用方继续走在线层。
  Future<bool> _applyEmbeddedChineseSubtitle() async {
    final player = _playerModule.playerService.player;
    if (player == null) return false;
    String? raw;
    try {
      raw = await getMpvProperty(player, 'track-list');
    } catch (e) {
      debugPrint('字幕自动匹配: 读取 track-list 失败: $e');
      return false;
    }
    final tracks = parseMpvSubtitleTracks(raw);
    final chinese = tracks.where(isChineseSubtitle).toList();
    if (chinese.isEmpty) return false;

    final sorted = sortChineseTracksSimplifiedFirst(chinese);
    final pick = sorted.first;
    DebugLog.log(
      'Subtitle',
      '内封轨候选: '
      '${sorted.map((t) => 'id=${t.id}/lang=${t.lang}/title=${t.title}').join(' | ')}',
    );
    // 语言偏好先下发：即使显式 sid 因 track id 语义不同而被 mpv 拒绝，
    // `sid=auto` 也能按 slang 顺序挑到中文轨。
    try {
      await setMpvProperty(player, 'slang', 'chi,zho,zh,chs,cht,zh-Hans');
    } catch (e) {
      debugPrint('字幕自动匹配: 设置 slang 失败: $e');
    }
    try {
      await setMpvProperty(player, 'sid', '${pick.id}');
      // 属性通道在部分 libmpv 构建上对 sid 不生效（实测设 1 后读回 no），
      // 再走命令通道 `set sid` 与 `sub-select` 兜底。
      await runMpvCommand(player, ['set', 'sid', '${pick.id}']);
      await runMpvCommand(player, ['sub-select', '${pick.id}']);
    } catch (e) {
      debugPrint('字幕自动匹配: 设置 sid 失败: $e');
      return false;
    }
    // 立即回读：区分「sid 设置被 mpv 拒绝」与「设置成功后又被别处覆盖」。
    try {
      final applied = await getMpvProperty(player, 'sid');
      DebugLog.log('Subtitle', '内封轨设置后立即回读: sid=$applied（期望 ${pick.id}）');
      if (applied == null || applied == 'no') {
        // track-list 的 id 在部分 libmpv 构建上按类型独立编号（video/audio/sub
        // 都可能是 1），`sid=<id>` 会被拒。这里暴力探测 1..N，以
        // `current-tracks/sub` 是否真的挂上作为判据，成功后立即生效。
        final limit = tracks.length + 8;
        for (var id = 1; id <= limit; id++) {
          await setMpvProperty(player, 'sid', '$id');
          final cur = await getMpvProperty(player, 'current-tracks/sub');
          final ok = cur != null && cur.trim().isNotEmpty && cur.trim() != '{}';
          DebugLog.log('Subtitle', '内封轨探测 sid=$id → ${ok ? "命中" : "空"}');
          if (ok) break;
        }
        final retried = await getMpvProperty(player, 'sid');
        DebugLog.log('Subtitle', '内封轨探测结束: sid=${retried ?? '-'}');
      }
    } catch (e) {
      DebugLog.log('Subtitle', '内封轨立即回读失败: $e');
    }
    if (!mounted) return true;
    final variant = classifyChineseVariant(lang: pick.lang, title: pick.title);
    final variantLabel =
        variant == ChineseVariant.traditional ? '繁体' : '简体';
    _setState(() {
      _playerModule.showSubtitles = true;
      _playerModule.subtitleFileName =
          pick.title?.trim().isNotEmpty == true ? pick.title! : '内封中文字幕';
    });
    debugPrint(
      '字幕自动匹配: 已挂内封中文轨 sid=${pick.id} '
      'lang=${pick.lang ?? '-'} $variantLabel',
    );
    // 诊断：回读 mpv 真实生效的字幕状态。用于区分「轨没选中」与
    // 「选中了但没渲染（libass/hwdec/可见性）」——后者画面无字幕但状态正常。
    unawaited(_dumpEmbeddedSubtitleState(pick.id));
    // 内封轨没有独立文件，只做帧率归一与可选的 sub-speed 纠偏。
    unawaited(
      _inspectSubtitleTiming(
        label: '内封轨',
        subtitleName: pick.title,
      ),
    );
    return true;
  }

  /// 免费在线源：片名/文本里的 IMDb 优先，否则用免费的 IMDb 联想接口解析。
  Future<void> _applyFreeOnlineChineseSubtitle(Movie movie) async {
    final q = _subtitleQueryOf(movie);
    final imdbId = await _resolveSubtitleImdbId(movie);
    if (imdbId == null || imdbId.isEmpty) {
      DebugLog.log('Subtitle', '自动匹配: 片名未能解析到 IMDb，跳过在线源');
      return;
    }
    final svc = SubtitleService();
    final list = await svc.searchFreeChinese(
      imdbId: imdbId,
      season: q.season,
      episode: q.episode,
    );
    if (!mounted || list.isEmpty) {
      DebugLog.log(
        'Subtitle',
        '自动匹配: 在线源无中文字幕（imdb=$imdbId '
        'S${q.season ?? 0}E${q.episode ?? 0}）${svc.lastError}',
      );
      return;
    }
    final path = await svc.downloadFreeSubtitle(list.first);
    if (!mounted || path == null) return;
    await _playerModule.playerService.setExternalSubtitleFromFile(path);
    if (!mounted) return;
    _setState(() {
      _playerModule.showSubtitles = true;
      _playerModule.subtitleFileName = list.first.fileName;
    });
    debugPrint('字幕自动匹配: 已挂在线简中字幕 ${list.first.fileName}');
    unawaited(
      _inspectSubtitleTiming(
        label: '在线简中',
        subtitlePath: path,
        subtitleName: '${list.first.fileName} ${list.first.releaseName}',
      ),
    );
  }

  /// S4：字幕挂载后的时轴体检。**只诊断，不自动乱调**。
  ///
  /// 仍挂在首帧成功后 4s 的链路里，全程 unawaited + 静默降级，不污染
  /// 25s / 40s 起播看门狗。三件事：
  /// ① 读 mpv `container-fps` / `estimated-vf-fps` / `duration` 并归一记日志；
  /// ② 只有字幕名里**明确写出**基准帧率、且属于 25 ↔ 23.976/24 转换时才设
  ///    `sub-speed`，其它情况一律不碰时间轴；
  /// ③ 读字幕 cue 跨度与片长比对，明确不匹配时只给一次「换一个字幕」提示。
  ///
  /// 「首个音轨活动 / 场景切换」当前 mpv 链路读不到，因此不参与判定
  ///（纯函数层保留为可选入参）。Web 无 mpv 属性桥，S6 之前保持跳过。
  Future<void> _inspectSubtitleTiming({
    required String label,
    String? subtitlePath,
    String? subtitleName,
  }) async {
    if (kIsWeb) return;
    final player = _playerModule.playerService.player;
    if (player == null) return;

    String? containerFps;
    String? vfFps;
    String? durationRaw;
    try {
      containerFps = await getMpvProperty(player, 'container-fps');
      vfFps = await getMpvProperty(player, 'estimated-vf-fps');
      durationRaw = await getMpvProperty(player, 'duration');
    } catch (e) {
      debugPrint('字幕时轴: 读取 mpv 属性失败: $e');
      return;
    }
    final videoRate = resolvePlaybackFrameRate(
      containerFps: containerFps,
      estimatedVfFps: vfFps,
    );
    final duration = double.tryParse(durationRaw?.trim() ?? '') ?? 0;
    DebugLog.log(
      'Subtitle',
      '时轴体检[$label]: container=${containerFps ?? '?'} '
      'vf=${vfFps ?? '?'} 归一=${videoRate.label}fps '
      '片长=${duration.toStringAsFixed(1)}s',
    );

    // 明确标记 + PAL/电影帧组合才设 sub-speed；拿不到证据就什么都不做。
    final baseRate = detectSubtitleBaseFrameRate(subtitleName);
    final speed = computeSubSpeed(video: videoRate, subtitleBase: baseRate);
    if (speed != null && speed != 1.0) {
      try {
        await setMpvProperty(player, 'sub-speed', speed.toStringAsFixed(5));
        DebugLog.log(
          'Subtitle',
          '时轴体检[$label]: 帧率标记=${baseRate?.label}fps → sub-speed=$speed',
        );
      } catch (e) {
        debugPrint('字幕时轴: 设置 sub-speed 失败: $e');
      }
    }

    if (subtitlePath == null || subtitlePath.isEmpty) return;
    final text = await SubtitleService().readCachedSubtitleText(subtitlePath);
    if (!mounted || text == null) return;
    final range = parseSubtitleCueRange(text);
    final verdict = judgeSubtitleMatch(
      range: range,
      videoDurationSeconds: duration,
    );
    DebugLog.log(
      'Subtitle',
      '时轴体检[$label]: cue=${range.cueCount} '
      '首=${range.firstCueSeconds?.toStringAsFixed(1) ?? '?'}s '
      '跨度=${range.spanSeconds.toStringAsFixed(1)}s 判定=${verdict.name}',
    );
    if (verdict != SubtitleMatchVerdict.mismatched || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(subtitleMismatchHint)),
    );
  }

  /// 用 AI 离线识别生成本地中文字幕，并挂到当前播放器。
  Future<void> _runAiSubtitleGeneration(Movie movie) async {
    final source =
        _playerModule.activeStreamUrl ?? _playerModule.currentOpenUrl ?? '';
    if (source.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有可识别的视频源')),
      );
      return;
    }

    await runSubtitleAiGeneration(
      context: context,
      source: source,
      title: movie.name,
      onReady: _attachAiSubtitle,
    );
  }

  /// 把 AI 生成的字幕挂到播放器。
  ///
  /// [srtOrPath] 有两种形态：桌面/移动端是已落盘的 **SRT 文件路径**，
  /// Web（无本地文件系统）是 **SRT 文本**。用内容里有没有时间轴分隔符
  /// `-->` 来区分，避免引入 `dart:io` 破坏 Web 构建。
  Future<void> _attachAiSubtitle(String srtOrPath) async {
    if (srtOrPath.trim().isEmpty) return;
    final player = _playerModule.playerService.player;
    if (player == null) return;

    final track = srtOrPath.contains('-->')
        ? SubtitleTrack.data(
            srtOrPath,
            title: 'AI 中文字幕',
            language: 'zh',
          )
        : SubtitleTrack.uri(
            Uri.file(srtOrPath).toString(),
            title: 'AI 中文字幕',
            language: 'zh',
          );
    await player.setSubtitleTrack(track);
    if (mounted) {
      _setState(() => _playerModule.showSubtitles = true);
    }
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
              // AI 离线生成中文字幕。
              // 注意：本入口之前只接在 player_page 上，而 PlayerPage 在整个 App 里
              // 没有任何跳转点、也没注册进路由 —— 等于永远打不开，用户看不到。
              // 详情页才是实际播放路径，入口必须在这里。
              if (!kIsWeb)
                ListTile(
                  leading: const Icon(Icons.graphic_eq_outlined),
                  title: const Text('本地离线生成中文字幕'),
                  subtitle: const Text('无需联网，首次需下载约 50MB 模型'),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_runAiSubtitleGeneration(movie));
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
                    _setState(() => _playerModule.showSubtitles = false);
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
    _setState(() => _playerModule.subtitleDelaySeconds = v);
  }

  /// 重置外挂字幕时间轴偏移。
  Future<void> _resetSubtitleDelay() async {
    if (kIsWeb) return;
    await _playerModule.playerService.setSubtitleDelaySeconds(0);
    if (!mounted) return;
    _setState(() => _playerModule.subtitleDelaySeconds = 0);
  }

  /// 手动「在线自动匹配」：与自动链共用免费的 IMDb 解析与在线源。
  /// S5 起不再有 API Key 门槛，也不需要 login。
  Future<void> _runSubtitleAutoMatch(Movie movie) async {
    if (kIsWeb) return;
    final l10n = AppLocalizations.of(context)!;
    final svc = SubtitleService();
    final imdbId = await _resolveSubtitleImdbId(movie);
    if (!mounted) return;
    if (imdbId == null || imdbId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未能解析到 IMDb，无法在线匹配字幕')),
      );
      return;
    }
    final q = _subtitleQueryOf(movie);
    final list = await svc.searchFreeChinese(
      imdbId: imdbId,
      season: q.season,
      episode: q.episode,
    );
    if (!mounted) return;
    if (list.isEmpty) {
      final reason = svc.lastError.isNotEmpty
          ? svc.lastError
          : l10n.detailPlayerSubtitleNone;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason)),
      );
      return;
    }
    final pick = list.first;
    final path = await svc.downloadFreeSubtitle(pick);
    if (!mounted) return;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            svc.lastError.isNotEmpty
                ? svc.lastError
                : l10n.detailPlayerSubtitleApplyFailed,
          ),
        ),
      );
      return;
    }
    await _playerModule.playerService.setExternalSubtitleFromFile(path);
    if (!mounted) return;
    _setState(() {
      _playerModule.showSubtitles = true;
      _playerModule.subtitleFileName = pick.fileName;
    });
    unawaited(
      _inspectSubtitleTiming(
        label: '手动在线',
        subtitlePath: path,
        subtitleName: '${pick.fileName} ${pick.releaseName}',
      ),
    );
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
      _setState(() => _playerModule.showSubtitles = true);
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
    final svc = SubtitleService();
    final imdbId = await _resolveSubtitleImdbId(movie);
    if (!mounted) return;
    final q = _subtitleQueryOf(movie);
    final list = (imdbId == null || imdbId.isEmpty)
        ? <SubtitleInfo>[]
        : await svc.searchFreeChinese(
            imdbId: imdbId,
            season: q.season,
            episode: q.episode,
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
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        (imdbId == null || imdbId.isEmpty)
                            ? '未能解析到 IMDb，无法在线匹配字幕'
                            : (svc.lastError.isNotEmpty
                                ? svc.lastError
                                : l10n.detailPlayerSubtitleNone),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
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
                          '${s.language} · '
                          '${s.releaseName.isEmpty ? s.providerId : s.releaseName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          if (!mounted) return;
                          final path = await svc.downloadFreeSubtitle(s);
                          if (!mounted) return;
                          if (path == null) {
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  svc.lastError.isNotEmpty
                                      ? svc.lastError
                                      : l10n.detailPlayerSubtitleApplyFailed,
                                ),
                              ),
                            );
                            return;
                          }
                          await _playerModule.playerService
                              .setExternalSubtitleFromFile(path);
                          if (!mounted) return;
                          _setState(() {
                            _playerModule.showSubtitles = true;
                            _playerModule.subtitleFileName = s.fileName;
                          });
                          unawaited(
                            _inspectSubtitleTiming(
                              label: '手动浏览',
                              subtitlePath: path,
                              subtitleName: '${s.fileName} ${s.releaseName}',
                            ),
                          );
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
}
