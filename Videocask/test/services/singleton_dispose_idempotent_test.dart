import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/deep_link_stream_service.dart';
import 'package:movie_app/services/dlna_service.dart';
import 'package:movie_app/services/local_media_http_server.dart';
import 'package:movie_app/services/torrent_player_service.dart';

/// 单例 dispose 幂等性契约。
///
/// 背景（v1.0.41 真实回归）：应用退出路径（`_MovieAppState.dispose`）开始
/// 统一调用各单例的 dispose。单例跨测试共享，widget 测试反复装配-卸载
/// `MovieApp` 会让同一单例被 dispose 多次 —— ChangeNotifier 重复 dispose
/// 后再 notifyListeners 直接抛 `debugAssertNotDisposed`。
///
/// 契约：任一单例的 dispose 调用任意多次都不抛、不挂死。
void main() {
  group('单例 dispose 幂等', () {
    test('TorrentPlayerService：连续 dispose 不抛', () async {
      final service = TorrentPlayerService();
      await service.dispose();
      await service.dispose();
      await service.dispose();
      // dispose 后触发内部 notify 路径（stop）也不抛
      await service.stop();
      expect(service.isInitialized, isFalse);
    });

    test('TorrentPlayerService：dispose 后 stop 不抛', () async {
      final service = TorrentPlayerService();
      await service.stop();
      await service.dispose();
      await service.stop();
    });

    test('DlnaService：连续 dispose 不抛', () {
      final service = DlnaService();
      service.dispose();
      service.dispose();
      service.dispose();
    });

    test('DeepLinkStreamService：连续 dispose 不抛', () async {
      final service = DeepLinkStreamService.instance;
      await service.dispose();
      await service.dispose();
    });

    test('LocalMediaHttpServer：连续 dispose 不抛', () async {
      final server = LocalMediaHttpServer.instance;
      await server.dispose();
      await server.dispose();
    });
  });
}
