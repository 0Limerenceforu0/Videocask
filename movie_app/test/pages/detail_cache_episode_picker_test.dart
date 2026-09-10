import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/pages/detail/detail_cache_episode_picker.dart';
import 'package:movie_app/providers/cache_provider.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DetailCacheEpisodePicker', () {
    testWidgets('toggles selection and supports select all', (tester) async {
      final episodes = List.generate(
        6,
        (i) => Episode(
          index: i,
          name: '第${i + 1}期 综艺超长标题示例',
          url: 'https://example.com/$i.mp4',
        ),
      );
      var selected = <int>{0};

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: ChangeNotifierProvider(
            create: (_) => CacheProvider(),
            child: Builder(
              builder: (context) {
                return Scaffold(
                  body: DetailCacheEpisodePicker(
                    episodes: episodes,
                    movieId: 'm1',
                    sourceId: 's1',
                    playingEpisodeIndex: 0,
                    selectedIndices: selected,
                    onSelectionChanged: (next) => selected = next,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('第1期'), findsWidgets);
      expect(find.text('第2期'), findsOneWidget);

      await tester.tap(find.text('第2期'));
      await tester.pumpAndSettle();
      expect(selected, {0, 1});

      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(selected, {0, 1, 2, 3, 4, 5});
    });
  });
}
