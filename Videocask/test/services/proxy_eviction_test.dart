import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/proxy_eviction.dart';

void main() {
  group('evictOldest - 数量上限', () {
    test('空 map 不淘汰', () {
      final map = <String, int>{};
      final removed = evictOldest(map, 8);
      expect(removed, isEmpty);
      expect(map, isEmpty);
    });

    test('未超上限不淘汰', () {
      final map = {'a': 1, 'b': 2, 'c': 3};
      final removed = evictOldest(map, 8);
      expect(removed, isEmpty);
      expect(map.length, 3);
    });

    test('恰好等于上限不淘汰', () {
      final map = {'a': 1, 'b': 2, 'c': 3, 'd': 4, 'e': 5, 'f': 6, 'g': 7, 'h': 8};
      final removed = evictOldest(map, 8);
      expect(removed, isEmpty);
      expect(map.length, 8);
    });

    test('超出 1 个 -> 淘汰最旧 1 个', () {
      final map = {'a': 1, 'b': 2, 'c': 3};
      final removed = evictOldest(map, 2);
      expect(removed.length, 1);
      expect(removed.first.key, 'a'); // 最旧
      expect(map.length, 2);
      expect(map.keys, containsAll(['b', 'c']));
    });

    test('超出多个 -> 淘汰数量恰好为多出部分', () {
      final map = {'a': 1, 'b': 2, 'c': 3, 'd': 4, 'e': 5};
      final removed = evictOldest(map, 2);
      expect(removed.length, 3);
      expect(map.length, 2);
    });

    test('maxCount=0 -> 全部淘汰', () {
      final map = {'a': 1, 'b': 2};
      final removed = evictOldest(map, 0);
      expect(removed.length, 2);
      expect(map, isEmpty);
    });

    test('maxCount 为负 -> 视为 0，全部淘汰', () {
      final map = {'a': 1, 'b': 2, 'c': 3};
      final removed = evictOldest(map, -5);
      expect(removed.length, 3);
      expect(map, isEmpty);
    });
  });

  group('evictOldest - 淘汰顺序 (LRU)', () {
    test('淘汰的是最旧（最先插入）的若干项，剩余保持插入顺序', () {
      final map = <String, int>{};
      for (final c in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j']) {
        map[c] = c.codeUnitAt(0);
      }
      final removed = evictOldest(map, 8);
      // 最旧 2 项 a,b 被淘汰
      expect(removed.map((e) => e.key).toList(), ['a', 'b']);
      // 剩余为 c..j，且顺序不变
      expect(map.keys.toList(), ['c', 'd', 'e', 'f', 'g', 'h', 'i', 'j']);
    });

    test('返回的被淘汰条目携带原 value，供调用方关闭资源', () {
      final map = {
        'x': 'sessionX',
        'y': 'sessionY',
        'z': 'sessionZ',
      };
      final removed = evictOldest(map, 2);
      expect(removed.length, 1);
      expect(removed.first.key, 'x');
      expect(removed.first.value, 'sessionX');
    });
  });

  group('evictOldest - 与代理会话上限一致 (maxCount=8)', () {
    test('注册 12 个会话后淘汰到 8 个，且是最旧 4 个', () {
      final map = <int, String>{};
      for (var i = 1; i <= 12; i++) {
        map[i] = 'session-$i';
      }
      final removed = evictOldest(map, 8);
      expect(removed.length, 4);
      expect(removed.map((e) => e.key).toList(), [1, 2, 3, 4]);
      expect(map.length, 8);
      expect(map.keys.first, 5); // 剩余最旧是 5
    });
  });
}
