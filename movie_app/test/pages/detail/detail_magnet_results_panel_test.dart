import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/models/torrent_info.dart';
import 'package:movie_app/pages/detail/detail_magnet_results_panel.dart';

const String _longLatinTitle =
    'The Wandering Earth 2019 1080p BluRay DoVi HDR10 TrueHD Atmos 7.1 x265-Gene';

Movie _movie(String name) => Movie(id: 'm1', name: name);

List<TorrentInfo> _results(int count) {
  return List<TorrentInfo>.generate(count, (i) {
    final n = (i + 1).toString().padLeft(2, '0');
    return TorrentInfo(
      name: 'RES-$n.2024.1080p.BluRay.x265',
      size: 4 * 1024 * 1024 * 1024,
      seeders: 12,
      leechers: 3,
      magnetUri: 'magnet:?xt=urn:btih:$n',
      source: 'Torrentio',
    );
  });
}

Widget _host({
  required Movie movie,
  required List<TorrentInfo> results,
  double width = 360,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    theme: ThemeData.dark(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: DetailMagnetResultsPanel(
              movie: movie,
              results: results,
              isLoading: false,
              statusMessage: '',
              onRefreshStrict: () async {},
              onRefreshLoose: () async {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('超长片名不会横向溢出（回归：名称超出屏幕）', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(
        movie: _movie(_longLatinTitle),
        results: [
          TorrentInfo(
            name: _longLatinTitle,
            size: 6 * 1024 * 1024 * 1024,
            seeders: 6,
            leechers: 0,
            magnetUri: 'magnet:?xt=urn:btih:aa',
            source: 'Torrentio',
          ),
        ],
        width: 320,
      ),
    );
    await tester.pumpAndSettle();

    // 溢出由 Row 无界布局引起：旧实现会抛 RenderFlex overflowed。
    expect(tester.takeException(), isNull);

    final paragraph = tester.renderObject<RenderParagraph>(
      find.text(_longLatinTitle).first,
    );
    expect(paragraph.size.width, lessThanOrEqualTo(320));
  });

  testWidgets('默认每页 20 条，翻页到第 2 页', (tester) async {
    await tester.pumpWidget(
      _host(movie: _movie('流浪地球'), results: _results(34)),
    );
    await tester.pumpAndSettle();

    expect(find.text('共 34 条结果'), findsOneWidget);
    // 顶部与底部各有一组翻页控件
    expect(find.text('1 / 2'), findsNWidgets(2));

    // 第 1 页：RES-01 .. RES-20 可见，RES-21 不在
    expect(find.text('RES-01.2024.1080p.BluRay.x265'), findsOneWidget);
    expect(find.text('RES-20.2024.1080p.BluRay.x265'), findsOneWidget);
    expect(find.text('RES-21.2024.1080p.BluRay.x265'), findsNothing);

    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();

    expect(find.text('2 / 2'), findsNWidgets(2));
    expect(find.text('RES-34.2024.1080p.BluRay.x265'), findsOneWidget);
    expect(find.text('RES-01.2024.1080p.BluRay.x265'), findsNothing);
  });

  testWidgets('每页条数可切换为 50', (tester) async {
    await tester.pumpWidget(
      _host(movie: _movie('流浪地球'), results: _results(34)),
    );
    await tester.pumpAndSettle();

    expect(find.text('每页 20 条'), findsOneWidget);

    await tester.tap(find.text('每页 20 条'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每页 50 条').last);
    await tester.pumpAndSettle();

    expect(find.text('每页 50 条'), findsOneWidget);
    // 34 条一页放得下 → 不再显示翻页控件
    expect(find.text('1 / 1'), findsNothing);
    expect(find.text('RES-34.2024.1080p.BluRay.x265'), findsOneWidget);
  });
}
