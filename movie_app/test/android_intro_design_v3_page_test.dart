import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/pages/design_reference/android_intro_design_v3_page.dart';

void main() {
  testWidgets('AndroidIntroDesignV3Page 简介可展开与 Tab 可切换', (tester) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.setSurfaceSize(const Size(390, 900));

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh'),
        home: AndroidIntroDesignV3Page(),
      ),
    );
    await tester.pump();

    expect(find.byType(AndroidIntroDesignV3Page), findsOneWidget);

    await tester.tap(find.byKey(const Key('design_v3_intro_toggle')));
    await tester.pump();
    expect(find.byIcon(Icons.expand_less_rounded), findsOneWidget);

    await tester.ensureVisible(find.text('播放线路'));
    await tester.tap(find.text('播放线路').last);
    await tester.pump();

    await tester.ensureVisible(find.text('磁力'));
    await tester.tap(find.text('磁力').last);
    await tester.pump();

    await binding.setSurfaceSize(null);
  });
}
