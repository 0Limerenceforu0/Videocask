/// 旧「硬件解码」总开关 → 新「硬解档位」的迁移结果。
class HwDecodeMigration {
  const HwDecodeMigration({
    required this.modeKey,
    required this.clearLegacyKey,
    required this.didMigrateDisabled,
  });

  /// 迁移后应写入 `hw_decode_mode` 的值（空串 = 跟随平台默认）。
  final String modeKey;

  /// 是否清理旧的 `hardware_decode` 键。
  final bool clearLegacyKey;

  /// 是否发生了「旧开关 = 关闭」的实质迁移（供日志/测试断言）。
  final bool didMigrateDisabled;
}

/// 纯函数：合并「旧的布尔总开关」与「新的档位键」。
///
/// - 已经存过档位键：一律以档位为准（新设置优先），旧键存在就清理掉；
/// - 只有旧开关且为 false：等价于新档位的「关闭」（`off`）；
/// - 只有旧开关且为 true：保持平台默认，不需要写档位键；
/// - 两者都没有：全新安装，什么都不做。
HwDecodeMigration resolveHwDecodeMigration({
  required bool? legacyHardwareDecode,
  required String savedModeKey,
}) {
  if (savedModeKey.isNotEmpty) {
    return HwDecodeMigration(
      modeKey: savedModeKey,
      clearLegacyKey: legacyHardwareDecode != null,
      didMigrateDisabled: false,
    );
  }
  if (legacyHardwareDecode == false) {
    // 与 HwDecodeMode.disabled.name 一致，别写成 'off'：
    // `hwDecodeModeFromKey` 不认识别名，会悄悄回落到平台默认（即又开硬解）。
    return const HwDecodeMigration(
      modeKey: 'disabled',
      clearLegacyKey: true,
      didMigrateDisabled: true,
    );
  }
  return HwDecodeMigration(
    modeKey: '',
    clearLegacyKey: legacyHardwareDecode != null,
    didMigrateDisabled: false,
  );
}
