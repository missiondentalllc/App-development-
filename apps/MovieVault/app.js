/* Movie Vault — browse every movie, track upcoming releases, rate, get recommendations.
   Data: The Movie Database (TMDB) API. All personal data stays in this browser (localStorage). */
'use strict';

const API = 'https://api.themoviedb.org/3';
const IMG = 'https://image.tmdb.org/t/p/';
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];

// ---------- storage ----------
const store = {
  get(k, d) { try { const v = localStorage.getItem('mv.' + k); return v == null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem('mv.' + k, JSON.stringify(v)); } catch {} },
  del(k) { try { localStorage.removeItem('mv.' + k); } catch {} },
};

const state = {
  key: store.get('key', ''),
  region: store.get('region', 'US'),
  ratings: store.get('ratings', {}),     // id -> {stars, title, poster, date, genres, directors, cast, keywords, ratedAt}
  hidden: store.get('hidden', {}),       // id -> {title} (not interested)
  follows: store.get('follows', {}),     // id -> {title, poster, date, notified}
  genres: {},                            // id -> name
  view: store.get('view', 'grid'),
  browse: { page: 0, total: 1, loading: false, items: [], seq: 0 },
  upcoming: { page: 0, total: 1 },
};
const save = () => {
  store.set('ratings', state.ratings); store.set('hidden', state.hidden); store.set('follows', state.follows);
};

