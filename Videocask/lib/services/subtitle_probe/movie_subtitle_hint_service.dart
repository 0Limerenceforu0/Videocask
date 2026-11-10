/// 影片级的「这部片子有没有在线中文字幕」提示。
///
/// 🔴 边界（必须守住）：这是**影片级**信息，只能说明「网上能找到这部片子的
/// 中文字幕」，**不能**冒充「这条磁力种子自带中文字幕」。所以 UI 上单独用
/// 一个措辞明确的小徽标展示，且与资源级结论（[SubtitleProbeResult]）分开。
///
/// 复用现成链路：IMDb 联想（无 Key）+ 免费在线字幕源（无 Key）。
/// 同一部片子的搜索结果往往有十几条磁力，按 imdbId / 片名去重后只查一次。
library;

import 'dart:async';

import '../debug_log.dart';
import '../imdb_lookup_service.dart';
import '../subtitle/subtitle_title_extractor.dart';
import '../subtitle_service.dart';

enum MovieSubtitleHintState {
  /// 在线字幕库里查到了中文字幕。
  available,

  /// 查到了 IMDb，但没有中文字幕。
  unavailable,

  /// 没查到 IMDb / 接口失败 / 超时。
  unknown,
}

class MovieSubtitleHint {
  const MovieSubtitleHint({
    required this.state,
    this.count = 0,
    this.reason = '',
    this.imdbId = '',
  });

  final MovieSubtitleHintState state;
  final int count;
  final String reason;
  final String imdbId;

  static const unknown = MovieSubtitleHint(
    state: MovieSubtitleHintState.unknown,
    reason: '影片级字幕信息未取到',
  );

  bool get hasChinese => state == MovieSubtitleHintState.available;
}

class MovieSubtitleHintService {
  MovieSubtitleHintService._();
  static final MovieSubtitleHintService instance =
      MovieSubtitleHintService._();

  final Map<String, MovieSubtitleHint> _cache = {};
  final Map<String, Future<MovieSubtitleHint>> _jobs = {};

  static final RegExp _imdbIdRe = RegExp(r'^tt\d{7,12}$');

  /// 查一次影片级提示。命中缓存/正在查则直接复用同一个 Future。
  Future<MovieSubtitleHint> lookup({
    String? imdbId,
    required String title,
  }) {
    final id = (imdbId ?? '').trim().toLowerCase();
    final key = _imdbIdRe.hasMatch(id)
        ? 'imdb:$id'
        : 'title:${_normalizeTitle(title)}';
    if (key == 'title:') return Future.value(MovieSubtitleHint.unknown);

    final cached = _cache[key];
    if (cached != null) return Future.value(cached);
    final running = _jobs[key];
    if (running != null) return running;

    final job = _lookupInternal(id, title).timeout(
      const Duration(seconds: 22),
      onTimeout: () => const MovieSubtitleHint(
        state: MovieSubtitleHintState.unknown,
        reason: '查询影片字幕超时',
      ),
    );
    _jobs[key] = job;
    job.then(
      (value) {
        _cache[key] = value;
        _jobs.remove(key);
      },
      onError: (_) {
        _jobs.remove(key);
      },
    );
    return job;
  }

  String _normalizeTitle(String raw) {
    final q = extractSubtitleTitleQuery(primary: raw, releaseName: raw);
    final base = q.local.isNotEmpty ? q.local : q.english;
    return base.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<MovieSubtitleHint> _lookupInternal(String id, String title) async {
    String? resolved = _imdbIdRe.hasMatch(id) ? id : null;
    if (resolved == null) {
      final q = extractSubtitleTitleQuery(primary: title, releaseName: title);
      final primary = q.local.isNotEmpty ? q.local : q.english;
      if (primary.isEmpty) {
        return const MovieSubtitleHint(
          state: MovieSubtitleHintState.unknown,
          reason: '发布名里剥不出片名',
        );
      }
      try {
        resolved = await ImdbLookupService.instance
            .resolveForVideoTitle(
              primary,
              year: q.year,
              alias: q.english.isNotEmpty ? q.english : null,
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => null,
            );
      } catch (e) {
        DebugLog.log('MovieSubtitleHint', 'IMDb 解析失败: $e');
      }
      if (resolved == null) {
        return const MovieSubtitleHint(
          state: MovieSubtitleHintState.unknown,
          reason: '没匹配到 IMDb 条目',
        );
      }
    }

    try {
      final list = await SubtitleService()
          .searchFreeChinese(imdbId: resolved)
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => <SubtitleInfo>[],
          );
      if (list.isEmpty) {
        return MovieSubtitleHint(
          state: MovieSubtitleHintState.unavailable,
          reason: '在线字幕库暂无中文字幕',
          imdbId: resolved,
        );
      }
      return MovieSubtitleHint(
        state: MovieSubtitleHintState.available,
        count: list.length,
        reason: '在线字幕库有 ${list.length} 条中文字幕',
        imdbId: resolved,
      );
    } catch (e) {
      DebugLog.log('MovieSubtitleHint', '在线字幕查询失败: $e');
      return MovieSubtitleHint(
        state: MovieSubtitleHintState.unknown,
        reason: '在线字幕查询失败',
        imdbId: resolved,
      );
    }
  }
}
