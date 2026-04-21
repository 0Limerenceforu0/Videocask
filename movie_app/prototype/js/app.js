/**
 * 静态壳：hash 路由 + 页面渲染
 * 路由: #/home | #/discover | #/follow | #/profile | #/search | #/detail/:id | ...
 */
(function () {
  const $ = (sel, el = document) => el.querySelector(sel);
  const $$ = (sel, el = document) => [...el.querySelectorAll(sel)];

  const state = {
    searchTab: "all",
    searchQuery: "三体",
    detailTab: "routes",
    followTab: 0,
    rankTab: 0,
    currentDetailId: "m1",
    playerTitle: "",
  };

  function parseHash() {
    const h = (location.hash || "#/home").replace(/^#/, "") || "/home";
    const parts = h.split("/").filter(Boolean);
    const name = parts[0] || "home";
    return { name, parts };
  }

  function navTo(path) {
    location.hash = path.startsWith("#") ? path : "#" + path;
  }

  function getDetail(id) {
    const M = window.MOCK.detailById;
    return M[id] || { ...M.default, id, title: "影片 " + id };
  }

  function header(title, opts = {}) {
    const back = opts.back
      ? `<button type="button" class="icon-btn" data-back="${opts.back}" aria-label="返回">←</button>`
      : `<span style="width:40px"></span>`;
    const right = opts.right || `<span style="width:40px"></span>`;
    return `<header class="app-header">${back}<h1>${title}</h1>${right}</header>`;
  }

  function renderHome() {
    const M = window.MOCK;
    const cw = M.continueWatching
      .map(
        (x) => `
      <a href="#/detail/${x.id}" class="poster">
        <div class="img"></div>
        <div class="progress"><span style="width:${Math.round(x.progress * 100)}%"></span></div>
        <div class="meta">${x.title}<br/>${x.ep}</div>
      </a>`
      )
      .join("");

    const rec = M.recommend
      .map(
        (x) => `
      <a href="#/detail/${x.id}" class="card-poster">
        <div class="img"></div>
        <div class="t">${x.title}</div>
        <div class="sub">${x.sub}</div>
      </a>`
      )
      .join("");

    const hot = M.hotRow
      .map(
        (x) => `
      <a href="#/detail/${x.id}" class="poster">
        <div class="img"></div>
        <div class="meta">${x.title}</div>
      </a>`
      )
      .join("");

    const homeTabs = ["直播", "推荐", "热门", "追番", "影视", "综艺"]
      .map(
        (t, i) =>
          `<button type="button" class="${i === 1 ? "active" : ""}" data-bili-tab>${t}</button>`
      )
      .join("");

    const biliFeed = M.biliFeed
      .map(
        (v) => `
      <a href="#/detail/${v.id}" class="bili-feed-card">
        <div class="cover">
          <span class="dur">${v.dur}</span>
          <div class="play-meta"><span>▶ ${v.plays}</span><span>弹 ${v.danmu}</span></div>
        </div>
        <div class="body">
          <h3>${v.title}</h3>
          <div class="up">${v.up} · 点击进入详情（原型）</div>
        </div>
      </a>`
      )
      .join("");

    return `
      ${header("首页", { right: `<button type="button" class="icon-btn" data-go="#/search" aria-label="搜索">🔍</button>` })}
      <div class="bili-top">
        <div class="bili-search-pill" data-go="#/search" role="link" tabindex="0">
          <span aria-hidden="true">🔍</span> 搜索视频、影视、UP主…
        </div>
      </div>
      <div class="bili-home-tabs">${homeTabs}</div>
      <div class="hero">
        <div class="hero-inner">
          <h2>三体 · 正在热播</h2>
          <div style="display:flex;gap:10px">
            <a href="#/detail/m1" class="btn-primary">▶ 继续观看</a>
            <a href="#/detail/m1" class="btn-outline">详情</a>
          </div>
        </div>
      </div>
      <div class="section-title bili-with-more">
        <span style="display:flex;align-items:center;gap:8px"><span class="accent-bar"></span>推荐</span>
        <span class="more-link" data-go="#/discover">更多 ›</span>
      </div>
      <div class="bili-feed-row">${biliFeed}</div>
      <div class="section-title"><span class="accent-bar"></span>继续观看</div>
      <div class="row-scroll">${cw}</div>
      <div class="section-title"><span class="accent-bar"></span>热门精选</div>
      <div class="row-scroll">${hot}</div>
      <div class="chips">
        <span class="chip active">全部</span>
        <span class="chip">电影</span>
        <span class="chip">剧集</span>
        <span class="chip">综艺</span>
      </div>
      <div class="section-title"><span class="accent-bar"></span>为你推荐</div>
      <div class="grid-2">${rec}</div>
      <div style="padding:16px;text-align:center">
        <button type="button" class="btn-outline" data-go="#/ranking">查看完整排行榜 →</button>
      </div>
    `;
  }

  function renderDiscover() {
    const M = window.MOCK;
    const grid = M.discoverMovies
      .map(
        (x) => `
      <a href="#/detail/${x.id}" class="card-poster">
        <div class="img"></div>
        <div class="t">${x.title}</div>
        <div class="sub">${x.sub}</div>
      </a>`
      )
      .join("");
    return `
      ${header("发现", { right: `<button type="button" class="icon-btn" data-go="#/search">🔍</button>` })}
      <div style="padding:12px 16px;font-size:12px;color:var(--text2)">当前源：<strong style="color:var(--primary)">主 CMS 源</strong>（假数据）</div>
      <div class="chips">
        <span class="chip active">地区：全部</span>
        <span class="chip">年份：全部</span>
        <span class="chip">排序：综合</span>
      </div>
      <div class="grid-2">${grid}</div>
    `;
  }

  function renderFollow() {
    const M = window.MOCK;
    const tabs = ["收藏", "历史", "缓存"];
    const panels = [
      M.favorites
        .map(
          (x) => `
        <a href="#/detail/${x.id}" class="list-movie">
          <div class="thumb"></div>
          <div class="info"><h3>${x.title}</h3><p>${x.sub}</p></div>
        </a>`
        )
        .join("") || `<div class="empty-state">暂无收藏</div>`,
      M.history
        .map(
          (x) => `
        <a href="#/detail/${x.id}" class="list-movie">
          <div class="thumb"></div>
          <div class="info"><h3>${x.title}</h3><p>${x.sub}</p></div>
        </a>`
        )
        .join(""),
      M.cache
        .map(
          (x) => `
        <a href="#/cache" class="list-movie">
          <div class="thumb"></div>
          <div class="info"><h3>${x.title}</h3><p>${x.sub}</p></div>
        </a>`
        )
        .join(""),
    ];
    const tabHtml = tabs
      .map(
        (t, i) =>
          `<button type="button" class="${i === state.followTab ? "active" : ""}" data-follow-tab="${i}">${t}</button>`
      )
      .join("");
    return `
      ${header("追剧")}
      <div class="sub-tabs">${tabHtml}</div>
      <div class="follow-panel">${panels[state.followTab]}</div>
    `;
  }

  function renderProfile() {
    const u = window.MOCK.user;
    const st = window.MOCK.stats;
    return `
      ${header("我的")}
      <div style="padding:24px 16px;display:flex;gap:14px;align-items:center">
        <div style="width:56px;height:56px;border-radius:50%;background:var(--surface2)"></div>
        <div>
          <div style="font-weight:700">${u.name}</div>
          <div style="font-size:12px;color:var(--text2)">${u.mode}</div>
        </div>
      </div>
      <div class="stat-grid">
        <a href="#/follow" class="stat-card"><div class="num">24</div><div class="lbl">收藏</div></a>
        <a href="#/follow" class="stat-card"><div class="num">128</div><div class="lbl">历史</div></a>
        <a href="#/cache" class="stat-card"><div class="num">3</div><div class="lbl">缓存</div></a>
        <a href="#/playlist" class="stat-card"><div class="num">3</div><div class="lbl">片单</div></a>
      </div>
      <div class="menu-section">账号</div>
      <div class="menu-list">
        <a href="#/login" class="menu-item">登录 / 注册 <small>当前游客</small></a>
      </div>
      <div class="menu-section">数据与源</div>
      <div class="menu-list">
        <a href="#/sources" class="menu-item">播放源管理 <small>3 个源</small></a>
        <a href="#/magnet-sources" class="menu-item">磁力搜索源 <small>已启用 2</small></a>
        <a href="#/cache" class="menu-item">缓存管理 <small>2.9 GB</small></a>
        <a href="#/settings" class="menu-item">设置 <small>播放 · WebDAV</small></a>
      </div>
      <div class="menu-section">其他</div>
      <div class="menu-list">
        <a href="#/stats" class="menu-item">观影统计 <small>${st.hours} 小时</small></a>
        <a href="#/ranking" class="menu-item">排行榜</a>
      </div>
    `;
  }

  function renderSearch() {
    const M = window.MOCK;
    const q = state.searchQuery;
    const tab = state.searchTab;
    let body = "";
    if (tab === "magnet") {
      body = M.magnets
        .map(
          (t) => `
        <div class="magnet-card">
          <h4>${t.name}</h4>
          <div class="magnet-meta">
            <span>体积 ${t.size}</span><span>${t.source}</span>
            <span>做种 ${t.seeders}</span><span>下载 ${t.leechers}</span>
            <span>IMDb ${t.imdb}</span>
          </div>
          <div style="display:flex;gap:10px">
            <button type="button" class="btn-primary" data-play-magnet="${t.id}">▶ 播放</button>
            <a href="#/detail/magnet-${t.id}" class="btn-outline" style="display:inline-flex;align-items:center">进入详情</a>
          </div>
        </div>`
        )
        .join("");
    } else if (tab === "movie") {
      body = M.searchMovies
        .map(
          (m) => `
        <a href="#/detail/${m.id}" class="list-movie">
          <div class="thumb"></div>
          <div class="info"><h3>${m.title}</h3><p>${m.meta}</p></div>
        </a>`
        )
        .join("");
    } else {
      body = `
        <div class="section-title"><span class="accent-bar"></span>影视（${M.searchMovies.length}）</div>
        ${M.searchMovies
          .map(
            (m) => `
          <a href="#/detail/${m.id}" class="list-movie">
            <div class="thumb"></div>
            <div class="info"><h3>${m.title}</h3><p>${m.meta}</p></div>
          </a>`
          )
          .join("")}
        <div class="section-title"><span class="accent-bar"></span>磁力（${M.magnets.length}）</div>
        ${M.magnets
          .map(
            (t) => `
          <div class="magnet-card">
            <h4>${t.name}</h4>
            <div class="magnet-meta"><span>${t.size}</span><span>${t.source}</span></div>
            <button type="button" class="btn-primary" data-play-magnet="${t.id}">▶ 播放</button>
          </div>`
          )
          .join("")}`;
    }

    const tabs = [
      { k: "all", l: "全部" },
      { k: "movie", l: "影视" },
      { k: "magnet", l: "磁力" },
    ];
    const tabBtns = tabs
      .map(
        (t) =>
          `<button type="button" class="${state.searchTab === t.k ? "active" : ""}" data-search-tab="${t.k}">${t.l}</button>`
      )
      .join("");

    return `
      ${header("搜索", { back: "#/home" })}
      <div class="search-bar-wrap">
        <div class="search-bar">
          <span>🔍</span>
          <input type="search" id="search-input" value="${q}" placeholder="搜索影片、演员..." />
          <button type="button" class="btn-primary" style="padding:6px 14px;font-size:13px" id="search-btn">搜索</button>
        </div>
      </div>
      <div class="search-tabs">${tabBtns}</div>
      ${body}
    `;
  }

  function renderDetail(id) {
    state.currentDetailId = id;
    const base = getDetail(id.startsWith("magnet-") ? "m1" : id);
    const d =
      id.startsWith("magnet-")
        ? {
            ...base,
            title: "磁力资源 · " + id.replace("magnet-", ""),
            desc: "（磁力详情壳）此处为静态演示，真实 App 会合并 CMS 海报与种子信息。",
          }
        : { ...base };
    const eps = d.episodes
      .map(
        (e, i) =>
          `<button type="button" class="episode-pill ${i === 7 ? "active" : ""}" data-ep="${e.n}">${e.label}</button>`
      )
      .join("");
    const routes = d.routes
      .map(
        (r) => `
      <a href="#/player" class="route-item" data-player-title="${d.title} · ${r.name}">
        <span>${r.name}</span>
        <span>${r.tag || "播放"}</span>
      </a>`
      )
      .join("");

    const tabs = [
      { k: "routes", l: "线路" },
      { k: "desc", l: "简介" },
      { k: "talk", l: "讨论" },
    ];
    const tabHtml = tabs
      .map(
        (t) =>
          `<button type="button" class="${state.detailTab === t.k ? "active" : ""}" data-detail-tab="${t.k}">${t.l}</button>`
      )
      .join("");

    let main = "";
    if (state.detailTab === "routes") main = `<div class="route-list">${routes}</div>`;
    else if (state.detailTab === "desc") main = `<div class="desc-block">${d.desc}</div>`;
    else main = `<div class="empty-state">暂无讨论（原型占位）<br/><button type="button" class="btn-outline mt-16" data-go="#/login">登录后参与</button></div>`;

    return `
      ${header("影片详情", { back: "#/home" })}
      <div class="detail-backdrop"></div>
      <div class="detail-head">
        <div class="detail-poster"></div>
        <div class="detail-info">
          <h2>${d.title}</h2>
          <div class="detail-meta">${d.alias ? d.alias + " · " : ""}${d.year} · ${d.region} · ${d.genres}</div>
          <div class="detail-meta">评分 <strong style="color:var(--accent)">${d.rating}</strong></div>
        </div>
      </div>
      <div class="detail-actions">
        <a href="#/player" class="btn-primary" data-player-title="${d.title} · 第 8 集">▶ 立即播放</a>
        <button type="button" class="btn-outline">♡ 收藏</button>
        <button type="button" class="btn-outline" data-go="#/playlist">＋ 片单</button>
      </div>
      <div class="section-title"><span class="accent-bar"></span>选集</div>
      <div class="episode-scroll">${eps}</div>
      <div class="detail-tabs">${tabHtml}</div>
      ${main}
      <div class="section-title"><span class="accent-bar"></span>磁力资源（演示）</div>
      <div class="magnet-card">
        <h4>3.Body.Problem.S01.1080p.NF.WEB</h4>
        <div class="magnet-meta"><span>16 GB</span><span>PirateBay</span></div>
        <a href="#/detail/magnet-t1" class="btn-outline" style="display:inline-block;margin-right:8px">磁力详情页</a>
        <button type="button" class="btn-primary" data-go="#/player" data-player-title="磁力流 · 三体">▶ 磁力播放</button>
      </div>
    `;
  }

  function renderPlayer() {
    const t = state.playerTitle || "三体 · 第 8 集";
    return ""; // 叠加层单独处理
  }

  function renderSettings() {
    return `
      ${header("设置", { back: "#/profile" })}
      <div class="menu-section">播放</div>
      <div class="menu-list">
        <a href="#" class="menu-item" onclick="alert('原型：倍速');return false">默认倍速 <small>1.0x</small></a>
        <a href="#" class="menu-item" onclick="alert('原型：清晰度');return false">默认清晰度 <small>1080P</small></a>
        <a href="#" class="menu-item" onclick="alert('原型：字幕 Key');return false">OpenSubtitles API Key <small>未配置</small></a>
        <a href="#" class="menu-item" onclick="alert('原型');return false">硬件解码 <small>开</small></a>
        <a href="#" class="menu-item" onclick="alert('原型');return false">自动连播 <small>开</small></a>
      </div>
      <div class="menu-section">同步</div>
      <div class="menu-list">
        <a href="#" class="menu-item" onclick="alert('原型：WebDAV');return false">WebDAV 配置 <small>未连接</small></a>
      </div>
      <div class="menu-section">外观</div>
      <div class="menu-list">
        <a href="#" class="menu-item" onclick="alert('原型：主题');return false">深色模式 <small>跟随系统</small></a>
      </div>
    `;
  }

  function renderSources() {
    const rows = window.MOCK.sources
      .map(
        (s) => `
      <div class="menu-item" style="cursor:default">
        <span>${s.on ? "✓" : "○"} ${s.name} <small style="display:block;margin-top:4px;color:var(--text2)">${s.url}</small></span>
        <small>${s.type}</small>
      </div>`
      )
      .join("");
    return `
      ${header("播放源管理", { back: "#/profile" })}
      <div style="padding:12px 16px">
        <button type="button" class="btn-primary" onclick="alert('原型：添加源')">＋ 添加源</button>
      </div>
      <div class="menu-list">${rows}</div>
    `;
  }

  function renderMagnetSources() {
    const rows = window.MOCK.magnetSources
      .map(
        (s) => `
      <div class="menu-item" style="cursor:default">
        <span>${s.on ? "✓" : "○"} ${s.name}</span>
        <small>${s.on ? "已启用" : "已关闭"}</small>
      </div>`
      )
      .join("");
    return `
      ${header("磁力搜索源", { back: "#/settings" })}
      <div class="menu-list">${rows}</div>
      <div class="desc-block">从「我的 → 设置」也可进入此页；此处为静态演示。</div>
    `;
  }

  function renderCache() {
    return `
      ${header("缓存管理", { back: "#/profile" })}
      <div style="padding:12px 16px;display:flex;justify-content:space-between;align-items:center">
        <span style="font-size:13px">仅 Wi-Fi 下载</span>
        <button type="button" class="btn-outline" style="padding:6px 12px" onclick="alert('原型')">开关</button>
      </div>
      <div class="menu-list">
        <div class="menu-item">三体 <small>2.1 GB · 4 集</small></div>
        <div class="menu-item">地球脉动 <small>890 MB</small></div>
      </div>
      <div style="padding:16px"><button type="button" class="btn-primary w-full" onclick="alert('原型：清空')">清空全部缓存</button></div>
    `;
  }

  function renderRanking() {
    const R = window.MOCK.ranking;
    const keys = ["rating", "hot", "new", "rise"];
    const labels = ["好评", "热播", "最新", "飙升"];
    const list = R[keys[state.rankTab]];
    const tabs = labels
      .map(
        (l, i) =>
          `<button type="button" class="${state.rankTab === i ? "active" : ""}" data-rank-tab="${i}">${l}</button>`
      )
      .join("");
    const items = list
      .map(
        (x, i) => `
      <a href="#/detail/${x.id}" class="list-movie">
        <span class="rank-num">${i + 1}</span>
        <div class="thumb"></div>
        <div class="info"><h3>${x.title}</h3><p>${x.sub}</p></div>
      </a>`
      )
      .join("");
    return `
      ${header("排行榜", { back: "#/home" })}
      <div class="sub-tabs">${tabs}</div>
      ${items}
    `;
  }

  function renderPlaylist() {
    const rows = window.MOCK.playlists
      .map(
        (p) => `
      <a href="#/playlist/${p.id}" class="menu-item">
        <span>${p.name}</span>
        <small>${p.count} 部</small>
      </a>`
      )
      .join("");
    return `
      ${header("播放列表", { back: "#/profile" })}
      <div style="padding:12px 16px">
        <button type="button" class="btn-primary" onclick="alert('原型：新建片单')">＋ 新建列表</button>
      </div>
      <div class="menu-list">${rows}</div>
    `;
  }

  function renderPlaylistDetail(pid) {
    const p = window.MOCK.playlists.find((x) => x.id === pid) || {
      name: "片单",
      id: pid,
    };
    const items = window.MOCK.playlistItems
      .map(
        (x) => `
      <a href="#/detail/${x.id}" class="list-movie">
        <div class="thumb"></div>
        <div class="info"><h3>${x.title}</h3><p>点击进详情</p></div>
      </a>`
      )
      .join("");
    return `
      ${header(p.name, { back: "#/playlist" })}
      ${items}
      <div style="padding:16px"><a href="#/player" class="btn-primary w-full" style="display:block;text-align:center;text-decoration:none" data-player-title="片单连播 · ${p.name}">▶ 从第一部开始播（演示）</a></div>
    `;
  }

  function renderStats() {
    const s = window.MOCK.stats;
    return `
      ${header("观影统计", { back: "#/profile" })}
      <div class="stat-grid" style="padding-top:24px">
        <div class="stat-card"><div class="num">${s.days}</div><div class="lbl">活跃天数</div></div>
        <div class="stat-card"><div class="num">${s.hours}</div><div class="lbl">总时长(小时)</div></div>
        <div class="stat-card"><div class="num">${s.films}</div><div class="lbl">看过部数</div></div>
        <div class="stat-card"><div class="num">${s.reviews}</div><div class="lbl">短评数</div></div>
      </div>
      <div class="empty-state">图表占位：真实 App 可接图表库</div>
    `;
  }

  function renderLogin() {
    return `
      ${header("登录", { back: "#/profile" })}
      <div class="login-hero">
        <h2>欢迎回来</h2>
        <p style="color:var(--text2);font-size:14px">原型仅演示布局，无真实登录</p>
      </div>
      <div class="login-form">
        <input class="input" placeholder="手机号 / 邮箱" />
        <input class="input" type="password" placeholder="密码" />
        <button type="button" class="btn-primary w-full" onclick="alert('原型：登录');location.hash='#/profile'">登录</button>
        <button type="button" class="btn-outline w-full mt-8" onclick="location.hash='#/profile'">游客继续使用</button>
      </div>
    `;
  }

  function showPlayer(title) {
    state.playerTitle = title;
    const el = $("#player-overlay");
    el.classList.add("active");
    $("#player-episode-title").textContent = title;
  }

  function hidePlayer() {
    $("#player-overlay").classList.remove("active");
  }

  const pages = {
    home: renderHome,
    discover: renderDiscover,
    follow: renderFollow,
    profile: renderProfile,
    search: renderSearch,
    detail: () => renderDetail(state.currentDetailId),
    settings: renderSettings,
    sources: renderSources,
    "magnet-sources": renderMagnetSources,
    cache: renderCache,
    ranking: renderRanking,
    playlist: renderPlaylist,
    stats: renderStats,
    login: renderLogin,
  };

  function render() {
    const { name, parts } = parseHash();
    const app = $("#app");

    if (name === "detail" && parts[1]) {
      state.currentDetailId = parts[1];
    }
    if (name === "playlist" && parts[1]) {
      app.innerHTML = renderPlaylistDetail(parts[1]);
      bindApp();
      setBottomNav("profile");
      return;
    }

    const fn = pages[name] || pages.home;
    app.innerHTML = fn();
    bindApp();
    const navMap = {
      home: "home",
      discover: "discover",
      follow: "follow",
      profile: "profile",
    };
    setBottomNav(navMap[name] || null);
  }

  function setBottomNav(active) {
    $$(".bottom-nav a").forEach((a) => {
      a.classList.toggle("active", a.dataset.nav === active);
    });
  }

  function bindApp() {
    const app = $("#app");
    app.querySelectorAll("[data-go]").forEach((el) => {
      el.addEventListener("click", () => navTo(el.dataset.go));
    });
    app.querySelectorAll("[data-back]").forEach((el) => {
      el.addEventListener("click", () => navTo(el.dataset.back));
    });
    app.querySelectorAll("[data-follow-tab]").forEach((el) => {
      el.addEventListener("click", () => {
        state.followTab = +el.dataset.followTab;
        render();
      });
    });
    app.querySelectorAll("[data-search-tab]").forEach((el) => {
      el.addEventListener("click", () => {
        state.searchTab = el.dataset.searchTab;
        render();
      });
    });
    app.querySelectorAll("[data-detail-tab]").forEach((el) => {
      el.addEventListener("click", () => {
        state.detailTab = el.dataset.detailTab;
        render();
      });
    });
    app.querySelectorAll("[data-rank-tab]").forEach((el) => {
      el.addEventListener("click", () => {
        state.rankTab = +el.dataset.rankTab;
        render();
      });
    });
    app.querySelectorAll("[data-play-magnet]").forEach((el) => {
      el.addEventListener("click", () => {
        showPlayer("磁力 · " + el.dataset.playMagnet + "（演示）");
      });
    });
    app.querySelectorAll('a[href="#/player"], .btn-primary[data-go="#/player"]').forEach((el) => {
      el.addEventListener("click", (e) => {
        e.preventDefault();
        const t = el.dataset.playerTitle || state.playerTitle || "正在播放";
        showPlayer(t);
      });
    });
    const si = $("#search-input");
    const sb = $("#search-btn");
    if (si && sb) {
      sb.addEventListener("click", () => {
        state.searchQuery = si.value || "三体";
        render();
      });
    }
    $$("[data-bili-tab]", app).forEach((btn) => {
      btn.addEventListener("click", () => {
        $$("[data-bili-tab]", app).forEach((b) => b.classList.remove("active"));
        btn.classList.add("active");
      });
    });
  }

  window.addEventListener("hashchange", render);
  window.addEventListener("DOMContentLoaded", () => {
    $("#player-close").addEventListener("click", hidePlayer);
    render();
  });
})();
