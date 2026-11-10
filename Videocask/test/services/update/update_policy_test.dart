import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/update/update_policy.dart';

/// 更新策略单测。
///
/// 注意：这里的用例都尽量「摘掉实现就红」——
/// 例如版本比较用例如果改回「构建号优先」会立刻失败，
/// 资产挑选用例如果去掉平台关键词过滤也会立刻失败。
void main() {
  group('AppVersion.tryParse', () {
    test('解析纯版本号', () {
      final v = AppVersion.tryParse('1.1.8')!;
      expect(v.major, 1);
      expect(v.minor, 1);
      expect(v.patch, 8);
      expect(v.build, isNull);
    });

    test('解析带 v 前缀与构建号', () {
      final v = AppVersion.tryParse('v1.1.8+68')!;
      expect(v.label, '1.1.8+68');
      expect(v.build, 68);
    });

    test('从 Release 标题里抓版本', () {
      expect(AppVersion.tryParse('罐子 1.1.8')!.label, '1.1.8');
    });

    test('两段版本号补 0', () {
      expect(AppVersion.tryParse('1.2')!.label, '1.2.0');
    });

    test('无法解析返回 null（不抛异常）', () {
      expect(AppVersion.tryParse(null), isNull);
      expect(AppVersion.tryParse(''), isNull);
      expect(AppVersion.tryParse('latest'), isNull);
    });
  });

  group('AppVersion.compareTo', () {
    test('远程 tag 不带构建号时，仍能识别为更新版本', () {
      // 回归保护：若改成「构建号优先」，v1.1.8(build=0) 会被判成比
      // 1.1.7+67(build=67) 更旧，用户就永远收不到更新。
      final latest = AppVersion.tryParse('v1.1.8')!;
      final current = AppVersion.tryParse('1.1.7+67')!;
      expect(latest.isNewerThan(current), isTrue);
    });

    test('三段相同才比较构建号', () {
      final a = AppVersion.tryParse('1.1.7+68')!;
      final b = AppVersion.tryParse('1.1.7+67')!;
      expect(a.isNewerThan(b), isTrue);
      expect(b.isNewerThan(a), isFalse);
    });

    test('相同的两段式与三段式视为同版本', () {
      expect(
        AppVersion.tryParse('1.1.7')!.sameAs(AppVersion.tryParse('1.1.7')!),
        isTrue,
      );
    });

    test('主版本优先于构建号', () {
      final a = AppVersion.tryParse('2.0.0')!;
      final b = AppVersion.tryParse('1.99.99+999')!;
      expect(a.isNewerThan(b), isTrue);
    });
  });

  group('pickAndroidAbiTag', () {
    test('按设备优先级选出首个认识的 abi', () {
      expect(
        pickAndroidAbiTag(['arm64-v8a', 'armeabi-v7a', 'armeabi']),
        'arm64-v8a',
      );
      expect(pickAndroidAbiTag(['armeabi-v7a', 'armeabi']), 'armeabi-v7a');
      expect(pickAndroidAbiTag(['x86_64', 'x86']), 'x86_64');
    });

    test('全都不认识返回 null', () {
      expect(pickAndroidAbiTag(['mips']), isNull);
      expect(pickAndroidAbiTag([]), isNull);
    });
  });

  group('pickAsset', () {
    const assets = [
      ReleaseAsset(
        name: 'videocask-android-arm64-v1.1.8.apk',
        downloadUrl: 'https://x/a.apk',
        size: 36 * 1024 * 1024,
      ),
      ReleaseAsset(
        name: 'videocask-android-armeabi-v7a-v1.1.8.apk',
        downloadUrl: 'https://x/b.apk',
      ),
      ReleaseAsset(
        name: 'videocask-android-x86_64-v1.1.8.apk',
        downloadUrl: 'https://x/c.apk',
      ),
      ReleaseAsset(name: 'videocask-windows-x64-v1.1.8.zip', downloadUrl: 'https://x/d.zip'),
      ReleaseAsset(name: 'videocask-web-v1.1.8.zip', downloadUrl: 'https://x/e.zip'),
    ];

    test('Android 精确命中设备 abi', () {
      expect(
        pickAsset(
          assets: assets,
          platform: UpdatePlatform.android,
          androidAbi: 'armeabi-v7a',
        )!.name,
        'videocask-android-armeabi-v7a-v1.1.8.apk',
      );
    });

    test('Android 设备 abi 无产物时回退到其它 abi', () {
      expect(
        pickAsset(
          assets: assets,
          platform: UpdatePlatform.android,
          androidAbi: 'mips',
        )!.name,
        'videocask-android-arm64-v1.1.8.apk',
      );
    });

    test('Windows 只挑 windows 的 zip，不会拿到 apk', () {
      final picked = pickAsset(assets: assets, platform: UpdatePlatform.windows)!;
      expect(picked.name, 'videocask-windows-x64-v1.1.8.zip');
    });

    test('Web 挑 web 的 zip', () {
      expect(
        pickAsset(assets: assets, platform: UpdatePlatform.web)!.name,
        'videocask-web-v1.1.8.zip',
      );
    });

    test('缺少目标平台资产返回 null', () {
      expect(
        pickAsset(
          assets: const [
            ReleaseAsset(name: 'videocask-android-arm64-v1.1.8.apk', downloadUrl: 'u'),
          ],
          platform: UpdatePlatform.windows,
        ),
        isNull,
      );
    });

    test('中文命名的历史产物同样能匹配', () {
      const legacy = [
        ReleaseAsset(
          name: '罐子_android_arm64_v1.1.7.apk',
          downloadUrl: 'https://x/legacy.apk',
        ),
      ];
      expect(
        pickAsset(
          assets: legacy,
          platform: UpdatePlatform.android,
          androidAbi: 'arm64-v8a',
        )!.name,
        '罐子_android_arm64_v1.1.7.apk',
      );
    });

    test('不带 abi 的通用 apk 作为兜底', () {
      const generic = [
        ReleaseAsset(name: 'videocask-android-v1.1.8.apk', downloadUrl: 'https://x/g.apk'),
      ];
      expect(
        pickAsset(
          assets: generic,
          platform: UpdatePlatform.android,
          androidAbi: 'arm64-v8a',
        )!.name,
        'videocask-android-v1.1.8.apk',
      );
    });

    test('空资产列表返回 null', () {
      expect(
        pickAsset(assets: const [], platform: UpdatePlatform.android),
        isNull,
      );
    });
  });

  group('isMandatoryNotes', () {
    test('识别中英文强制标记', () {
      expect(isMandatoryNotes('[强制更新] 修复崩溃'), isTrue);
      expect(isMandatoryNotes('notes\n[MANDATORY]'), isTrue);
      expect(isMandatoryNotes('普通更新说明'), isFalse);
      expect(isMandatoryNotes(null), isFalse);
    });
  });

  group('shouldPromptUpdate', () {
    final current = AppVersion.tryParse('1.1.7+67')!;

    test('远程不新于本地时不提示', () {
      expect(
        shouldPromptUpdate(
          current: current,
          latest: AppVersion.tryParse('1.1.7')!,
          mandatory: false,
        ),
        isFalse,
      );
    });

    test('有新版本时提示', () {
      expect(
        shouldPromptUpdate(
          current: current,
          latest: AppVersion.tryParse('1.1.8')!,
          mandatory: false,
        ),
        isTrue,
      );
    });

    test('用户跳过该构建后不再打扰', () {
      expect(
        shouldPromptUpdate(
          current: current,
          latest: AppVersion.tryParse('1.1.8')!,
          mandatory: false,
          skippedBuild: 0,
        ),
        isFalse,
      );
    });

    test('强制更新无视跳过记录', () {
      expect(
        shouldPromptUpdate(
          current: current,
          latest: AppVersion.tryParse('1.1.8')!,
          mandatory: true,
          skippedBuild: 0,
        ),
        isTrue,
      );
    });
  });
}
