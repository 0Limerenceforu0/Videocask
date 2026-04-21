import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'高清影视'**
  String get appTitle;

  /// No description provided for @appInitLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在初始化…'**
  String get appInitLoading;

  /// No description provided for @appInitRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get appInitRetry;

  /// No description provided for @appInitErrorTitle.
  ///
  /// In zh, this message translates to:
  /// **'启动失败'**
  String get appInitErrorTitle;

  /// No description provided for @navHome.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get navHome;

  /// No description provided for @toolbarBrandGoHome.
  ///
  /// In zh, this message translates to:
  /// **'回到首页'**
  String get toolbarBrandGoHome;

  /// No description provided for @navFollow.
  ///
  /// In zh, this message translates to:
  /// **'追剧'**
  String get navFollow;

  /// No description provided for @navProfile.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get navProfile;

  /// No description provided for @detailIntro.
  ///
  /// In zh, this message translates to:
  /// **'简介'**
  String get detailIntro;

  /// No description provided for @detailPlayRoutes.
  ///
  /// In zh, this message translates to:
  /// **'播放线路'**
  String get detailPlayRoutes;

  /// No description provided for @detailMagnetSearch.
  ///
  /// In zh, this message translates to:
  /// **'磁力搜索'**
  String get detailMagnetSearch;

  /// No description provided for @detailMagnetSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'以下为多源聚合结果：优先按 IMDb/片名/年份匹配；英文资源旁显示本片中文名标签。'**
  String get detailMagnetSearchHint;

  /// No description provided for @detailOpenMagnetSearch.
  ///
  /// In zh, this message translates to:
  /// **'打开磁力搜索'**
  String get detailOpenMagnetSearch;

  /// No description provided for @detailRelated.
  ///
  /// In zh, this message translates to:
  /// **'相关推荐'**
  String get detailRelated;

  /// No description provided for @detailRelatedHint.
  ///
  /// In zh, this message translates to:
  /// **'相关推荐功能'**
  String get detailRelatedHint;

  /// No description provided for @detailDesktopEpisodes.
  ///
  /// In zh, this message translates to:
  /// **'选集'**
  String get detailDesktopEpisodes;

  /// No description provided for @detailDesktopTabMagnet.
  ///
  /// In zh, this message translates to:
  /// **'磁力'**
  String get detailDesktopTabMagnet;

  /// No description provided for @detailDesktopTabRecommend.
  ///
  /// In zh, this message translates to:
  /// **'推荐'**
  String get detailDesktopTabRecommend;

  /// No description provided for @detailDesktopNoEpisodes.
  ///
  /// In zh, this message translates to:
  /// **'该线路暂无分集'**
  String get detailDesktopNoEpisodes;

  /// No description provided for @detailMagnetOpenInSearch.
  ///
  /// In zh, this message translates to:
  /// **'用片名打开搜索'**
  String get detailMagnetOpenInSearch;

  /// No description provided for @detailMagnetRefreshStrict.
  ///
  /// In zh, this message translates to:
  /// **'精准搜索'**
  String get detailMagnetRefreshStrict;

  /// No description provided for @detailMagnetRefreshLoose.
  ///
  /// In zh, this message translates to:
  /// **'扩大范围'**
  String get detailMagnetRefreshLoose;

  /// No description provided for @detailMagnetSearching.
  ///
  /// In zh, this message translates to:
  /// **'正在检索磁力…'**
  String get detailMagnetSearching;

  /// No description provided for @detailMagnetPlay.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get detailMagnetPlay;

  /// No description provided for @detailMagnetOpenDetail.
  ///
  /// In zh, this message translates to:
  /// **'磁力详情'**
  String get detailMagnetOpenDetail;

  /// No description provided for @detailMagnetZhLabelHint.
  ///
  /// In zh, this message translates to:
  /// **'对应本片'**
  String get detailMagnetZhLabelHint;

  /// No description provided for @designV3MovieTitle.
  ///
  /// In zh, this message translates to:
  /// **'星际穿越'**
  String get designV3MovieTitle;

  /// No description provided for @designV3DoubanLabel.
  ///
  /// In zh, this message translates to:
  /// **'豆瓣'**
  String get designV3DoubanLabel;

  /// No description provided for @designV3MetaLine.
  ///
  /// In zh, this message translates to:
  /// **'2014 | 科幻 冒险 | 169分钟'**
  String get designV3MetaLine;

  /// No description provided for @designV3SynopsisCollapsed.
  ///
  /// In zh, this message translates to:
  /// **'影片讲述了一队探险家利用对虫洞的新发现…'**
  String get designV3SynopsisCollapsed;

  /// No description provided for @designV3SynopsisFull.
  ///
  /// In zh, this message translates to:
  /// **'影片讲述了一队探险家利用对虫洞的新发现，超越人类对太空旅行的极限，在广袤的宇宙中进行星际航行。'**
  String get designV3SynopsisFull;

  /// No description provided for @designV3ExpandIntro.
  ///
  /// In zh, this message translates to:
  /// **'展开简介'**
  String get designV3ExpandIntro;

  /// No description provided for @designV3CollapseIntro.
  ///
  /// In zh, this message translates to:
  /// **'收起简介'**
  String get designV3CollapseIntro;

  /// No description provided for @designV3BufferDemo.
  ///
  /// In zh, this message translates to:
  /// **'缓冲 1.8 MB/s'**
  String get designV3BufferDemo;

  /// No description provided for @designV3TimeDemo.
  ///
  /// In zh, this message translates to:
  /// **'34:12 / 2:49:05'**
  String get designV3TimeDemo;

  /// No description provided for @designV3EpisodeChip1.
  ///
  /// In zh, this message translates to:
  /// **'星际穿越 主集 1'**
  String get designV3EpisodeChip1;

  /// No description provided for @designV3EpisodeChip2.
  ///
  /// In zh, this message translates to:
  /// **'星际穿越 2'**
  String get designV3EpisodeChip2;

  /// No description provided for @designV3RouteLine1.
  ///
  /// In zh, this message translates to:
  /// **'线路 1（主线路）'**
  String get designV3RouteLine1;

  /// No description provided for @designV3RouteLine2.
  ///
  /// In zh, this message translates to:
  /// **'线路 2（备用）'**
  String get designV3RouteLine2;

  /// No description provided for @designV3RelatedMartian.
  ///
  /// In zh, this message translates to:
  /// **'火星救援'**
  String get designV3RelatedMartian;

  /// No description provided for @designV3RelatedArrival.
  ///
  /// In zh, this message translates to:
  /// **'降临'**
  String get designV3RelatedArrival;

  /// No description provided for @designV3RelatedInception.
  ///
  /// In zh, this message translates to:
  /// **'盗梦空间'**
  String get designV3RelatedInception;

  /// No description provided for @designV3RelatedGravity.
  ///
  /// In zh, this message translates to:
  /// **'地心引力'**
  String get designV3RelatedGravity;

  /// No description provided for @designV3MagnetRowTitle.
  ///
  /// In zh, this message translates to:
  /// **'星际穿越.2160p.4K.HDR…'**
  String get designV3MagnetRowTitle;

  /// No description provided for @designV3MagnetRowMeta.
  ///
  /// In zh, this message translates to:
  /// **'22.5 GB · 磁力'**
  String get designV3MagnetRowMeta;

  /// No description provided for @designV3TooltipPlayPause.
  ///
  /// In zh, this message translates to:
  /// **'播放或暂停'**
  String get designV3TooltipPlayPause;

  /// No description provided for @designV3TooltipSpeed.
  ///
  /// In zh, this message translates to:
  /// **'播放速度'**
  String get designV3TooltipSpeed;

  /// No description provided for @designV3TooltipVolume.
  ///
  /// In zh, this message translates to:
  /// **'音量'**
  String get designV3TooltipVolume;

  /// No description provided for @designV3TooltipCast.
  ///
  /// In zh, this message translates to:
  /// **'投屏'**
  String get designV3TooltipCast;

  /// No description provided for @designV3TooltipFullscreen.
  ///
  /// In zh, this message translates to:
  /// **'全屏'**
  String get designV3TooltipFullscreen;

  /// No description provided for @designV3TooltipDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get designV3TooltipDownload;

  /// No description provided for @designV3TooltipFavorite.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get designV3TooltipFavorite;

  /// No description provided for @designV3TooltipShare.
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get designV3TooltipShare;

  /// No description provided for @detailPlayerPrevEpisode.
  ///
  /// In zh, this message translates to:
  /// **'上一集'**
  String get detailPlayerPrevEpisode;

  /// No description provided for @detailPlayerNextEpisode.
  ///
  /// In zh, this message translates to:
  /// **'下一集'**
  String get detailPlayerNextEpisode;

  /// No description provided for @detailPlayerTooltipCache.
  ///
  /// In zh, this message translates to:
  /// **'缓存'**
  String get detailPlayerTooltipCache;

  /// No description provided for @detailPlayerFullscreenEnter.
  ///
  /// In zh, this message translates to:
  /// **'全屏'**
  String get detailPlayerFullscreenEnter;

  /// No description provided for @detailPlayerFullscreenExit.
  ///
  /// In zh, this message translates to:
  /// **'退出全屏'**
  String get detailPlayerFullscreenExit;

  /// No description provided for @detailPlayerSubtitleMenu.
  ///
  /// In zh, this message translates to:
  /// **'字幕（自动匹配 / 选择）'**
  String get detailPlayerSubtitleMenu;

  /// No description provided for @detailPlayerSubtitleSheetTitle.
  ///
  /// In zh, this message translates to:
  /// **'字幕'**
  String get detailPlayerSubtitleSheetTitle;

  /// No description provided for @detailPlayerSubtitleAutoMatch.
  ///
  /// In zh, this message translates to:
  /// **'在线自动匹配'**
  String get detailPlayerSubtitleAutoMatch;

  /// No description provided for @detailPlayerSubtitleAutoMatchSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'磁力等无内嵌字幕时，按片名尝试匹配（需 OpenSubtitles API Key）'**
  String get detailPlayerSubtitleAutoMatchSubtitle;

  /// No description provided for @detailPlayerSubtitlePickFile.
  ///
  /// In zh, this message translates to:
  /// **'选择本地字幕文件…'**
  String get detailPlayerSubtitlePickFile;

  /// No description provided for @detailPlayerSubtitleOff.
  ///
  /// In zh, this message translates to:
  /// **'恢复内嵌轨 / 关闭外挂'**
  String get detailPlayerSubtitleOff;

  /// No description provided for @detailPlayerSubtitleBrowseOnline.
  ///
  /// In zh, this message translates to:
  /// **'浏览在线字幕…'**
  String get detailPlayerSubtitleBrowseOnline;

  /// No description provided for @detailPlayerSubtitleLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在搜索字幕…'**
  String get detailPlayerSubtitleLoading;

  /// No description provided for @detailPlayerSubtitleNone.
  ///
  /// In zh, this message translates to:
  /// **'未找到字幕'**
  String get detailPlayerSubtitleNone;

  /// No description provided for @detailPlayerSubtitleNoApiKey.
  ///
  /// In zh, this message translates to:
  /// **'请先在设置中填写 OpenSubtitles API Key'**
  String get detailPlayerSubtitleNoApiKey;

  /// No description provided for @detailPlayerSubtitleApplyFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载字幕失败'**
  String get detailPlayerSubtitleApplyFailed;

  /// No description provided for @detailPlayerSubtitleApplied.
  ///
  /// In zh, this message translates to:
  /// **'已加载字幕'**
  String get detailPlayerSubtitleApplied;

  /// No description provided for @homeTitleRecommend.
  ///
  /// In zh, this message translates to:
  /// **'推荐'**
  String get homeTitleRecommend;

  /// No description provided for @homeEndOfListHint.
  ///
  /// In zh, this message translates to:
  /// **'没有更多了'**
  String get homeEndOfListHint;

  /// No description provided for @toolbarSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get toolbarSearch;

  /// No description provided for @toolbarFollow.
  ///
  /// In zh, this message translates to:
  /// **'追剧'**
  String get toolbarFollow;

  /// No description provided for @toolbarProfile.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get toolbarProfile;

  /// No description provided for @toolbarSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get toolbarSettings;

  /// No description provided for @toolbarViewComfort.
  ///
  /// In zh, this message translates to:
  /// **'切换为舒适视图'**
  String get toolbarViewComfort;

  /// No description provided for @toolbarViewCompact.
  ///
  /// In zh, this message translates to:
  /// **'切换为紧凑视图'**
  String get toolbarViewCompact;

  /// No description provided for @toolbarTheme.
  ///
  /// In zh, this message translates to:
  /// **'切换主题'**
  String get toolbarTheme;

  /// No description provided for @toolbarThemeSwitched.
  ///
  /// In zh, this message translates to:
  /// **'已切换为：{name}'**
  String toolbarThemeSwitched(String name);

  /// No description provided for @toolbarSearchPlaceholderHome.
  ///
  /// In zh, this message translates to:
  /// **'搜索影片、剧集…'**
  String get toolbarSearchPlaceholderHome;

  /// No description provided for @toolbarSearchPlaceholderInChannel.
  ///
  /// In zh, this message translates to:
  /// **'搜索{channelLabel}…'**
  String toolbarSearchPlaceholderInChannel(String channelLabel);

  /// No description provided for @filterLabelGenre.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get filterLabelGenre;

  /// No description provided for @filterLabelRegion.
  ///
  /// In zh, this message translates to:
  /// **'地区'**
  String get filterLabelRegion;

  /// No description provided for @navChannelMovies.
  ///
  /// In zh, this message translates to:
  /// **'电影'**
  String get navChannelMovies;

  /// No description provided for @navChannelTv.
  ///
  /// In zh, this message translates to:
  /// **'连续剧'**
  String get navChannelTv;

  /// No description provided for @navChannelVariety.
  ///
  /// In zh, this message translates to:
  /// **'综艺'**
  String get navChannelVariety;

  /// No description provided for @navChannelAnime.
  ///
  /// In zh, this message translates to:
  /// **'动漫'**
  String get navChannelAnime;

  /// No description provided for @navChannelShort.
  ///
  /// In zh, this message translates to:
  /// **'短剧'**
  String get navChannelShort;

  /// No description provided for @homePortalChipLatest.
  ///
  /// In zh, this message translates to:
  /// **'最新'**
  String get homePortalChipLatest;

  /// No description provided for @homePortalRankSectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'{label}热播榜'**
  String homePortalRankSectionTitle(String label);

  /// No description provided for @searchWideAggregateHint.
  ///
  /// In zh, this message translates to:
  /// **'以下为多源聚合结果与搜索历史；与静态演示稿一致为功能说明。'**
  String get searchWideAggregateHint;

  /// No description provided for @categoryPortalHotRankTitle.
  ///
  /// In zh, this message translates to:
  /// **'热播榜'**
  String get categoryPortalHotRankTitle;

  /// No description provided for @categoryPortalModuleHighlights.
  ///
  /// In zh, this message translates to:
  /// **'精选'**
  String get categoryPortalModuleHighlights;

  /// No description provided for @categoryPortalModuleMorePicks.
  ///
  /// In zh, this message translates to:
  /// **'更多推荐'**
  String get categoryPortalModuleMorePicks;

  /// No description provided for @categoryPortalModuleKeepGoing.
  ///
  /// In zh, this message translates to:
  /// **'继续浏览'**
  String get categoryPortalModuleKeepGoing;

  /// No description provided for @categoryPortalModuleMore.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get categoryPortalModuleMore;

  /// No description provided for @categoryPortalModuleMoreTooltip.
  ///
  /// In zh, this message translates to:
  /// **'在首页浏览该分类'**
  String get categoryPortalModuleMoreTooltip;

  /// No description provided for @categoryPortalModuleTagged.
  ///
  /// In zh, this message translates to:
  /// **'{genre} · 精选'**
  String categoryPortalModuleTagged(String genre);

  /// No description provided for @categoryPortalModuleEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无该片单'**
  String get categoryPortalModuleEmpty;

  /// No description provided for @categoryPortalScrollForMore.
  ///
  /// In zh, this message translates to:
  /// **'继续滑动可加载更多'**
  String get categoryPortalScrollForMore;

  /// No description provided for @categoryPortalRankEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无榜单数据'**
  String get categoryPortalRankEmpty;

  /// No description provided for @categoryPortalRankScore.
  ///
  /// In zh, this message translates to:
  /// **'{score} 分'**
  String categoryPortalRankScore(String score);

  /// No description provided for @categoryPortalEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'暂无本频道数据，请检查网络或播放源。'**
  String get categoryPortalEmptyHint;

  /// No description provided for @homeOpenDedicatedChannel.
  ///
  /// In zh, this message translates to:
  /// **'宽屏频道页'**
  String get homeOpenDedicatedChannel;

  /// No description provided for @homeOpenDedicatedChannelTooltip.
  ///
  /// In zh, this message translates to:
  /// **'打开与静态稿一致的宽屏频道布局'**
  String get homeOpenDedicatedChannelTooltip;

  /// No description provided for @homeTabRecommend.
  ///
  /// In zh, this message translates to:
  /// **'推荐'**
  String get homeTabRecommend;

  /// No description provided for @homeScrollToTopTooltip.
  ///
  /// In zh, this message translates to:
  /// **'回到顶部'**
  String get homeScrollToTopTooltip;

  /// No description provided for @homeSnackbarRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get homeSnackbarRetry;

  /// No description provided for @homeLoadFailedTapRetry.
  ///
  /// In zh, this message translates to:
  /// **'加载失败，点击重试'**
  String get homeLoadFailedTapRetry;

  /// No description provided for @homeSectionSeeMore.
  ///
  /// In zh, this message translates to:
  /// **'查看更多'**
  String get homeSectionSeeMore;

  /// No description provided for @homeSectionCollapse.
  ///
  /// In zh, this message translates to:
  /// **'收起'**
  String get homeSectionCollapse;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
