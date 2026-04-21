import 'dart:async';

import 'package:flutter/foundation.dart';

import 'torrent_player_models.dart';

/// Web 等非 IO 平台占位实现（无 libtorrent / FFI）。
class TorrentPlayerService with ChangeNotifier {
  static final TorrentPlayerService _instance =
      TorrentPlayerService._internal();
  factory TorrentPlayerService() => _instance;
  TorrentPlayerService._internal();

  TorrentPlayState _state = TorrentPlayState.idle;
  TorrentPlayState get state => _state;

  String _errorMessage = '当前平台不支持磁力链接播放';
  String get errorMessage => _errorMessage;

  double _downloadProgress = 0;
  double get downloadProgress => _downloadProgress;

  int _downloadSpeed = 0;
  int get downloadSpeed => _downloadSpeed;

  int _peers = 0;
  int get peers => _peers;

  int _seeds = 0;
  int get seeds => _seeds;

  String? _streamUrl;
  String? get streamUrl => _streamUrl;

  List<TorrentFileItem> _files = [];
  List<TorrentFileItem> get files => _files;

  String _torrentName = '';
  String get torrentName => _torrentName;

  int _totalSize = 0;
  int get totalSize => _totalSize;

  bool get isInitialized => false;

  Future<void> init() async {
    _setState(TorrentPlayState.error, _errorMessage);
  }

  Future<bool> addMagnet(String magnetUri) async {
    _setState(TorrentPlayState.error, _errorMessage);
    return false;
  }

  void fetchFiles() {}

  Future<String?> playFile(int fileIndex) async => null;

  Future<void> stop() async {
    _streamUrl = null;
    _files = [];
    _torrentName = '';
    _totalSize = 0;
    _downloadProgress = 0;
    _downloadSpeed = 0;
    _peers = 0;
    _seeds = 0;
    _setState(TorrentPlayState.idle, '');
  }

  String get downloadSpeedFormatted => '0 B/s';

  String get progressFormatted => '0.0%';

  void _setState(TorrentPlayState state, String error) {
    _state = state;
    _errorMessage = error;
    notifyListeners();
  }
}
