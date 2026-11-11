// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Videocask';

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
  String get detailMagnetPlayingBadge => 'Magnet playback';

  @override
  String get detailMagnetMetaDirector => 'Director';

  @override
  String get detailMagnetMetaActors => 'Cast';

  @override
  String get detailMagnetMetaRegion => 'Region';

  @override
  String get detailMagnetMetaGenre => 'Genre';

  @override
  String get detailMagnetDownload => 'Download';

  @override
  String get detailMagnetCopiedToast => 'Magnet link copied to clipboard';

  @override
  String get detailMagnetResourceSection => 'Torrent info';

  @override
  String get detailMagnetMetaResourceTitle => 'Resource title';

  @override
  String detailMagnetMetaSource(String source) {
    return 'Source: $source';
  }

  @override
  String detailMagnetMetaSize(String size) {
    return 'Size $size';
  }

  @override
  String detailMagnetMetaSeeders(String count) {
    return 'Seeders $count';
  }

  @override
  String detailMagnetMetaLeechers(String count) {
    return 'Leechers $count';
  }

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
  String get speedSelectorNormal => 'Normal';

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
  String get detailPlayerTooltipBack => 'Back';

  @override
  String get detailPlayerTooltipRouteQuality => 'Source / quality';

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
      'Auto-match Simplified Chinese subtitles for magnets, free and no setup';

  @override
  String get detailPlayerSubtitlePickFile => 'Choose local subtitle file…';

  @override
  String get detailPlayerSubtitleOff => 'Use embedded / turn off external';

  @override
  String get detailPlayerSubtitleBrowseOnline => 'Browse online subtitles…';

  @override
  String get detailPlayerSubtitleNone => 'No subtitles found';

  @override
  String get detailPlayerSubtitleApplyFailed => 'Could not load subtitles';

  @override
  String get detailPlayerSubtitleApplied => 'Subtitles loaded';

  @override
  String get detailPlayerSubtitleDelay => 'Subtitle timing';

  @override
  String get detailPlayerSubtitleDelayReset => 'Reset offset';

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
  String get filterLabelSubClass => 'Category';

  @override
  String get filterLabelRegion => 'Region';

  @override
  String get magnetSearchEmptyHint =>
      'No magnet source returned results. The network may be unreachable or this title may not be indexed. Probe each source in Settings > Magnet search sources.';

  @override
  String get magnetSearchTimeoutHint =>
      'Magnet search timed out. Check your network and try again.';

  @override
  String get magnetSearchFailedHint =>
      'Magnet search failed. Check your network or magnet source settings.';

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

  @override
  String get settingsAutoPlayOnDetailEnter => 'Auto-play on detail';

  @override
  String get settingsAutoPlayOnDetailEnterSubtitle =>
      'Start playback when opening a title or magnet detail';

  @override
  String get settingsPreloadNextEpisode => 'Preload next episode';

  @override
  String get settingsPreloadNextEpisodeSubtitle =>
      'Resolve the next episode URL when playback reaches 80%';

  @override
  String get settingsPlaybackPrefetch => 'Playback prefetch';

  @override
  String get settingsPlaybackPrefetchSubtitle =>
      'Prefetch the first few MB of the next episode on any network';

  @override
  String get settingsTmdbApiKey => 'TMDB API Key';

  @override
  String get settingsTmdbApiKeyConfigured => 'Configured';

  @override
  String get settingsTmdbApiKeyNotConfigured =>
      'Not set (Douban lookup still works)';

  @override
  String get settingsTmdbApiKeyDialogBody =>
      'Register at themoviedb.org and create an API key to map Chinese titles to IMDb IDs and English names for better magnet results. Without a key, Douban suggest + IMDb lookup are still used.';

  @override
  String get settingsTmdbApiKeySaved => 'TMDB API settings saved';

  @override
  String get detailRouteFallbackSnack =>
      'Buffering is slow; trying another source';

  @override
  String get detailPlayerLockControls => 'Lock player controls';

  @override
  String get detailPlayerUnlockControls => 'Unlock player controls';

  @override
  String get homeContinueWatching => 'Continue watching';

  @override
  String get homeContinueWatchingSeeAll => 'See all';

  @override
  String get searchActionSearch => 'Search';

  @override
  String get searchClearFilters => 'Clear filters';

  @override
  String get searchPlay => 'Play';

  @override
  String get searchOpenDetail => 'Open detail';

  @override
  String get searchMagnetChineseName => 'Chinese title';

  @override
  String detailHistoryOverlay(int episode, String percent) {
    return 'Last watched ep. $episode at $percent%';
  }

  @override
  String get detailLoadError =>
      'Could not load title info. Check your network or switch source in Source Manager.';

  @override
  String get detailBufferingConnect => 'Connecting to stream…';

  @override
  String get detailBuffering => 'Buffering…';

  @override
  String get detailPlaybackFailed => 'Playback failed';

  @override
  String get detailRetry => 'Retry';

  @override
  String get detailVolumeTooltip => 'Volume (tap to expand)';

  @override
  String get detailMute => 'Mute';

  @override
  String get detailUnmute => 'Unmute';

  @override
  String detailRouteLabel(int index) {
    return 'Source $index';
  }

  @override
  String get detailDlnaSearching => 'Searching for devices on LAN…';

  @override
  String get detailDlnaTitle => 'DLNA devices';

  @override
  String get detailDlnaEmpty =>
      'No devices found. Make sure your TV and phone are on the same Wi‑Fi and DLNA/cast is enabled on the TV.';

  @override
  String get detailDlnaCastOk => 'Stream URL sent to device';

  @override
  String detailDlnaCastOkNamed(String device) {
    return 'Casting to $device';
  }

  @override
  String get detailDlnaCastFailed =>
      'Cast failed. Try another route or try again later.';

  @override
  String get detailDlnaHint =>
      'Pick a TV or box on your network. CMS, magnet, and offline cache URLs are converted for the TV.';

  @override
  String get detailDlnaRefresh => 'Search again';

  @override
  String get detailDlnaNeedPlayback => 'Start playback before casting';

  @override
  String get detailDlnaNoLanIp =>
      'No LAN IP found. Connect to Wi‑Fi and try again.';

  @override
  String get detailDlnaNoActiveStream =>
      'Magnet stream not ready yet. Try again shortly.';

  @override
  String get detailDlnaUnsupportedSource => 'This source cannot be cast yet';

  @override
  String get detailDlnaLocalServeFailed =>
      'Could not share the local file on LAN';

  @override
  String get detailDlnaResolveEmpty => 'Could not resolve a castable URL';

  @override
  String detailDlnaCastingNamed(String device) {
    return 'Casting · $device';
  }

  @override
  String get detailClose => 'Close';

  @override
  String get detailMagnetParsingMeta => 'Parsing magnet metadata…';

  @override
  String get detailMagnetAddFailed => 'Failed to add magnet link';

  @override
  String get detailMagnetNoVideoFile => 'No playable video file found';

  @override
  String get detailMagnetBuffering => 'Buffering data…';

  @override
  String get detailMagnetStreamFailed => 'Failed to start playback stream';

  @override
  String get detailMagnetConnectingPeers => 'Connecting to peers…';

  @override
  String get detailPlaybackErrorNoUrl => 'No playable URL';

  @override
  String get detailPlaybackErrorParseFailed => 'Parse failed';

  @override
  String get detailPlaybackErrorRouteSwitched => 'Switched source';

  @override
  String get detailPlaybackErrorMultiSourceFailed =>
      'Multi-source fallback failed';

  @override
  String get detailPlaybackErrorNetwork => 'Network or player error';

  @override
  String get detailPlaybackErrorMagnet => 'Magnet playback failed';

  @override
  String detailEpisodeLabel(int index) {
    return 'Episode $index';
  }

  @override
  String detailEpisodeGridCount(int count) {
    return '$count episodes';
  }

  @override
  String detailEpisodeGridPageInfo(int current, int total) {
    return 'Page $current / $total';
  }

  @override
  String get detailEpisodeGridPrevPage => 'Previous page';

  @override
  String get detailEpisodeGridNextPage => 'Next page';

  @override
  String get detailEpisodeGridJumpToEpisode => 'Jump to episode';

  @override
  String get detailEpisodeGridJumpTitle => 'Jump to episode';

  @override
  String detailEpisodeGridJumpHint(int max) {
    return 'Episode number (1–$max)';
  }

  @override
  String get detailEpisodeGridJumpConfirm => 'Go';

  @override
  String get detailCachePanelTitle => 'Offline cache';

  @override
  String get detailCacheDownloadCurrent => 'Cache current episode';

  @override
  String get detailCacheSelectEpisodes => 'Select episodes';

  @override
  String get detailCacheSelectAll => 'Select all';

  @override
  String get detailCacheClearSelection => 'Clear';

  @override
  String detailCacheDownloadSelected(int count) {
    return 'Download selected ($count)';
  }

  @override
  String detailCacheBatchQueued(int count) {
    return 'Added $count download tasks';
  }

  @override
  String get detailCacheBatchNone =>
      'Selected episodes are already queued or cached';

  @override
  String get detailCacheEmptyForMovie => 'No cache tasks for this title';

  @override
  String get detailCacheAlreadyCompleted => 'Current episode is already cached';

  @override
  String get detailCacheAlreadyDownloading =>
      'Current episode is already downloading';

  @override
  String get detailCacheQueued => 'Added to download queue';

  @override
  String get detailCacheDownloadStarted => 'Download started';

  @override
  String get detailCacheWebUnsupported =>
      'Offline cache is not supported on web';

  @override
  String get detailCacheMagnetUnsupported =>
      'Magnet sources cannot be cached offline';

  @override
  String get detailCacheNoEpisode => 'No playable URL to cache';

  @override
  String get detailCacheUnsupportedUrl => 'This URL cannot be cached';

  @override
  String get detailCacheParseFailed =>
      'Could not resolve a direct video URL for caching';

  @override
  String get detailCacheDeleted => 'Cache deleted';

  @override
  String get detailCacheManageAll => 'All downloads';

  @override
  String get detailCacheStatusWaiting => 'Waiting';

  @override
  String get detailCacheStatusDownloading => 'Downloading';

  @override
  String get detailCacheStatusPaused => 'Paused';

  @override
  String get detailCacheStatusCompleted => 'Completed';

  @override
  String get detailCacheStatusFailed => 'Failed';

  @override
  String get detailCachePause => 'Pause';

  @override
  String get detailCacheResume => 'Resume';

  @override
  String get detailCacheDelete => 'Delete';

  @override
  String get cacheManagerTitle => 'Downloads';

  @override
  String get cacheManagerOnlyWifi => 'Wi‑Fi only';

  @override
  String get cacheManagerStorageTitle => 'Storage';

  @override
  String get cacheManagerClearAll => 'Clear all';

  @override
  String get cacheManagerClearConfirmTitle => 'Clear cache';

  @override
  String get cacheManagerClearConfirmBody => 'Delete all cached videos?';

  @override
  String get cacheManagerClearDone => 'Cache cleared';

  @override
  String cacheManagerUsedLabel(String used, String max) {
    return 'Used: $used / $max';
  }

  @override
  String cacheManagerCompletedCount(int count) {
    return '$count videos cached';
  }

  @override
  String get cacheWebBanner =>
      'Web does not support offline video downloads; an empty list is expected.';

  @override
  String get cacheFileMissing => 'Cached file not found';

  @override
  String get cacheWebPlayUnsupported =>
      'On web, play online from the detail page';

  @override
  String get cachePlayOffline => 'Play offline';

  @override
  String cacheDownloadSpeed(String speed) {
    return '$speed/s';
  }

  @override
  String get followCacheTabEmpty => 'No downloads yet';

  @override
  String get settingsOnlyWifiCache => 'Download cache on Wi‑Fi only';

  @override
  String get settingsOnlyWifiCacheSubtitle =>
      'Pauses downloads on cellular; synced with cache manager';

  @override
  String get settingsHwDecodeMode => 'Hardware decode mode';

  @override
  String get settingsHwDecodeModeDesc =>
      'Performance = zero-copy, most power-efficient but freezes/crashes on a few devices; Compatible = copy mode, most stable; Off = pure software fallback. Switch manually if incompatible; the app never auto-adjusts';

  @override
  String get settingsHwDecodeModeAuto => 'Auto (recommended)';

  @override
  String get settingsHwDecodeModeCopy => 'Compatible (hardware decode, copy)';

  @override
  String get settingsHwDecodeModeZeroCopy =>
      'Performance (hardware decode, zero-copy)';

  @override
  String get settingsHwDecodeModeOff => 'Off (software decode)';

  @override
  String get settingsVideoOutputMode => 'Video output backend';

  @override
  String get settingsVideoOutputModeDesc =>
      'The descriptor leak is fixed at the engine level; all three backends are leak-free. Switching mainly affects picture compatibility and features (subtitles/filters/screenshots). Only switch if rendering fails';

  @override
  String get settingsVoGpuNext => 'New renderer (recommended)';

  @override
  String get settingsVoGpuNextDesc =>
      'Recommended default. GPU rendering (libplacebo), full features (subtitles/filters/screenshots work). A few GPUs may briefly black-screen on first launch; reopen once to recover. If it keeps black-screening, switch to \"Legacy renderer\"';

  @override
  String get settingsVoGpu => 'Legacy renderer (compatibility fallback)';

  @override
  String get settingsVoGpuDesc =>
      'Traditional GPU rendering (mpv legacy GL path). Same leak-free bridge; use it as a fallback when \"New renderer\" black-screens on your device. Color/tone-mapping is less precise than the new one';

  @override
  String get settingsVoEmbed => 'Hardware passthrough (bypasses renderer)';

  @override
  String get settingsVoEmbedDesc =>
      'Bypasses mpv renderer; system composites directly. Leak-free; cost: HW decode only (zero-copy), embedded subtitles/OSD/screenshots/filters all disabled, rotation/fullscreen may flicker, poor HDR/10bit support. Use only when the other two cannot show a picture';

  @override
  String get homeCategoryFilterUnavailable =>
      'This source provides no genre/region data, so this filter has no effect';

  @override
  String get detailSwitchSource => 'Switch source';

  @override
  String get detailSwitchSourceSubtitle =>
      'IDs differ across sites, so switching searches other sites by title';

  @override
  String get detailSwitchSourceSearching =>
      'Searching other sources for this title…';

  @override
  String get detailSwitchSourceEmpty => 'No other source has this title';

  @override
  String get detailSwitchSourceExact => 'Same title & year';

  @override
  String get detailSwitchSourceFuzzy => 'Same title';

  @override
  String detailSwitchSourceEpisodes(int count) {
    return '$count episodes';
  }

  @override
  String detailSwitchSourceProgress(int done, int total) {
    return 'Got results from $done/$total sources (still loading)';
  }

  @override
  String detailRouteSheetCount(int count) {
    return '$count routes';
  }

  @override
  String get detailRouteSheetHint =>
      'Pick the route to play; some sites offer several for one title';

  @override
  String get detailRouteSheetOnlyOne => 'This title has only 1 route here';

  @override
  String get detailRouteSheetOnlyOneHint =>
      'This site offers just one route for this title.\nUse \"Switch source\" to look up the same title on other sites.';

  @override
  String get detailMagnetNoPeers => 'No reachable peers for this torrent';

  @override
  String get detailMagnetNoPeersHint =>
      'The seeders may all be offline. Pick another torrent, or use the online route above.';

  @override
  String detailMagnetPaginationCount(String count) {
    return '$count results';
  }

  @override
  String detailMagnetPageSizeLabel(String size) {
    return '$size per page';
  }

  @override
  String get detailMagnetPrevPage => 'Previous page';

  @override
  String get detailMagnetNextPage => 'Next page';

  @override
  String get detailMagnetStageTitle => 'Magnet loading steps';

  @override
  String get detailMagnetStageInit => 'Starting P2P engine';

  @override
  String get detailMagnetStageMeta => 'Parsing torrent metadata';

  @override
  String get detailMagnetStagePeers => 'Connecting to peers';

  @override
  String get detailMagnetStagePickFile => 'Selecting video file';

  @override
  String get detailMagnetStageBuffer => 'Buffering first chunk';

  @override
  String get detailMagnetStageHandoff => 'Handing off to player';

  @override
  String get detailMagnetStageFailed => 'Connection failed';

  @override
  String detailMagnetAttemptLabel(String attempt) {
    return 'Attempt $attempt';
  }

  @override
  String detailMagnetStageProgress(String step, String total, String label) {
    return 'Step $step/$total · $label';
  }

  @override
  String detailMagnetAutoRetry(String attempt) {
    return 'Can\'t connect — retrying automatically (attempt $attempt)…';
  }

  @override
  String detailMagnetAutoRetryStage(String attempt, String stage) {
    return 'Auto-retry #$attempt · $stage';
  }

  @override
  String get detailMagnetEngineInitFailed => 'Failed to start the P2P engine';

  @override
  String get detailMagnetMetaTimeout =>
      'Timed out: no peer returned the torrent metadata';

  @override
  String get detailMagnetNoData =>
      'Timed out: no data downloaded within 45 seconds';

  @override
  String detailMagnetWeakSwarm(String count) {
    return 'This torrent only has $count connected peer(s) — not enough to stream';
  }

  @override
  String get detailMagnetWaitingFrame =>
      'Connected — waiting for the first frame…';

  @override
  String get detailMagnetNoFrame =>
      'Data is coming in, but the player can\'t decode any video (duration 0:00)';

  @override
  String get detailMagnetNoFrameNoData =>
      'Peers connected, but no data is being sent (buffer stalled)';

  @override
  String get detailMagnetNoFrameHint =>
      'This torrent connects but never produces a picture — pick another magnet, or use an online route.';

  @override
  String get detailMagnetExhaustedHint =>
      'This torrent is unusable — pick another magnet, or use an online route.';

  @override
  String get detailMagnetStreamLostHint =>
      'Playback stopped: the peers for this torrent may all be gone. Pick another magnet, or use an online route.';

  @override
  String get detailMagnetSwitchResource => 'Pick another';

  @override
  String get detailPlayerFitContain => 'Fit';

  @override
  String get detailPlayerFitCover => 'Fill';

  @override
  String get detailPlayerFitToCoverHint => 'Switch to fill (crop edges)';

  @override
  String get detailPlayerFitToContainHint =>
      'Switch to original ratio (keep bars)';
}
