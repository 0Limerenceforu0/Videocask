part of 'api_service.dart';

/// detail 业务域实现。
///
/// 通过 `extension on ApiService` 直接访问主类的私有成员；
/// 引用主类的 static 成员必须写 `ApiService.xxx`（见 detail_page 同款约定）。
extension DetailApiExt on ApiService {
  /// 获取影片详情
  ///
  /// 苹果CMS详情接口：GET {url}?ac=detail&ids={影片ID}
  /// 用指定源按 id 拉取影片详情，并补上该源的 sourceId（F2）。
  Future<Movie?> _fetchDetailByIdFromSource(
      String movieId, PlaySource source) async {
    final url = '${source.url}?ac=detail&ids=$movieId';
    final rawData = await _httpGet(url);
    if (rawData == null) return null;
    final data = _parseResponseData(rawData);
    if (data == null) return null;
    final listRaw = data['list'];
    if (listRaw is! List || listRaw.isEmpty) return null;
    final movie = Movie.fromCmsJson(listRaw[0] as Map<String, dynamic>);
    return movie.sourceId.isEmpty ? movie.copyWith(sourceId: source.id) : movie;
  }

  /// 按 sourceId 从已配置源里取 [PlaySource]（找不到返回 null）。
  PlaySource? _sourceById(String id) {
    if (id.isEmpty) return null;
    try {
      return _availableSources.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 当前源无法播放时，按片名跨源安全匹配出「同一部片」的其它源条目（修订版 F1）。
  ///
  /// 与手动换源面板 [DetailSourceSwitchPane] 共用 [DetailSourceMatcher] 的匹配口径：
  /// 拿片名去其它启用源各搜一遍，挑出名字+年份最像的那条，返回带正确 sourceId
  /// 与**该源自己 id** 的候选。匹配不到可信同名片时返回 null——
  /// 绝不退回「同一个 id 去别的源」这种会打开错片的旧逻辑。
  Future<Movie?> autoFallbackByTitle(
    String title,
    String year, {
    String? excludeSourceId,
    int minScore = 85,
  }) async {
    if (_currentSource == null || title.trim().isEmpty) return null;
    final candidates = _availableSources
        .where((s) => s.enabled && s.id != _currentSource!.id)
        .where((s) => s.id != excludeSourceId)
        .toList();
    Movie? best;
    var bestScore = 0;
    for (final source in candidates) {
      try {
        final list =
            await searchMovies(title, page: 1, maxPages: 2, source: source);
        final picked = DetailSourceMatcher.pickBest(
          list,
          targetName: title,
          targetYear: year,
        );
        if (picked == null) continue;
        final score = DetailSourceMatcher.score(
          candidateName: picked.name,
          targetName: title,
          candidateYear: picked.year,
          targetYear: year,
        );
        if (score > bestScore) {
          bestScore = score;
          best = picked;
        }
      } catch (_) {
        // 单个源搜索失败不阻断其它源。
      }
    }
    if (best == null || bestScore < minScore) return null;
    return best;
  }

  Future<Movie?> getMovieDetail(
    String movieId, {
    bool allowFallback = true,
    String? titleHint,
    String? yearHint,
  }) async {
    // 自动化测试模式：返回一个可渲染的详情对象，避免依赖外部接口。
    if (AppEnv.isTestMode) {
      return Movie(
        id: movieId.isEmpty ? 'mock_detail_1' : movieId,
        name: '示例影片（详情）',
        rating: 8.5,
        genres: const ['动作', '科幻'],
        year: '2024',
        updateStatus: '更新至第1集',
      );
    }
    if (_currentSource == null) return null;

    try {
      // 只用「当前源」按 id 加载；各 CMS 的 vod_id 仅在本站唯一，
      // 禁止用同一个 id 去其它源回退（会打开完全错误的片子）。
      final current =
          await _fetchDetailByIdFromSource(movieId, _currentSource!);
      Movie? result = current;

      // 当前源无有效可播数据时，按片名安全跨源匹配（用目标源自己的 id）。
      if (allowFallback &&
          (result == null || !_hasPlayableEpisode(result)) &&
          titleHint != null &&
          titleHint.trim().isNotEmpty) {
        final alt = await autoFallbackByTitle(titleHint.trim(), yearHint ?? '');
        if (alt != null) {
          final targetSource = _sourceById(alt.sourceId);
          if (targetSource != null) {
            final altDetail =
                await _fetchDetailByIdFromSource(alt.id, targetSource);
            if (altDetail != null && _hasPlayableEpisode(altDetail)) {
              result = altDetail;
            }
          }
        }
      }

      if (result != null) {
        debugPrint('📊 影片详情: id=$movieId, 成功'
            '${result.sourceId != _currentSource!.id ? "（已在其它源找到同名片）" : ""}');
      } else {
        debugPrint('📊 影片详情: id=$movieId, 无可用播放线路（含其它源均未找到同名片）');
      }
      return result;
    } catch (e) {
      debugPrint('获取影片详情失败: $e');
      debugPrint('📊 影片详情: id=$movieId, 失败');
      return null;
    }
  }

  /// 判断详情是否含有至少一个可用播放地址
  bool _hasPlayableEpisode(Movie? movie) {
    if (movie == null) return false;
    for (final route in movie.playRoutes) {
      for (final ep in route.episodes) {
        if (ep.url.trim().isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  /// 检测源是否有效
  ///
  /// 苹果CMS检测方式：GET {url}?ac=list
  /// 检查是否返回200状态码和正确的JSON格式
  Future<bool> checkSource(PlaySource source) async {
    try {
      final url = '${source.url}?ac=list';
      final rawData = await _httpGet(url);
      if (rawData == null) return false;

      final json = jsonDecode(rawData) as Map<String, dynamic>;
      final code = json['code'];
      return code == 200 || code == '200' || code == 1 || code == '1';
    } catch (e) {
      debugPrint('检测源失败: ${source.url}, 错误: $e');
      return false;
    }
  }

  /// 详情页侧栏「相关推荐」：用**类型、去季片名、全名**等对当前源做 `wd` 搜索并去重合并。
  ///
  /// 苹果 CMS 无独立推荐接口；旧逻辑仅用 [Movie.genres] 第一项且常与 [_loadData] 竞态，导致大量「暂无推荐」。
  Future<List<Movie>> getDetailSideRecommendations(Movie movie) async {
    if (_currentSource == null) return [];

    if (AppEnv.isTestMode) {
      return List<Movie>.generate(
        5,
        (i) => Movie(
          id: 'mock_rec_$i',
          name: '推荐 ${i + 1}（${movie.name}）',
          rating: 8.0,
          genres: movie.genres.isNotEmpty ? movie.genres : const ['剧情'],
          year: movie.year.isNotEmpty ? movie.year : '2024',
        ),
      );
    }

    final movieId = movie.id;
    final out = <Movie>[];
    final seen = <String>{};

    Future<void> tryKeyword(String raw, {int minNameScore = 0}) async {
      final kw = raw.trim();
      if (kw.length < 2) return;
      try {
        // 相关推荐只需首页（最多 ~20 条），避免翻页聚合在详情页发起过多请求。
        final list = await searchMovies(kw, page: 1, maxPages: 1);
        for (final m in list) {
          if (m.id == movieId) continue;
          // 仅兜底用的弱关键词（类型词）要求名字与当前片有包含/相似关系，
          // 否则会混入「剧情攻略手册」这类纯类型词垃圾。
          if (minNameScore > 0 &&
              DetailSourceMatcher.nameScore(m.name, movie.name) <
                  minNameScore) {
            continue;
          }
          if (seen.contains(m.id)) continue;
          seen.add(m.id);
          out.add(m);
          if (out.length >= 10) return;
        }
      } catch (e) {
        debugPrint('推荐搜索失败 keyword=$kw: $e');
      }
    }

    // 主推：与当前片强相关的关键词（同一作品 / 同导演 / 别名）。
    if (movie.name.trim().length >= 2) {
      await tryKeyword(movie.name.trim());
    }
    final baseTitle = ApiService.stripSeasonFromTitleForRecommend(movie.name);
    if (baseTitle.length >= 2 && baseTitle != movie.name.trim()) {
      await tryKeyword(baseTitle);
    }
    if (out.length < 6 && movie.alias.trim().length >= 2) {
      await tryKeyword(movie.alias.trim());
    }
    if (out.length < 6 && movie.director.trim().length >= 2) {
      await tryKeyword(movie.director.trim());
    }

    // 兜底：类型词只取前两个 genre 的第一段，并过滤名字明显无关的，
    // 避免旧逻辑把「动作/爱情」等类型词全量搜出的垃圾塞进推荐。
    if (out.length < 6) {
      for (final g in movie.genres.take(2)) {
        final part = g.split(RegExp(r'[,，/、]')).first.trim();
        if (part.length >= 2) {
          await tryKeyword(part, minNameScore: 70);
          if (out.length >= 10) break;
        }
      }
    }

    return out.take(10).toList();
  }

  /// 获取影片推荐（先拉详情再走 [getDetailSideRecommendations]）
  Future<List<Movie>> getRecommendations(String movieId) async {
    if (_currentSource == null) return [];

    try {
      final movie = await getMovieDetail(movieId);
      if (movie == null) return [];
      return getDetailSideRecommendations(movie);
    } catch (e) {
      debugPrint('获取推荐失败: $e');
      return [];
    }
  }
}
