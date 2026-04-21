// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Movie App';

  @override
  String get appInitLoading => 'Initializing…';

  @override
  String get appInitRetry => 'Retry';

  @override
  String get appInitErrorTitle => 'Startup failed';

  @override
  String get navHome => 'Home';

  @override
  String get toolbarBrandGoHome => 'Back to home';

  @override
  String get navFollow => 'Following';

  @override
  String get navProfile => 'Profile';

  @override
  String get detailIntro => 'Synopsis';

  @override
  String get detailPlayRoutes => 'Play sources';

  @override
  String get detailMagnetSearch => 'Magnet search';

  @override
  String get detailMagnetSearchHint =>
      'Multi-source magnet results: IMDb/title/year match; Chinese title tag on English-named torrents.';

  @override
  String get detailOpenMagnetSearch => 'Open magnet search';

  @override
  String get detailRelated => 'Related';

  @override
  String get detailRelatedHint => 'Related recommendations';

  @override
  String get detailDesktopEpisodes => 'Episodes';

  @override
  String get detailDesktopTabMagnet => 'Magnet';

  @override
  String get detailDesktopTabRecommend => 'Related';

  @override
  String get detailDesktopNoEpisodes => 'No episodes for this source';

  @override
  String get detailMagnetOpenInSearch => 'Search by title';

  @override
  String get detailMagnetRefreshStrict => 'Strict search';

  @override
  String get detailMagnetRefreshLoose => 'Broaden';

  @override
  String get detailMagnetSearching => 'Searching magnets…';

  @override
  String get detailMagnetPlay => 'Play';

  @override
  String get detailMagnetOpenDetail => 'Torrent detail';

  @override
  String get detailMagnetZhLabelHint => 'This title';

  @override
  String get designV3MovieTitle => 'Interstellar';

  @override
  String get designV3DoubanLabel => 'Douban';

  @override
  String get designV3MetaLine => '2014 · Sci‑Fi Adventure · 169 min';

  @override
  String get designV3SynopsisCollapsed =>
      'Explorers use a newly discovered wormhole…';

  @override
  String get designV3SynopsisFull =>
      'Explorers use a newly discovered wormhole to push beyond the limits of human space travel and journey across the galaxy.';

  @override
  String get designV3ExpandIntro => 'Expand synopsis';

  @override
  String get designV3CollapseIntro => 'Collapse synopsis';

  @override
  String get designV3BufferDemo => 'Buffer 1.8 MB/s';

  @override
  String get designV3TimeDemo => '34:12 / 2:49:05';

  @override
  String get designV3EpisodeChip1 => 'Interstellar · Part 1';

  @override
  String get designV3EpisodeChip2 => 'Interstellar · Part 2';

  @override
  String get designV3RouteLine1 => 'Source 1 (primary)';

  @override
  String get designV3RouteLine2 => 'Source 2 (backup)';

  @override
  String get designV3RelatedMartian => 'The Martian';

  @override
  String get designV3RelatedArrival => 'Arrival';

  @override
  String get designV3RelatedInception => 'Inception';

  @override
  String get designV3RelatedGravity => 'Gravity';

  @override
  String get designV3MagnetRowTitle => 'Interstellar.2160p.4K.HDR…';

  @override
  String get designV3MagnetRowMeta => '22.5 GB · magnet';

  @override
  String get designV3TooltipPlayPause => 'Play or pause';

  @override
  String get designV3TooltipSpeed => 'Playback speed';

  @override
  String get designV3TooltipVolume => 'Volume';

  @override
  String get designV3TooltipCast => 'Cast';

  @override
  String get designV3TooltipFullscreen => 'Fullscreen';

  @override
  String get designV3TooltipDownload => 'Download';

  @override
  String get designV3TooltipFavorite => 'Favorite';

  @override
  String get designV3TooltipShare => 'Share';

  @override
  String get detailPlayerPrevEpisode => 'Previous episode';

  @override
  String get detailPlayerNextEpisode => 'Next episode';

  @override
  String get detailPlayerTooltipCache => 'Cache / downloads';

  @override
  String get detailPlayerFullscreenEnter => 'Full screen';

  @override
  String get detailPlayerFullscreenExit => 'Exit full screen';

  @override
  String get detailPlayerSubtitleMenu => 'Subtitles (auto-match / pick)';

  @override
  String get detailPlayerSubtitleSheetTitle => 'Subtitles';

  @override
  String get detailPlayerSubtitleAutoMatch => 'Match online';

  @override
  String get detailPlayerSubtitleAutoMatchSubtitle =>
      'When magnets have no embedded subs, try by title (needs OpenSubtitles API key)';

  @override
  String get detailPlayerSubtitlePickFile => 'Choose local subtitle file…';

  @override
  String get detailPlayerSubtitleOff => 'Use embedded / turn off external';

  @override
  String get detailPlayerSubtitleBrowseOnline => 'Browse online subtitles…';

  @override
  String get detailPlayerSubtitleLoading => 'Searching subtitles…';

  @override
  String get detailPlayerSubtitleNone => 'No subtitles found';

  @override
  String get detailPlayerSubtitleNoApiKey =>
      'Add an OpenSubtitles API key in Settings first';

  @override
  String get detailPlayerSubtitleApplyFailed => 'Could not load subtitles';

  @override
  String get detailPlayerSubtitleApplied => 'Subtitles loaded';

  @override
  String get homeTitleRecommend => 'Recommendations';

  @override
  String get homeEndOfListHint => 'No more';

  @override
  String get toolbarSearch => 'Search';

  @override
  String get toolbarFollow => 'Following';

  @override
  String get toolbarProfile => 'Profile';

  @override
  String get toolbarSettings => 'Settings';

  @override
  String get toolbarViewComfort => 'Comfortable grid';

  @override
  String get toolbarViewCompact => 'Compact grid';

  @override
  String get toolbarTheme => 'Theme';

  @override
  String toolbarThemeSwitched(String name) {
    return 'Switched to: $name';
  }

  @override
  String get toolbarSearchPlaceholderHome => 'Search movies and shows…';

  @override
  String toolbarSearchPlaceholderInChannel(String channelLabel) {
    return 'Search $channelLabel…';
  }

  @override
  String get filterLabelGenre => 'Genre';

  @override
  String get filterLabelRegion => 'Region';

  @override
  String get navChannelMovies => 'Movies';

  @override
  String get navChannelTv => 'TV Series';

  @override
  String get navChannelVariety => 'Variety';

  @override
  String get navChannelAnime => 'Anime';

  @override
  String get navChannelShort => 'Short drama';

  @override
  String get homePortalChipLatest => 'Latest';

  @override
  String homePortalRankSectionTitle(String label) {
    return '$label trending';
  }

  @override
  String get searchWideAggregateHint =>
      'Results combine enabled CMS sources, magnets, and history—same role as the static demo note.';

  @override
  String get categoryPortalHotRankTitle => 'Trending';

  @override
  String get categoryPortalModuleHighlights => 'Featured';

  @override
  String get categoryPortalModuleMorePicks => 'More picks';

  @override
  String get categoryPortalModuleKeepGoing => 'Keep exploring';

  @override
  String get categoryPortalModuleMore => 'More';

  @override
  String get categoryPortalModuleMoreTooltip =>
      'Browse this category on the home screen';

  @override
  String categoryPortalModuleTagged(String genre) {
    return '$genre · Picks';
  }

  @override
  String get categoryPortalModuleEmpty => 'Nothing in this row yet';

  @override
  String get categoryPortalScrollForMore => 'Scroll down to load more';

  @override
  String get categoryPortalRankEmpty => 'No ranking data yet';

  @override
  String categoryPortalRankScore(String score) {
    return '$score pts';
  }

  @override
  String get categoryPortalEmptyHint =>
      'No titles in this channel. Check your network or sources.';

  @override
  String get homeOpenDedicatedChannel => 'Channel layout';

  @override
  String get homeOpenDedicatedChannelTooltip =>
      'Open the wide-screen channel layout (hi-fi spec)';

  @override
  String get homeTabRecommend => 'For you';

  @override
  String get homeScrollToTopTooltip => 'Back to top';

  @override
  String get homeSnackbarRetry => 'Retry';

  @override
  String get homeLoadFailedTapRetry => 'Load failed, tap to retry';

  @override
  String get homeSectionSeeMore => 'Show more';

  @override
  String get homeSectionCollapse => 'Show less';
}