// ---------- helpers ----------
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const today = () => new Date().toISOString().slice(0, 10);
const addDays = (d, n) => { const x = new Date(d + 'T00:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
const year = d => (d || '').slice(0, 4) || '—';
const fmtDate = d => d ? new Date(d + 'T00:00:00').toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' }) : 'Unknown';
const money = (n, compact = true) => !n ? 'n/a' : new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', notation: compact ? 'compact' : 'standard', maximumFractionDigits: compact ? 1 : 0 }).format(n);
const pop = n => n == null ? '—' : Math.round(n).toLocaleString();
const daysUntil = d => Math.round((new Date(d + 'T00:00:00') - new Date(today() + 'T00:00:00')) / 864e5);
const poster = (p, size = 'w185') => p ? IMG + size + p : '';
const genreNames = ids => (ids || []).map(id => state.genres[id]).filter(Boolean);

// ---------- TMDB client ----------
const cache = new Map();
async function api(path, params = {}) {
  if (!state.key) throw new Error('NO_KEY');
  const url = new URL(API + path);
  const isToken = state.key.length > 40; // v4 read-access token (JWT) vs v3 key
  if (!isToken) url.searchParams.set('api_key', state.key);
  for (const [k, v] of Object.entries(params)) if (v !== '' && v != null) url.searchParams.set(k, v);
  const ck = url.toString();
  if (cache.has(ck)) return cache.get(ck);
  const p = fetch(ck, { headers: isToken ? { Authorization: 'Bearer ' + state.key, accept: 'application/json' } : {} })
    .then(async r => {
      if (r.status === 429) { await new Promise(res => setTimeout(res, 1200)); cache.delete(ck); return api(path, params); }
      if (!r.ok) throw new Error(r.status === 401 ? 'BAD_KEY' : 'HTTP ' + r.status);
      return r.json();
    });
  cache.set(ck, p);
  p.catch(() => cache.delete(ck));
  return p;
}
const details = id => api('/movie/' + id);
const fullDetails = id => api('/movie/' + id, { append_to_response: 'credits,keywords,recommendations,videos' });

// small concurrency limiter for background detail lookups (box office numbers)
const queue = { running: 0, jobs: [] };
function enqueue(fn) {
  return new Promise((res, rej) => { queue.jobs.push({ fn, res, rej }); pump(); });
}
function pump() {
  while (queue.running < 6 && queue.jobs.length) {
    const { fn, res, rej } = queue.jobs.shift();
    queue.running++;
    fn().then(res, rej).finally(() => { queue.running--; pump(); });
  }
}

function needKey(el) {
  el.innerHTML = `<div class="empty">Add your free movie database key in <a href="#" data-goto="settings">Settings</a> to load movies.</div>`;
}

// ---------- rendering: cards & table ----------
function card(m, opts = {}) {
  const r = state.ratings[m.id];
  const isFuture = m.release_date && m.release_date > today();
  const followed = !!state.follows[m.id];
  const g = genreNames(m.genre_ids || (m.genres || []).map(x => x.id)).slice(0, 2);
  let badge = '';
  if (r) badge = `<span class="badge">${'★'.repeat(r.stars)}</span>`;
  else if (opts.score != null) badge = `<span class="badge">${opts.score}% match</span>`;
  const sub = isFuture
    ? `${fmtDate(m.release_date)} · ${daysUntil(m.release_date) === 0 ? 'today' : 'in ' + daysUntil(m.release_date) + ' days'}`
    : `${year(m.release_date)}${g.length ? ' · ' + esc(g.join(', ')) : ''}`;
  return `<div class="movie" data-id="${m.id}">
    ${badge}
    ${isFuture || followed ? `<button class="bell" data-follow="${m.id}" title="${followed ? 'Stop watching' : 'Alert me when released'}">${followed ? '🔔' : '🔕'}</button>` : ''}
    ${m.poster_path ? `<img class="poster" loading="lazy" src="${poster(m.poster_path)}" alt="">` : `<div class="noposter">${esc(m.title)}</div>`}
    <div class="meta">
      <div class="title">${esc(m.title)}</div>
      <div class="sub">${sub}</div>
      ${opts.noStats ? '' : `<div class="stats"><span title="Popularity">🔥 ${pop(m.popularity)}</span><span title="Worldwide gross" data-gross="${m.id}">${m.revenue != null ? '💰 ' + money(m.revenue) : '💰 …'}</span></div>`}
      ${opts.why ? `<div class="why">${esc(opts.why)}</div>` : ''}
    </div>
  </div>`;
}

const COLS = [
  { key: 'thumb', label: '' },
  { key: 'title', label: 'Title', sort: 'title.asc' },
  { key: 'genre', label: 'Genre' },
  { key: 'date', label: 'Release date', sort: 'primary_release_date.desc' },
  { key: 'pop', label: 'Popularity', sort: 'popularity.desc', num: true },
  { key: 'gross', label: 'Total gross', sort: 'revenue.desc', num: true },
  { key: 'mine', label: 'My rating' },
];
function table(items) {
  const cur = $('#sort').value;
  const searching = !!$('#q').value.trim();
  return `<div class="tablewrap"><table><thead><tr>${COLS.map(c =>
    `<th class="${c.num ? 'num' : ''} ${c.sort && c.sort.split('.')[0] === cur.split('.')[0] && !searching ? 'sorted' : ''}" ${c.sort ? `data-sortcol="${c.sort}"` : ''}>${c.label}</th>`).join('')}
    </tr></thead><tbody>${items.map(row).join('')}</tbody></table></div>`;
}
function row(m) {
  const r = state.ratings[m.id];
  return `<tr class="row" data-id="${m.id}">
    <td>${m.poster_path ? `<img class="thumb" loading="lazy" src="${poster(m.poster_path, 'w92')}" alt="">` : '<div class="thumb"></div>'}</td>
    <td><b>${esc(m.title)}</b></td>
    <td>${esc(genreNames(m.genre_ids).join(', '))}</td>
    <td>${fmtDate(m.release_date)}</td>
    <td class="num">${pop(m.popularity)}</td>
    <td class="num" data-gross="${m.id}" data-full="1">${m.revenue != null ? money(m.revenue, false) : '…'}</td>
    <td>${r ? '★'.repeat(r.stars) : ''}</td>
  </tr>`;
}

// Fill in box-office totals (only available from the per-movie detail endpoint)
const grossObserver = 'IntersectionObserver' in window ? new IntersectionObserver(entries => {
  for (const e of entries) {
    if (!e.isIntersecting) continue;
    const el = e.target; grossObserver.unobserve(el);
    const id = el.dataset.gross;
    enqueue(() => details(id)).then(d => {
      $$(`[data-gross="${id}"]`).forEach(x => { x.textContent = x.dataset.full ? money(d.revenue, false) : '💰 ' + money(d.revenue); });
    }).catch(() => { el.textContent = el.dataset.full ? 'n/a' : '💰 n/a'; });
  }
}, { rootMargin: '200px' }) : null;
function watchGross(root) {
  if (!grossObserver || !state.key) return;
  $$('[data-gross]', root).forEach(el => { if (el.textContent.includes('…')) grossObserver.observe(el); });
}

// ---------- BROWSE ----------
function browseParams() {
  const sort = $('#sort').value, g = $('#genre').value;
  const yf = $('#yearFrom').value, yt = $('#yearTo').value;
  const p = { sort_by: sort, with_genres: g, include_adult: false, page: state.browse.page + 1 };
  if (yf) p['primary_release_date.gte'] = yf + '-01-01';
  if (yt) p['primary_release_date.lte'] = yt + '-12-31';
  if ($('#releasedOnly').checked) {
    const lte = p['primary_release_date.lte'];
    p['primary_release_date.lte'] = lte && lte < today() ? lte : today();
  }
  if (sort.startsWith('vote_average')) p['vote_count.gte'] = 300;
  if (sort.startsWith('title') || sort.startsWith('primary_release_date')) p['vote_count.gte'] = p['vote_count.gte'] || 5; // skip empty placeholder entries
  return p;
}
function resetBrowse() {
  state.browse = { page: 0, total: 1, loading: false, items: [], seq: state.browse.seq + 1 };
  $('#browseResults').innerHTML = '';
  loadBrowse();
}
async function loadBrowse() {
  const b = state.browse;
  if (b.loading || b.page >= b.total) return;
  if (!state.key) { needKey($('#browseResults')); $('#browseInfo').textContent = ''; return; }
  b.loading = true;
  const seq = b.seq, q = $('#q').value.trim();
  $('#browseInfo').textContent = 'Loading…';
  try {
    let data;
    if (q) {
      data = await api('/search/movie', { query: q, include_adult: false, page: b.page + 1, primary_release_year: $('#yearFrom').value && $('#yearFrom').value === $('#yearTo').value ? $('#yearFrom').value : '' });
      const g = +$('#genre').value;
      if (g) data.results = data.results.filter(m => (m.genre_ids || []).includes(g));
    } else {
      data = await api('/discover/movie', browseParams());
    }
    if (seq !== state.browse.seq) return; // filters changed meanwhile
    b.page = data.page; b.total = Math.min(data.total_pages, 500);
    const fresh = data.results.filter(m => !state.hidden[m.id] && !b.items.some(x => x.id === m.id));
    b.items.push(...fresh);
    renderBrowse();
    const capped = data.total_pages > 500 && !q ? ' (narrow by year or genre to reach every one of them)' : '';
    $('#browseInfo').textContent = `${data.total_results.toLocaleString()} movies${capped} · showing ${b.items.length.toLocaleString()}`;
  } catch (e) {
    $('#browseInfo').textContent = errMsg(e);
  } finally { b.loading = false; }
}
function renderBrowse() {
  const el = $('#browseResults'), items = state.browse.items;
  if (!items.length) { el.innerHTML = '<div class="empty">No movies match.</div>'; return; }
  el.innerHTML = state.view === 'table' ? table(items) : `<div class="grid">${items.map(m => card(m)).join('')}</div>`;
  watchGross(el);
}
function errMsg(e) {
  if (e.message === 'BAD_KEY') return 'The movie database rejected your key. Check it in Settings.';
  if (e.message === 'NO_KEY') return 'Add your movie database key in Settings.';
  return 'Could not reach the movie database (' + e.message + '). Check your connection and try again.';
}

// ---------- MOVIE DETAIL ----------
async function openMovie(id) {
  const dlg = $('#modal'), body = $('#modalBody');
  body.innerHTML = '<p class="info" style="padding:30px">Loading…</p>';
  if (!dlg.open) dlg.showModal();
  try {
    const m = await fullDetails(id);
    const director = (m.credits?.crew || []).filter(c => c.job === 'Director');
    const cast = (m.credits?.cast || []).slice(0, 8);
    const trailer = (m.videos?.results || []).find(v => v.site === 'YouTube' && v.type === 'Trailer');
    const rec = (m.recommendations?.results || []).filter(x => !state.hidden[x.id]).slice(0, 12);
    const r = state.ratings[id];
    const future = m.release_date && m.release_date > today();
    body.innerHTML = `
      <div class="hero" style="background-image:url('${m.backdrop_path ? IMG + 'w780' + m.backdrop_path : ''}')"></div>
      <div class="detail">
        ${m.poster_path ? `<img class="poster" src="${poster(m.poster_path, 'w342')}" alt="">` : ''}
        <div style="flex:1;min-width:0">
          <h2>${esc(m.title)} <small style="color:var(--muted)">(${year(m.release_date)})</small></h2>
          ${m.tagline ? `<p class="info"><i>${esc(m.tagline)}</i></p>` : ''}
          <div class="chips">${(m.genres || []).map(g => `<span class="chip">${esc(g.name)}</span>`).join('')}</div>
          <div class="facts">
            <div class="fact"><b>Release date</b>${fmtDate(m.release_date)}${future ? ` (in ${daysUntil(m.release_date)} days)` : ''}</div>
            <div class="fact"><b>Worldwide gross</b>${money(m.revenue, false)}</div>
            <div class="fact"><b>Budget</b>${money(m.budget, false)}</div>
            <div class="fact"><b>Popularity</b>${pop(m.popularity)}</div>
            <div class="fact"><b>Audience score</b>${m.vote_count ? (m.vote_average).toFixed(1) + '/10 (' + m.vote_count.toLocaleString() + ' votes)' : 'n/a'}</div>
            <div class="fact"><b>Runtime</b>${m.runtime ? Math.floor(m.runtime / 60) + 'h ' + (m.runtime % 60) + 'm' : 'n/a'}</div>
            <div class="fact"><b>Director</b>${esc(director.map(d => d.name).join(', ') || 'n/a')}</div>
          </div>
          <p>${esc(m.overview || 'No summary available.')}</p>
          ${cast.length ? `<p class="small"><b>Starring:</b> ${esc(cast.map(c => c.name).join(', '))}</p>` : ''}
          <div class="stars" id="starBox">
            ${[1, 2, 3, 4, 5].map(n => `<button class="star ${r && r.stars >= n ? 'on' : ''}" data-star="${n}" title="${n} star${n > 1 ? 's' : ''}">★</button>`).join('')}
            <span class="lbl">${r ? 'Your rating' : future ? 'Rate it after you see it' : 'Tap to rate'}</span>
          </div>
          <div class="actions">
            ${r ? '<button class="btn" id="clearRating">Clear rating</button>' : ''}
            <button class="btn" id="hideBtn">${state.hidden[id] ? 'Show again in lists' : '👎 Not interested'}</button>
            ${future || state.follows[id] ? `<button class="btn" id="followBtn">${state.follows[id] ? '🔔 Watching — stop' : '🔕 Alert me when released'}</button>` : ''}
            ${trailer ? `<a class="btn" target="_blank" rel="noopener" href="https://www.youtube.com/watch?v=${encodeURIComponent(trailer.key)}">▶ Trailer</a>` : ''}
            <a class="btn" target="_blank" rel="noopener" href="https://www.themoviedb.org/movie/${m.id}">Where to watch</a>
          </div>
        </div>
      </div>
      ${rec.length ? `<div class="related"><h2>More like this</h2><div class="grid">${rec.map(x => card(x, { noStats: true })).join('')}</div></div>` : ''}`;
    $$('[data-star]', body).forEach(b => b.onclick = () => { rate(m, +b.dataset.star); openMovie(id); });
    $('#clearRating', body)?.addEventListener('click', () => { delete state.ratings[id]; save(); refreshAfterChange(); openMovie(id); });
    $('#hideBtn', body).onclick = () => {
      if (state.hidden[id]) delete state.hidden[id]; else state.hidden[id] = { title: m.title };
      save(); refreshAfterChange(); openMovie(id);
    };
    $('#followBtn', body)?.addEventListener('click', () => { toggleFollow(m); openMovie(id); });
    body.scrollTop = 0; dlg.scrollTop = 0;
  } catch (e) {
    body.innerHTML = `<p class="info" style="padding:30px">${esc(errMsg(e))}</p>`;
  }
}

function rate(m, stars) {
  state.ratings[m.id] = {
    stars, title: m.title, poster: m.poster_path, date: m.release_date, popularity: m.popularity, revenue: m.revenue,
    genres: (m.genres || []).map(g => g.id),
    directors: (m.credits?.crew || []).filter(c => c.job === 'Director').map(c => ({ id: c.id, name: c.name })),
    cast: (m.credits?.cast || []).slice(0, 5).map(c => ({ id: c.id, name: c.name })),
    keywords: (m.keywords?.keywords || []).slice(0, 15).map(k => ({ id: k.id, name: k.name })),
    recs: (m.recommendations?.results || []).slice(0, 20).map(x => x.id),
    ratedAt: Date.now(),
  };
  delete state.hidden[m.id];
  save();
  store.del('recs'); // profile changed → recompute next time
  refreshAfterChange();
}

function refreshAfterChange() {
  const active = $('.tab.active').id;
  if (active === 'tab-browse') renderBrowse();
  renderRatings(); renderFollowed(); renderSummary();
}

// ---------- COMING SOON + ALERTS ----------
function toggleFollow(m) {
  if (state.follows[m.id]) delete state.follows[m.id];
  else state.follows[m.id] = { title: m.title, poster: m.poster_path, date: m.release_date, notified: false };
  save();
  $$(`[data-follow="${m.id}"]`).forEach(b => { b.textContent = state.follows[m.id] ? '🔔' : '🔕'; });
  renderFollowed();
}
function renderFollowed() {
  const el = $('#followedList');
  const list = Object.entries(state.follows).map(([id, f]) => ({ id: +id, title: f.title, poster_path: f.poster, release_date: f.date }))
    .sort((a, b) => (a.release_date || '9999').localeCompare(b.release_date || '9999'));
  el.innerHTML = list.length ? list.map(m => card(m, { noStats: true })).join('')
    : '<div class="empty">Nothing yet. Tap 🔕 on a movie below to get an alert when it comes out.</div>';
}
async function loadUpcoming(more = false) {
  const el = $('#upcomingList');
  if (!state.key) { needKey(el); $('#newReleases').innerHTML = ''; $('#upcomingMore').hidden = true; return; }
  if (!more) { state.upcoming = { page: 0, total: 1 }; el.innerHTML = ''; loadNewReleases(); }
  if (state.upcoming.page >= state.upcoming.total) return;
  try {
    const data = await api('/discover/movie', {
      'primary_release_date.gte': addDays(today(), 1), 'primary_release_date.lte': addDays(today(), 365),
      sort_by: 'popularity.desc', include_adult: false, region: state.region, with_release_type: state.region ? '2|3' : '',
      page: state.upcoming.page + 1,
    });
    state.upcoming.page = data.page; state.upcoming.total = Math.min(data.total_pages, 500);
    const profile = buildProfile();
    el.insertAdjacentHTML('beforeend', data.results.filter(m => !state.hidden[m.id]).map(m => {
      const s = profile.n ? quickScore(m, profile) : null;
      return card(m, { noStats: true, why: s != null && s >= 70 ? `Fits your taste (${s}%)` : '' });
    }).join(''));
    $('#upcomingCount').textContent = `(${data.total_results.toLocaleString()} in the next year)`;
    $('#upcomingMore').hidden = state.upcoming.page >= state.upcoming.total;
  } catch (e) { el.innerHTML = `<div class="empty">${esc(errMsg(e))}</div>`; }
}
async function loadNewReleases() {
  const el = $('#newReleases');
  try {
    const data = await api('/discover/movie', {
      'primary_release_date.gte': addDays(today(), -14), 'primary_release_date.lte': today(),
      sort_by: 'popularity.desc', include_adult: false, region: state.region, with_release_type: state.region ? '2|3' : '',
    });
    el.innerHTML = data.results.filter(m => !state.hidden[m.id]).slice(0, 12).map(m => card(m, { noStats: true })).join('')
      || '<div class="empty">No new releases found.</div>';
  } catch (e) { el.innerHTML = `<div class="empty">${esc(errMsg(e))}</div>`; }
}

// Check followed movies: refresh their release dates (they move), and alert when one is out.
async function checkFollows() {
  if (!state.key) return;
  const out = [];
  for (const [id, f] of Object.entries(state.follows)) {
    try {
      const d = await details(id);
      let date = d.release_date;
      if (state.region) {
        // prefer the theatrical/digital date for the chosen country
        const rd = await api(`/movie/${id}/release_dates`).catch(() => null);
        const local = rd?.results?.find(x => x.iso_3166_1 === state.region)?.release_dates
          ?.filter(x => [2, 3, 4].includes(x.type)).map(x => x.release_date.slice(0, 10)).sort()[0];
        if (local) date = local;
      }
      f.date = date || f.date; f.poster = d.poster_path || f.poster; f.title = d.title || f.title;
    } catch {}
    if (f.date && f.date <= today() && !f.notified) out.push({ id, ...f });
  }
  save(); renderFollowed();
  if (!out.length) return;
  const box = $('#alerts');
  box.hidden = false;
  box.innerHTML = `🎉 Now released: ${out.map(f => `<a href="#" data-open="${f.id}" style="color:inherit">${esc(f.title)}</a>`).join(', ')}
    <button class="btn" id="dismissAlerts">Got it</button>`;
  $('#dismissAlerts').onclick = () => { out.forEach(f => { state.follows[f.id].notified = true; }); save(); box.hidden = true; };
  if ('Notification' in window && Notification.permission === 'granted') {
    out.forEach(f => { try { new Notification('Now released: ' + f.title, { icon: poster(f.poster) || 'icon.svg' }); } catch {} });
  }
}

// ---------- MY RATINGS ----------
function renderRatings() {
  const el = $('#ratingsList'), by = $('#ratingsSort').value;
  const list = Object.entries(state.ratings).map(([id, r]) => ({ id: +id, ...r }));
  const cmp = {
    ratedAt: (a, b) => b.ratedAt - a.ratedAt,
    stars: (a, b) => b.stars - a.stars || b.ratedAt - a.ratedAt,
    title: (a, b) => a.title.localeCompare(b.title),
    date: (a, b) => (b.date || '').localeCompare(a.date || ''),
  }[by];
  list.sort(cmp);
  const avg = list.length ? (list.reduce((s, r) => s + r.stars, 0) / list.length).toFixed(1) : 0;
  $('#ratingsInfo').textContent = list.length ? `${list.length} movies rated · average ${avg} stars · ${Object.keys(state.hidden).length} marked not interested` : '';
  el.innerHTML = list.length ? list.map(r => card({ id: r.id, title: r.title, poster_path: r.poster, release_date: r.date, genre_ids: r.genres }, { noStats: true })).join('')
    : '<div class="empty">You haven\'t rated anything yet. Open any movie and tap the stars. The more you rate, the better your recommendations get.</div>';
}

// ---------- RECOMMENDATIONS ----------
// Taste profile: each rated movie pushes its features up (4–5★) or down (1–2★).
function buildProfile() {
  const f = {}, names = {}, cnt = {};
  const add = (k, w, name) => { f[k] = (f[k] || 0) + w; cnt[k] = (cnt[k] || 0) + 1; if (name) names[k] = name; };
  const rated = Object.values(state.ratings);
  for (const r of rated) {
    const w = r.stars - 3; // 5★ = +2, 4★ = +1, 3★ = 0, 2★ = -1, 1★ = -2
    if (!w) continue;
    (r.genres || []).forEach(g => add('g' + g, w, state.genres[g]));
    (r.directors || []).forEach(d => add('d' + d.id, w * 1.5, d.name));
    (r.cast || []).forEach(c => add('c' + c.id, w * 0.6, c.name));
    (r.keywords || []).forEach(k => add('k' + k.id, w * 0.5, k.name));
    if (r.date) add('y' + r.date.slice(0, 3), w * 0.4, r.date.slice(0, 3) + '0s');
  }
  for (const k in f) f[k] /= Math.sqrt(cnt[k]); // repeated features count, but with diminishing returns
  return { f, names, n: rated.length };
}
function scoreFeatures(feats, profile) {
  let s = 0; const hits = [];
  for (const k of feats) { const v = profile.f[k]; if (v) { s += v; if (v > 0) hits.push([v, k]); } }
  hits.sort((a, b) => b[0] - a[0]);
  return { s, hits: hits.map(h => h[1]) };
}
const toPct = raw => Math.max(1, Math.min(99, Math.round(100 / (1 + Math.exp(-raw / 2.5)))));
function quickScore(m, profile) {
  const feats = (m.genre_ids || []).map(g => 'g' + g);
  if (m.release_date) feats.push('y' + m.release_date.slice(0, 3));
  return toPct(scoreFeatures(feats, profile).s);
}
function featuresOf(d) {
  return [
    ...(d.genres || []).map(g => 'g' + g.id),
    ...(d.credits?.crew || []).filter(c => c.job === 'Director').map(c => 'd' + c.id),
    ...(d.credits?.cast || []).slice(0, 8).map(c => 'c' + c.id),
    ...(d.keywords?.keywords || []).slice(0, 20).map(k => 'k' + k.id),
    ...(d.release_date ? ['y' + d.release_date.slice(0, 3)] : []),
  ];
}

async function computeRecs() {
  const status = $('#recsStatus'), list = $('#recsList');
  if (!state.key) { needKey(list); return; }
  const rated = Object.entries(state.ratings).map(([id, r]) => ({ id: +id, ...r }));
  if (!rated.length) {
    list.innerHTML = '<div class="empty">Rate a few movies (open any movie and tap the stars) and your picks will show up here. 5–10 ratings is a good start.</div>';
    renderTaste(); return;
  }
  $('#recsRefresh').disabled = true;
  status.textContent = 'Studying your ratings…';
  const profile = buildProfile();
  renderTaste(profile);
  const liked = rated.filter(r => r.stars >= 4).sort((a, b) => b.stars - a.stars || b.ratedAt - a.ratedAt).slice(0, 12);
  const seeds = liked.length ? liked : rated.sort((a, b) => b.stars - a.stars).slice(0, 5);
  const cand = new Map(); // id -> {m, from:Set(titles)}
  const addC = (m, from) => {
    if (state.ratings[m.id] || state.hidden[m.id] || !m.release_date || m.release_date > today()) return;
    const c = cand.get(m.id) || { m, from: new Set() };
    if (from) c.from.add(from);
    cand.set(m.id, c);
  };
  try {
    // 1) "People who liked X also liked" lists for each movie you loved
    await Promise.all(seeds.map(s => enqueue(() => api(`/movie/${s.id}/recommendations`)).then(d => d.results.forEach(m => addC(m, s.title))).catch(() => {})));
    // 2) Top-rated movies in your favorite genres
    const favG = Object.entries(profile.f).filter(([k, v]) => k[0] === 'g' && v > 0).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([k]) => k.slice(1));
    await Promise.all(favG.map(g => api('/discover/movie', { with_genres: g, sort_by: 'vote_average.desc', 'vote_count.gte': 1000, include_adult: false })
      .then(d => d.results.forEach(m => addC(m, null))).catch(() => {})));
    // 3) More from directors you rate highly
    const favD = Object.entries(profile.f).filter(([k, v]) => k[0] === 'd' && v > 0).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([k]) => k.slice(1));
    await Promise.all(favD.map(d => api('/discover/movie', { with_crew: d, sort_by: 'vote_average.desc', 'vote_count.gte': 100 })
      .then(r => r.results.forEach(m => addC(m, null))).catch(() => {})));

    // Pre-rank cheaply, then fetch full details (director, cast, keywords) for the best 60
    status.textContent = `Scoring ${cand.size} candidates…`;
    const pre = [...cand.values()].map(c => ({ ...c, pre: scoreFeatures((c.m.genre_ids || []).map(g => 'g' + g), profile).s + c.from.size * 1.2 + ((c.m.vote_average || 6) - 6) * 0.4 }))
      .sort((a, b) => b.pre - a.pre).slice(0, 60);
    const scored = await Promise.all(pre.map(c => enqueue(() => api('/movie/' + c.m.id, { append_to_response: 'credits,keywords' })).then(d => {
      const { s, hits } = scoreFeatures(featuresOf(d), profile);
      const quality = d.vote_count > 50 ? (d.vote_average - 6.5) * 0.6 : -0.5;
      const raw = s + Math.log2(1 + c.from.size) * 1.5 + quality;
      const because = [...c.from][0];
      const why = because ? `Because you liked ${because}` : hits.length ? 'Matches: ' + hits.slice(0, 2).map(k => profile.names[k]).filter(Boolean).join(', ') : '';
      return { m: { ...d, genre_ids: (d.genres || []).map(g => g.id) }, raw, why };
    }).catch(() => null)));
    const recs = scored.filter(Boolean).sort((a, b) => b.raw - a.raw).slice(0, 40)
      .map(r => ({ m: { id: r.m.id, title: r.m.title, poster_path: r.m.poster_path, release_date: r.m.release_date, genre_ids: r.m.genre_ids, popularity: r.m.popularity, revenue: r.m.revenue }, score: toPct(r.raw), why: r.why }));
    store.set('recs', { at: Date.now(), recs });
    renderRecs(recs);
    status.textContent = `Based on ${rated.length} rating${rated.length > 1 ? 's' : ''} · updated just now`;
  } catch (e) {
    status.textContent = errMsg(e);
  } finally { $('#recsRefresh').disabled = false; }
}
function renderRecs(recs) {
  $('#recsList').innerHTML = recs.length ? recs.filter(r => !state.ratings[r.m.id] && !state.hidden[r.m.id]).map(r => card(r.m, { score: r.score, why: r.why })).join('')
    : '<div class="empty">No recommendations yet — try rating a few more movies.</div>';
}
function renderTaste(profile = buildProfile()) {
  const el = $('#tasteProfile');
  if (!profile.n) { el.innerHTML = ''; return; }
  const group = (prefix, title) => {
    const items = Object.entries(profile.f).filter(([k, v]) => k[0] === prefix && Math.abs(v) > 0.01).sort((a, b) => Math.abs(b[1]) - Math.abs(a[1])).slice(0, 6);
    if (!items.length) return '';
    const max = Math.max(...items.map(i => Math.abs(i[1])));
    return `<div class="card"><h3>${title}</h3>${items.map(([k, v]) => `<div class="bar"><span>${esc(profile.names[k] || '?')}</span><span class="track"><span class="fill ${v < 0 ? 'neg' : ''}" style="width:${Math.round(Math.abs(v) / max * 100)}%"></span></span></div>`).join('')}</div>`;
  };
  el.innerHTML = group('g', 'Genres you like (red = dislike)') + group('d', 'Directors') + group('c', 'Actors') + group('k', 'Themes');
}
function showForYou() {
  const cached = store.get('recs', null);
  renderTaste();
  if (cached && cached.recs?.length && Date.now() - cached.at < 864e5) {
    renderRecs(cached.recs);
    $('#recsStatus').textContent = `Updated ${new Date(cached.at).toLocaleString()}`;
  } else computeRecs();
}

