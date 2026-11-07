part of 'api_service.dart';

/// search 业务域实现。
///
/// 通过 `extension on ApiService` 直接访问主类的私有成员；
/// 引用主类的 static 成员必须写 `ApiService.xxx`（见 detail_page 同款约定）。
extension SearchApiExt on ApiService {
  Future<List<Movie>> searchMovies(
    String keyword, {
    int page = 1,
    int maxPages = ApiService._maxSearchPagesPerSource,
    PlaySource? source,
  }) async {
    // 自动化测试模式：返回稳定的模拟搜索结果，便于验证搜索页面交互与列表渲染。
    if (AppEnv.isTestMode) {
      if (keyword.trim().isEmpty) return [];
      return List<Movie>.generate(
        10,
        (i) => Movie(
          id: 'mock_search_${page}_$i',
          name: '搜索结果 ${i + 1}：$keyword',
          rating: 7.5,
          genres: const ['剧情'],
          year: '2024',
          updateStatus: i.isEven ? '已完结' : '更新中',
        ),
      );
    }
    // 显式指定源（多源并发搜索用）：不经过 [_currentSource] 的保存/恢复，
    // 避免 4 路并发互相踩对方的临时切换，导致搜索后当前源被留错。
    if (_currentSource == null && source == null) return [];
    if (keyword.trim().isEmpty) return [];

    try {
      // 第 1 页：拿到本页结果 + 总页数 pagecount。
      final first = await _fetchSearchPageRaw(keyword, page, source: source);
      // 实际翻到的最后一页（受单源页数上限约束）。
      final upper = first.pagecount > maxPages ? maxPages : first.pagecount;
      final all = <Movie>[...first.movies];

      // 翻页聚合：把后续页并发拉取并合并（同一源内按 id 去重）。
      if (first.pagecount > page) {
        final pages = <int>[];
        for (var p = page + 1; p <= upper; p++) {
          pages.add(p);
        }
        if (pages.isNotEmpty) {
          final rest = await ApiService._mapInBatches<int, List<Movie>>(
            pages,
            3,
            (p) => _fetchSearchPageRaw(keyword, p, source: source)
                .then((r) => r.movies),
          );
          final seen = <String>{...all.map((m) => m.id)};
          for (final list in rest) {
            for (final m in list) {
              if (!seen.contains(m.id)) {
                seen.add(m.id);
                all.add(m);
              }
            }
          }
        }
      }

      debugPrint('📊 搜索结果: keyword=$keyword, 获取到 ${all.length} 条'
          '（共 ${first.pagecount} 页，已聚合至第 $upper 页）');
      // F2：统一补上来源 sourceId，避免下游（推荐卡、换源匹配）拿到空源。
      final resolvedSourceId = (source ?? _currentSource)?.id ?? '';
      final withSource = resolvedSourceId.isEmpty
          ? all
          : all
              .map((m) => m.sourceId.isEmpty
                  ? m.copyWith(sourceId: resolvedSourceId)
                  : m)
              .toList();
      return withSource;
    } catch (e) {
      debugPrint('搜索影片失败: $e');
      return [];
    }
  }

  /// 取单页关键词搜索结果，并解析响应里的 `pagecount`（供翻页聚合使用）。
  ///
  /// [source] 显式指定搜索源；为空则用当前源 [_currentSource]。
  Future<_SearchPageResult> _fetchSearchPageRaw(String keyword, int page,
      {PlaySource? source}) async {
    final target = source ?? _currentSource;
    if (target == null) return ApiService._emptySearchPage;
    try {
      final url = '${target.url}'
          '?ac=detail&wd=${Uri.encodeQueryComponent(keyword)}&pg=$page';
      final rawData = await _httpGet(url);
      if (rawData == null) return ApiService._emptySearchPage;
      final json = _parseResponseData(rawData);
      final movies = _parseMovieListFromResponse(rawData);
      final pagecount =
          int.tryParse(json?['pagecount']?.toString() ?? '1') ?? 1;
      return _SearchPageResult(
        movies: movies,
        pagecount: pagecount < 1 ? 1 : pagecount,
        page: page,
      );
    } catch (e) {
      debugPrint('搜索第 $page 页失败: $e');
      return ApiService._emptySearchPage;
    }
  }

