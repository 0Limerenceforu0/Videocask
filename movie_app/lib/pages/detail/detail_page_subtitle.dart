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

  /// 未配置 Key 时**不再弹提示**。
  ///
  /// 2026-10-28 用户要求：这个 SnackBar 每进一次详情页就弹一次（状态标志只活在
  /// 单个页面 State 里，页面重建即失效），非常打扰。引导文案已在
  /// 「设置 → OpenSubtitles API Key」里常驻，无需在每次起播时重复打扰。
  void _hintSubtitleApiKeyIfNeeded() {
    debugPrint('字幕自动匹配: 未配置 OpenSubtitles API Key，已跳过（不再弹提示）');
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
    _setState(() {
      _playerModule.showSubtitles = true;
      _playerModule.subtitleFileName = pick.fileName;
    });
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
    _setState(() => _playerModule.showSubtitles = true);
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
                          _setState(() => _playerModule.showSubtitles = true);
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
}
