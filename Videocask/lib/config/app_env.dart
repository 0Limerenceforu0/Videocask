/// 运行环境开关（通过 `--dart-define` 控制）。
///
/// 示例：
/// - 集成测试：`flutter test integration_test --dart-define=APP_TEST_MODE=true`
class AppEnv {
  AppEnv._();

  /// 自动化测试模式：
  /// - 不依赖外部接口可用性
  /// - 避免网络、播放器等平台能力导致的非业务失败
  static const bool isTestMode =
      bool.fromEnvironment('APP_TEST_MODE', defaultValue: false);
}
