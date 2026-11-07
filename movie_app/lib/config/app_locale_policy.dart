import 'package:flutter/material.dart' show Locale;

/// 应用界面语言策略：固定中文。
///
/// 背景：`MaterialApp.router` 原先会用 `localeListResolutionCallback` 跟随系统
/// 语言，英文系统（en-US 模拟器、部分刷机 ROM）下加载 app_en.arb。但界面里仍
/// 有大量中文硬编码文案（设置项、缓存页、提示语），于是出现「Downloads /
/// Storage」与「已用 0 B · 不设上限」同屏的中英混排，看起来像翻译没做完。
///
/// 英文资源目前只覆盖了 l10n 词条，远不足以构成完整英文版；与其逐条补齐
/// 几百处中文硬编码，先统一走中文。等英文文案整体补齐、且提供应用内语言
/// 开关之后，再在这里接入系统首选语言。
const Locale kAppLocale = Locale('zh');

/// 返回实际使用的界面语言。
///
/// [supported] 为 `AppLocalizations.supportedLocales`；只要其中含中文就取该
/// Locale（保留生成文件里的 countryCode 等元信息），否则兜底为 [kAppLocale]。
Locale resolveAppLocale(List<Locale> supported) {
  for (final locale in supported) {
    if (locale.languageCode == kAppLocale.languageCode) return locale;
  }
  return kAppLocale;
}
