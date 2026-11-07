import 'package:flutter/foundation.dart' show ChangeNotifier;

/// Web 占位：与原生实现保持同一套 API，让按钮/徽标在 Web 上也能编译。
class MagnetDownloadTask {
  MagnetDownloadTask({
    required this.hash,
    required this.name,
    required this.torrentId,
    required this.savePath,
  });

  final String hash;
  final String name;
  final int torrentId;
  final String savePath;
  double progress = 0;
  bool finished = false;
}

class MagnetDownloadService extends ChangeNotifier {
  MagnetDownloadService._();

  static final MagnetDownloadService instance = MagnetDownloadService._();

  factory MagnetDownloadService() => instance;

  List<MagnetDownloadTask> get tasks => const <MagnetDownloadTask>[];

  MagnetDownloadTask? taskFor(String magnetUri) => null;

  Future<({bool ok, String message})> start({
    required String magnetUri,
    required String name,
  }) async =>
      (ok: false, message: 'Web 端暂不支持磁力下载，请在手机或桌面端使用');

  void cancel(String magnetUri) {}
}
