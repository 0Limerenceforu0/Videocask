import 'package:flutter/material.dart';
import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/pages/design_reference/android_intro_design_v3_page.dart';

/// 仅用于本地预览设计稿复刻页，勿作为生产入口。
///
/// 运行：`flutter run -t lib/main_design_preview.dart -d chrome`
/// 或：`flutter run -t lib/main_design_preview.dart`
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Design preview',
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const AndroidIntroDesignV3Page(),
    ),
  );
}