  /// 按**一组片名**批量检索（人名搜索用：豆瓣给出代表作，逐部按片名搜源站）。
  ///
  /// 与 [searchFromAllSources] 的区别：
  /// * 只取每个片名的**第 1 页**（人名搜索要的是「这个人有哪些片」，
  ///   不是某部片的全部资源，补页纯属浪费）；
  /// * **不做关键词相关性过滤** —— 关键词是人名，片名当然不含它；
  /// * 但对**作品名本身**做精确匹配 + 年份校验。实测 `wd=功夫` 返回 83 条
  ///   （功夫女足 / 功夫星猫 / 功夫小子闯佛山…），不校验的话「搜周星驰」
  ///   会出来一堆无关的「功夫 XX」；
  /// * 每批 3 部并发，避免 8 部 × 6 源 = 48 个请求同时打出去被限流。
  Future<List<Movie>> searchByTitles(
    List<TitleQuery> works, {
    required List<PlaySource> sources,
    int maxTitles = 6,
  }) async {
    final picked = works
        .where((w) => w.title.trim().isNotEmpty)
        .take(maxTitles)
        .toList(growable: false);
    if (picked.isEmpty || sources.isEmpty) return const [];

    final perTitle = await ApiService._mapInBatches<TitleQuery, List<Movie>>(
      picked,
      3,
      (work) async {
        final out = <Movie>[];
        await for (final event in _searchSourcesConcurrently(
          sources,
          work.title.trim(),
          1,
          // 只要第 1 页：人名搜索要的是「这个人有哪些片」，不是某部片的
          // 全部资源。补页会让 6 部作品 × N 个源炸成几百个请求。
          fillPages: false,
        )) {
          if (event.error != null) continue;
          final hits = event.movies
              .where((m) => ApiService.matchesTitleQuery(m.name, m.year, work))
              .toList(growable: false);
          if (hits.isEmpty) continue;
          _mergeMultiSourceSearchResults(out, hits, event.source);
        }
        // 精确同名的排前面（「喜剧之王」1999 要压过「喜剧之王单口季」）。
        final exact = ApiService._relevanceKey(work.title);
        out.sort((a, b) {
          final ae = ApiService._relevanceKey(a.name) == exact ? 0 : 1;
          final be = ApiService._relevanceKey(b.name) == exact ? 0 : 1;
          if (ae != be) return ae - be;
          return b.rating.compareTo(a.rating);
        });
        return out;
      },
    );

    // 跨作品去重：同一个源的不同作品之间可能重复（续集/合集），
    // 以及同一部片被算进两部代表作里。
    final all = <Movie>[];
    for (final list in perTitle) {
      for (final m in list) {
        final idx = all.indexWhere((e) => ApiService.isSameMovieForMerge(e, m));
        if (idx < 0) {
          all.add(m);
          continue;
        }
        final keeper = all[idx];
        if (keeper.alternateSources.isEmpty && m.alternateSources.isEmpty) {
          continue;
        }
        all[idx] = keeper.copyWith(
          alternateSources: [
            ...keeper.alternateSources,
            ...m.alternateSources.where(
              (a) => !keeper.alternateSources.any(
                (b) => b.sourceId == a.sourceId && b.movieId == a.movieId,
              ),
            ),
          ],
        );
      }
    }
    return all;
  }

  /// 逐个片名去源站查，**第一个命中的源就停**（2026-10-28）。
  ///
  /// 为什么不做「全源并发」：人名通道现在要查几十部片（周星驰 58 部），
  /// 全源并发 = 58 × 6 源 ≈ 350 个请求，而且每部都要等**最慢的那个源**
  /// 才返回，实测能把整轮拖到分钟级。实测量子资源对这批老片的命中率是
  /// 52/56 ≈ 93%，按源顺序试、命中即停，平均每部 1.1 个请求。
  Future<List<Movie>> _searchOneTitleFirstHit(
    TitleQuery work,
    List<PlaySource> sources,
  ) async {
    final keyword = work.title.trim();
    if (keyword.isEmpty) return const [];
    for (final source in sources) {
      final events = <SourceSearchResult>[];
      try {
        await _searchSingleSourceStaged(
          source,
          keyword,
          1,
          events.add,
          // 只要第 1 页：要的是「这部片在不在」，不是它的全部线路。
          fillPages: false,
        );
      } catch (e) {
        debugPrint('按片名检索失败（${source.name} / $keyword）: $e');
        continue;
      }
      final out = <Movie>[];
      for (final event in events) {
        if (event.error != null) continue;
        final hits = event.movies
            .where((m) => ApiService.matchesTitleQuery(m.name, m.year, work))
            // 解说类不是正片（`功夫[电影解说]` 也能命中「功夫」）：
            // 过滤后若一条不剩，会继续试下一个源，而不是把「只有解说版」
            // 当成这部片已经找到了。
            .where((m) => !CommentaryContentFilter.isMovie(m))
            .toList(growable: false);
        if (hits.isEmpty) continue;
        _mergeMultiSourceSearchResults(out, hits, event.source);
      }
      if (out.isNotEmpty) return out;
    }
    return const [];
  }

