import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/home/search_channel_gate.dart';

void main() {
  group('SearchChannelGate 通道开关', () {
    test('普通片名：严格片名过滤 + 照搜磁力', () {
      final gate = SearchChannelGate.resolve(
        isTypeWord: false,
        isConfirmedPerson: false,
        personProbeFailed: false,
      );
      expect(gate.strictTitleFilter, isTrue);
      expect(gate.runMagnet, isTrue);
    });

    test('确认人名：不过滤 + 不搜磁力（省 45s）', () {
      final gate = SearchChannelGate.resolve(
        isTypeWord: false,
        isConfirmedPerson: true,
        personProbeFailed: false,
      );
      expect(gate.strictTitleFilter, isFalse);
      expect(gate.runMagnet, isFalse);
    });

    test('类型词：不过滤 + 不搜磁力', () {
      final gate = SearchChannelGate.resolve(
        isTypeWord: true,
        isConfirmedPerson: false,
        personProbeFailed: false,
      );
      expect(gate.strictTitleFilter, isFalse);
      expect(gate.runMagnet, isFalse);
    });

    test('探测失败：放宽过滤，但磁力照搜', () {
      // 🔴 回归用例：旧实现把「看起来像人名」也塞进这个判定，
      // 「功夫」「长江七号」被当成人名 → 磁力通道整片关闭。
      // 探测失败只意味着「不知道」，不能据此关磁力。
      final gate = SearchChannelGate.resolve(
        isTypeWord: false,
        isConfirmedPerson: false,
        personProbeFailed: true,
      );
      expect(gate.strictTitleFilter, isFalse);
      expect(gate.runMagnet, isTrue);
    });

    test('类型词优先于探测失败：仍然不过滤', () {
      final gate = SearchChannelGate.resolve(
        isTypeWord: true,
        isConfirmedPerson: false,
        personProbeFailed: true,
      );
      expect(gate.strictTitleFilter, isFalse);
      expect(gate.runMagnet, isFalse);
    });

    test('确认人名同时探测失败（理论不该发生）：按确认人名处理', () {
      final gate = SearchChannelGate.resolve(
        isTypeWord: false,
        isConfirmedPerson: true,
        personProbeFailed: true,
      );
      expect(gate.strictTitleFilter, isFalse);
      expect(gate.runMagnet, isFalse);
    });
  });
}
