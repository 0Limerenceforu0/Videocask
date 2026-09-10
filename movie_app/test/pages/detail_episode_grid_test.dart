import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/pages/detail/detail_episode_grid.dart';
import 'package:movie_app/pages/detail/detail_ui_tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DetailEpisodeGrid', () {
    testWidgets('paginates large episode lists', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final episodes = List.generate(
        500,
        (i) => Episode(
          index: i,
          name: 'E${i + 1}',
          url: 'https://example.com/$i.mp4',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context)!;
              return Scaffold(
                body: DetailEpisodeGrid(
                  episodes: episodes,
                  playingIndex: 0,
                  l10n: l10n,
                  colors: DetailPageColors.of(context),
                  onEpisodeTap: (_) {},
                  largeListThreshold: 80,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('500'), findsOneWidget);
      expect(find.text('E1'), findsOneWidget);
      expect(find.text('E500'), findsNothing);

      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();

      expect(find.textContaining('/ 25'), findsOneWidget);
      expect(find.text('E21'), findsOneWidget);
      expect(find.text('E500'), findsNothing);
    });

    testWidgets('uses list rows for long episode titles', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final episodes = List.generate(
        4,
        (i) => Episode(
          index: i,
          name: '第${i + 1}期 综艺节目超长标题示例内容',
          url: 'https://example.com/$i.mp4',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context)!;
              return Scaffold(
                body: DetailEpisodeGrid(
                  episodes: episodes,
                  playingIndex: 0,
                  l10n: l10n,
                  colors: DetailPageColors.of(context),
                  onEpisodeTap: (_) {},
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('第1期'), findsOneWidget);
      expect(
        find.textContaining('综艺节目超长标题示例内容'),
        findsWidgets,
      );
    });
  });
}