  /// 人名搜索的**全量作品**通道（2026-10-28）。
  ///
  /// 与 [searchByTitles] 的区别：
  /// * 上限从 6 部提到 [maxTitles]（默认 120）—— 豆瓣作品全集能给出
  ///   71 部电影（含导演身份），卡在 40 部等于把后面的作品全丢了；
  /// * 每部「首个命中源即停」，不是全源并发（见 [_searchOneTitleFirstHit]）；
  /// * [onProgress] 每命中一部就回调**累计结果**，页面可以边查边投递，
  ///   用户看到 30 → 38 → 45 逐步长出来，而不是转圈等一次性替换。
  Future<List<Movie>> searchPersonWorks(
    List<TitleQuery> works, {
    required List<PlaySource> sources,
    int maxTitles = 120,
    void Function(List<Movie> merged)? onProgress,
  }) async {
    final picked = works
        .where((w) => w.title.trim().isNotEmpty)
        .take(maxTitles)
        .toList(growable: false);
    if (picked.isEmpty || sources.isEmpty) return const [];

    final merged = <Movie>[];
    await ApiService._mapInBatches<TitleQuery, int>(picked, 3, (work) async {
      final hits = await _searchOneTitleFirstHit(work, sources);
      if (hits.isEmpty) return 0;
      for (final m in hits) {
        // 同一部片可能被两个作品名同时命中（续集/合集），只留一份。
        if (merged.any((e) => ApiService.isSameMovieForMerge(e, m))) continue;
        merged.add(m);
      }
      onProgress?.call(List<Movie>.unmodifiable(merged));
      return 1;
    });
    return merged;
  }

