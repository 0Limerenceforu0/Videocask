import 'package:flutter/material.dart';
import '../models/play_source.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';
import '../config/constants.dart';

/// 播放源状态管理
class SourceProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final ApiService _api = ApiService();

  /// 源配置变更回调（用于通知首页刷新数据）
  VoidCallback? onSourcesChanged;

  /// 播放源列表
  List<PlaySource> _sources = [];

  /// 播放源列表
  List<PlaySource> get sources => _sources;

  /// 播放源展示名（用于搜索列表等）
  String? sourceDisplayName(String? sourceId) {
    if (sourceId == null || sourceId.isEmpty) return null;
    for (final s in _sources) {
      if (s.id == sourceId) return s.name;
    }
    return null;
  }

  /// 当前选中的源
  PlaySource? _currentSource;

  /// 当前选中的源
  PlaySource? get currentSource => _currentSource;

  /// 是否正在加载
  final bool _isLoading = false;

  /// 是否正在加载
  bool get isLoading => _isLoading;

  /// 是否正在检测
  bool _isChecking = false;

  /// 是否正在检测
  bool get isChecking => _isChecking;

  /// 初始化
  Future<void> init() async {
    await _loadSources();
    // 启动时快速验证当前源是否可用，不可用则自动切换
    await _ensureValidSource();
  }

  /// 加载播放源
  Future<void> _loadSources() async {
    _sources = _storage.getAllSources();

    // 如果没有源，添加默认源
    if (_sources.isEmpty) {
      for (int i = 0; i < AppConstants.defaultSources.length; i++) {
        final defaultSource = AppConstants.defaultSources[i];
        final source = PlaySource(
          id: 'default_$i',
          name: defaultSource['name']!,
          url: defaultSource['url']!,
          type: defaultSource['type']!,
          sortOrder: i,
        );
        _sources.add(source);
        await _storage.saveSource(source);
      }
    } else {
      // 检查是否有新增的默认源（版本更新后可能有新源）
      final existingUrls = _sources.map((s) => s.url).toSet();
      for (int i = 0; i < AppConstants.defaultSources.length; i++) {
        final defaultSource = AppConstants.defaultSources[i];
        if (!existingUrls.contains(defaultSource['url'])) {
          final source = PlaySource(
            id: 'default_$i',
            name: defaultSource['name']!,
            url: defaultSource['url']!,
            type: defaultSource['type']!,
            sortOrder: i,
          );
          _sources.add(source);
          await _storage.saveSource(source);
        }
      }

      // 重置所有默认源的isValid状态（避免旧检测结果影响）
      for (int i = 0; i < _sources.length; i++) {
        if (_sources[i].id.startsWith('default_') && !_sources[i].isValid) {
          _sources[i] = _sources[i].copyWith(isValid: true);
          await _storage.saveSource(_sources[i]);
        }
      }
    }

    // 设置当前源为第一个启用的源
    _currentSource = _sources.where((s) => s.enabled).firstOrNull;
    if (_currentSource != null) {
      _api.setCurrentSource(_currentSource!);
    }

    // 设置可用源列表（用于自动切换）
    _api.setAvailableSources(_sources);

    // 注册源切换回调
    _api.onSourceSwitched = (PlaySource newSource) {
      _currentSource = newSource;
      notifyListeners();
    };

    notifyListeners();
  }

  /// 添加播放源
  Future<void> addSource({
    required String name,
    required String url,
    String type = 'cms',
    String remark = '',
  }) async {
    final source = PlaySource(
      id: 'source_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      url: url,
      type: type,
      sortOrder: _sources.length,
      remark: remark,
    );

    _sources.add(source);
    await _storage.saveSource(source);
    _api.setAvailableSources(_sources);
    notifyListeners();
    onSourcesChanged?.call();
  }

  /// 编辑播放源
  Future<void> updateSource(PlaySource source) async {
    final index = _sources.indexWhere((s) => s.id == source.id);
    if (index >= 0) {
      _sources[index] = source;
      await _storage.saveSource(source);
      _api.setAvailableSources(_sources);
      notifyListeners();
    }
  }

  /// 删除播放源
  Future<void> deleteSource(String id) async {
    _sources.removeWhere((s) => s.id == id);
    await _storage.deleteSource(id);

    // 如果删除的是当前源，切换到第一个启用的源
    if (_currentSource?.id == id) {
      _currentSource = _sources.where((s) => s.enabled).firstOrNull;
      if (_currentSource != null) {
        _api.setCurrentSource(_currentSource!);
      }
    }

    _api.setAvailableSources(_sources);
    notifyListeners();
    onSourcesChanged?.call();
  }

  /// 切换源启用状态
  Future<void> toggleSource(String id) async {
    final index = _sources.indexWhere((s) => s.id == id);
    if (index >= 0) {
      final source =
          _sources[index].copyWith(enabled: !_sources[index].enabled);
      _sources[index] = source;
      await _storage.saveSource(source);
      _api.setAvailableSources(_sources);
      notifyListeners();
      onSourcesChanged?.call();
    }
  }

  /// 选择当前源
  Future<void> selectSource(String id) async {
    final source = _sources.where((s) => s.id == id).firstOrNull;
    if (source != null && source.enabled) {
      _currentSource = source;
      _api.setCurrentSource(source);
      notifyListeners();
      onSourcesChanged?.call();
    }
  }

  /// 检测所有源的有效性
  Future<void> checkAllSources() async {
    _isChecking = true;
    notifyListeners();

    for (int i = 0; i < _sources.length; i++) {
      final source = _sources[i];
      final isValid = await _api.checkSource(source);
      _sources[i] = source.copyWith(
        isValid: isValid,
        lastCheckTime: DateTime.now(),
      );
      await _storage.saveSource(_sources[i]);
      notifyListeners();
    }

    _isChecking = false;
    notifyListeners();
  }

  /// 检测单个源
  Future<bool> checkSingleSource(String id) async {
    final source = _sources.where((s) => s.id == id).firstOrNull;
    if (source == null) return false;

    final isValid = await _api.checkSource(source);
    final index = _sources.indexWhere((s) => s.id == id);
    if (index >= 0) {
      _sources[index] = source.copyWith(
        isValid: isValid,
        lastCheckTime: DateTime.now(),
      );
      await _storage.saveSource(_sources[index]);
      notifyListeners();
    }

    return isValid;
  }

  /// 排序源
  Future<void> reorderSources(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    final item = _sources.removeAt(oldIndex);
    _sources.insert(newIndex, item);

    // 更新排序权重
    for (int i = 0; i < _sources.length; i++) {
      _sources[i] = _sources[i].copyWith(sortOrder: i);
      await _storage.saveSource(_sources[i]);
    }

    notifyListeners();
  }

  /// 导入源（JSON字符串）
  Future<int> importSources(String jsonStr) async {
    try {
      // 简单解析JSON数组格式的源
      final RegExp regExp =
          RegExp(r'"name"\s*:\s*"([^"]+)"\s*,\s*"url"\s*:\s*"([^"]+)"');
      final matches = regExp.allMatches(jsonStr);

      int count = 0;
      for (final match in matches) {
        final name = match.group(1) ?? '';
        final url = match.group(2) ?? '';
        if (name.isNotEmpty && url.isNotEmpty) {
          await addSource(name: name, url: url);
          count++;
        }
      }
      return count;
    } catch (e) {
      return 0;
    }
  }

  /// 导出源
  String exportSources() {
    final list = _sources.map((s) => s.toJson()).toList();
    return '{"sources": $list}';
  }

  /// 获取启用的源
  List<PlaySource> get enabledSources =>
      _sources.where((s) => s.enabled && s.isValid).toList();

  /// 确保当前源可用，不可用则自动切换到下一个可用源
  ///
  /// 启动时调用，快速检测当前源是否能正常返回数据。
  /// 如果当前源不可用，依次尝试其他启用的源，找到第一个可用的。
  Future<void> _ensureValidSource() async {
    if (_currentSource == null) return;

    final isValid = await _api.checkSource(_currentSource!);
    if (isValid) {
      debugPrint('✅ 当前源 "${_currentSource!.name}" 可用');
      return;
    }

    debugPrint('⚠️ 当前源 "${_currentSource!.name}" 不可用，自动切换...');

    // 标记当前源为不可用
    final index = _sources.indexWhere((s) => s.id == _currentSource!.id);
    if (index >= 0) {
      _sources[index] = _sources[index].copyWith(isValid: false);
      await _storage.saveSource(_sources[index]);
    }

    // 依次尝试其他启用的源
    final otherSources =
        _sources.where((s) => s.enabled && s.id != _currentSource!.id).toList();
    for (final source in otherSources) {
      final sourceValid = await _api.checkSource(source);
      if (sourceValid) {
        debugPrint('✅ 切换到可用源: "${source.name}"');
        _currentSource = source;
        _api.setCurrentSource(source);

        // 更新源的可用状态
        final idx = _sources.indexWhere((s) => s.id == source.id);
        if (idx >= 0) {
          _sources[idx] = _sources[idx].copyWith(isValid: true);
          await _storage.saveSource(_sources[idx]);
        }

        _api.setAvailableSources(_sources);
        notifyListeners();
        return;
      }
    }

    debugPrint('❌ 没有找到可用的源');
    _api.setAvailableSources(_sources);
    notifyListeners();
  }
}
