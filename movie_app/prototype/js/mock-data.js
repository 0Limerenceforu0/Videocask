/**
 * 静态原型假数据 — 仅用于 HTML 壳演示
 */
window.MOCK = {
  user: {
    name: "影迷_8924",
    mode: "游客模式",
    avatar: null,
  },

  continueWatching: [
    {
      id: "m1",
      title: "三体",
      ep: "第 8 集 / 共 30 集",
      progress: 0.42,
    },
    {
      id: "m2",
      title: "流浪地球2",
      ep: "已看 62%",
      progress: 0.62,
    },
    {
      id: "m3",
      title: "漫长的季节",
      ep: "第 12 集 完",
      progress: 1,
    },
  ],

  recommend: [
    { id: "r1", title: "狂飙", sub: "9.1 · 犯罪" },
    { id: "r2", title: "隐秘的角落", sub: "8.9 · 悬疑" },
    { id: "r3", title: "开端", sub: "8.2 · 科幻" },
    { id: "r4", title: "去有风的地方", sub: "8.0 · 治愈" },
    { id: "r5", title: "繁花", sub: "8.7 · 剧情" },
    { id: "r6", title: "庆余年2", sub: "8.4 · 古装" },
  ],

  hotRow: [
    { id: "h1", title: "热榜 · 漫长的季节" },
    { id: "h2", title: "热榜 · 人世间" },
    { id: "h3", title: "热榜 · 觉醒年代" },
    { id: "h4", title: "热榜 · 山海情" },
  ],

  /** B站信息流风格：16:9 + 播放量/时长（仅原型展示） */
  biliFeed: [
    {
      id: "m1",
      title: "【三体】名场面！整个宇宙将为你闪烁",
      up: "影视解说菌",
      plays: "328.5万",
      danmu: "1.2万",
      dur: "18:42",
    },
    {
      id: "r1",
      title: "狂飙：高启强人物弧光全梳理，一遍看懂",
      up: "剧评团",
      plays: "892万",
      danmu: "6.8万",
      dur: "24:05",
    },
    {
      id: "r3",
      title: "开端：时间循环类作品怎么拍才不腻",
      up: "电影课代表",
      plays: "156万",
      danmu: "4021",
      dur: "12:33",
    },
  ],

  discoverMovies: [
    { id: "d1", title: "奥本海默", sub: "2023 · 美国" },
    { id: "d2", title: "芭比", sub: "2023 · 喜剧" },
    { id: "d3", title: "坠落的审判", sub: "2023 · 法国" },
    { id: "d4", title: "可怜的东西", sub: "2023 · 奇幻" },
    { id: "d5", title: "过往人生", sub: "2023 · 爱情" },
    { id: "d6", title: "留校联盟", sub: "2023 · 剧情" },
  ],

  favorites: [
    { id: "f1", title: "三体", sub: "剧集 · 更新至 30 集" },
    { id: "f2", title: "流浪地球2", sub: "电影 · 2023" },
  ],

  history: [
    { id: "m1", title: "三体", sub: "第 8 集 · 昨天" },
    { id: "m2", title: "流浪地球2", sub: "62% · 3 天前" },
    { id: "m3", title: "漫长的季节", sub: "全剧 · 上周" },
  ],

  cache: [
    { id: "c1", title: "三体", sub: "已缓存 4 集 · 2.1 GB" },
    { id: "c2", title: "纪录片：地球脉动", sub: "1080P · 890 MB" },
  ],

  searchMovies: [
    {
      id: "m1",
      title: "三体",
      meta: "剧集 · 2024 · 腾讯源",
    },
    {
      id: "m-sim",
      title: "三体（动画）",
      meta: "动漫 · B站源",
    },
    {
      id: "m-doc",
      title: "三体：纪录片",
      meta: "纪录 · 优酷源",
    },
  ],

  magnets: [
    {
      id: "t1",
      name: "3.Body.Problem.S01.COMPLETE.1080p.NF.WEB.H264-StereotypedGazelle",
      size: "16.91 GB",
      source: "PirateBay",
      seeders: 1240,
      leechers: 88,
      imdb: "tt13016388",
    },
    {
      id: "t2",
      name: "3 Body Problem S01 Season 1 2024 1080p NF WEBRip x265-Rapta",
      size: "8.2 GB",
      source: "1337x",
      seeders: 560,
      leechers: 34,
      imdb: "tt13016388",
    },
    {
      id: "t3",
      name: "3.Body.Problem.2024.S01.MULTI.2160p.WEB-DL.H265-AOC",
      size: "42.1 GB",
      source: "RARBG",
      seeders: 210,
      leechers: 12,
      imdb: "tt13016388",
    },
  ],

  detailById: {
    m1: {
      id: "m1",
      title: "三体",
      alias: "The Three-Body Problem",
      rating: "9.2",
      year: "2024",
      region: "中国大陆",
      genres: "科幻 · 悬疑",
      desc: "地球文明向宇宙发出广播，三体文明接收信号后展开跨越光年的博弈。本剧改编自刘慈欣同名小说，讲述科学家与军方共同面对人类文明危机的故事。（静态假文案）",
      episodes: Array.from({ length: 12 }, (_, i) => ({
        n: i + 1,
        label: `第 ${i + 1} 集`,
      })),
      routes: [
        { name: "腾讯线路 · 1080P", tag: "推荐" },
        { name: "备用线路 · 720P", tag: "流畅" },
        { name: "海外 CDN", tag: "高清" },
      ],
    },
    default: {
      id: "def",
      title: "示例影片",
      alias: "Demo Movie",
      rating: "8.5",
      year: "2023",
      region: "美国",
      genres: "剧情",
      desc: "这是一部用于原型演示的占位影片简介。点击播放将打开全屏播放器壳，所有数据均为前端静态模拟。",
      episodes: Array.from({ length: 8 }, (_, i) => ({
        n: i + 1,
        label: `第 ${i + 1} 集`,
      })),
      routes: [
        { name: "CMS 主线路", tag: "默认" },
        { name: "备用线路", tag: "" },
      ],
    },
  },

  sources: [
    { id: "s1", name: "主 CMS 源", url: "https://api.example.com", type: "cms", on: true },
    { id: "s2", name: "备用影视", url: "https://bak.example.com", type: "cms", on: true },
    { id: "s3", name: "测试源（关）", url: "https://test.example.com", type: "cms", on: false },
  ],

  magnetSources: [
    { id: "ms1", name: "Jackett 聚合", on: true },
    { id: "ms2", name: "内置 BT 源 A", on: true },
    { id: "ms3", name: "内置 BT 源 B", on: false },
  ],

  playlists: [
    { id: "p1", name: "周末补番", count: 12 },
    { id: "p2", name: "科幻必看", count: 8 },
    { id: "p3", name: "和家人一起看", count: 5 },
  ],

  playlistItems: [
    { id: "m1", title: "三体" },
    { id: "r3", title: "开端" },
    { id: "r1", title: "狂飙" },
  ],

  ranking: {
    rating: [
      { id: "rk1", title: "肖申克的救赎", sub: "9.7" },
      { id: "rk2", title: "霸王别姬", sub: "9.6" },
      { id: "rk3", title: "阿甘正传", sub: "9.5" },
    ],
    hot: [
      { id: "hk1", title: "三体", sub: "热播" },
      { id: "hk2", title: "繁花", sub: "更新中" },
      { id: "hk3", title: "庆余年2", sub: "热播" },
    ],
    new: [
      { id: "nk1", title: "新片 A", sub: "今日上架" },
      { id: "nk2", title: "新片 B", sub: "本周" },
    ],
    rise: [
      { id: "uk1", title: "飙升榜 1", sub: "+120%" },
      { id: "uk2", title: "飙升榜 2", sub: "+88%" },
    ],
  },

  stats: {
    days: 42,
    hours: 128,
    films: 86,
    reviews: 12,
  },
};