  /// 多源并发搜索
  ///
  /// 并发请求所有已启用的源，通过 Stream 流式返回结果。
  /// 源列表由调用方通过 [sources] 参数传入，避免 ApiService 内部依赖 Provider。
  Stream<MultiSourceSearchEvent> searchFromAllSources(
    String keyword, {
    required List<PlaySource> sources,
    int page = 1,
    SearchRelevance relevance = SearchRelevance.strict,
  }) async* {
    if (keyword.trim().isEmpty || sources.isEmpty) {
      yield MultiSourceSearchProgress(
        completed: 0,
        total: 0,
        results: [],
      );
      return;
    }

    int completedCount = 0;
    int readyCount = 0;
    int finalCount = 0;
    final countedReady = <String>{};
    final allResults = <Movie>[];

    /// 本轮是否有源因为「严格片名匹配一条都没有」而被放宽了一档。
    /// 传给 UI 用于提示，避免用户以为自己搜的词被悄悄换了。
    var relaxedAny = false;

    // 先发送初始进度事件。
    // 注意：results 必须发**防御性拷贝**，不能发 allResults 活引用——
    // 下方合并会原地改 allResults，消费者（provider 的 _multiSearchResults
    // 直接存 event.results 引用）若在事件之间读它，会看到与 completed/
    // readySources/statusText 自相矛盾的数据（初始事件说"0/1 个源"，
    // 列表里却已经躺着合并后的结果）。后续事件（下方）发的就是拷贝，
    // 初始事件漏了这层，被 api_service_multi_source_stream_test 抓个正着。
    yield MultiSourceSearchProgress(
      completed: 0,
      total: sources.length,
      results: List<Movie>.from(allResults),
    );

    // 并发请求所有源，谁先返回谁先处理
    await for (final event
        in _searchSourcesConcurrently(sources, keyword, page)) {
      if (event.error != null) {
        debugPrint('源 "${event.source.name}" 搜索失败: ${event.error}');
      }

      final beforeLen = allResults.length;
      // 2026-10-28 用户反馈「搜出来的影视资源一大半不相干」：
      // 采集站搜索是模糊匹配，会顺带返回续集/同名短片/无关条目，
      // 直接并集后条数轻易破百。这里先按「与关键词相关」过一遍。
      //
      // 但同一个过滤不能套在所有人身上（用户当天第二次反馈「怎么跟二极管
      // 一样」）：搜人名「周星驰」、搜类型「科幻」时，结果片名里本来就不会
      // 出现关键词，硬过滤等于把这些能力全砍掉。所以：
      //   - 人名 / 类型 / 分类 → 调用方传 [SearchRelevance.off]，不过滤；
      //   - 片名 → 严格过滤，但**严格命中为 0 时自动放宽一档**
      //     （[isSearchResultLooselyRelevant]），至少命中一个词就留下，
      //     绝不因为「没人完全对上」而把一个源整个清空。
      final rawMovies = event.movies;
      var sourceMovies = rawMovies;
      var relaxedThisSource = false;
      if (relevance == SearchRelevance.strict && rawMovies.isNotEmpty) {
        final strictHits = rawMovies
            .where((m) => ApiService.isSearchResultRelevant(keyword, m.name))
            .toList(growable: false);
        if (strictHits.isNotEmpty) {
          sourceMovies = strictHits;
        } else {
          final looseHits = rawMovies
              .where((m) =>
                  ApiService.isSearchResultLooselyRelevant(keyword, m.name))
              .toList(growable: false);
          // 一个词都不沾 → 真的无关，保持为空（宁缺勿滥）；
          // 沾了至少一个词 → 放宽保留，并给 UI 一个提示。
          sourceMovies = looseHits;
          relaxedThisSource = looseHits.isNotEmpty;
        }
      }
      if (relaxedThisSource) relaxedAny = true;
      final dropped = rawMovies.length - sourceMovies.length;
      if (dropped > 0) {
        debugPrint(
          '源 "${event.source.name}" 过滤无关结果: '
          '${rawMovies.length} → ${sourceMovies.length}（丢弃 $dropped 条，'
          '${relaxedThisSource ? "已放宽片名匹配" : "严格片名匹配"}）',
        );
      }
      _mergeMultiSourceSearchResults(allResults, sourceMovies, event.source);
      // 两段式投递：阶段 1（第 1 页）与阶段 2（补齐页）分属两次事件。
      //   - 该源第一次投递 → 计入「已出结果的源数」（用户感知的进度）；
      //   - 该源最后一次投递（isFinal）→ 计入「彻底搜完的源数」。
      // 单页源只投递一次，两种计数同时 +1。
      if (countedReady.add(event.source.id) && event.error == null) {
        readyCount++;
      }
      if (event.isFinal) {
        completedCount++;
        finalCount++;
      }

      yield MultiSourceSearchProgress(
        completed: completedCount,
        total: sources.length,
        results: List<Movie>.from(allResults),
        newMovies: allResults.length > beforeLen
            ? allResults.sublist(beforeLen)
            : const [],
        readySources: readyCount,
        allSourcesDone: finalCount >= sources.length,
        relevanceRelaxed: relaxedAny,
      );
    }
  }

