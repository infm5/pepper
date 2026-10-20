/// The self-contained demo page served at `/`.
const relicVaultUi = r'''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Relic Vault · pepper demo</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #0b0d12;
      --panel: #131722;
      --panel-2: #1a2030;
      --border: #2a3245;
      --text: #e8ecf5;
      --muted: #8e9bb3;
      --accent: #f7b955;
      --accent-2: #7dd3fc;
      --good: #6ee7b7;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background:
        radial-gradient(circle at 15% 0%, rgba(247,185,85,.14), transparent 35%),
        radial-gradient(circle at 85% 10%, rgba(125,211,252,.10), transparent 30%),
        var(--bg);
      color: var(--text);
      min-height: 100vh;
    }
    main { max-width: 1180px; margin: 0 auto; padding: 56px 24px 80px; }
    header { display: flex; gap: 28px; justify-content: space-between; align-items: flex-start; flex-wrap: wrap; }
    h1 { margin: 0 0 10px; font-size: clamp(2.4rem, 5vw, 4.6rem); letter-spacing: -.05em; line-height: .95; }
    h1 span { color: var(--accent); }
    .lede { margin: 0; max-width: 640px; color: var(--muted); font-size: 1.05rem; line-height: 1.6; }
    .badge { display: inline-flex; align-items: center; gap: 8px; padding: 8px 12px; border: 1px solid var(--border); border-radius: 999px; color: var(--muted); font-size: .82rem; background: rgba(19,23,34,.7); }
    .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--good); box-shadow: 0 0 14px var(--good); }
    .search { display: flex; gap: 10px; margin: 36px 0 22px; }
    .search input {
      flex: 1; min-width: 0; padding: 15px 18px; border-radius: 14px; border: 1px solid var(--border);
      background: var(--panel); color: var(--text); font-size: 1rem; outline: none;
    }
    .search input:focus { border-color: var(--accent); box-shadow: 0 0 0 3px rgba(247,185,85,.12); }
    button {
      border: 0; border-radius: 14px; padding: 0 20px; font-weight: 700; font-size: .95rem;
      background: var(--accent); color: #1b1406; cursor: pointer;
    }
    button.ghost { background: transparent; color: var(--muted); border: 1px solid var(--border); font-weight: 600; }
    button:hover { filter: brightness(1.06); }
    .stats { display: grid; grid-template-columns: repeat(6, minmax(0, 1fr)); gap: 12px; margin-bottom: 30px; }
    .stat { background: linear-gradient(180deg, var(--panel), var(--panel-2)); border: 1px solid var(--border); border-radius: 16px; padding: 16px; min-height: 92px; }
    .stat .label { color: var(--muted); font-size: .72rem; letter-spacing: .1em; text-transform: uppercase; }
    .stat .value { margin-top: 10px; font-size: 1.45rem; font-weight: 750; font-variant-numeric: tabular-nums; }
    .stat .sub { margin-top: 3px; color: var(--muted); font-size: .76rem; }
    .section-head { display: flex; align-items: center; justify-content: space-between; margin: 26px 0 14px; }
    .section-head h2 { margin: 0; font-size: 1.1rem; letter-spacing: -.01em; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(245px, 1fr)); gap: 14px; }
    .card {
      background: linear-gradient(160deg, var(--panel), #10141e);
      border: 1px solid var(--border); border-radius: 18px; padding: 18px;
      transition: transform .18s ease, border-color .18s ease;
    }
    .card:hover { transform: translateY(-2px); border-color: #46536e; }
    .glyph {
      width: 44px; height: 44px; border-radius: 13px; display: grid; place-items: center;
      background: linear-gradient(135deg, rgba(247,185,85,.22), rgba(125,211,252,.14));
      border: 1px solid rgba(247,185,85,.28); color: var(--accent); font-weight: 800; font-size: 1.1rem;
    }
    .card h3 { margin: 14px 0 4px; font-size: 1.02rem; line-height: 1.25; }
    .meta { color: var(--muted); font-size: .82rem; line-height: 1.5; }
    .rarity { color: var(--accent); letter-spacing: .08em; font-size: .82rem; }
    .footer { margin-top: 42px; color: var(--muted); font-size: .82rem; line-height: 1.7; }
    .footer code { color: var(--accent-2); }
    .empty { padding: 40px; text-align: center; color: var(--muted); border: 1px dashed var(--border); border-radius: 18px; }
    @media (max-width: 900px) { .stats { grid-template-columns: repeat(3, minmax(0, 1fr)); } }
    @media (max-width: 560px) {
      main { padding: 30px 16px 60px; }
      .stats { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .search { flex-direction: column; }
      .search button { padding: 14px 18px; }
    }
  </style>
</head>
<body>
<main>
  <header>
    <div>
      <h1>Relic <span>Vault</span></h1>
      <p class="lede">
        A read-heavy catalog served by Relic, backed by SQLite, and protected by
        <strong>pepper</strong>. Search the vault and watch the cache counters move.
      </p>
    </div>
    <div class="badge"><span class="dot"></span><span id="cache-status">cache connecting…</span></div>
  </header>

  <form class="search" id="search-form">
    <input id="q" type="search" placeholder="Search relics, materials, cultures…" autocomplete="off">
    <button type="submit">Search</button>
    <button type="button" class="ghost" id="purge">Clear cache</button>
  </form>

  <section class="stats" id="stats">
    <div class="stat"><div class="label">Requests</div><div class="value" id="requests">—</div><div class="sub">HTTP handled</div></div>
    <div class="stat"><div class="label">DB queries</div><div class="value" id="db-queries">—</div><div class="sub">SQLite reads + writes</div></div>
    <div class="stat"><div class="label">Detail hit rate</div><div class="value" id="detail-rate">—</div><div class="sub" id="detail-counts">no lookups yet</div></div>
    <div class="stat"><div class="label">Search hit rate</div><div class="value" id="search-rate">—</div><div class="sub" id="search-counts">no lookups yet</div></div>
    <div class="stat"><div class="label">Cache entries</div><div class="value" id="entries">—</div><div class="sub" id="missing-entries">negative cache —</div></div>
    <div class="stat"><div class="label">RSS</div><div class="value" id="rss">—</div><div class="sub">resident memory</div></div>
  </section>

  <div class="section-head">
    <h2>Catalog</h2>
    <span class="meta" id="result-count"></span>
  </div>
  <section class="grid" id="results"></section>

  <p class="footer">
    Run with <code>dart run bin/server.dart --db=data/relics.db</code>.
    The API lives at <code>/api/relics</code> and stats at <code>/api/cache/stats</code>.
    Cache entries are encoded JSON, so hits skip both SQLite and serialization.
  </p>
</main>
<script>
  const $ = (selector) => document.querySelector(selector);
  const number = new Intl.NumberFormat();

  function pct(value) {
    return `${(value * 100).toFixed(1)}%`;
  }

  function mb(bytes) {
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  }

  function esc(value) {
    return String(value).replace(/[&<>"']/g, (character) => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#39;',
    })[character]);
  }

  async function getJson(url, options) {
    const response = await fetch(url, options);
    if (!response.ok) {
      throw new Error(`${response.status} ${await response.text()}`);
    }
    return response.json();
  }

  function renderStats(stats) {
    const cache = stats.cache;
    const detail = cache.detail;
    const search = cache.search;
    $('#requests').textContent = number.format(stats.requests);
    $('#db-queries').textContent = number.format(stats.dbQueries);
    $('#rss').textContent = mb(stats.rssBytes);
    if (!cache.enabled || !detail) {
      $('#cache-status').textContent = 'cache disabled';
      $('#detail-rate').textContent = 'off';
      $('#search-rate').textContent = 'off';
      $('#entries').textContent = '0';
      $('#missing-entries').textContent = 'cache disabled';
      return;
    }
    $('#cache-status').textContent = `${cache.algorithm.toUpperCase()} · ${number.format(cache.capacity)} detail entries`;
    $('#detail-rate').textContent = pct(detail.hitRate);
    $('#detail-counts').textContent = `${number.format(detail.hits)} hits / ${number.format(detail.misses)} misses`;
    $('#search-rate').textContent = pct(search.hitRate);
    $('#search-counts').textContent = `${number.format(search.hits)} hits / ${number.format(search.misses)} misses`;
    $('#entries').textContent = number.format(detail.length + search.length);
    $('#missing-entries').textContent = `negative cache ${number.format(detail.missingLength)}`;
  }

  function renderRelics(relics) {
    const root = $('#results');
    $('#result-count').textContent = `${number.format(relics.length)} result${relics.length === 1 ? '' : 's'}`;
    if (!relics.length) {
      root.innerHTML = '<div class="empty">No relics matched that search. Try “gold”, “jade”, or “Roman”.</div>';
      return;
    }
    root.innerHTML = relics.map((relic) => {
      const stars = '★'.repeat(relic.rarity) + '☆'.repeat(Math.max(0, 5 - relic.rarity));
      const initial = relic.name.trim().charAt(0).toUpperCase() || 'R';
      return `
        <article class="card">
          <div class="glyph">${esc(initial)}</div>
          <h3>${esc(relic.name)}</h3>
          <div class="rarity">${stars}</div>
          <div class="meta">${esc(relic.culture)} · ${esc(relic.era)}</div>
          <div class="meta">${esc(relic.material)} · recovered ${esc(relic.discoveredYear)}</div>
          <div class="meta">${esc(relic.discoverySite)}</div>
        </article>`;
    }).join('');
  }

  async function refreshStats() {
    try {
      renderStats(await getJson('/api/cache/stats'));
    } catch (error) {
      $('#cache-status').textContent = 'stats unavailable';
      console.error(error);
    }
  }

  async function search() {
    const query = encodeURIComponent($('#q').value.trim());
    try {
      renderRelics(await getJson(`/api/relics?q=${query}&limit=24`));
      await refreshStats();
    } catch (error) {
      $('#results').innerHTML = `<div class="empty">Search failed: ${error.message}</div>`;
    }
  }

  $('#search-form').addEventListener('submit', (event) => {
    event.preventDefault();
    search();
  });

  $('#purge').addEventListener('click', async () => {
    try {
      await getJson('/api/cache/purge', { method: 'POST' });
      await search();
    } catch (error) {
      console.error(error);
    }
  });

  search();
  setInterval(refreshStats, 3000);
</script>
</body>
</html>
''';
