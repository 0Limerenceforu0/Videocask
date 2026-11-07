import 'package:flutter/material.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/config/app_locale_policy.dart';
import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/l10n/app_localizations_zh.dart';

void main() {
  group('resolveAppLocale', () {
    test('系统语言是英文也固定中文（回归：设置页/缓存页中英混排）', () {
      const supported = AppLocalizations.supportedLocales;
      // 生成文件把 en 排在第一位，跟随系统时会优先命中英文资源。
      expect(supported.first.languageCode, 'en');
      expect(resolveAppLocale(supported), kAppLocale);
      expect(resolveAppLocale(supported).languageCode, 'zh');
    });

    test('支持列表缺中文时兜底为中文，不抛异常', () {
      expect(resolveAppLocale(const [Locale('en')]), kAppLocale);
      expect(resolveAppLocale(const <Locale>[]), kAppLocale);
    });

    test('命中中文时返回支持列表里的原始 Locale', () {
      const zhHant = Locale('zh', 'TW');
      expect(resolveAppLocale(const [Locale('en'), zhHant]), zhHant);
    });

    test('实际加载的是中文本地化资源', () {
      final l10n = lookupAppLocalizations(
        resolveAppLocale(AppLocalizations.supportedLocales),
      );
      expect(l10n, isA<AppLocalizationsZh>());
      expect(l10n.appTitle, '罐子');
      // 下列各条正是英文系统截图里显示为英文的条目。
      expect(l10n.settingsAutoPlayOnDetailEnter, '进入详情自动播放');
      expect(
        l10n.settingsAutoPlayOnDetailEnterSubtitle,
        '打开影片或磁力详情时自动开始播放',
      );
      expect(l10n.settingsHwDecodeMode, '硬解档位');
      expect(l10n.settingsVideoOutputMode, '视频输出后端');
      expect(l10n.cacheManagerTitle, '缓存管理');
      expect(l10n.cacheManagerStorageTitle, '存储空间');
    });
  });
}