  /// 并发请求多个源
  ///
  /// 谁先返回谁先 yield，实现流式效果。并发上限 [_maxConcurrent]（滑动窗口：
  /// 完成一个补一个，保证全部源都会被搜索到）。
  ///
  /// 实现说明（释放纪律）：合并直接走**单一事件队列**，不为每个源建
  /// StreamController——旧实现给每个源建 controller 再由 [_mergeStreams]
  /// 逐个 listen 转发，存在三个问题：
  /// 1. 装配时快照：窗口滑动后新增的 controller 永远拿不到 listener，
  ///    超过 4 个源时第 5 个以后的结果被静默丢弃、流提前收摊；
  /// 2. 那些 listen 订阅没有取消路径，消费者提前取消即泄漏 N 个订阅；
  /// 3. 两个 Completer 只写不读。
  /// 现在消费者取消时 finally 统一关闭队列，在飞任务的结果因 `isClosed`
  /// 检查而无处可投，任务自然结束后整张对象图即可回收。
  Stream<SourceSearchResult> _searchSourcesConcurrently(
    List<PlaySource> sources,
    String keyword,
    int page, {
    /// 是否在阶段 1 之后**后台补齐第 2..N 页**。
    ///
    /// 首页搜索要补（多拿结果）；而**按片名批量检索**（人名搜索：一次 6 部
    /// 代表作 × N 个源）绝对不能补 —— 每部片、每个源都去拉满 10 页，
    /// 请求量是 6×6×9 ≈ 300+ 个，`await for` 要等它们全部回来才结束，
    /// 表现就是搜「周星驰」转圈两分钟以上还没有任何结果。
    bool fillPages = true,
  }) async* {
    if (sources.isEmpty) return;

    final eventQueue = StreamController<SourceSearchResult>();
    final total = sources.length;
    int running = 0;
    int index = 0;
    int finished = 0;

    // 2026-10-24：后台补齐页（阶段 2）**不再占用并发槽位**。
    //
    // 旧实现里阶段 2 跑在 [_searchSingleSourceStaged] 内部，槽位要等
    // 「补齐最多 10 页」全部结束才释放 → 一个慢源就能占死 4 个槽位中的
    // 一个，排队的第 5~N 个源**连启动都被推迟**。用户观感正是
    // 「第一个主源出来的时间还可以，其他源很慢」：首个源的阶段 1
    // （第 1 页）~2s 就到，屏幕有东西了；但第 5~8 个源要等前面几个源
    // 补完页才开跑，首屏就停在"只有一两个源"。
    //
    // 现在：阶段 1 交付后本方法立即返回 → 槽位立刻给下一个源用；
    // 阶段 2 变成脱离槽位的后台任务，回来后再 deliver 一次。
    // 队列关闭条件相应改为「所有源的阶段 1 都结束 **且** 所有后台补页都结束」。
    int backgroundPending = 0;

    void deliver(SourceSearchResult event) {
      if (!eventQueue.isClosed) eventQueue.add(event);
    }

    void maybeCloseQueue() {
      if (finished >= total && backgroundPending == 0 && !eventQueue.isClosed) {
        unawaited(eventQueue.close());
      }
    }

    void startNext() {
      while (running < ApiService._maxConcurrent && index < total) {
        final source = sources[index++];
        running++;
        _searchSingleSourceStaged(
          source,
          keyword,
          page,
          deliver,
          fillPages: fillPages,
          onBackground: (background) {
            backgroundPending++;
            background.whenComplete(() {
              backgroundPending--;
              maybeCloseQueue();
            });
          },
        ).catchError((e) {
          deliver(
            SourceSearchResult(
              source: source,
              movies: [],
              error: e.toString(),
            ),
          );
        }).whenComplete(() {
          running--;
          finished++;
          // 全部源的阶段 1 都已返回（且后台补页已收口）→ 关闭队列，
          // 使 await for 退出。
          maybeCloseQueue();
          startNext();
        });
      }
    }

    try {
      startNext();
      await for (final event in eventQueue.stream) {
        yield event;
      }
    } finally {
      // 消费者提前取消 / 上游异常：关闭队列收口。在飞请求（Dio 有 30s
      // 超时）无法取消，但 deliver 内判 isClosed，其结果不会进入队列，
      // 请求结束后引用链自然断开。
      if (!eventQueue.isClosed) unawaited(eventQueue.close());
    }
  }

  /// 搜索单个源（**两段式投递**）。
  ///
  /// 2026-10-22：原先要等这个源把 [_maxSearchPagesPerSource]（10）页**全部**
  /// 拉完才交付结果，首屏因此被放大约 10 倍（用户反馈「以前秒出，现在很慢」）。
  /// 现在拆成两段：
  ///  * 阶段 1：只取第 1 页 → 立刻 [deliver]，首屏秒回；
  ///  * 阶段 2：后台补齐第 2..N 页 → 再 [deliver] 一次，
  ///    保留「同名多作品」场景下拿到更多结果的能力。
  ///
  /// 2026-10-24：阶段 2 进一步**脱离并发槽位**——阶段 1 交付后本方法立刻
  /// 返回（槽位马上给下一个源用），阶段 2 作为后台任务交给 [onBackground]。
  /// 旧实现阶段 2 占着槽位不放，是「第一个源快、其他源慢」的根因。
  ///
  /// 两段都带同一个 [source]，合并层按 id 去重，不会重复。
  ///
  /// 自动化测试模式直接返回稳定的模拟结果（单段）。
  Future<void> _searchSingleSourceStaged(
    PlaySource source,
    String keyword,
    int page,
    void Function(SourceSearchResult) deliver, {
    bool fillPages = true,
    void Function(Future<void> background)? onBackground,
  }) async {
    final sid = source.id;
    List<Movie> tag(List<Movie> list) => list
        .map((m) => m.sourceId.isEmpty ? m.copyWith(sourceId: sid) : m)
        .toList();

    if (AppEnv.isTestMode) {
      final mock = List<Movie>.generate(
        10,
        (i) => Movie(
          id: 'mock_search_${page}_$i',
          name: '搜索结果 ${i + 1}：$keyword',
          rating: 7.5,
          genres: const ['剧情'],
          year: '2024',
          updateStatus: i.isEven ? '已完结' : '更新中',
        ),
      );
      deliver(SourceSearchResult(source: source, movies: tag(mock)));
      return;
    }

    // 阶段 1：只取第 1 页。
    final first = await _fetchSearchPageRaw(keyword, page, source: source);
    final upper = first.pagecount > ApiService._maxSearchPagesPerSource
        ? ApiService._maxSearchPagesPerSource
        : first.pagecount;

    // 没有后续页 → 一次性交付（isFinal=true）。
    // 这样「只有 1 页的源」仍然只产生**一个**事件，与两段式之前的契约一致
    // （既有流式测试依赖这个不变量）。
    if (!fillPages || first.pagecount <= page || upper <= page) {
      deliver(
        SourceSearchResult(
          source: source,
          movies: tag(first.movies),
          isFinal: true,
        ),
      );
      return;
    }

    // 有后续页 → 阶段 1 先交付，阶段 2 补齐后再交付。
    deliver(
      SourceSearchResult(
        source: source,
        movies: tag(first.movies),
        isFinal: false,
      ),
    );

    // 阶段 2：补齐后续页（同一源内按 id 去重）。
    // 2026-10-24：作为**脱离槽位的后台任务**启动，本方法立刻返回 →
    // 并发槽位立刻空出来给下一个源，补齐页回来后再 deliver 一次。
    final background = _fetchRemainingPages(
      keyword: keyword,
      source: source,
      page: page,
      upper: upper,
      firstMovies: first.movies,
      tag: tag,
      deliver: deliver,
    );
    onBackground?.call(background);
  }

