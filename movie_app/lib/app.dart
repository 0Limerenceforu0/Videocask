import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'config/app_env.dart';
import 'config/routes.dart';
import 'providers/theme_provider.dart';
import 'providers/user_provider.dart';
import 'providers/movie_provider.dart';
import 'providers/player_provider.dart';
import 'providers/source_provider.dart';
import 'providers/favorite_provider.dart';
import 'providers/history_provider.dart';
import 'providers/cache_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/playlist_provider.dart';
import 'services/storage_service.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/search_service.dart';
import 'services/player_service.dart';
import 'services/cache_service.dart';
import 'services/sync_service.dart';
import 'l10n/app_localizations.dart';
import 'widgets/material_app_deep_link_child.dart';
import 'services/deep_link_stream_service.dart';

/// 应用程序配置
class MovieApp extends StatefulWidget {
  const MovieApp({super.key});

  @override
  State<MovieApp> createState() => _MovieAppState();
}

class _MovieAppState extends State<MovieApp> {
  /// 是否初始化完成
  bool _isInitialized = false;

  /// 初始化错误信息
  String _initError = '';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  /// 初始化应用
  Future<void> _initialize() async {
    try {
      // 自动化测试模式：跳过依赖平台通道/磁盘/网络的初始化，保证测试稳定与可重复。
      if (AppEnv.isTestMode) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
        return;
      }

      // 第一步：初始化本地存储（必须最先，其他服务依赖它）
      await StorageService().init();

      // 第二步：并行初始化所有独立服务
      await Future.wait([
        AuthService().init(),
        SearchService().init(),
        if (!kIsWeb) CacheService().init() else Future.value(),
        SyncService().init(),
        PlayerService().init(),
      ]);

      // API服务初始化现在是异步的
      await ApiService().init();

      // 设置状态栏样式（仅移动端，不阻塞）
      if (!kIsWeb) {
        SystemChrome.setSystemUIOverlayStyle(
          const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        );
        unawaited(
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]),
        );
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(DeepLinkStreamService.instance.start());
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = '初始化失败: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Builder(
                builder: (context) {
                  final l10n = AppLocalizations.of(context)!;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_initError.isEmpty) ...[
                        const CircularProgressIndicator(
                          color: Color(0xFF2196F3),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          l10n.appInitLoading,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ] else ...[
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.appInitErrorTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _initError,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _initialize,
                          child: Text(l10n.appInitRetry),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        // 主题
        ChangeNotifierProvider(create: (_) => ThemeProvider()),

        // 用户
        ChangeNotifierProvider(create: (_) => UserProvider()),

        // 播放源（必须在 MovieProvider 之前初始化，确保 API 源可用）
        ChangeNotifierProvider(create: (_) => SourceProvider()),

        // 影片数据（依赖 SourceProvider）
        ChangeNotifierProvider(create: (_) => MovieProvider()),

        // 播放器
        ChangeNotifierProvider(create: (_) => PlayerProvider()),

        // 收藏
        ChangeNotifierProvider(create: (_) => FavoriteProvider()),

        // 观看历史
        ChangeNotifierProvider(create: (_) => HistoryProvider()),

        // 缓存
        ChangeNotifierProvider(create: (_) => CacheProvider()),

        // 设置
        ChangeNotifierProvider(create: (_) => SettingsProvider()),

        // 播放列表
        ChangeNotifierProvider(create: (_) => PlaylistProvider()),
      ],
      child: Builder(
        builder: (context) {
          // 延迟初始化Provider，实现懒加载
          if (!AppEnv.isTestMode) {
            // 初始化必要的Provider
            Future.microtask(() async {
              if (!context.mounted) return;
              // 首先初始化主题和设置
              final themeProvider = context.read<ThemeProvider>();
              final settingsProvider = context.read<SettingsProvider>();

              // 然后初始化源和用户相关
              final sourceProvider = context.read<SourceProvider>();
              final userProvider = context.read<UserProvider>();

              // 最后初始化其他Provider
              final movieProvider = context.read<MovieProvider>();
              final playerProvider = context.read<PlayerProvider>();
              final favoriteProvider = context.read<FavoriteProvider>();
              final historyProvider = context.read<HistoryProvider>();
              final cacheProvider = context.read<CacheProvider>();
              final playlistProvider = context.read<PlaylistProvider>();

              await themeProvider.init();
              if (!context.mounted) return;
              await settingsProvider.init();
              if (!context.mounted) return;
              await sourceProvider.init();
              if (!context.mounted) return;
              await userProvider.init();
              if (!context.mounted) return;
              await movieProvider.init();
              if (!context.mounted) return;
              await playerProvider.init();
              if (!context.mounted) return;
              await favoriteProvider.init();
              if (!context.mounted) return;
              await historyProvider.init();
              if (!context.mounted) return;
              await cacheProvider.init();
              if (!context.mounted) return;
              await playlistProvider.init();
            });
          }

          // 设置源变更回调：源配置变更后刷新首页数据
          final sourceProvider = context.read<SourceProvider>();
          final movieProvider = context.read<MovieProvider>();
          sourceProvider.onSourcesChanged = () {
            unawaited(movieProvider.loadHomeData());
          };

          return Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return MaterialApp.router(
                onGenerateTitle: (context) =>
                    AppLocalizations.of(context)!.appTitle,
                debugShowCheckedModeBanner: false,
                theme: themeProvider.currentTheme,
                routerConfig: AppRoutes.router,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                localeListResolutionCallback: (locales, supported) {
                  if (locales == null) return const Locale('zh');
                  for (final locale in locales) {
                    for (final s in supported) {
                      if (s.languageCode == locale.languageCode) {
                        return s;
                      }
                    }
                  }
                  return const Locale('zh');
                },
                builder: (context, child) =>
                    MaterialAppDeepLinkChild(child: child),
              );
            },
          );
        },
      ),
    );
  }
}
