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
    // 在线线路同样需要自动字幕：原先这里 `return false`，把全部非磁力片源
    // 挡在自动匹配之外，真机实测（2026-11-08 在线线路《流浪地球》）一条
    // `[Subtitle]` 日志都没有，用户看到的就是「在线看完全没字幕」。
    // 放行是安全的：① 内封中文轨仍由 _applyEmbeddedChineseSubtitle 优先；
    // ② 种子内字幕层有 `lastMagnetUri.isEmpty → false` 的 guard，不会
    //    给在线源误建磁力任务；③ 在线源失败走静默降级，不弹窗不阻塞。
    return true;
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
    // 🔴 磁力详情页偶尔把 btih 哈希塞进 Movie.name（真机 2026-11-08
    // `原始=9a384d...` → IMDb tt0230911 → 在线源无中文字幕）。这时优先用
    // 种子内 release 名，再退到影片别名，绝不拿哈希当片名去查。
    final rawTitle = movie.name.trim();
    final nameIsOpaqueId = RegExp(r'^[0-9a-fA-F]{24,}$')
        .hasMatch(rawTitle.replaceAll(RegExp(r'[\s.\-_:/\[\]]+'), ''));
    final title = nameIsOpaqueId
        ? (release.isNotEmpty
            ? release
            : (movie.alias.trim().isNotEmpty ? movie.alias.trim() : rawTitle))
        : rawTitle;
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
      title: title,
      releaseName: release.isEmpty ? null : release,
      imdbId: imdbId,
      year: year,
      season: se.season,
      episode: se.episode,
    );
  }

  /// 自动匹配与手动浏览共用的 IMDb 解析。
  ///
  /// 磁力详情页的 `Movie.name` 常是整串 release 名，例如
  /// `[DBD-Raws][流浪地球/The.Wandering.Earth.][1080P][BDRip][简体内封][MKV]`。
  /// 之前把它原封不动丢给 IMDb 联想，命中率为 0（真机日志
  /// 「片名未能解析到 IMDb」）。这里先剥出干净的中英文片名，再按
  /// 「英文直查 IMDb 联想 → 中文多源解析 → 英文多源解析 → 原始串」逐路尝试。
  Future<String?> _resolveSubtitleImdbId(Movie movie) async {
    final q = _subtitleQueryOf(movie);
    if (q.imdbId != null && q.imdbId!.isNotEmpty) return q.imdbId;

    final t = extractSubtitleTitleQuery(
      primary: q.title,
      releaseName: q.releaseName ?? '',
    );
    final fallbackYear =
        movie.year.trim().isEmpty ? null : movie.year.trim();
    final year = t.year ?? fallbackYear;
    final aliasFromMovie =
        movie.alias.trim().isEmpty ? null : movie.alias.trim();

    DebugLog.log(
      'Subtitle',
      '自动匹配: 片名清洗 中文=${t.local} 英文=${t.english} '
      '年份=${year ?? '-'} 原始=${q.title}',
    );

    final lookups = <Future<String?> Function()>[];
    // ① 英文片名直查 IMDb 联想：一次请求、最快，流浪地球这类中外合拍片命中率高。
    if (t.english.isNotEmpty) {
      lookups.add(
        () => ImdbLookupService.instance.resolveForVideoTitle(
          t.english,
          year: year,
          alias: t.local.isNotEmpty ? t.local : aliasFromMovie,
        ),
      );
    }
    // ② 中文片名走多源（豆瓣英文名 / TMDB / IMDb 联想）。
    if (t.local.isNotEmpty) {
      lookups.add(() async {
        final r = await VideoTitleResolveService.instance.resolve(
          t.local,
          year: year,
          alias: t.english.isNotEmpty ? t.english : aliasFromMovie,
        );
        return r?.imdbId;
      });
    }
    // ③ 英文片名走多源（豆瓣那条会跳过，但 CMS 别名兜底仍能补英文名）。
    if (t.english.isNotEmpty) {
      lookups.add(() async {
        final r = await VideoTitleResolveService.instance.resolve(
          t.english,
          year: year,
          alias: t.local.isNotEmpty ? t.local : aliasFromMovie,
        );
        return r?.imdbId;
      });
    }
    // ④ 原始片名兜底，保证老路径不被破坏。
    lookups.add(() async {
      final r = await VideoTitleResolveService.instance.resolve(
        q.title,
        year: fallbackYear,
        alias: aliasFromMovie,
      );
      return r?.imdbId;
    });

    for (var i = 0; i < lookups.length; i++) {
      try {
        final id = await lookups[i]();
        DebugLog.log('Subtitle', '自动匹配: IMDb 第${i + 1}路 -> ${id ?? 'null'}');
        if (id != null && id.isNotEmpty) return id;
      } catch (e) {
        DebugLog.log('Subtitle', '自动匹配: IMDb 第${i + 1}路异常 $e');
      }
    }
    return null;
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
  ///
  /// 真机结论（2026-11-08，device_debug5）：`setSubtitleTrack(auto)` 与
  /// 一次性裸写 `sid=1` 都回读 `sid=no` / `current-tracks/sub` 空。
  /// mpv 的 track id 是**按轨道类型各自从 1 开始编号**（track-list 里
  /// video id=1、audio id=1 同时存在）；磁力流大 seek 后 demuxer 会重建
  /// 轨道表，4 秒前读到的 id 可能已经失效，mpv 收到不存在的 id 就静默
  /// 回落 `sid=no`，而 media_kit 的 `setProperty` 丢掉了错误码。
  /// 所以这里：每轮重读 track-list 拿最新 id → 用精确 id 构造
  /// `SubtitleTrack`（同步 media_kit 状态且不经过会回落的 `auto()`）→
  /// 属性与命令双通道下发 → 最后一轮用 `cycle sub` 强制切轨 → 回读确认。
  /// 4 轮都不中就返回 false，让种子内 / 在线简中降级链路接上。
  Future<bool> _applyEmbeddedChineseSubtitle() async {
    final player = _playerModule.playerService.player;
    if (player == null) return false;

    // 完整轨道摘要逐条落盘（DebugLog 单条会被截断，必须拆行）。
    Future<List<SubtitleTrackInfo>> readChineseTracks() async {
      final raw = await getMpvProperty(player, 'track-list');
      for (final line in describeMpvTracks(raw)) {
        DebugLog.log('Subtitle', 'track-list: $line');
      }
      final tracks = parseMpvSubtitleTracks(raw);
      final chinese = tracks.where(isChineseSubtitle).toList();
      if (chinese.isEmpty) return <SubtitleTrackInfo>[];
      // 优先片源内封轨，避免把之前挂过、带 zh 标签的外挂轨当成内封。
      final embedded = chinese.where((t) => !t.isExternal).toList();
      return sortChineseTracksSimplifiedFirst(
        embedded.isNotEmpty ? embedded : chinese,
      );
    }

    List<SubtitleTrackInfo> sorted;
    try {
      sorted = await readChineseTracks();
    } catch (e) {
      debugPrint('字幕自动匹配: 读取 track-list 失败: $e');
      return false;
    }
    if (sorted.isEmpty) {
      DebugLog.log('Subtitle', '内封轨: track-list 无中文 sub 轨，转降级链路');
      return false;
    }
    DebugLog.log(
      'Subtitle',
      '内封轨候选: '
      '${sorted.map((t) => 'id=${t.id}/lang=${t.lang}/title=${t.title}').join(' | ')}',
    );

    // 语言偏好与可见性在加载期已由 PlayerService 设过，这里再补一次，
    // 覆盖轨道重建后属性被重置的情况。
    try {
      await setMpvProperty(player, 'slang', 'chi,zho,zh,chs,cht,zh-Hans');
    } catch (_) {}
    // 🔴 可见性必须跟着 showSubtitles 走，不能无条件写 yes。
    // 单一渲染源改为 mpv 之后，这里的裸 yes 会把「用户关掉的字幕」重新打开；
    // 而浮层兜底模式也需要 yes —— mpv 画不出，但要继续吐 sub-text 供浮层显示。
    // 分支语义见 services/subtitle_render_policy.dart。
    try {
      await setMpvProperty(
        player,
        'sub-visibility',
        subtitleVisibilityValue(showSubtitles: _playerModule.showSubtitles),
      );
    } catch (_) {}

    for (var attempt = 1; attempt <= 4; attempt++) {
      if (!mounted) return false;
      if (attempt > 1) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        try {
          final refreshed = await readChineseTracks();
          if (refreshed.isNotEmpty) sorted = refreshed;
        } catch (_) {}
      }
      final pick = sorted.first;
      final id = '${pick.id}';

      // 精确 id 构造：setSubtitleTrack 的非外挂分支写 sid 且同步
      // Player.state.track.subtitle，不会像 auto() 那样按 slang 回落到 no。
      try {
        await player.setSubtitleTrack(
          SubtitleTrack(id, pick.title, pick.lang),
        );
      } catch (e) {
        DebugLog.log('Subtitle', '内封轨第$attempt 轮 setSubtitleTrack 异常 $e');
      }
      // 属性通道与命令通道都发：media_kit 两条路径实现不同，互为兜底。
      try {
        await setMpvProperty(player, 'sid', id);
      } catch (_) {}
      try {
        await runMpvCommand(player, ['set', 'sid', id]);
      } catch (_) {}
      if (attempt == 4) {
        // 最后一轮：从 no 强制切到下一条字幕轨，绕开 sid 数字解析。
        try {
          await runMpvCommand(player, ['cycle', 'sub']);
        } catch (_) {}
      }

      await Future<void>.delayed(const Duration(milliseconds: 320));
      String? sid;
      String? cur;
      try {
        sid = await getMpvProperty(player, 'sid');
        cur = await getMpvProperty(player, 'current-tracks/sub');
      } catch (_) {}
      final lang = _langOfCurrentSub(cur);
      final currentIsChinese = lang != null &&
          classifySubtitleLanguage(lang) == SubtitleLanguage.chinese;
      final selected =
          (sid != null && sid.trim() == id) || currentIsChinese;
      DebugLog.log(
        'Subtitle',
        '内封轨选轨第$attempt 轮: 期望sid=$id 实际sid=${sid ?? '?'} '
        'current-lang=${lang ?? '-'} ${selected ? '(选中)' : '(未选中)'}',
      );
      if (!selected) continue;

      if (!mounted) return true;
      final variant =
          classifyChineseVariant(lang: pick.lang, title: pick.title);
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
      unawaited(_dumpEmbeddedSubtitleState(pick.id));
      unawaited(
        _inspectSubtitleTiming(label: '内封轨', subtitleName: pick.title),
      );
      return true;
    }

    DebugLog.log('Subtitle', '内封轨: 4 轮均未选中，转降级链路');
    return false;
  }

  /// 从 mpv `current-tracks/sub` 的 JSON 里取出语言码，取不到返回 null。
  /// 这里不依赖 dart:convert（本 part 未引入），用轻量正则解析。
  String? _langOfCurrentSub(String? raw) {
    if (raw == null || raw.trim().isEmpty || raw.trim() == '{}') return null;
    final m = RegExp(r'"lang"\s*:\s*"([^"]*)"').firstMatch(raw);
    return m?.group(1);
  }

  /// 免费在线源：片名/文本里的 IMDb 优先，否则用免费的 IMDb 联想接口解析。
  /// 在线字幕挂载后的状态回读。
  ///
  /// `setExternalSubtitleFromFile` 走 media_kit 的 `sub-add <file> select`，
  /// 它丢掉了 mpv 返回码，「没抛异常」不等于「字幕真的解析出文本」。
  /// 这里按 2s / 7s / 12s / 17s / 22s / 27s 采样 `sub-text`，覆盖用户
  /// 在挂载后拖进度条到有字幕 cue 的位置的场景，是字幕是否出画的硬证据。
  Future<void> _dumpOnlineSubtitleState() async {
    final player = _playerModule.playerService.player;
    if (player == null) return;
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(
        Duration(seconds: i == 0 ? 2 : 5),
      );
      if (!mounted) return;
      try {
        final sid = await getMpvProperty(player, 'sid');
        final subText = await getMpvProperty(player, 'sub-text') ?? '';
        final visibility = await getMpvProperty(player, 'sub-visibility');
        final subAss = await getMpvProperty(player, 'sub-ass');
        final subs = describeMpvTracks(
          await getMpvProperty(player, 'track-list'),
        ).where((l) => l.contains('type=sub')).toList();
        final head = subText.length > 80
            ? '${subText.substring(0, 80)}…'
            : subText;
        DebugLog.log(
          'Subtitle',
          '在线字幕回读#${i + 1}: sid=${sid ?? '?'} '
          'visibility=${visibility ?? '?'} sub-ass=${subAss ?? '?'} '
          'sub-text=[$head] sub轨=${subs.join(' | ')}',
        );
      } catch (e) {
        DebugLog.log('Subtitle', '在线字幕回读#${i + 1}失败: $e');
      }
    }
  }

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
    // 逐个试候选：lang 标错 / 正文是外语的会被 downloadFreeSubtitle 丢弃，
    // 继续找下一条真正含中文的，而不是只试 list.first 就放弃。
    String? path;
    var pickedIndex = -1;
    for (var i = 0; i < list.length && i < 6; i++) {
      path = await svc.downloadFreeSubtitle(list[i]);
      if (path != null) {
        pickedIndex = i;
        break;
      }
    }
    if (!mounted || path == null || pickedIndex < 0) {
      DebugLog.log('Subtitle', '自动匹配: 候选均非中文内容，未挂载字幕');
      return;
    }
    final picked = list[pickedIndex];
    await _playerModule.playerService.setExternalSubtitleFromFile(path);
    if (!mounted) return;
    _setState(() {
      _playerModule.showSubtitles = true;
      _playerModule.subtitleFileName = picked.fileName;
    });
    debugPrint('字幕自动匹配: 已挂在线简中字幕 ${picked.fileName}');
    unawaited(_dumpOnlineSubtitleState());
    unawaited(
      _inspectSubtitleTiming(
        label: '在线简中',
        subtitlePath: path,
        subtitleName: '${picked.fileName} ${picked.releaseName}',
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