// ---------- SETTINGS ----------
function renderSummary() {
  $('#dataSummary').textContent = `${Object.keys(state.ratings).length} ratings, ${Object.keys(state.follows).length} release alerts, ${Object.keys(state.hidden).length} hidden movies are saved on this device. Use "Export backup" on My Ratings to keep a copy.`;
  const n = $('#notifyBtn');
  if (!('Notification' in window)) { n.textContent = 'Notifications not supported here'; n.disabled = true; }
  else if (Notification.permission === 'granted') { n.textContent = 'Notifications on ✓'; n.disabled = true; }
}
async function loadGenres() {
  try {
    const d = await api('/genre/movie/list');
    d.genres.forEach(g => { state.genres[g.id] = g.name; });
    $('#genre').innerHTML = '<option value="">All genres</option>' + d.genres.map(g => `<option value="${g.id}">${esc(g.name)}</option>`).join('');
    return true;
  } catch (e) { return e; }
}

// ---------- tabs & events ----------
function showTab(name) {
  $$('.tabs button').forEach(b => b.classList.toggle('active', b.dataset.tab === name));
  $$('.tab').forEach(t => t.classList.toggle('active', t.id === 'tab-' + name));
  if (name === 'browse' && !state.browse.items.length) resetBrowse();
  if (name === 'upcoming') { renderFollowed(); if (!$('#upcomingList').children.length || !state.upcoming.page) loadUpcoming(); }
  if (name === 'ratings') renderRatings();
  if (name === 'foryou') showForYou();
  if (name === 'settings') renderSummary();
  window.scrollTo(0, 0);
}

