// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '高清影视';

  @override
  String get appInitLoading => '正在初始化…';

  @override
  String get appInitRetry => '重试';

  @override
  String get appInitErrorTitle => '启动失败';

  @override
  String get navHome => '首页';

  @override
  String get toolbarBrandGoHome => '回到首页';

  @override
  String get navFollow => '追剧';

  @override
  String get navProfile => '我的';

  @override
  String get detailIntro => '简介';

  @override
  String get detailPlayRoutes => '播放线路';

  @override
  String get detailMagnetSearch => '磁力搜索';

  @override
  String get detailMagnetSearchHint =>
      '以下为多源聚合结果：优先按 IMDb/片名/年份匹配；英文资源旁显示本片中文名标签。';

  @override
  String get detailOpenMagnetSearch => '打开磁力搜索';

  @override
  String get detailRelated => '相关推荐';

  @override
  String get detailRelatedHint => '相关推荐功能';

  @override
  String get detailDesktopEpisodes => '选集';

  @override
  String get detailDesktopTabMagnet => '磁力';

  @override
  String get detailDesktopTabRecommend => '推荐';

  @override
  String get detailDesktopNoEpisodes => '该线路暂无分集';

  @override
  String get detailMagnetOpenInSearch => '用片名打开搜索';

  @override
  String get detailMagnetRefreshStrict => '精准搜索';

  @override
  String get detailMagnetRefreshLoose => '扩大范围';

  @override
  String get detailMagnetSearching => '正在检索磁力…';

  @override
  String get detailMagnetPlay => '播放';

  @override
  String get detailMagnetOpenDetail => '磁力详情';

  @override
  String get detailMagnetZhLabelHint => '对应本片';

  @override
  String get detailMagnetPlayingBadge => '磁力播放';

  @override
  String get detailMagnetMetaDirector => '导演';

  @override
  String get detailMagnetMetaActors => '主演';

  @override
  String get detailMagnetMetaRegion => '地区';

  @override
  String get detailMagnetResourceSection => '资源信息';

  @override
  String get detailMagnetMetaResourceTitle => '资源标题';

  @override
  String detailMagnetMetaSource(String source) {
    return '来源 $source';
  }

  @override
  String detailMagnetMetaSize(String size) {
    return '大小 $size';
  }

  @override
  String detailMagnetMetaSeeders(String count) {
    return '做种 $count';
  }

  @override
  String detailMagnetMetaLeechers(String count) {
    return '下载 $count';
  }

  @override
  String get designV3MovieTitle => '星际穿越';

  @override
  String get designV3DoubanLabel => '豆瓣';

  @override
  String get designV3MetaLine => '2014 | 科幻 冒险 | 169分钟';

  @override
  String get designV3SynopsisCollapsed => '影片讲述了一队探险家利用对虫洞的新发现…';

  @override
  String get designV3SynopsisFull =>
      '影片讲述了一队探险家利用对虫洞的新发现，超越人类对太空旅行的极限，在广袤的宇宙中进行星际航行。';

  @override
  String get designV3ExpandIntro => '展开简介';

  @override
  String get designV3CollapseIntro => '收起简介';

  @override
  String get designV3BufferDemo => '缓冲 1.8 MB/s';

  @override
  String get designV3TimeDemo => '34:12 / 2:49:05';

  @override
  String get designV3EpisodeChip1 => '星际穿越 主集 1';

  @override
  String get designV3EpisodeChip2 => '星际穿越 2';

  @override
  String get designV3RouteLine1 => '线路 1（主线路）';

  @override
  String get designV3RouteLine2 => '线路 2（备用）';

  @override
  String get designV3RelatedMartian => '火星救援';

  @override
  String get designV3RelatedArrival => '降临';

  @override
  String get designV3RelatedInception => '盗梦空间';

  @override
  String get designV3RelatedGravity => '地心引力';

  @override
  String get designV3MagnetRowTitle => '星际穿越.2160p.4K.HDR…';

  @override
  String get designV3MagnetRowMeta => '22.5 GB · 磁力';

  @override
  String get designV3TooltipPlayPause => '播放或暂停';

  @override
  String get designV3TooltipSpeed => '播放速度';

  @override
  String get speedSelectorNormal => '正常';

  @override
  String get designV3TooltipVolume => '音量';

  @override
  String get designV3TooltipCast => '投屏';

  @override
  String get designV3TooltipFullscreen => '全屏';

  @override
  String get designV3TooltipDownload => '下载';

  @override
  String get designV3TooltipFavorite => '收藏';

  @override
  String get designV3TooltipShare => '分享';

  @override
  String get detailPlayerPrevEpisode => '上一集';

  @override
  String get detailPlayerNextEpisode => '下一集';

  @override
  String get detailPlayerTooltipCache => '缓存';

  @override
  String get detailPlayerTooltipRouteQuality => '线路 / 清晰度';

  @override
  String get detailPlayerFullscreenEnter => '全屏';

  @override
  String get detailPlayerFullscreenExit => '退出全屏';

  @override
  String get detailPlayerSubtitleMenu => '字幕（自动匹配 / 选择）';

  @override
  String get detailPlayerSubtitleSheetTitle => '字幕';

  @override
  String get detailPlayerSubtitleAutoMatch => '在线自动匹配';

  @override
  String get detailPlayerSubtitleAutoMatchSubtitle =>
      '磁力等无内嵌字幕时，按片名尝试匹配（需 OpenSubtitles API Key）';

  @override
  String get detailPlayerSubtitlePickFile => '选择本地字幕文件…';

  @override
  String get detailPlayerSubtitleOff => '恢复内嵌轨 / 关闭外挂';

  @override
  String get detailPlayerSubtitleBrowseOnline => '浏览在线字幕…';

  @override
  String get detailPlayerSubtitleLoading => '正在搜索字幕…';

  @override
  String get detailPlayerSubtitleNone => '未找到字幕';

  @override
  String get detailPlayerSubtitleNoApiKey => '请先在设置中填写 OpenSubtitles API Key';

  @override
  String get detailPlayerSubtitleApplyFailed => '加载字幕失败';

  @override
  String get detailPlayerSubtitleApplied => '已加载字幕';

  @override
  String get detailPlayerSubtitleNoApiKeyHint =>
      '磁力资源可自动匹配字幕，需先在「设置 → OpenSubtitles API Key」填写 Key';

  @override
  String get detailPlayerSubtitleDelay => '字幕时间轴';

  @override
  String get detailPlayerSubtitleDelayReset => '重置偏移';

  @override
  String get homeTitleRecommend => '推荐';

  @override
  String get homeEndOfListHint => '没有更多了';

  @override
  String get toolbarSearch => '搜索';

  @override
  String get toolbarFollow => '追剧';

  @override
  String get toolbarProfile => '我的';

  @override
  String get toolbarSettings => '设置';

  @override
  String get toolbarViewComfort => '切换为舒适视图';

  @override
  String get toolbarViewCompact => '切换为紧凑视图';

  @override
  String get toolbarTheme => '切换主题';

  @override
  String toolbarThemeSwitched(String name) {
    return '已切换为：$name';
  }

  @override
  String get toolbarSearchPlaceholderHome => '搜索影片、剧集…';

  @override
  String toolbarSearchPlaceholderInChannel(String channelLabel) {
    return '搜索$channelLabel…';
  }

  @override
  String get filterLabelGenre => '类型';

  @override
  String get filterLabelRegion => '地区';

  @override
  String get navChannelMovies => '电影';

  @override
  String get navChannelTv => '连续剧';

  @override
  String get navChannelVariety => '综艺';

  @override
  String get navChannelAnime => '动漫';

  @override
  String get navChannelShort => '短剧';

  @override
  String get homePortalChipLatest => '最新';

  @override
  String homePortalRankSectionTitle(String label) {
    return '$label热播榜';
  }

  @override
  String get searchWideAggregateHint => '以下为多源聚合结果与搜索历史；与静态演示稿一致为功能说明。';

  @override
  String get categoryPortalHotRankTitle => '热播榜';

  @override
  String get categoryPortalModuleHighlights => '精选';

  @override
  String get categoryPortalModuleMorePicks => '更多推荐';

  @override
  String get categoryPortalModuleKeepGoing => '继续浏览';

  @override
  String get categoryPortalModuleMore => '更多';

  @override
  String get categoryPortalModuleMoreTooltip => '在首页浏览该分类';

  @override
  String categoryPortalModuleTagged(String genre) {
    return '$genre · 精选';
  }

  @override
  String get categoryPortalModuleEmpty => '暂无该片单';

  @override
  String get categoryPortalScrollForMore => '继续滑动可加载更多';

  @override
  String get categoryPortalRankEmpty => '暂无榜单数据';

  @override
  String categoryPortalRankScore(String score) {
    return '$score 分';
  }

  @override
  String get categoryPortalEmptyHint => '暂无本频道数据，请检查网络或播放源。';

  @override
  String get homeOpenDedicatedChannel => '宽屏频道页';

  @override
  String get homeOpenDedicatedChannelTooltip => '打开与静态稿一致的宽屏频道布局';

  @override
  String get homeTabRecommend => '推荐';

  @override
  String get homeScrollToTopTooltip => '回到顶部';

  @override
  String get homeSnackbarRetry => '重试';

  @override
  String get homeLoadFailedTapRetry => '加载失败，点击重试';

  @override
  String get homeSectionSeeMore => '查看更多';

  @override
  String get homeSectionCollapse => '收起';

  @override
  String get settingsAutoPlayOnDetailEnter => '进入详情自动播放';

  @override
  String get settingsAutoPlayOnDetailEnterSubtitle => '打开影片或磁力详情时自动开始播放';

  @override
  String get settingsPreloadNextEpisode => '预加载下一集';

  @override
  String get settingsPreloadNextEpisodeSubtitle => '当前集播放到 80% 时后台解析下一集地址';

  @override
  String get settingsPlaybackPrefetch => '播放预缓冲';

  @override
  String get settingsPlaybackPrefetchSubtitle => '任意网络下预拉下一集前几 MB，加快切集';

  @override
  String get settingsTmdbApiKey => 'TMDB API Key';

  @override
  String get settingsTmdbApiKeyConfigured => '已配置';

  @override
  String get settingsTmdbApiKeyNotConfigured => '未配置（仍可用豆瓣解析）';

  @override
  String get settingsTmdbApiKeyDialogBody =>
      '在 themoviedb.org 注册并申请 API Key，用于中文片名解析为 IMDb 编号与英文片名，提升磁力搜索命中率。留空时仍会通过豆瓣联想 + IMDb 解析。';

  @override
  String get settingsTmdbApiKeySaved => '已保存 TMDB API 配置';

  @override
  String get detailRouteFallbackSnack => '缓冲较慢，已尝试切换线路';

  @override
  String get detailPlayerLockControls => '锁定播放控件';

  @override
  String get detailPlayerUnlockControls => '解锁播放控件';

  @override
  String get homeContinueWatching => '继续观看';

  @override
  String get homeContinueWatchingSeeAll => '查看全部';

  @override
  String get searchActionSearch => '搜索';

  @override
  String get searchClearFilters => '清除筛选';

  @override
  String get searchPlay => '播放';

  @override
  String get searchOpenDetail => '进入详情';

  @override
  String get detailReplay => '重播';

  @override
  String get detailEpisodeFinished => '本集已播放完毕';

  @override
  String detailHistoryOverlay(int episode, String percent) {
    return '上次看到 第$episode集 $percent%';
  }

  @override
  String get detailLoadError => '无法加载影片信息，请检查网络或在「源管理」中切换采集源后重试。';

  @override
  String get detailBufferingMagnet => '正在加载磁力资源…';

  @override
  String get detailBufferingConnect => '正在连接播放资源…';

  @override
  String get detailBuffering => '正在缓冲…';

  @override
  String get detailPlaybackFailed => '播放失败';

  @override
  String get detailRetry => '重试';

  @override
  String get detailVolumeTooltip => '音量（点击展开）';

  @override
  String get detailMute => '静音';

  @override
  String get detailUnmute => '取消静音';

  @override
  String detailRouteLabel(int index) {
    return '线路 $index';
  }

  @override
  String get detailDlnaSearching => '正在搜索局域网设备…';

  @override
  String get detailDlnaTitle => 'DLNA 设备';

  @override
  String get detailDlnaEmpty => '未发现设备，请确认电视与手机连接同一 Wi‑Fi，并已开启电视上的 DLNA/投屏功能';

  @override
  String get detailDlnaCastOk => '已推送播放地址到设备';

  @override
  String detailDlnaCastOkNamed(String device) {
    return '已投屏到 $device';
  }

  @override
  String get detailDlnaCastFailed => '投屏失败，请换线路或稍后重试';

  @override
  String get detailDlnaHint => '请选择要投屏的电视或盒子。CMS、磁力、离线缓存均会转换为电视可访问的地址。';

  @override
  String get detailDlnaRefresh => '重新搜索';

  @override
  String get detailDlnaNeedPlayback => '请先开始播放，再投屏';

  @override
  String get detailDlnaNoLanIp => '未获取到局域网 IP，请连接 Wi‑Fi 后重试';

  @override
  String get detailDlnaNoActiveStream => '磁力流尚未就绪，请稍候再试';

  @override
  String get detailDlnaUnsupportedSource => '当前片源暂不支持投屏';

  @override
  String get detailDlnaLocalServeFailed => '无法在局域网分享本地文件';

  @override
  String get detailDlnaResolveEmpty => '无法解析可投屏的播放地址';

  @override
  String detailDlnaCastingNamed(String device) {
    return '投屏中 · $device';
  }

  @override
  String get detailClose => '关闭';

  @override
  String get detailMagnetParsingMeta => '正在解析磁力元数据…';

  @override
  String get detailMagnetAddFailed => '添加磁力链接失败';

  @override
  String get detailMagnetNoVideoFile => '未找到可播放的视频文件';

  @override
  String get detailMagnetBuffering => '正在缓冲数据…';

  @override
  String get detailMagnetStreamFailed => '启动播放流失败';

  @override
  String get detailMagnetConnectingPeers => '正在连接节点…';

  @override
  String get detailPlaybackErrorNoUrl => '无可播放地址';

  @override
  String get detailPlaybackErrorParseFailed => '解析失败';

  @override
  String get detailPlaybackErrorRouteSwitched => '已切换线路';

  @override
  String get detailPlaybackErrorMultiSourceFailed => '多源回退失败';

  @override
  String get detailPlaybackErrorNetwork => '网络或播放器错误';

  @override
  String get detailPlaybackErrorMagnet => '磁力播放失败';

  @override
  String detailEpisodeLabel(int index) {
    return '第$index集';
  }

  @override
  String detailEpisodeGridCount(int count) {
    return '共 $count 集';
  }

  @override
  String detailEpisodeGridPageInfo(int current, int total) {
    return '第 $current / $total 页';
  }

  @override
  String get detailEpisodeGridPrevPage => '上一页';

  @override
  String get detailEpisodeGridNextPage => '下一页';

  @override
  String get detailEpisodeGridJumpToEpisode => '跳转到集数';

  @override
  String get detailEpisodeGridJumpTitle => '跳转到集数';

  @override
  String detailEpisodeGridJumpHint(int max) {
    return '输入集数（1–$max）';
  }

  @override
  String get detailEpisodeGridJumpConfirm => '跳转';

  @override
  String get detailCachePanelTitle => '离线缓存';

  @override
  String get detailCacheDownloadCurrent => '缓存当前集';

  @override
  String get detailCacheSelectEpisodes => '选择集数';

  @override
  String get detailCacheSelectAll => '全选';

  @override
  String get detailCacheClearSelection => '取消';

  @override
  String detailCacheDownloadSelected(int count) {
    return '下载所选 ($count)';
  }

  @override
  String detailCacheBatchQueued(int count) {
    return '已加入 $count 个下载任务';
  }

  @override
  String get detailCacheBatchNone => '所选集数均已在队列或已缓存';

  @override
  String get detailCacheEmptyForMovie => '本影片暂无缓存任务';

  @override
  String get detailCacheAlreadyCompleted => '当前集已缓存完成';

  @override
  String get detailCacheAlreadyDownloading => '当前集已在下载队列中';

  @override
  String get detailCacheQueued => '已加入下载队列';

  @override
  String get detailCacheDownloadStarted => '已开始下载';

  @override
  String get detailCacheWebUnsupported => 'Web 端暂不支持离线缓存';

  @override
  String get detailCacheMagnetUnsupported => '磁力资源暂不支持离线缓存';

  @override
  String get detailCacheNoEpisode => '无可缓存的播放地址';

  @override
  String get detailCacheUnsupportedUrl => '该地址暂不支持缓存';

  @override
  String get detailCacheParseFailed => '无法解析真实视频地址，暂不能缓存';

  @override
  String get detailCacheDeleted => '已删除缓存';

  @override
  String get detailCacheManageAll => '全部缓存';

  @override
  String get detailCacheStatusWaiting => '等待中';

  @override
  String get detailCacheStatusDownloading => '下载中';

  @override
  String get detailCacheStatusPaused => '已暂停';

  @override
  String get detailCacheStatusCompleted => '已完成';

  @override
  String get detailCacheStatusFailed => '失败';

  @override
  String get detailCachePause => '暂停';

  @override
  String get detailCacheResume => '继续';

  @override
  String get detailCacheDelete => '删除';

  @override
  String get cacheManagerTitle => '缓存管理';

  @override
  String get cacheManagerOnlyWifi => '仅 WiFi 下载';

  @override
  String get cacheManagerStorageTitle => '存储空间';

  @override
  String get cacheManagerClearAll => '清理全部';

  @override
  String get cacheManagerClearConfirmTitle => '清理缓存';

  @override
  String get cacheManagerClearConfirmBody => '确定要清理所有缓存吗？';

  @override
  String get cacheManagerClearDone => '缓存已清理';

  @override
  String cacheManagerUsedLabel(String used, String max) {
    return '已用: $used / $max';
  }

  @override
  String cacheManagerCompletedCount(int count) {
    return '已缓存 $count 个视频';
  }

  @override
  String get cacheWebBanner => 'Web 端不支持视频离线下载；列表为空属正常情况。';

  @override
  String get cacheFileMissing => '缓存文件不存在';

  @override
  String get cacheWebPlayUnsupported => 'Web 端请从详情页在线播放';

  @override
  String get cachePlayOffline => '离线播放';

  @override
  String cacheDownloadSpeed(String speed) {
    return '$speed/s';
  }

  @override
  String get followCacheTabEmpty => '暂无缓存';

  @override
  String get settingsOnlyWifiCache => '仅 WiFi 下载缓存';

  @override
  String get settingsOnlyWifiCacheSubtitle => '移动网络下不自动下载，与缓存管理页开关同步';
}
