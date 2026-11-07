import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/buffer_tier.dart';

void main() {
  const int mb = 1024 * 1024;

  group('BufferTier 自动挡位（按物理内存）', () {
    test('2GB 入门机 → 128MB（下限）', () {
      expect(BufferTier.autoBytesFor(2 * 1024 * mb), 128 * mb);
      expect(BufferTier.autoBytesFor(3 * 1024 * mb), 128 * mb);
    });

    test('4GB → 192MB', () {
      expect(BufferTier.autoBytesFor(4 * 1024 * mb), 192 * mb);
    });

    test('6GB → 256MB', () {
      expect(BufferTier.autoBytesFor(6 * 1024 * mb), 256 * mb);
    });

    test('8GB → 384MB', () {
      expect(BufferTier.autoBytesFor(8 * 1024 * mb), 384 * mb);
    });

    test('12GB 及以上 → 512MB（上限）', () {
      expect(BufferTier.autoBytesFor(12 * 1024 * mb), 512 * mb);
      expect(BufferTier.autoBytesFor(16 * 1024 * mb), 512 * mb);
    });

    test('探测失败（0）→ 保守的 192MB，不能是 0', () {
      expect(BufferTier.autoBytesFor(0), BufferTier.fallbackBytes);
      expect(BufferTier.autoBytesFor(0), 192 * mb);
      expect(BufferTier.autoBytesFor(-1), 192 * mb);
    });
  });

  group('BufferTier 自动挡动态评估（按当前可用内存）', () {
    int total8g = 8 * 1024 * mb;

    test('可用内存宽裕 → 保持天花板（8GB 机 384MB）', () {
      expect(
        BufferTier.adaptiveBytesFor(
          totalMemoryBytes: total8g,
          availableMemoryBytes: 4 * 1024 * mb,
          currentBytes: 384 * mb,
        ),
        384 * mb,
      );
    });

    test('可用内存紧张 → 降档', () {
      // budget = 800/4 = 200MB → 目标 192MB
      expect(
        BufferTier.adaptiveBytesFor(
          totalMemoryBytes: total8g,
          availableMemoryBytes: 800 * mb,
          currentBytes: 384 * mb,
        ),
        192 * mb,
      );
    });

    test('极低可用内存 → 降到下限 128MB，不会更低', () {
      expect(
        BufferTier.adaptiveBytesFor(
          totalMemoryBytes: total8g,
          availableMemoryBytes: 100 * mb,
          currentBytes: 256 * mb,
        ),
        128 * mb,
      );
    });

    test('可用内存回升 → 升档（余量够才升）', () {
      // budget = 1400/4 = 350MB，目标 256MB，350 ≥ 256×1.25 → 升
      expect(
        BufferTier.adaptiveBytesFor(
          totalMemoryBytes: total8g,
          availableMemoryBytes: 1400 * mb,
          currentBytes: 192 * mb,
        ),
        256 * mb,
      );
      // budget = 300MB，目标同为 256MB，但 300 < 320 → 不升，避免抖动
      expect(
        BufferTier.adaptiveBytesFor(
          totalMemoryBytes: total8g,
          availableMemoryBytes: 1200 * mb,
          currentBytes: 192 * mb,
        ),
        192 * mb,
      );
    });

    test('降档迟滞：预算略低于当前档不降', () {
      // current 192，budget = 700/4 = 175MB，175 ≥ 192×0.8=153.6 → 保持
      expect(
        BufferTier.adaptiveBytesFor(
          totalMemoryBytes: total8g,
          availableMemoryBytes: 700 * mb,
          currentBytes: 192 * mb,
        ),
        192 * mb,
      );
    });

    test('永远不会超过物理内存算出的天花板', () {
      // 4GB 机天花板 192MB，哪怕可用 8GB 也不能升到 512
      expect(
        BufferTier.adaptiveBytesFor(
          totalMemoryBytes: 4 * 1024 * mb,
          availableMemoryBytes: 8 * 1024 * mb,
          currentBytes: 192 * mb,
        ),
        192 * mb,
      );
    });

    test('探测失败（0）→ 保持现状，不能因为一次异常就砍到 128', () {
      expect(
        BufferTier.adaptiveBytesFor(
          totalMemoryBytes: total8g,
          availableMemoryBytes: 0,
          currentBytes: 384 * mb,
        ),
        384 * mb,
      );
    });

    test('评估周期是 10 分钟', () {
      expect(BufferTier.autoTuneInterval, const Duration(minutes: 10));
    });
  });

  group('BufferTier 手动挡位', () {
    test('合法挡位原样生效', () {
      for (final m in BufferTier.manualMegabytes) {
        expect(
          BufferTier.resolveBytes(tier: '$m', totalMemoryBytes: 8 * 1024 * mb),
          m * mb,
        );
      }
    });

    test('手动挡位不受设备内存影响（4GB 选 512 就是 512）', () {
      expect(
        BufferTier.resolveBytes(tier: '512', totalMemoryBytes: 4 * 1024 * mb),
        512 * mb,
      );
    });

    test('非法/缺失 key 回退到自动', () {
      final auto = BufferTier.autoBytesFor(6 * 1024 * mb);
      expect(
          BufferTier.resolveBytes(tier: 'abc', totalMemoryBytes: 6 * 1024 * mb),
          auto);
      expect(BufferTier.resolveBytes(tier: '', totalMemoryBytes: 6 * 1024 * mb),
          auto);
    });

    test('越界值被夹到 128~512，绝不能变成 0', () {
      expect(BufferTier.resolveBytes(tier: '8', totalMemoryBytes: 0),
          BufferTier.minBytes);
      expect(BufferTier.resolveBytes(tier: '4096', totalMemoryBytes: 0),
          BufferTier.maxBytes);
    });

    test('allKeys 覆盖 auto + 全部手动挡位', () {
      expect(BufferTier.allKeys.first, BufferTier.autoKey);
      expect(BufferTier.allKeys.length, BufferTier.manualMegabytes.length + 1);
    });
  });

  group('BufferTier 文案', () {
    test('自动档副标题带上本机内存与推出来的 MB', () {
      final text = BufferTier.describe(
        tier: BufferTier.autoKey,
        totalMemoryBytes: 8 * 1024 * mb,
      );
      expect(text, contains('8.0GB'));
      expect(text, contains('384 MB'));
    });

    test('内存探测失败时明确说按多少处理', () {
      final text = BufferTier.describe(
        tier: BufferTier.autoKey,
        totalMemoryBytes: 0,
      );
      expect(text, contains('未知'));
      expect(text, contains('192 MB'));
    });

    test('自动挡标签带上当前实际生效的挡位', () {
      expect(
        BufferTier.labelOf(BufferTier.autoKey, autoBytes: 256 * mb),
        contains('256 MB'),
      );
      // 没有自动值时保持原来的粗标签
      expect(BufferTier.labelOf(BufferTier.autoKey), '自动');
      expect(BufferTier.labelOf('384'), '384 MB');
    });

    test('自动挡副标题显示当前可用内存', () {
      final text = BufferTier.describe(
        tier: BufferTier.autoKey,
        totalMemoryBytes: 8 * 1024 * mb,
        availableMemoryBytes: 2 * 1024 * mb,
        autoBytes: 256 * mb,
      );
      expect(text, contains('8.0GB'));
      expect(text, contains('256 MB'));
      expect(text, contains('2.0GB'));
    });

    test('手动挡位副标题不谎报设备内存', () {
      final text =
          BufferTier.describe(tier: '256', totalMemoryBytes: 8 * 1024 * mb);
      expect(text, contains('256 MB'));
      expect(text, isNot(contains('8.0GB')));
    });
  });
}
