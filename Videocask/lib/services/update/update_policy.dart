/// 应用更新策略（纯函数，可单测）。
///
/// 这里不碰网络 / 文件 / 平台通道，只做「比版本、挑资产、判强制」这类纯计算，
/// 便于在 `test/services/update/update_policy_test.dart` 里直接覆盖边界。
///
/// 约定（与发版脚本 `tool/publish_release.py` 保持一致）：
/// - GitHub tag 形如 `v1.1.8`，Release 标题形如 `罐子 1.1.8`；
/// - 产物名形如 `videocask-android-arm64-v1.1.8.apk`；
/// - 正文含 `[强制更新]` 或 `[mandatory]` 时，跳过「稍后」直接要求更新。
library;

/// 平台枚举（Web 也参与，只是不落地安装，只提示刷新）。
enum UpdatePlatform { android, windows, web, unsupported }

/// 语义版本 + 构建号。
///
/// 比较规则：**先比 `major.minor.patch`，相等时才比构建号**。
/// 不能反过来「构建号优先」——远程 tag 通常只写 `v1.1.8` 不带 `+build`，
/// 若按构建号 0 与本地 67 比，会把新版本误判成更旧。
class AppVersion implements Comparable<AppVersion> {
  const AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.build,
  });

  final int major;
  final int minor;
  final int patch;

  /// `+N` 的构建号；远程 tag 未写时为 null。
  final int? build;

  /// 宽松解析：从任意含版本号的字符串里抓出第一组三段式版本。
  ///
  /// 支持 `1.1.8`、`v1.1.8`、`1.1.8+68`、`罐子 1.1.8`、`release-1.1.8`。
  /// 解析不出返回 null（调用方应视为「无可用更新」而不是抛异常）。
  static AppVersion? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final match = _pattern.firstMatch(raw);
    if (match == null) return null;
    final major = int.tryParse(match.group(1)!);
    final minor = int.tryParse(match.group(2)!);
    final patch = int.tryParse(match.group(3) ?? '0');
    if (major == null || minor == null || patch == null) return null;
    final buildRaw = match.group(4);
    return AppVersion(
      major: major,
      minor: minor,
      patch: patch,
      build: buildRaw == null ? null : int.tryParse(buildRaw),
    );
  }

  static final RegExp _pattern = RegExp(
    r'(\d+)\.(\d+)(?:\.(\d+))?(?:\+(\d+))?',
  );

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    // 三段全等时才比构建号；缺省按 0 处理。
    return (build ?? 0).compareTo(other.build ?? 0);
  }

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  bool sameAs(AppVersion other) => compareTo(other) == 0;

  /// `1.1.8` / `1.1.8+68`
  String get label =>
      build == null ? '$major.$minor.$patch' : '$major.$minor.$patch+$build';

  @override
  String toString() => label;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, build ?? 0);
}

/// GitHub Release 里的一个附件（只保留更新需要的字段）。
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    this.size = 0,
  });

  final String name;
  final String downloadUrl;
  final int size;

  /// 体积的人类可读形式，用于弹窗展示。
  String get sizeLabel {
    if (size <= 0) return '';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 一条可用的更新信息。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.assets,
    this.notes = '',
    this.htmlUrl = '',
    this.publishedAt,
  });

  final AppVersion version;
  final String tagName;
  final List<ReleaseAsset> assets;
  final String notes;
  final String htmlUrl;
  final DateTime? publishedAt;

  /// 正文是否要求强制更新。
  bool get isMandatory => isMandatoryNotes(notes);

  /// 按平台挑出要下载的资产；没有匹配项返回 null。
  ReleaseAsset? assetFor(UpdatePlatform platform, {String? androidAbi}) =>
      pickAsset(assets: assets, platform: platform, androidAbi: androidAbi);
}

/// 正文里的强制更新标记。
const List<String> kMandatoryMarkers = ['[强制更新]', '[mandatory]'];

/// 判断 Release 正文是否要求强制更新。
bool isMandatoryNotes(String? notes) {
  if (notes == null || notes.isEmpty) return false;
  final lower = notes.toLowerCase();
  for (final marker in kMandatoryMarkers) {
    if (lower.contains(marker.toLowerCase())) return true;
  }
  return false;
}

/// 由 `Build.SUPPORTED_ABIS`（已按优先级排好）选出要匹配的 abi 标签。
///
/// 返回值是资产名里出现的写法（`arm64-v8a` / `armeabi-v7a` / `x86_64`），
/// 全都不认识时返回 null，交给 [pickAsset] 走「通用包」兜底。
String? pickAndroidAbiTag(List<String> supportedAbis) {
  for (final raw in supportedAbis) {
    final abi = raw.trim().toLowerCase();
    if (abi == 'arm64-v8a') return 'arm64-v8a';
    if (abi == 'armeabi-v7a' || abi == 'armeabi' || abi == 'armv7') {
      return 'armeabi-v7a';
    }
    if (abi == 'x86_64' || abi == 'x64') return 'x86_64';
    if (abi == 'x86') return 'x86';
  }
  return null;
}