  /// 阶段 2：补齐第 2..N 页（**后台任务**，不占并发槽位）。
  ///
  /// 独立成方法，是为了让 [_searchSingleSourceStaged] 交付阶段 1 后能立刻
  /// 返回，把槽位让给排队中的下一个源。异常在这里就地吞掉（不能让后台
  /// 任务的错误变成未捕获异常），补页失败只是少几页结果，不影响已交付的
  /// 阶段 1。
  Future<void> _fetchRemainingPages({
    required String keyword,
    required PlaySource source,
    required int page,
    required int upper,
    required List<Movie> firstMovies,
    required List<Movie> Function(List<Movie>) tag,
    required void Function(SourceSearchResult) deliver,
  }) async {
    try {
      final rest = <Movie>[];
      final pages = <int>[];
      for (var p = page + 1; p <= upper; p++) {
        pages.add(p);
      }
      if (pages.isNotEmpty) {
        final batches = await ApiService._mapInBatches<int, List<Movie>>(
          pages,
          3,
          (p) => _fetchSearchPageRaw(keyword, p, source: source)
              .then((r) => r.movies),
        );
        final seen = <String>{...firstMovies.map((m) => m.id)};
        for (final list in batches) {
          for (final m in list) {
            if (seen.add(m.id)) rest.add(m);
          }
        }
      }
      deliver(
        SourceSearchResult(
          source: source,
          movies: tag(rest),
          isFinal: true,
        ),
      );
    } catch (e) {
      debugPrint('源 "${source.name}" 补齐页失败: $e');
    }
  }

  /// 多源搜索合并：同款影片只保留一行，并把其它源的 [MovieAlternateSource] 记在首条上。
  void _mergeMultiSourceSearchResults(
    List<Movie> allResults,
    List<Movie> newMovies,
    PlaySource source,
  ) {
    for (final raw in newMovies) {
      final movie =
          raw.sourceId.isEmpty ? raw.copyWith(sourceId: source.id) : raw;

      final idx = allResults
          .indexWhere((e) => ApiService.isSameMovieForMerge(e, movie));
      if (idx < 0) {
        allResults.add(movie);
        continue;
      }

      final keeper = allResults[idx];
      if (keeper.id == movie.id && keeper.sourceId == movie.sourceId) {
        continue;
      }
      if (keeper.sourceId == movie.sourceId) {
        continue;
      }
      final exists = keeper.alternateSources.any(
        (a) => a.sourceId == movie.sourceId && a.movieId == movie.id,
      );
      if (exists) continue;

      allResults[idx] = keeper.copyWith(
        alternateSources: [
          ...keeper.alternateSources,
          MovieAlternateSource(
            sourceId: movie.sourceId,
            movieId: movie.id,
            sourceDisplayName: source.name,
          ),
        ],
      );
    }
  }
}