function bind() {
  $$('.tabs button').forEach(b => b.onclick = () => showTab(b.dataset.tab));
  let t;
  $('#q').addEventListener('input', () => { clearTimeout(t); t = setTimeout(resetBrowse, 350); });
  ['#sort', '#genre', '#releasedOnly'].forEach(s => $(s).addEventListener('change', resetBrowse));
  ['#yearFrom', '#yearTo'].forEach(s => $(s).addEventListener('change', resetBrowse));
  const setView = v => { state.view = v; store.set('view', v); $('#viewGrid').classList.toggle('active', v === 'grid'); $('#viewTable').classList.toggle('active', v === 'table'); renderBrowse(); };
  $('#viewGrid').onclick = () => setView('grid'); $('#viewTable').onclick = () => setView('table');
  $('#viewGrid').classList.toggle('active', state.view === 'grid'); $('#viewTable').classList.toggle('active', state.view === 'table');

  if ('IntersectionObserver' in window) {
    new IntersectionObserver(e => { if (e[0].isIntersecting && $('#tab-browse').classList.contains('active') && state.browse.items.length) loadBrowse(); }, { rootMargin: '600px' })
      .observe($('#browseSentinel'));
  }

  // delegated clicks: open movie, follow bell, table sort, links to settings
  document.addEventListener('click', e => {
    const goto = e.target.closest('[data-goto]'); if (goto) { e.preventDefault(); $('#modal').close(); showTab(goto.dataset.goto); return; }
    const op = e.target.closest('[data-open]'); if (op) { e.preventDefault(); openMovie(+op.dataset.open); return; }
    const fb = e.target.closest('[data-follow]');
    if (fb) {
      e.stopPropagation();
      const id = +fb.dataset.follow;
      const m = state.browse.items.find(x => x.id === id) || { id, ...(state.follows[id] ? { title: state.follows[id].title, poster_path: state.follows[id].poster, release_date: state.follows[id].date } : {}) };
      if (!m.title) { details(id).then(d => toggleFollow(d)); return; }
      const card = fb.closest('.movie');
      toggleFollow({ id, title: m.title || $('.title', card)?.textContent, poster_path: m.poster_path, release_date: m.release_date });
      return;
    }
    const th = e.target.closest('[data-sortcol]');
    if (th) { $('#q').value = ''; $('#sort').value = th.dataset.sortcol; resetBrowse(); return; }
    const mv = e.target.closest('[data-id]');
    if (mv) openMovie(+mv.dataset.id);
  });
  $('#modalClose').onclick = () => $('#modal').close();
  $('#modal').addEventListener('click', e => { if (e.target.id === 'modal') $('#modal').close(); });

  $('#upcomingMore').onclick = () => loadUpcoming(true);
  $('#ratingsSort').onchange = renderRatings;
  $('#recsRefresh').onclick = computeRecs;

  $('#exportBtn').onclick = () => {
    const blob = new Blob([JSON.stringify({ app: 'MovieVault', version: 1, exported: new Date().toISOString(), ratings: state.ratings, hidden: state.hidden, follows: state.follows }, null, 2)], { type: 'application/json' });
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = `movie-vault-backup-${today()}.json`; a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  };
  $('#importFile').onchange = async e => {
    const file = e.target.files[0]; if (!file) return;
    try {
      const d = JSON.parse(await file.text());
      Object.assign(state.ratings, d.ratings || {}); Object.assign(state.hidden, d.hidden || {}); Object.assign(state.follows, d.follows || {});
      save(); store.del('recs'); refreshAfterChange();
      alert(`Imported ${Object.keys(d.ratings || {}).length} ratings.`);
    } catch { alert('That file is not a Movie Vault backup.'); }
    e.target.value = '';
  };

  $('#apiKey').value = state.key;
  $('#saveKey').onclick = async () => {
    state.key = $('#apiKey').value.trim(); store.set('key', state.key); cache.clear();
    $('#keyStatus').textContent = 'Testing…';
    const ok = await loadGenres();
    $('#keyStatus').textContent = ok === true ? '✓ Key works. Every movie is ready to browse.' : errMsg(ok);
    if (ok === true) { state.browse.items = []; state.upcoming.page = 0; $('#upcomingList').innerHTML = ''; checkFollows(); }
  };
  $('#region').value = state.region;
  $('#region').onchange = () => { state.region = $('#region').value; store.set('region', state.region); state.upcoming.page = 0; $('#upcomingList').innerHTML = ''; };
  $('#notifyBtn').onclick = async () => { if ('Notification' in window) { await Notification.requestPermission(); renderSummary(); } };
  $('#clearData').onclick = () => {
    if (!confirm('Erase all your ratings, hidden movies and release alerts on this device?')) return;
    state.ratings = {}; state.hidden = {}; state.follows = {}; save(); store.del('recs'); refreshAfterChange();
  };
}

async function init() {
  bind();
  if (!state.key) { showTab('settings'); needKey($('#browseResults')); return; }
  const ok = await loadGenres();
  if (ok !== true) { $('#keyStatus').textContent = errMsg(ok); }
  showTab('browse');
  checkFollows();
  setInterval(checkFollows, 6 * 3600e3); // re-check every 6 hours while the app stays open
}
init();
