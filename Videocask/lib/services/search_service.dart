import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../models/movie.dart';
import 'api_service.dart';

/// 搜索服务
class SearchService {
  SearchService._();
  static final SearchService _instance = SearchService._();
  factory SearchService() => _instance;

  final ApiService _api = ApiService();

  /// 搜索历史（带时间戳）
  List<Map<String, dynamic>> _searchHistoryWithTime = [];

  /// 搜索历史（纯关键词列表，保持向后兼容）
  List<String> get searchHistory =>
      _searchHistoryWithTime.map((e) => e['keyword'] as String).toList();

  /// 搜索历史（带时间戳）
  List<Map<String, dynamic>> get searchHistoryWithTime =>
      List.unmodifiable(_searchHistoryWithTime);

  /// 热门搜索关键词
  List<String> _hotKeywords = [];

  /// 热门搜索关键词
  List<String> get hotKeywords => List.unmodifiable(_hotKeywords);

  /// 搜索建议
  List<String> _suggestions = [];

  /// 搜索建议
  List<String> get suggestions => List.unmodifiable(_suggestions);

  /// 初始化
  Future<void> init() async {
    await _loadSearchHistory();
    await _loadHotKeywords();
  }

  /// 加载搜索历史
  Future<void> _loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyStr = prefs.getString(AppConstants.keySearchHistory);
      if (historyStr != null) {
        final list = jsonDecode(historyStr) as List;
        // 兼容旧格式（纯字符串列表）和新格式（带时间戳的Map列表）
        final parsed = list.map((e) {
          if (e is String) {
            return {'keyword': e, 'time': DateTime.now().toIso8601String()};
          }
          return Map<String, dynamic>.from(e as Map);
        }).toList();
        // 规范化空白并去重（保证删除与展示一致）
        final seen = <String>{};
        _searchHistoryWithTime = [];
        for (final m in parsed) {
          final kw = (m['keyword']?.toString() ?? '').trim();
          if (kw.isEmpty || seen.contains(kw)) continue;
          seen.add(kw);
          _searchHistoryWithTime.add({
            'keyword': kw,
            'time': m['time']?.toString() ?? DateTime.now().toIso8601String(),
          });
        }
        await _saveSearchHistory();
      }
    } catch (e) {
      debugPrint('加载搜索历史失败: $e');
      _searchHistoryWithTime = [];
    }
  }

  /// 保存搜索历史
  Future<void> _saveSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AppConstants.keySearchHistory,
        jsonEncode(_searchHistoryWithTime),
      );
    } catch (e) {
      debugPrint('保存搜索历史失败: $e');
    }
  }

  /// 加载热门搜索关键词
  Future<void> _loadHotKeywords() async {
    // 使用固定的热门搜索词作为默认热词
    // 注意：不能调用 searchMovies('')，因为 API 会因空关键词直接返回空列表
    _hotKeywords = [
      '动作片',
      '喜剧',
      '科幻',
      '爱情',
      '悬疑',
      '恐怖',
      '动画',
      '纪录片',
      '流浪地球',
      '三体',
      '满江红',
      '长津湖',
      '你好，李焕英',
      '哪吒之魔童降世',
      '战狼',
      '我不是药神',
      '速度与激情',
      '复仇者联盟',
      '变形金刚',
      '灌篮高手',
    ];
  }

  /// 添加搜索历史
  Future<void> addSearchHistory(String keyword) async {
    final k = keyword.trim();
    if (k.isEmpty) return;

    // 移除已存在的相同关键词（trim 后比较）
    _searchHistoryWithTime
        .removeWhere((e) => (e['keyword']?.toString() ?? '').trim() == k);

    // 添加到开头（带时间戳）
    _searchHistoryWithTime.insert(0, {
      'keyword': k,
      'time': DateTime.now().toIso8601String(),
    });

    // 限制最大条数
    if (_searchHistoryWithTime.length > AppConstants.maxSearchHistory) {
      _searchHistoryWithTime =
          _searchHistoryWithTime.take(AppConstants.maxSearchHistory).toList();
    }

    await _saveSearchHistory();
  }

  /// 删除搜索历史
  Future<void> deleteSearchHistory(String keyword) async {
    final k = keyword.trim();
    if (k.isEmpty) return;
    _searchHistoryWithTime.removeWhere(
      (e) => (e['keyword']?.toString() ?? '').trim() == k,
    );
    await _saveSearchHistory();
  }

  /// 清空搜索历史
  Future<void> clearSearchHistory() async {
    _searchHistoryWithTime.clear();
    await _saveSearchHistory();
  }

  /// 获取搜索建议（实时联想）
  Future<List<String>> getSuggestions(String query) async {
    if (query.trim().isEmpty) {
      _suggestions = [];
      return [];
    }

    final results = <String>[];

    // 从搜索历史中匹配
    for (final entry in _searchHistoryWithTime) {
      final history = entry['keyword'] as String;
      if (history.toLowerCase().contains(query.toLowerCase())) {
        results.add(history);
      }
    }

    // 从热门关键词中匹配
    for (final keyword in _hotKeywords) {
      if (keyword.toLowerCase().contains(query.toLowerCase()) &&
          !results.contains(keyword)) {
        results.add(keyword);
      }
    }

    _suggestions = results.take(10).toList();
    return _suggestions;
  }

  /// 搜索影片
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
  }) async {
    if (keyword.trim().isEmpty) {
      return SearchResult(results: [], hasMore: false, page: page);
    }

    try {
      final results = await _api.searchMovies(keyword, page: page);
      final hasMore = results.length >= AppConstants.pageSize;

      // 添加搜索历史
      if (page == 1) {
        await addSearchHistory(keyword);
      }

      return SearchResult(
        results: results,
        hasMore: hasMore,
        page: page,
      );
    } catch (e) {
      debugPrint('搜索失败: $e');
      return SearchResult(results: [], hasMore: false, page: page);
    }
  }

  /// 高亮关键词
  static String highlightKeyword(String text, String keyword) {
    if (keyword.isEmpty) return text;
    return text.replaceAll(
      RegExp(keyword, caseSensitive: false),
      '<<HIGHLIGHT>>$keyword<</HIGHLIGHT>>',
    );
  }
}

/// 搜索结果
class SearchResult {
  /// 搜索结果列表
  final List<Movie> results;

  /// 是否有更多
  final bool hasMore;

  /// 当前页码
  final int page;

  SearchResult({
    required this.results,
    required this.hasMore,
    required this.page,
  });
}
