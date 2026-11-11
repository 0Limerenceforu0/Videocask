import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/magnet_weak_swarm_policy.dart';

void main() {
  group('MagnetWeakSwarmPolicy.isWeak', () {
    test('已经够起播缓冲时一律不算弱', () {
      expect(
        MagnetWeakSwarmPolicy.isWeak(
          activePeers: 0,
          downloadSpeed: 0,
          bufferPct: 5,
          readyBufferPct: 5,
        ),
        isFalse,
      );
      expect(
        MagnetWeakSwarmPolicy.isWeak(
          activePeers: 1,
          downloadSpeed: 0,
          bufferPct: 30,
          readyBufferPct: 5,
        ),
        isFalse,
      );
    });

    test('peer 数达到健康线时不算弱（哪怕速度很低）', () {
      // 多个 peer 但暂时没数据：交给 45s 交接 + 首帧看门狗，不在这里判死。
      expect(
        MagnetWeakSwarmPolicy.isWeak(
          activePeers: MagnetWeakSwarmPolicy.minHealthyPeers,
          downloadSpeed: 0,
          bufferPct: 0,
          readyBufferPct: 5,
        ),
        isFalse,
      );
    });

    test('速度达到下限时不算弱（哪怕只有 1 个 peer）', () {
      expect(
        MagnetWeakSwarmPolicy.isWeak(
          activePeers: 1,
          downloadSpeed: MagnetWeakSwarmPolicy.minSpeedBytesPerSec,
          bufferPct: 0,
          readyBufferPct: 5,
        ),
        isFalse,
      );
    });

    test('只连上 1 个 peer 且下行低于阈值 → 弱', () {
      // 真机 2026-11-10：索引写 17 做种，实际 activePeers=1、几十 KB/s。
      expect(
        MagnetWeakSwarmPolicy.isWeak(
          activePeers: 1,
          downloadSpeed: 60 * 1024,
          bufferPct: 2,
          readyBufferPct: 5,
        ),
        isTrue,
      );
    });

    test('一个 peer 都没连上且零下行 → 弱', () {
      expect(
        MagnetWeakSwarmPolicy.isWeak(
          activePeers: 0,
          downloadSpeed: 0,
          bufferPct: 0,
          readyBufferPct: 5,
        ),
        isTrue,
      );
    });

    test('速度刚好低于阈值 1 字节也算弱（边界取严格小于）', () {
      expect(
        MagnetWeakSwarmPolicy.isWeak(
          activePeers: 1,
          downloadSpeed: MagnetWeakSwarmPolicy.minSpeedBytesPerSec - 1,
          bufferPct: 0,
          readyBufferPct: 5,
        ),
        isTrue,
      );
    });
  });

  group('常量约束', () {
    test('确认窗口不能短到误杀「连得慢但能连上」的资源', () {
      // 受限网络下 peer 连接实测要 20–45s 才完成；窗口过短会把可恢复的
      // 弱 swarm 误判成死种。
      expect(
        MagnetWeakSwarmPolicy.confirmWindow.inSeconds,
        greaterThanOrEqualTo(15),
      );
    });

    test('弱 swarm 重试上限是有限的', () {
      // 无限重试会让用户对着死种一直转圈；0/1 又太激进。
      expect(MagnetWeakSwarmPolicy.maxWeakStrikes, greaterThanOrEqualTo(2));
      expect(MagnetWeakSwarmPolicy.maxWeakStrikes, lessThanOrEqualTo(3));
    });
  });
}
