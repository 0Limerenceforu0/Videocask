import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/hw_decode_migration.dart';

void main() {
  group('旧硬件解码总开关 → 档位迁移', () {
    test('全新安装：没有任何旧设置 → 保持平台默认，不动旧键', () {
      final r = resolveHwDecodeMigration(
        legacyHardwareDecode: null,
        savedModeKey: '',
      );
      expect(r.modeKey, '');
      expect(r.clearLegacyKey, isFalse);
      expect(r.didMigrateDisabled, isFalse);
    });

    test('旧开关=false 且没存过档位 → 迁移成 disabled（软解行为不变）', () {
      final r = resolveHwDecodeMigration(
        legacyHardwareDecode: false,
        savedModeKey: '',
      );
      expect(r.modeKey, 'disabled');
      expect(r.clearLegacyKey, isTrue);
      expect(r.didMigrateDisabled, isTrue);
    });

    test('旧开关=true 且没存过档位 → 平台默认，只清旧键', () {
      final r = resolveHwDecodeMigration(
        legacyHardwareDecode: true,
        savedModeKey: '',
      );
      expect(r.modeKey, '');
      expect(r.clearLegacyKey, isTrue);
      expect(r.didMigrateDisabled, isFalse);
    });

    test('已经存过档位 → 档位优先，不被旧开关覆盖', () {
      final r = resolveHwDecodeMigration(
        legacyHardwareDecode: false,
        savedModeKey: 'mediaCodecZeroCopy',
      );
      expect(r.modeKey, 'mediaCodecZeroCopy');
      expect(r.didMigrateDisabled, isFalse);
    });

    test('迁移重复执行（旧键已删）→ 幂等，不会再次写 disabled', () {
      final once = resolveHwDecodeMigration(
        legacyHardwareDecode: false,
        savedModeKey: '',
      );
      final twice = resolveHwDecodeMigration(
        legacyHardwareDecode: null,
        savedModeKey: once.modeKey,
      );
      expect(twice.modeKey, 'disabled');
      expect(twice.didMigrateDisabled, isFalse);
      expect(twice.clearLegacyKey, isFalse);
    });
  });
}
