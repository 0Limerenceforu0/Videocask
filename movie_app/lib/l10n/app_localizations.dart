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

  /// No description provided for @detailMagnetPlayingBadge.
  ///
  /// In zh, this message translates to:
  /// **'磁力播放'**
  String get detailMagnetPlayingBadge;

  /// No description provided for @detailMagnetMetaDirector.
  ///
  /// In zh, this message translates to:
  /// **'导演'**
  String get detailMagnetMetaDirector;

  /// No description provided for @detailMagnetMetaActors.
  ///
  /// In zh, this message translates to:
  /// **'主演'**
  String get detailMagnetMetaActors;

  /// No description provided for @detailMagnetMetaRegion.
  ///
  /// In zh, this message translates to:
  /// **'地区'**
  String get detailMagnetMetaRegion;

  /// No description provided for @detailMagnetResourceSection.
  ///
  /// In zh, this message translates to:
  /// **'资源信息'**
  String get detailMagnetResourceSection;

  /// No description provided for @detailMagnetMetaResourceTitle.
  ///
  /// In zh, this message translates to:
  /// **'资源标题'**
  String get detailMagnetMetaResourceTitle;

  /// No description provided for @detailMagnetMetaSource.
  ///
  /// In zh, this message translates to:
  /// **'来源 {source}'**
  String detailMagnetMetaSource(String source);

  /// No description provided for @detailMagnetMetaSize.
  ///
  /// In zh, this message translates to:
  /// **'大小 {size}'**
  String detailMagnetMetaSize(String size);

  /// No description provided for @detailMagnetMetaSeeders.
  ///
  /// In zh, this message translates to:
  /// **'做种 {count}'**
  String detailMagnetMetaSeeders(String count);

  /// No description provided for @detailMagnetMetaLeechers.
  ///
  /// In zh, this message translates to:
  /// **'下载 {count}'**
  String detailMagnetMetaLeechers(String count);

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

  /// No description provided for @speedSelectorNormal.
  ///
  /// In zh, this message translates to:
  /// **'正常'**
  String get speedSelectorNormal;

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

  /// No description provided for @detailPlayerTooltipRouteQuality.
  ///
  /// In zh, this message translates to:
  /// **'线路 / 清晰度'**
  String get detailPlayerTooltipRouteQuality;

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

  /// No description provided for @detailPlayerSubtitleNoApiKeyHint.
  ///
  /// In zh, this message translates to:
  /// **'磁力资源可自动匹配字幕，需先在「设置 → OpenSubtitles API Key」填写 Key'**
  String get detailPlayerSubtitleNoApiKeyHint;

  /// No description provided for @detailPlayerSubtitleDelay.
  ///
  /// In zh, this message translates to:
  /// **'字幕时间轴'**
  String get detailPlayerSubtitleDelay;

  /// No description provided for @detailPlayerSubtitleDelayReset.
  ///
  /// In zh, this message translates to:
  /// **'重置偏移'**
  String get detailPlayerSubtitleDelayReset;

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

  /// No description provided for @settingsAutoPlayOnDetailEnter.
  ///
  /// In zh, this message translates to:
  /// **'进入详情自动播放'**
  String get settingsAutoPlayOnDetailEnter;

  /// No description provided for @settingsAutoPlayOnDetailEnterSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'打开影片或磁力详情时自动开始播放'**
  String get settingsAutoPlayOnDetailEnterSubtitle;

  /// No description provided for @settingsPreloadNextEpisode.
  ///
  /// In zh, this message translates to:
  /// **'预加载下一集'**
  String get settingsPreloadNextEpisode;

  /// No description provided for @settingsPreloadNextEpisodeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'当前集播放到 80% 时后台解析下一集地址'**
  String get settingsPreloadNextEpisodeSubtitle;

  /// No description provided for @settingsPlaybackPrefetch.
  ///
  /// In zh, this message translates to:
  /// **'播放预缓冲'**
  String get settingsPlaybackPrefetch;

  /// No description provided for @settingsPlaybackPrefetchSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'任意网络下预拉下一集前几 MB，加快切集'**
  String get settingsPlaybackPrefetchSubtitle;

  /// No description provided for @settingsTmdbApiKey.
  ///
  /// In zh, this message translates to:
  /// **'TMDB API Key'**
  String get settingsTmdbApiKey;

  /// No description provided for @settingsTmdbApiKeyConfigured.
  ///
  /// In zh, this message translates to:
  /// **'已配置'**
  String get settingsTmdbApiKeyConfigured;

  /// No description provided for @settingsTmdbApiKeyNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置（仍可用豆瓣解析）'**
  String get settingsTmdbApiKeyNotConfigured;

  /// No description provided for @settingsTmdbApiKeyDialogBody.
  ///
  /// In zh, this message translates to:
  /// **'在 themoviedb.org 注册并申请 API Key，用于中文片名解析为 IMDb 编号与英文片名，提升磁力搜索命中率。留空时仍会通过豆瓣联想 + IMDb 解析。'**
  String get settingsTmdbApiKeyDialogBody;

  /// No description provided for @settingsTmdbApiKeySaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存 TMDB API 配置'**
  String get settingsTmdbApiKeySaved;

  /// No description provided for @detailRouteFallbackSnack.
  ///
  /// In zh, this message translates to:
  /// **'缓冲较慢，已尝试切换线路'**
  String get detailRouteFallbackSnack;

  /// No description provided for @detailPlayerLockControls.
  ///
  /// In zh, this message translates to:
  /// **'锁定播放控件'**
  String get detailPlayerLockControls;

  /// No description provided for @detailPlayerUnlockControls.
  ///
  /// In zh, this message translates to:
  /// **'解锁播放控件'**
  String get detailPlayerUnlockControls;

  /// No description provided for @homeContinueWatching.
  ///
  /// In zh, this message translates to:
  /// **'继续观看'**
  String get homeContinueWatching;

  /// No description provided for @homeContinueWatchingSeeAll.
  ///
  /// In zh, this message translates to:
  /// **'查看全部'**
  String get homeContinueWatchingSeeAll;

  /// No description provided for @searchActionSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get searchActionSearch;

  /// No description provided for @searchClearFilters.
  ///
  /// In zh, this message translates to:
  /// **'清除筛选'**
  String get searchClearFilters;

  /// No description provided for @searchPlay.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get searchPlay;

  /// No description provided for @searchOpenDetail.
  ///
  /// In zh, this message translates to:
  /// **'进入详情'**
  String get searchOpenDetail;

  /// No description provided for @detailReplay.
  ///
  /// In zh, this message translates to:
  /// **'重播'**
  String get detailReplay;

  /// No description provided for @detailEpisodeFinished.
  ///
  /// In zh, this message translates to:
  /// **'本集已播放完毕'**
  String get detailEpisodeFinished;

  /// No description provided for @detailHistoryOverlay.
  ///
  /// In zh, this message translates to:
  /// **'上次看到 第{episode}集 {percent}%'**
  String detailHistoryOverlay(int episode, String percent);

  /// No description provided for @detailLoadError.
  ///
  /// In zh, this message translates to:
  /// **'无法加载影片信息，请检查网络或在「源管理」中切换采集源后重试。'**
  String get detailLoadError;

  /// No description provided for @detailBufferingMagnet.
  ///
  /// In zh, this message translates to:
  /// **'正在加载磁力资源…'**
  String get detailBufferingMagnet;

  /// No description provided for @detailBufferingConnect.
  ///
  /// In zh, this message translates to:
  /// **'正在连接播放资源…'**
  String get detailBufferingConnect;

  /// No description provided for @detailBuffering.
  ///
  /// In zh, this message translates to:
  /// **'正在缓冲…'**
  String get detailBuffering;

  /// No description provided for @detailPlaybackFailed.
  ///
  /// In zh, this message translates to:
  /// **'播放失败'**
  String get detailPlaybackFailed;

  /// No description provided for @detailRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get detailRetry;

  /// No description provided for @detailVolumeTooltip.
  ///
  /// In zh, this message translates to:
  /// **'音量（点击展开）'**
  String get detailVolumeTooltip;

  /// No description provided for @detailMute.
  ///
  /// In zh, this message translates to:
  /// **'静音'**
  String get detailMute;

  /// No description provided for @detailUnmute.
  ///
  /// In zh, this message translates to:
  /// **'取消静音'**
  String get detailUnmute;

  /// No description provided for @detailRouteLabel.
  ///
  /// In zh, this message translates to:
  /// **'线路 {index}'**
  String detailRouteLabel(int index);

  /// No description provided for @detailDlnaSearching.
  ///
  /// In zh, this message translates to:
  /// **'正在搜索局域网设备…'**
  String get detailDlnaSearching;

  /// No description provided for @detailDlnaTitle.
  ///
  /// In zh, this message translates to:
  /// **'DLNA 设备'**
  String get detailDlnaTitle;

  /// No description provided for @detailDlnaEmpty.
  ///
  /// In zh, this message translates to:
  /// **'未发现设备，请确认电视与手机连接同一 Wi‑Fi，并已开启电视上的 DLNA/投屏功能'**
  String get detailDlnaEmpty;

  /// No description provided for @detailDlnaCastOk.
  ///
  /// In zh, this message translates to:
  /// **'已推送播放地址到设备'**
  String get detailDlnaCastOk;

  /// No description provided for @detailDlnaCastOkNamed.
  ///
  /// In zh, this message translates to:
  /// **'已投屏到 {device}'**
  String detailDlnaCastOkNamed(String device);

  /// No description provided for @detailDlnaCastFailed.
  ///
  /// In zh, this message translates to:
  /// **'投屏失败，请换线路或稍后重试'**
  String get detailDlnaCastFailed;

  /// No description provided for @detailDlnaHint.
  ///
  /// In zh, this message translates to:
  /// **'请选择要投屏的电视或盒子。CMS、磁力、离线缓存均会转换为电视可访问的地址。'**
  String get detailDlnaHint;

  /// No description provided for @detailDlnaRefresh.
  ///
  /// In zh, this message translates to:
  /// **'重新搜索'**
  String get detailDlnaRefresh;

  /// No description provided for @detailDlnaNeedPlayback.
  ///
  /// In zh, this message translates to:
  /// **'请先开始播放，再投屏'**
  String get detailDlnaNeedPlayback;

  /// No description provided for @detailDlnaNoLanIp.
  ///
  /// In zh, this message translates to:
  /// **'未获取到局域网 IP，请连接 Wi‑Fi 后重试'**
  String get detailDlnaNoLanIp;

  /// No description provided for @detailDlnaNoActiveStream.
  ///
  /// In zh, this message translates to:
  /// **'磁力流尚未就绪，请稍候再试'**
  String get detailDlnaNoActiveStream;

  /// No description provided for @detailDlnaUnsupportedSource.
  ///
  /// In zh, this message translates to:
  /// **'当前片源暂不支持投屏'**
  String get detailDlnaUnsupportedSource;

  /// No description provided for @detailDlnaLocalServeFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法在局域网分享本地文件'**
  String get detailDlnaLocalServeFailed;

  /// No description provided for @detailDlnaResolveEmpty.
  ///
  /// In zh, this message translates to:
  /// **'无法解析可投屏的播放地址'**
  String get detailDlnaResolveEmpty;

  /// No description provided for @detailDlnaCastingNamed.
  ///
  /// In zh, this message translates to:
  /// **'投屏中 · {device}'**
  String detailDlnaCastingNamed(String device);

  /// No description provided for @detailClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get detailClose;

  /// No description provided for @detailMagnetParsingMeta.
  ///
  /// In zh, this message translates to:
  /// **'正在解析磁力元数据…'**
  String get detailMagnetParsingMeta;

  /// No description provided for @detailMagnetAddFailed.
  ///
  /// In zh, this message translates to:
  /// **'添加磁力链接失败'**
  String get detailMagnetAddFailed;

  /// No description provided for @detailMagnetNoVideoFile.
  ///
  /// In zh, this message translates to:
  /// **'未找到可播放的视频文件'**
  String get detailMagnetNoVideoFile;

  /// No description provided for @detailMagnetBuffering.
  ///
  /// In zh, this message translates to:
  /// **'正在缓冲数据…'**
  String get detailMagnetBuffering;

  /// No description provided for @detailMagnetStreamFailed.
  ///
  /// In zh, this message translates to:
  /// **'启动播放流失败'**
  String get detailMagnetStreamFailed;

  /// No description provided for @detailMagnetConnectingPeers.
  ///
  /// In zh, this message translates to:
  /// **'正在连接节点…'**
  String get detailMagnetConnectingPeers;

  /// No description provided for @detailPlaybackErrorNoUrl.
  ///
  /// In zh, this message translates to:
  /// **'无可播放地址'**
  String get detailPlaybackErrorNoUrl;

  /// No description provided for @detailPlaybackErrorParseFailed.
  ///
  /// In zh, this message translates to:
  /// **'解析失败'**
  String get detailPlaybackErrorParseFailed;

  /// No description provided for @detailPlaybackErrorRouteSwitched.
  ///
  /// In zh, this message translates to:
  /// **'已切换线路'**
  String get detailPlaybackErrorRouteSwitched;

  /// No description provided for @detailPlaybackErrorMultiSourceFailed.
  ///
  /// In zh, this message translates to:
  /// **'多源回退失败'**
  String get detailPlaybackErrorMultiSourceFailed;

  /// No description provided for @detailPlaybackErrorNetwork.
  ///
  /// In zh, this message translates to:
  /// **'网络或播放器错误'**
  String get detailPlaybackErrorNetwork;

  /// No description provided for @detailPlaybackErrorMagnet.
  ///
  /// In zh, this message translates to:
  /// **'磁力播放失败'**
  String get detailPlaybackErrorMagnet;

  /// No description provided for @detailEpisodeLabel.
  ///
  /// In zh, this message translates to:
  /// **'第{index}集'**
  String detailEpisodeLabel(int index);

  /// No description provided for @detailEpisodeGridCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 集'**
  String detailEpisodeGridCount(int count);

  /// No description provided for @detailEpisodeGridPageInfo.
  ///
  /// In zh, this message translates to:
  /// **'第 {current} / {total} 页'**
  String detailEpisodeGridPageInfo(int current, int total);

  /// No description provided for @detailEpisodeGridPrevPage.
  ///
  /// In zh, this message translates to:
  /// **'上一页'**
  String get detailEpisodeGridPrevPage;

  /// No description provided for @detailEpisodeGridNextPage.
  ///
  /// In zh, this message translates to:
  /// **'下一页'**
  String get detailEpisodeGridNextPage;

  /// No description provided for @detailEpisodeGridJumpToEpisode.
  ///
  /// In zh, this message translates to:
  /// **'跳转到集数'**
  String get detailEpisodeGridJumpToEpisode;

  /// No description provided for @detailEpisodeGridJumpTitle.
  ///
  /// In zh, this message translates to:
  /// **'跳转到集数'**
  String get detailEpisodeGridJumpTitle;

  /// No description provided for @detailEpisodeGridJumpHint.
  ///
  /// In zh, this message translates to:
  /// **'输入集数（1–{max}）'**
  String detailEpisodeGridJumpHint(int max);

  /// No description provided for @detailEpisodeGridJumpConfirm.
  ///
  /// In zh, this message translates to:
  /// **'跳转'**
  String get detailEpisodeGridJumpConfirm;

  /// No description provided for @detailCachePanelTitle.
  ///
  /// In zh, this message translates to:
  /// **'离线缓存'**
  String get detailCachePanelTitle;

  /// No description provided for @detailCacheDownloadCurrent.
  ///
  /// In zh, this message translates to:
  /// **'缓存当前集'**
  String get detailCacheDownloadCurrent;

  /// No description provided for @detailCacheSelectEpisodes.
  ///
  /// In zh, this message translates to:
  /// **'选择集数'**
  String get detailCacheSelectEpisodes;

  /// No description provided for @detailCacheSelectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get detailCacheSelectAll;

  /// No description provided for @detailCacheClearSelection.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get detailCacheClearSelection;

  /// No description provided for @detailCacheDownloadSelected.
  ///
  /// In zh, this message translates to:
  /// **'下载所选 ({count})'**
  String detailCacheDownloadSelected(int count);

  /// No description provided for @detailCacheBatchQueued.
  ///
  /// In zh, this message translates to:
  /// **'已加入 {count} 个下载任务'**
  String detailCacheBatchQueued(int count);

  /// No description provided for @detailCacheBatchNone.
  ///
  /// In zh, this message translates to:
  /// **'所选集数均已在队列或已缓存'**
  String get detailCacheBatchNone;

  /// No description provided for @detailCacheEmptyForMovie.
  ///
  /// In zh, this message translates to:
  /// **'本影片暂无缓存任务'**
  String get detailCacheEmptyForMovie;

  /// No description provided for @detailCacheAlreadyCompleted.
  ///
  /// In zh, this message translates to:
  /// **'当前集已缓存完成'**
  String get detailCacheAlreadyCompleted;

  /// No description provided for @detailCacheAlreadyDownloading.
  ///
  /// In zh, this message translates to:
  /// **'当前集已在下载队列中'**
  String get detailCacheAlreadyDownloading;

  /// No description provided for @detailCacheQueued.
  ///
  /// In zh, this message translates to:
  /// **'已加入下载队列'**
  String get detailCacheQueued;

  /// No description provided for @detailCacheDownloadStarted.
  ///
  /// In zh, this message translates to:
  /// **'已开始下载'**
  String get detailCacheDownloadStarted;

  /// No description provided for @detailCacheWebUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'Web 端暂不支持离线缓存'**
  String get detailCacheWebUnsupported;

  /// No description provided for @detailCacheMagnetUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'磁力资源暂不支持离线缓存'**
  String get detailCacheMagnetUnsupported;

  /// No description provided for @detailCacheNoEpisode.
  ///
  /// In zh, this message translates to:
  /// **'无可缓存的播放地址'**
  String get detailCacheNoEpisode;

  /// No description provided for @detailCacheUnsupportedUrl.
  ///
  /// In zh, this message translates to:
  /// **'该地址暂不支持缓存'**
  String get detailCacheUnsupportedUrl;

  /// No description provided for @detailCacheParseFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法解析真实视频地址，暂不能缓存'**
  String get detailCacheParseFailed;

  /// No description provided for @detailCacheDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除缓存'**
  String get detailCacheDeleted;

  /// No description provided for @detailCacheManageAll.
  ///
  /// In zh, this message translates to:
  /// **'全部缓存'**
  String get detailCacheManageAll;

  /// No description provided for @detailCacheStatusWaiting.
  ///
  /// In zh, this message translates to:
  /// **'等待中'**
  String get detailCacheStatusWaiting;

  /// No description provided for @detailCacheStatusDownloading.
  ///
  /// In zh, this message translates to:
  /// **'下载中'**
  String get detailCacheStatusDownloading;

  /// No description provided for @detailCacheStatusPaused.
  ///
  /// In zh, this message translates to:
  /// **'已暂停'**
  String get detailCacheStatusPaused;

  /// No description provided for @detailCacheStatusCompleted.
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get detailCacheStatusCompleted;

  /// No description provided for @detailCacheStatusFailed.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get detailCacheStatusFailed;

  /// No description provided for @detailCachePause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get detailCachePause;

  /// No description provided for @detailCacheResume.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get detailCacheResume;

  /// No description provided for @detailCacheDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get detailCacheDelete;

  /// No description provided for @cacheManagerTitle.
  ///
  /// In zh, this message translates to:
  /// **'缓存管理'**
  String get cacheManagerTitle;

  /// No description provided for @cacheManagerOnlyWifi.
  ///
  /// In zh, this message translates to:
  /// **'仅 WiFi 下载'**
  String get cacheManagerOnlyWifi;

  /// No description provided for @cacheManagerStorageTitle.
  ///
  /// In zh, this message translates to:
  /// **'存储空间'**
  String get cacheManagerStorageTitle;

  /// No description provided for @cacheManagerClearAll.
  ///
  /// In zh, this message translates to:
  /// **'清理全部'**
  String get cacheManagerClearAll;

  /// No description provided for @cacheManagerClearConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'清理缓存'**
  String get cacheManagerClearConfirmTitle;

  /// No description provided for @cacheManagerClearConfirmBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要清理所有缓存吗？'**
  String get cacheManagerClearConfirmBody;

  /// No description provided for @cacheManagerClearDone.
  ///
  /// In zh, this message translates to:
  /// **'缓存已清理'**
  String get cacheManagerClearDone;

  /// No description provided for @cacheManagerUsedLabel.
  ///
  /// In zh, this message translates to:
  /// **'已用: {used} / {max}'**
  String cacheManagerUsedLabel(String used, String max);

  /// No description provided for @cacheManagerCompletedCount.
  ///
  /// In zh, this message translates to:
  /// **'已缓存 {count} 个视频'**
  String cacheManagerCompletedCount(int count);

  /// No description provided for @cacheWebBanner.
  ///
  /// In zh, this message translates to:
  /// **'Web 端不支持视频离线下载；列表为空属正常情况。'**
  String get cacheWebBanner;

  /// No description provided for @cacheFileMissing.
  ///
  /// In zh, this message translates to:
  /// **'缓存文件不存在'**
  String get cacheFileMissing;

  /// No description provided for @cacheWebPlayUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'Web 端请从详情页在线播放'**
  String get cacheWebPlayUnsupported;

  /// No description provided for @cachePlayOffline.
  ///
  /// In zh, this message translates to:
  /// **'离线播放'**
  String get cachePlayOffline;

  /// No description provided for @cacheDownloadSpeed.
  ///
  /// In zh, this message translates to:
  /// **'{speed}/s'**
  String cacheDownloadSpeed(String speed);

  /// No description provided for @followCacheTabEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无缓存'**
  String get followCacheTabEmpty;

  /// No description provided for @settingsOnlyWifiCache.
  ///
  /// In zh, this message translates to:
  /// **'仅 WiFi 下载缓存'**
  String get settingsOnlyWifiCache;

  /// No description provided for @settingsOnlyWifiCacheSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'移动网络下不自动下载，与缓存管理页开关同步'**
  String get settingsOnlyWifiCacheSubtitle;
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