/// 各 abi 标签在资产名里的同义写法（都小写比较）。
const Map<String, List<String>> _abiAliases = {
  'arm64-v8a': ['arm64-v8a', 'arm64', 'aarch64'],
  'armeabi-v7a': ['armeabi-v7a', 'armeabi', 'armv7', 'arm32'],
  'x86_64': ['x86_64', 'x64'],
  'x86': ['x86'],
};

/// 从资产列表里挑出目标平台的安装包。
///
/// 匹配规则（大小写不敏感）：
/// - Android：名字必须含 `android`；优先与设备 abi 精确对应，
///   其次其它 abi，最后接受不带 abi 的通用包（`videocask-android-v1.1.8.apk`）。
/// - Windows：名字必须含 `windows` 且以 `.zip` 结尾（项目发的是绿色版压缩包）。
/// - Web：名字必须含 `web` 且以 `.zip` 结尾。
///
/// 中文命名（`罐子_android_arm64_v1.1.8.apk`）同样能命中，因为只依赖关键词。
ReleaseAsset? pickAsset({
  required List<ReleaseAsset> assets,
  required UpdatePlatform platform,
  String? androidAbi,
}) {
  if (assets.isEmpty) return null;
  final candidates = assets
      .where((a) => a.name.trim().isNotEmpty && a.downloadUrl.trim().isNotEmpty)
      .toList(growable: false);
  if (candidates.isEmpty) return null;

  switch (platform) {
    case UpdatePlatform.android:
      final androidAssets = candidates
          .where((a) => a.name.toLowerCase().contains('android'))
          .toList(growable: false);
      if (androidAssets.isEmpty) return null;
      return _pickAndroid(androidAssets, androidAbi);

    case UpdatePlatform.windows:
      return _pickZip(candidates, 'windows');

    case UpdatePlatform.web:
      return _pickZip(candidates, 'web');

    case UpdatePlatform.unsupported:
      return null;
  }
}

ReleaseAsset? _pickZip(List<ReleaseAsset> assets, String keyword) {
  for (final asset in assets) {
    final name = asset.name.toLowerCase();
    if (name.contains(keyword) && name.endsWith('.zip')) return asset;
  }
  return null;
}

ReleaseAsset? _pickAndroid(List<ReleaseAsset> assets, String? androidAbi) {
  // 1) 精确命中设备 abi。
  if (androidAbi != null) {
    final aliases = _abiAliases[androidAbi] ?? [androidAbi];
    for (final asset in assets) {
      final name = asset.name.toLowerCase();
      if (aliases.any(name.contains)) return asset;
    }
  }

  // 2) 设备 abi 不明或该 abi 没有产物：按通用优先级挑一个能装的。
  for (final abi in const ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86']) {
    final aliases = _abiAliases[abi]!;
    for (final asset in assets) {
      final name = asset.name.toLowerCase();
      if (aliases.any(name.contains)) return asset;
    }
  }

  // 3) 兜底：不带 abi 的通用 apk。
  for (final asset in assets) {
    final name = asset.name.toLowerCase();
    if (!name.endsWith('.apk')) continue;
    final hasAbi = _abiAliases.values
        .expand((e) => e)
        .any((alias) => name.contains(alias));
    if (!hasAbi) return asset;
  }
  return null;
}

/// 是否需要向用户提示更新。
///
/// - 远程版本不比本地新 → 不提示；
/// - 强制更新 → 即使已提示过也提示（强更必须拦住）；
/// - **同一个版本已经提示过 → 不再提示**。判断依据是 [promptedVersion]（三段号，
///   忽略 `+build`），它在弹窗真正展示前就落盘，因此用户点「稍后」、点关闭按钮、
///   点右上角 ×、按 Esc 还是直接杀进程，都不会在下次启动时再次被提醒；
///   下一个新版本发布时仍会各提醒一次。
/// - [skippedBuild] 是旧版「稍后」的记录，保留以兼容已升级用户的本地数据。
bool shouldPromptUpdate({
  required AppVersion current,
  required AppVersion latest,
  required bool mandatory,
  int? skippedBuild,
  String? promptedVersion,
}) {
  if (!latest.isNewerThan(current)) return false;
  if (mandatory) return true;
  if (promptedVersion != null && promptedVersion == versionKey(latest)) {
    return false;
  }
  return skippedBuild == null || skippedBuild != (latest.build ?? 0);
}

/// 版本号的三段核心（忽略 `+build`），用于「该版本是否已提示过」的持久化比较。
///
/// 不能用 [AppVersion.label]：远程 tag 通常不带 `+build`，而本地注入的构建号
/// 可能存在，两者字符串不相等会把「已提示」误判成「没提示」。
String versionKey(AppVersion version) =>
    '${version.major}.${version.minor}.${version.patch}';

/// 版本变化的简短描述，用于弹窗标题。
String describeVersionChange(AppVersion current, AppVersion latest) =>
    '${current.label} → ${latest.label}';
