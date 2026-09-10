/// 常量定义
class AppConstants {
  // 私有构造函数，防止实例化
  AppConstants._();

  /// 应用名称
  static const String appName = '高清影视';

  /// 应用版本
  static const String appVersion = '1.0.0';

  /// 默认API超时时间（毫秒）—— 10秒，减少用户等待
  static const int apiTimeout = 30000;

  /// 每页加载数量
  static const int pageSize = 20;

  /// 最大缓存大小（MB）
  static const int maxCacheSize = 2048;

  /// 搜索历史最大条数
  static const int maxSearchHistory = 20;

  /// 播放进度保存间隔（秒）
  static const int progressSaveInterval = 5;

  /// 仅磁力详情占位条目使用的 sourceId（与 CMS vod_id 区分，避免串片）
  static const String magnetDetailSourceId = 'magnet';

  /// 自动连播间隔（秒）
  static const int autoPlayNextInterval = 3;

  /// 轮播自动播放间隔（毫秒）
  static const int bannerAutoPlayInterval = 4000;

  /// WebDAV同步间隔（分钟）
  static const int syncInterval = 30;

  /// AES加密密钥长度
  static const int aesKeyLength = 32;

  /// AES加密IV长度
  static const int aesIvLength = 16;

  /// Hive Box名称
  static const String historyBox = 'watch_history';
  static const String favoriteBox = 'favorites';
  static const String cacheBox = 'cache_items';
  static const String settingsBox = 'settings';
  static const String sourceBox = 'play_sources';
  static const String userBox = 'user_info';
  static const String playlistBox = 'playlists';

  /// SharedPreferences键名
  static const String keyThemeIndex = 'theme_index';
  static const String keyDefaultSpeed = 'default_speed';
  static const String keyDefaultQuality = 'default_quality';
  static const String keyHardwareDecode = 'hardware_decode';
  static const String keyAutoPlayNext = 'auto_play_next';
  static const String keyAutoPlayOnDetailEnter = 'auto_play_on_detail_enter';
  static const String keyOnlyWifiCache = 'only_wifi_cache';
  static const String keyWebdavConfig = 'webdav_config';
  static const String keyLastSyncTime = 'last_sync_time';
  static const String keySearchHistory = 'search_history';
  static const String keyPlaybackStrategy = 'playback_strategy';
  static const String keyPreloadNextEpisode = 'preload_next_episode';
  static const String keyPlaybackPrefetch = 'playback_prefetch';

  /// 旧键名，仅用于读取迁移
  static const String keyWifiPlaybackPrefetch = 'wifi_playback_prefetch';

  /// OpenSubtitles.com REST API Key（在线搜索字幕）
  static const String keyOpensubtitlesApiKey = 'opensubtitles_api_key';

  /// TMDB API Key（中文片名 → IMDb / 英文片名，磁力搜索）
  static const String keyTmdbApiKey = 'tmdb_api_key';

  /// 磁力搜索源配置（JSON 数组）
  static const String keyMagnetSources = 'magnet_sources_json';

  /// 影视分类
  static const List<String> categories = [
    '电影',
    '剧集',
    '动漫',
    '综艺',
    '纪录片',
  ];

  /// 分类浏览「类型」筛选（对接苹果 CMS 列表 class 参数；选「全部」不传）
  static const List<String> filterGenres = [
    '全部',
    '剧情',
    '喜剧',
    '惊悚',
    '动作',
    '爱情',
    '犯罪',
    '恐怖',
    '冒险',
    '悬疑',
    '科幻',
    '家庭',
    '奇幻',
    '动画',
    '战争',
    '历史',
    '传记',
    '音乐',
    '歌舞',
    '运动',
    '西部',
    '灾难',
    '古装',
    '儿童',
    '纪录片',
  ];

  /// 影视地区
  static const List<String> regions = [
    '全部',
    '中国大陆',
    '中国香港',
    '中国台湾',
    '美国',
    '韩国',
    '日本',
    '英国',
    '法国',
    '德国',
    '泰国',
    '印度',
    '其他',
  ];

  /// 影视年份
  static const List<String> years = [
    '全部',
    '2026',
    '2025',
    '2024',
    '2023',
    '2022',
    '2021',
    '2020',
    '2019',
    '2018',
    '2017',
    '2016',
    '更早',
  ];

  /// 影视排序
  static const List<String> sortOptions = [
    '综合排序',
    '最近更新',
    '评分最高',
    '播放最多',
  ];

  /// 播放倍速选项
  static const List<double> speedOptions = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
    3.0,
    4.0,
  ];

  /// 清晰度选项
  static const List<String> qualityOptions = [
    '自动',
    '标清',
    '高清',
    '1080P',
    '4K',
  ];

  /// WebDAV预置服务商
  static const List<Map<String, String>> webdavPresets = [
    {
      'name': '坚果云',
      'url': 'https://dav.jianguoyun.com/dav/',
      'hint': '坚果云 -> 账户信息 -> 第三方应用管理 -> 生成密码',
    },
    {
      'name': '阿里云盘',
      'url': 'https://dav.aliyundrive.com/dav/',
      'hint': '请先在阿里云盘中开启WebDAV服务',
    },
    {
      'name': '115网盘',
      'url': 'https://dav.115.com/',
      'hint': '请先在115网盘中开启WebDAV服务',
    },
    {
      'name': '百度网盘',
      'url': 'https://dav.baidu.com/',
      'hint': '请先在百度网盘中开启WebDAV服务',
    },
    {
      'name': '群晖NAS',
      'url': 'https://your-nas:5006/',
      'hint': '请替换your-nas为你的NAS地址',
    },
    {
      'name': '自定义',
      'url': '',
      'hint': '请输入自定义WebDAV地址',
    },
  ];

  /// 默认播放源（苹果CMS采集接口格式）
  ///
  /// 以下源地址为公开的苹果CMS采集站API，实际可用性可能随时变化。
  /// 用户可在"播放源管理"中自行添加或替换为其他可用的采集源。
  static const List<Map<String, String>> defaultSources = [
    {
      'name': '非凡资源',
      'url': 'https://cj.ffzyapi.com/api.php/provide/vod/from/ffm3u8/',
      'type': 'cms',
    },
    {
      'name': '暴风资源',
      'url': 'https://bfzyapi.com/api.php/provide/vod/from/bfzym3u8/',
      'type': 'cms',
    },
    {
      'name': '量子资源',
      'url': 'https://cj.lziapi.com/api.php/provide/vod/from/lzm3u8/',
      'type': 'cms',
    },
    {
      'name': 'BD资源',
      'url': 'https://api.apibdzy.com/api.php/provide/vod/',
      'type': 'cms',
    },
    {
      'name': '索尼资源',
      'url': 'https://suoniapi.com/api.php/provide/vod/from/subm3u8/',
      'type': 'cms',
    },
    {
      'name': '红牛资源',
      'url': 'https://www.hongniuzy2.com/api.php/provide/vod/from/hnm3u8/',
      'type': 'cms',
    },
  ];
}
