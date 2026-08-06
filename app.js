/* ===== Webinário Pompeu · Funil — app.js ===== */
(function () {
  'use strict';
  var D = window.POMPEU;
  if (!D || !window.POMPEU_OK) { document.getElementById('views').innerHTML = '<p class="empty">Dados indisponíveis. Aguarde a próxima atualização.</p>'; return; }
  var NM = D.names;
  var arr = function (x) { return Array.isArray(x) ? x : (x == null ? [] : [x]); };
  var $ = function (s, r) { return (r || document).querySelector(s); };

  /* ---------- formatting ---------- */
  function fInt(n) { return Math.round(n || 0).toLocaleString('pt-BR'); }
  function fBRL(n) { return 'R$ ' + (n || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }
  function fBRL0(n) { return 'R$ ' + Math.round(n || 0).toLocaleString('pt-BR'); }
  function fPct(n, d) { if (n == null || !isFinite(n)) return '—'; return (n * 100).toFixed(d == null ? 1 : d).replace('.', ',') + '%'; }
  function money(n) { return (n == null || !isFinite(n)) ? '—' : fBRL(n); }
  function dfmt(iso) { if (!iso) return ''; var p = iso.split('-'); return p[2] + '/' + p[1]; }
  function dfull(iso) { if (!iso) return ''; var p = iso.split('-'); return p[2] + '/' + p[1] + '/' + p[0]; }
  function addDays(iso, n) { var d = new Date(iso + 'T00:00:00'); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); }

  /* ---------- date range over a funnel ---------- */
  function funnelRange(f) {
    var lo = null, hi = null;
    arr(f.daily).forEach(function (r) { if (!lo || r.date < lo) lo = r.date; if (!hi || r.date > hi) hi = r.date; });
    return { lo: lo, hi: hi };
  }

  /* ---------- aggregate a funnel over [lo,hi] ---------- */
  function agg(f, lo, hi) {
    var SS = D.surveyStart;
    var o = { gSp: 0, mSp: 0, gLd: 0, mLd: 0, oLd: 0, gIm: 0, mIm: 0, gCk: 0, mCk: 0, mLp: 0, mRc: 0, resp: 0, f: 0, m: 0, q: 0, qSp: 0, qLd: 0,
      gRev: 0, mRev: 0, oRev: 0, gSl: 0, mSl: 0, oSl: 0, days: {} };
    arr(f.daily).forEach(function (r) {
      if (r.date < lo || r.date > hi) return;
      if (r.p === 'g') { o.gSp += r.sp; o.gLd += r.ld; o.gIm += r.im; o.gCk += r.ck; o.gRev += r.rev || 0; o.gSl += r.sales || 0; }
      else if (r.p === 'm') { o.mSp += r.sp; o.mLd += r.ld; o.mIm += r.im; o.mCk += r.ck; o.mLp += r.lp; o.mRc += r.rc; o.mRev += r.rev || 0; o.mSl += r.sales || 0; }
      else { o.oLd += r.ld; o.oRev += r.rev || 0; o.oSl += r.sales || 0; }
      o.resp += r.rs; o.f += r.f; o.m += r.m; o.q += r.q;
      if (r.date >= SS) { o.qSp += r.sp; o.qLd += r.ld; }  // survey-era scope for qualification metrics
      var d = o.days[r.date] || (o.days[r.date] = { date: r.date, gLd: 0, mLd: 0, sp: 0, ld: 0, rev: 0 });
      if (r.p === 'g') d.gLd += r.ld; else if (r.p === 'm') d.mLd += r.ld;
      d.sp += r.sp; d.ld += r.ld; d.rev += r.rev || 0;
    });
    o.spend = o.gSp + o.mSp;
    o.leads = o.gLd + o.mLd + o.oLd;
    o.rev = o.gRev + o.mRev + o.oRev;
    o.sales = o.gSl + o.mSl + o.oSl;
    o.roas = o.spend ? o.rev / o.spend : null;
    o.gRoas = o.gSp ? o.gRev / o.gSp : null;
    o.mRoas = o.mSp ? o.mRev / o.mSp : null;
    o.ticket = o.sales ? o.rev / o.sales : null;
    o.cac = o.sales ? o.spend / o.sales : null;
    o.cpl = o.leads ? o.spend / o.leads : null;
    o.gCpl = o.gLd ? o.gSp / o.gLd : null;
    o.mCpl = o.mLd ? o.mSp / o.mLd : null;
    o.ctr = o.gIm + o.mIm ? (o.gCk + o.mCk) / (o.gIm + o.mIm) : null;
    o.cpm = (o.gIm + o.mIm) ? o.spend / ((o.gIm + o.mIm) / 1000) : null;
    // respostas contadas por DATA DA RESPOSTA (bate com a planilha ao filtrar por dia)
    o.respTotal = 0; o.respTraffic = 0;
    arr(f.survDaily).forEach(function (s) { if (s.date >= lo && s.date <= hi) { o.respTotal += s.tot; o.respTraffic += s.mat; } });
    // qualification metrics scoped to survey era (∩ period) so pre-survey days don't dilute
    o.respRate = o.qLd ? o.respTraffic / o.qLd : null;
    o.pctQ = o.resp ? o.q / o.resp : null;
    o.cplQ = o.q ? o.qSp / o.q : null;
    o.scoped = lo < SS;  // period includes pre-survey days
    o.dayArr = Object.keys(o.days).sort().map(function (k) { return o.days[k]; });
    return o;
  }

  /* ---------- tree from grain ---------- */
  function buildTree(f, plat, lo, hi) {
    var camps = {};
    arr(f.grain).forEach(function (g) {
      if (g.p !== plat) return;
      if (g.d < lo || g.d > hi) return;
      var cN = NM.c[g.c], sN = NM.s[g.s], aN = NM.a[g.a];
      var c = camps[cN] || (camps[cN] = node(cN, 0));
      accN(c, g);
      var s = c.kids[sN] || (c.kids[sN] = node(sN, 1));
      accN(s, g);
      var a = s.kids[aN] || (s.kids[aN] = node(aN, 2));
      accN(a, g);
    });
    var list = Object.keys(camps).map(function (k) { return finalize(camps[k]); });
    list.sort(function (a, b) { return b.sp - a.sp; });
    return list;
  }
  var MAT_CUTOFF = '';  // datas de lead <= isto ja tiveram webinario (vendas maturaram)
  function node(name, lvl) { return { name: name, lvl: lvl, sp: 0, qsp: 0, spMat: 0, rev: 0, sales: 0, ld: 0, rs: 0, f: 0, m: 0, q: 0, kids: {} }; }
  function accN(n, g) {
    n.sp += g.sp; if (g.d >= D.surveyStart) n.qsp += g.sp; if (g.d <= MAT_CUTOFF) n.spMat += g.sp;
    n.rev += g.rev || 0; n.sales += g.sales || 0;
    n.ld += g.ld; n.rs += g.rs; n.f += g.f; n.m += g.m; n.q += g.q;
  }
  function finalize(n) {
    n.children = Object.keys(n.kids).map(function (k) { return finalize(n.kids[k]); });
    n.children.sort(function (a, b) { return b.sp - a.sp; });
    n.kids = null;
    n.cpl = n.ld ? n.sp / n.ld : null;
    n.cplQ = n.q ? n.qsp / n.q : null;
    n.roas = n.sp ? n.rev / n.sp : null;
    n.roasMat = n.spMat ? n.rev / n.spMat : null;      // ROAS julgando só o gasto ja maturado (justo)
    n.matFrac = n.sp ? n.spMat / n.sp : 0;             // fração do gasto que ja pôde converter
    return n;
  }
  function median(a) { if (!a.length) return null; var s = a.slice().sort(function (x, y) { return x - y; }); var m = Math.floor(s.length / 2); return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; }

  /* ---- janela de DECISÃO = últimas ~5 semanas já maturadas ---- */
  function decisionWindow(f) {
    var today = funnelRange(f).hi;
    var cut = addDays(today, -4);                 // edição madura: webinário (hi+1) + ~3 dias de venda
    var mat = arr(f.editions).filter(function (e) { return e.hi <= cut; });
    if (!mat.length) return null;
    var decHi = mat[mat.length - 1].hi;
    return { lo: addDays(decHi, -34), hi: decHi };  // ~5 semanas maturadas
  }
  function decisionMap(f, plat, w) {
    var m = {};
    if (!w) return m;
    arr(f.grain).forEach(function (g) {
      if (g.p !== plat || g.d < w.lo || g.d > w.hi) return;
      var cN = NM.c[g.c], sN = NM.s[g.s], aN = NM.a[g.a];
      var ks = ['¦' + cN, '¦' + cN + '¦' + sN, '¦' + cN + '¦' + sN + '¦' + aN];
      ks.forEach(function (k) { var o = m[k] || (m[k] = { sp: 0, rev: 0, sales: 0 }); o.sp += g.sp; o.rev += g.rev || 0; o.sales += g.sales || 0; });
    });
    return m;
  }
  function attachDecision(list, dm, parentPath) {
    list.forEach(function (n) {
      var path = parentPath + '¦' + n.name;
      n.dr = dm[path] && dm[path].sp > 0 ? dm[path] : null;
      if (n.children && n.children.length) attachDecision(n.children, dm, path);
    });
  }
  // ROAS de decisão: usa o período se ele já maturou; senão cai pras últimas semanas maturadas
  function nodeRoas(n) {
    if (n.matFrac >= 0.4 && n.spMat > 0) return { roas: n.rev / n.spMat, sp: n.spMat, rev: n.rev, sales: n.sales, src: 'p' };
    if (n.dr) return { roas: n.dr.rev / n.dr.sp, sp: n.dr.sp, rev: n.dr.rev, sales: n.dr.sales, src: 'd' };
    return null;
  }
  // Tag de ação — foco em LUCRO (ROAS das últimas semanas maturadas). Sem histórico => Maturando.
  function tagOf(n) {
    if (n.sp <= 0) return null;
    var d = nodeRoas(n);
    if (!d || d.sp < 40) return { c: 'matur', t: '🕐 Maturando' };  // campanha nova / sem venda maturada
    var r = d.roas;
    if (r == null || r < 0.4) return { c: 'pausar', t: 'Pausar' };  // queima dinheiro
    if (r >= 1.0) return { c: 'acelerar', t: 'Acelerar' };          // paga o tráfego -> escalar
    if (r >= 0.7) return { c: 'manter', t: 'Manter' };
    return { c: 'revisar', t: 'Revisar' };                          // ROAS 0,4–0,7 fraco
  }
  function countTag(n, cls) {
    var c = 0;
    if (n.children) n.children.forEach(function (ch) {
      var t = tagOf(ch);
      if (t && t.c === cls) c++;
      c += countTag(ch, cls);
    });
    return c;
  }
  function roasColor(r) {
    if (r == null) return 'var(--muted)';
    if (r >= 1.0) return 'var(--teal)';
    if (r >= 0.5) return 'var(--gold)';
    return 'var(--red)';
  }
  function cplColor(cpl, med) {
    if (cpl == null || !med) return 'var(--muted)';
    var r = cpl / med;
    if (r <= 0.85) return 'var(--teal)';
    if (r >= 1.35) return 'var(--red)';
    return 'var(--gold)';
  }

  /* =====================================================================
     FUNNEL VIEW
  ===================================================================== */
  var STATE = {}; // per funnel: {preset, lo, hi}
  function mountFunnel(key) {
    var f = D[key];
    var host = document.getElementById('view-' + key);
    var rng = funnelRange(f);
    var maxD = rng.hi, minD = rng.lo;
    if (!STATE[key]) {
      var d30 = addDays(maxD, -29); if (d30 < minD) d30 = minD;
      STATE[key] = { preset: '30d', lo: d30, hi: maxD };
    }
    host.innerHTML = periodBar(key) + '<div id="fbody-' + key + '"></div>';
    wirePeriod(key, minD, maxD);
    renderFunnel(key);
  }

  function periodBar(key) {
    return '' +
      '<div class="periodbar" id="pb-' + key + '">' +
      '<span class="pb-label">Período</span>' +
      preset(key, 'hoje', 'Hoje') + preset(key, 'ontem', 'Ontem') +
      preset(key, '7d', '7 dias') + preset(key, '30d', '30 dias') +
      preset(key, 'pesq', 'Pesquisa') + preset(key, 'tudo', 'Tudo') +
      edSelect(key) +
      '<span class="daterange">' +
      '<input type="date" id="dl-' + key + '"> <span>até</span> <input type="date" id="dh-' + key + '">' +
      '</span></div>';
  }
  function preset(key, id, lab) { return '<button class="preset" data-p="' + id + '" data-k="' + key + '">' + lab + '</button>'; }
  function edLabel(e) { return e.tag.replace(/^WBN-2026-/, '') + ' · ' + dfmt(e.lo) + '–' + dfmt(e.hi); }
  // dropdown proprio (o <select> nativo tem a lista desenhada pelo SO e ignora CSS)
  function edSelect(key) {
    var eds = arr(D[key].editions);
    if (!eds.length) return '';
    var items = '<div class="ed-item" data-v="">Todas as semanas</div>';
    eds.slice().sort(function (a, b) { return b.num - a.num; }).forEach(function (e) {
      items += '<div class="ed-item" data-v="' + e.tag + '"><span>' + edLabel(e) + '</span><span class="ed-it-sub">' + fInt(e.leads) + ' leads</span></div>';
    });
    return '<div class="ed-dd" id="edwrap-' + key + '">' +
      '<button type="button" class="ed-btn" id="edbtn-' + key + '" title="Filtrar por edição/semana do webinário">' +
      '<span class="ed-btn-t">📅 Semana</span><span class="ed-caret">▾</span></button>' +
      '<div class="ed-menu" id="edmenu-' + key + '" hidden>' + items + '</div></div>';
  }

  function wirePeriod(key, minD, maxD) {
    var pb = $('#pb-' + key);
    var dl = $('#dl-' + key), dh = $('#dh-' + key);
    dl.min = minD; dl.max = maxD; dh.min = minD; dh.max = maxD;
    Array.prototype.forEach.call(pb.querySelectorAll('.preset'), function (b) {
      b.addEventListener('click', function () {
        var p = b.getAttribute('data-p'); var lo, hi = maxD;
        if (p === 'hoje') lo = maxD;
        else if (p === 'ontem') { lo = addDays(maxD, -1); hi = addDays(maxD, -1); }
        else if (p === '7d') lo = addDays(maxD, -6);
        else if (p === '30d') lo = addDays(maxD, -29);
        else if (p === 'pesq') lo = D.surveyStart;
        else { lo = minD; }
        if (lo < minD) lo = minD;
        STATE[key] = { preset: p, lo: lo, hi: hi };
        renderFunnel(key);
      });
    });
    function onDate() {
      var lo = dl.value || minD, hi = dh.value || maxD;
      if (lo > hi) { var t = lo; lo = hi; hi = t; }
      STATE[key] = { preset: 'custom', lo: lo, hi: hi };
      renderFunnel(key);
    }
    dl.addEventListener('change', onDate); dh.addEventListener('change', onDate);
    var wrap = $('#edwrap-' + key);
    if (wrap) {
      var btn = $('#edbtn-' + key), menu = $('#edmenu-' + key);
      var edMap = {}; arr(D[key].editions).forEach(function (e) { edMap[e.tag] = e; });
      btn.addEventListener('click', function (ev) { ev.stopPropagation(); menu.hidden = !menu.hidden; });
      menu.addEventListener('click', function (ev) {
        var t = ev.target, it = null;
        while (t && t !== menu) { if (t.classList && t.classList.contains('ed-item')) { it = t; break; } t = t.parentNode; }
        if (!it) return;
        menu.hidden = true;
        var tag = it.getAttribute('data-v');
        if (!tag) { STATE[key] = { preset: 'tudo', lo: minD, hi: maxD }; renderFunnel(key); return; }
        var e = edMap[tag];
        STATE[key] = { preset: 'ed', ed: tag, lo: e.lo, hi: e.hi }; renderFunnel(key);
      });
      document.addEventListener('click', function (ev) { if (!wrap.contains(ev.target)) menu.hidden = true; });
      document.addEventListener('keydown', function (ev) { if (ev.key === 'Escape') menu.hidden = true; });
    }
  }

  function renderFunnel(key) {
    var f = D[key], st = STATE[key];
    var pb = $('#pb-' + key);
    Array.prototype.forEach.call(pb.querySelectorAll('.preset'), function (b) { b.classList.toggle('active', b.getAttribute('data-p') === st.preset); });
    $('#dl-' + key).value = st.lo; $('#dh-' + key).value = st.hi;
    var edBtn = $('#edbtn-' + key);
    if (edBtn) {
      var curEd = st.preset === 'ed' ? st.ed : '';
      var lbl = '📅 Semana';
      if (curEd) { var ee = arr(f.editions).filter(function (x) { return x.tag === curEd; })[0]; if (ee) lbl = '📅 ' + edLabel(ee); }
      edBtn.querySelector('.ed-btn-t').textContent = lbl;
      edBtn.classList.toggle('on', !!curEd);
      Array.prototype.forEach.call(document.querySelectorAll('#edmenu-' + key + ' .ed-item'), function (it) { var v = it.getAttribute('data-v'); it.classList.toggle('sel', !!v && v === curEd); });
    }
    var edBadge = st.preset === 'ed' ? '<span class="ed-badge">Edição ' + st.ed.replace(/^WBN-2026-/, '') + ' · semana ' + dfmt(st.lo) + '–' + dfmt(st.hi) + '</span>' : '';

    var a = agg(f, st.lo, st.hi);
    var body = $('#fbody-' + key);
    var showScore = st.hi >= D.surveyStart;
    body.innerHTML =
      (edBadge ? '<div class="ed-badge-wrap">' + edBadge + '<span class="ed-hint">todas as métricas abaixo filtradas por esta semana</span></div>' : '') +
      kpiRow(key, a) +
      receitaBlock(a) +
      (showScore ? scoreStrip(a) : coverageBanner()) +
      chartsBlock(key) +
      '<div class="section-title">Otimização por plataforma <span class="st-line"></span></div>' +
      '<div class="banner" style="margin-bottom:14px">💰 <div><b>Ação e ROAS</b> = lucro real das <b>últimas ~5 semanas já maturadas</b> (otimize a semana atual pelo resultado das anteriores). <b>Acelerar</b> ROAS ≥ 1,0 · <b>Manter</b> 0,7–1 · <b>Revisar</b> 0,4–0,7 · <b>Pausar</b> &lt; 0,4 · 🕐 <b>Maturando</b> = campanha nova, ainda sem venda. Investimento/Leads/CPL seguem o período selecionado.</div></div>' +
      '<div class="opt-cols">' + optCol(f, 'g', st.lo, st.hi) + optCol(f, 'm', st.lo, st.hi) + '</div>';
    drawCharts(key, a);
    wireTrees(key);
  }

  function coverageBanner() {
    return '<div class="banner">⏳ <div>A <b>pesquisa de qualificação</b> (leadscore) começou em <b>' + dfull(D.surveyStart) + '</b>. Selecione o período <b>“Pesquisa”</b> ou <b>“30 dias”</b> para ver taxa de resposta, qualificados e CPL qualificado.</div></div>';
  }

  function fRoas(x) { return (x || 0).toFixed(2).replace('.', ',') + '×'; }
  function retBar(lab, w, val, cls) { return '<div class="rr"><span>' + lab + '</span><div class="bar"><i class="' + cls + '" style="width:' + Math.max(2, w) + '%"></i></div><b>' + val + '</b></div>'; }
  function receitaBlock(a) {
    var titleR = '<div class="section-title">Receita &amp; ROAS <span style="font-weight:400;text-transform:none;letter-spacing:0;color:var(--muted2)">· Fórmula dos Investimentos</span><span class="st-line"></span></div>';
    if (!(a.rev > 0 || a.sales > 0)) return titleR + '<div class="card"><div class="empty">Nenhuma venda de FDI atribuída neste período. As vendas são creditadas ao lead que comprou <b>depois</b> de entrar no funil — selecione <b>“Tudo”</b> para o histórico completo.</div></div>';
    var roas = a.roas, cls = roas == null ? '' : (roas >= 1.5 ? 'good' : roas >= 1 ? 'ok' : 'bad');
    var max = Math.max(a.spend, a.rev) || 1;
    var conv = a.leads ? a.sales / a.leads : null;
    var prodTot = D.sales ? D.sales.totalRev : null;
    return titleR + '<div class="receita-grid">' +
      '<div class="card roas-hero ' + cls + '"><div class="klabel">↩️ ROAS do tráfego</div>' +
        '<div class="roas-val">' + (roas == null ? '—' : fRoas(roas)) + '</div>' +
        '<div class="retorno">' + retBar('Investido', a.spend / max * 100, fBRL0(a.spend), 'inv') + retBar('Receita', a.rev / max * 100, fBRL0(a.rev), 'rev') + '</div>' +
        '<div class="roas-foot">por plataforma · <span class="dot g"></span>Google <b>' + (a.gRoas == null ? '—' : fRoas(a.gRoas)) + '</b> &nbsp; <span class="dot m"></span>Meta <b>' + (a.mRoas == null ? '—' : fRoas(a.mRoas)) + '</b></div>' +
        '<div class="roas-note">Receita creditada ao dia do lead. Recortes recentes subestimam (vendas ainda maturam) — use <b>“Tudo”</b> para o ROAS consolidado.</div>' +
      '</div>' +
      '<div class="card kpi"><div class="klabel">💵 Faturamento <span style="text-transform:none;font-weight:500;color:var(--muted2)">líquido</span></div><div class="kval">' + fBRL0(a.rev) + '</div><div class="ksub"><span>atribuído ao funil (leads captados)</span>' + (prodTot ? '<span style="color:var(--muted2)">produto todo: ' + fBRL0(prodTot) + '</span>' : '') + '</div></div>' +
      '<div class="card kpi"><div class="klabel">🛒 Vendas de FDI</div><div class="kval">' + fInt(a.sales) + '</div><div class="ksub"><span>Ticket <span class="kv">' + money(a.ticket) + '</span></span><span>CAC <span class="kv">' + money(a.cac) + '</span></span><span>conv. lead→venda <span class="kv">' + fPct(conv, 2) + '</span></span></div></div>' +
      '</div>';
  }

  function kpiRow(key, a) {
    var mColor = 'var(--meta)', gColor = 'var(--goog)';
    return '<div class="kpi-row">' +
      // Investment hero
      '<div class="card kpi hero"><div class="klabel">💰 Investimento total</div>' +
      '<div class="kval">' + fBRL0(a.spend) + '</div>' +
      '<div class="ksub">' +
      '<span><span class="dot g"></span>Google <span class="kv">' + fBRL0(a.gSp) + '</span></span>' +
      '<span><span class="dot m"></span>Meta <span class="kv">' + fBRL0(a.mSp) + '</span> <span class="pill-plat m">c/ imposto</span></span>' +
      '</div></div>' +
      // Leads
      card3('👥 Leads captados', fInt(a.leads),
        '<span><span class="dot g"></span>' + fInt(a.gLd) + '</span><span><span class="dot m"></span>' + fInt(a.mLd) + '</span>' + (a.oLd ? '<span>outros ' + fInt(a.oLd) + '</span>' : '')) +
      // CPL
      card3('🎯 CPL', money(a.cpl),
        '<span>G <span class="kv">' + money(a.gCpl) + '</span></span><span>M <span class="kv">' + money(a.mCpl) + '</span></span>') +
      // secondary metrics
      card3('📊 Alcance & cliques', fInt(a.gIm + a.mIm) + ' <span style="font-size:13px;color:var(--muted)">impr.</span>',
        '<span>Cliques <span class="kv">' + fInt(a.gCk + a.mCk) + '</span></span><span>CTR <span class="kv">' + fPct(a.ctr) + '</span></span><span>CPM <span class="kv">' + money(a.cpm) + '</span></span>') +
      // response rate — respostas por DATA DA RESPOSTA (bate com a planilha)
      card3('📝 Respostas <span class="pill-plat m" style="background:rgba(91,157,255,.14);color:var(--goog)">totais</span>', fInt(a.respTotal),
        '<span>do tráfego <span class="kv">' + fInt(a.respTraffic) + '</span></span><span>Taxa resp. <span class="kv">' + fPct(a.respRate) + '</span></span><span style="color:var(--muted2)">contadas pela data da resposta</span>') +
      // qualified
      card3('🔥 Qualificados <span class="pill-plat m" style="background:rgba(255,106,77,.16);color:var(--hot)">Quente</span>', fInt(a.q),
        '<span>% qualif <span class="kv">' + fPct(a.pctQ) + '</span></span><span>CPL qualif. <span class="kv">' + money(a.cplQ) + '</span></span>' + (a.scoped ? '<span style="color:var(--muted2)">qualif. desde ' + dfull(D.surveyStart) + '</span>' : '')) +
      '</div>';
  }
  function card3(label, val, sub) {
    return '<div class="card kpi"><div class="klabel">' + label + '</div><div class="kval">' + val + '</div><div class="ksub">' + (sub || '') + '</div></div>';
  }

  function scoreStrip(a) {
    var tot = a.f + a.m + a.q || 1;
    var wf = a.f / tot * 100, wm = a.m / tot * 100, wq = a.q / tot * 100;
    function seg(cls, w, n) { return '<span class="' + cls + '" style="width:' + w + '%">' + (w > 9 ? n : '') + '</span>'; }
    return '<div class="card" style="margin-top:14px"><div class="klabel" style="margin-bottom:12px">Leadscore — distribuição das respostas rastreadas no período</div>' +
      '<div class="score-strip">' +
      '<div class="score-bar">' + seg('seg-frio', wf, a.f) + seg('seg-morno', wm, a.m) + seg('seg-quente', wq, a.q) + '</div>' +
      '<div class="score-legend">' +
      liScore('var(--cold)', 'Frio', '0–4 pts', a.f, tot) +
      liScore('var(--warm)', 'Morno', '5–10 pts', a.m, tot) +
      liScore('var(--hot)', 'Quente', '11–15 · Qualificado', a.q, tot) +
      '</div></div></div>';
  }
  function liScore(c, name, rng, n, tot) {
    return '<div class="li"><span class="sw" style="background:' + c + '"></span><span><b>' + name + '</b> ' + fInt(n) + ' <span style="color:var(--muted)">(' + fPct(tot ? n / tot : 0, 0) + ' · ' + rng + ')</span></span></div>';
  }

  function chartsBlock(key) {
    return '<div class="section-title">Evolução diária <span class="st-line"></span></div>' +
      '<div class="charts">' +
      '<div class="chart-card"><div class="chart-head"><h4>Leads por dia</h4><div class="legend"><span><i style="background:var(--goog)"></i>Google</span><span><i style="background:var(--meta)"></i>Meta</span></div></div><div id="ch-leads-' + key + '"></div></div>' +
      '<div class="chart-card"><div class="chart-head"><h4>Investimento × CPL</h4><div class="legend"><span><i style="background:var(--gold)"></i>Investimento</span><span><i style="background:var(--teal)"></i>CPL</span></div></div><div id="ch-inv-' + key + '"></div></div>' +
      '</div>';
  }

  /* ---------- optimization column ---------- */
  var TREE_STATE = {}; // key_plat -> Set of expanded paths
  function optCol(f, plat, lo, hi) {
    MAT_CUTOFF = addDays(funnelRange(f).hi, -9);   // leads ate 9 dias atras ja tiveram webinario
    var list = buildTree(f, plat, lo, hi);
    var dw = decisionWindow(f);                    // últimas ~5 semanas maturadas
    attachDecision(list, decisionMap(f, plat, dw), '');
    var tot = list.reduce(function (o, n) { o.sp += n.sp; o.ld += n.ld; var d = nodeRoas(n); if (d) { o.dsp += d.sp; o.rev += d.rev; o.sales += d.sales; } return o; }, { sp: 0, ld: 0, dsp: 0, rev: 0, sales: 0 });
    var cpl = tot.ld ? tot.sp / tot.ld : null;
    var roas = tot.dsp ? tot.rev / tot.dsp : null;   // ROAS maduro (base de decisão)
    var medCpl = median(list.filter(function (n) { return n.sp > 0 && n.ld >= 1; }).map(function (n) { return n.cpl; }));
    var nmeP = plat === 'g' ? 'Google Ads' : 'Meta Ads';
    var sub = plat === 'g' ? 'campanha › grupo › anúncio · sem imposto' : 'campanha › conjunto › anúncio · imposto ×1,1385';
    var withSp = list.filter(function (n) { return n.sp > 0; });
    var noSp = list.filter(function (n) { return n.sp <= 0; });
    var sortKey = f.key + '_' + plat;
    var so = SORT_STATE[sortKey] || { sk: 'sp', dir: -1 };
    sortTree(withSp, so.sk, so.dir);
    var rows = withSp.map(function (c) { return treeRows(c, plat, f.key, medCpl, '', true); }).join('');
    if (noSp.length) {
      var orph = { name: '— leads sem investimento rastreado —', lvl: 0, sp: 0, ld: 0, rev: 0, sales: 0, matFrac: 1, children: [], cpl: null, roas: null, roasMat: null };
      noSp.forEach(function (n) { orph.ld += n.ld; orph.rev += n.rev; orph.sales += n.sales; });
      if (orph.ld > 0) rows += treeRows(orph, plat, f.key, null, '', true);
    }
    if (!withSp.length && !noSp.length) rows = '<div class="empty">Sem investimento neste período.</div>';
    return '<div class="opt-col ' + plat + '">' +
      '<div class="opt-head"><div class="oh-ic">' + (plat === 'g' ? 'G' : 'M') + '</div><div><h3>' + nmeP + '</h3><div class="oh-sub">' + sub + '</div></div></div>' +
      '<div class="opt-totals">' +
      ot('Investimento', fBRL0(tot.sp)) + ot('Leads', fInt(tot.ld)) + ot('CPL', money(cpl)) +
      ot('ROAS maduro', roas == null ? '—' : fRoas(roas)) + ot('Receita mad.', fBRL0(tot.rev)) + ot('Vendas mad.', fInt(tot.sales)) +
      '</div>' +
      '<div class="tree">' +
      '<div class="tr-row head">' +
      sHead(sortKey, so, 'name', 'Campanha / conjunto / anúncio', 'tr-name') +
      sHead(sortKey, so, 'sp', 'Invest.', 'tr-num') +
      sHead(sortKey, so, 'ld', 'Leads', 'tr-num') +
      sHead(sortKey, so, 'cpl', 'CPL', 'tr-num') +
      sHead(sortKey, so, 'roas', 'ROAS', 'tr-num') +
      sHead(sortKey, so, 'acao', 'Ação', 'tr-num') +
      '</div>' +
      rows + '</div></div>';
  }
  function ot(l, v) { return '<div class="ot"><div class="l">' + l + '</div><div class="v">' + v + '</div></div>'; }

  /* ---------- sortable tree headers ---------- */
  var SORT_STATE = {}; // fk_plat -> {sk, dir}  (dir: 1 asc, -1 desc)
  var ACT_RANK = { acelerar: 0, manter: 1, revisar: 2, matur: 3, insuf: 4, pausar: 5 };
  function bestDir(sk) { return (sk === 'cpl' || sk === 'name' || sk === 'acao') ? 1 : -1; } // 1º clique = melhor→pior (cpl/ação sobe; roas/leads/invest desce)
  function sortVal(n, sk) {
    if (sk === 'name') return n.name;
    if (sk === 'sp') return n.sp;
    if (sk === 'ld') return n.ld;
    if (sk === 'roas') { var dr = nodeRoas(n); return dr ? dr.roas : null; }   // null -> fim
    if (sk === 'cpl') return n.cpl;               // null (sem leads) -> vai pro fim
    if (sk === 'acao') { var t = tagOf(n); return t ? ACT_RANK[t.c] : 9; }
    return 0;
  }
  function sortTree(list, sk, dir) {
    list.sort(function (a, b) {
      var va = sortVal(a, sk), vb = sortVal(b, sk);
      if (va == null && vb == null) return 0;
      if (va == null) return 1;                   // nulos sempre por último
      if (vb == null) return -1;
      if (sk === 'name') return va.localeCompare(vb) * dir;
      return (va - vb) * dir;
    });
    list.forEach(function (n) { if (n.children && n.children.length) sortTree(n.children, sk, dir); });
  }
  function sHead(sortKey, so, sk, lab, cls) {
    var active = so.sk === sk;
    var arrow = active ? (so.dir === 1 ? ' <span class="sarr">▲</span>' : ' <span class="sarr">▼</span>') : '';
    return '<div class="' + cls + ' sortable' + (active ? ' sorted' : '') + '" data-sk="' + sk + '" data-sortk="' + sortKey + '" title="Ordenar por ' + lab + '">' + lab + arrow + '</div>';
  }

  function treeRows(n, plat, fk, medCpl, parentPath, visible) {
    var path = parentPath + '¦' + n.name;
    var skey = fk + '_' + plat;
    var set = TREE_STATE[skey] || (TREE_STATE[skey] = {});
    var open = !!set[path];
    var hasKids = n.children && n.children.length;
    var tag = tagOf(n);
    var accelN = hasKids ? countTag(n, 'acelerar') : 0;
    var pausarN = hasKids ? countTag(n, 'pausar') : 0;
    var cplc = cplColor(n.cpl, medCpl);
    var caret = hasKids ? '<span class="caret ' + (open ? 'open' : '') + '">▶</span>' : '<span class="caret" style="opacity:0">•</span>';
    var d = nodeRoas(n);
    var rv = d ? d.roas : null;
    var noHist = (n.sp > 0 && !d);
    var ttl = 'Investido(período) ' + fBRL0(n.sp) + ' · ' + fInt(n.ld) + ' leads' + (d ? ' · ROAS maduro ' + fRoas(rv) + ' (' + fInt(d.sales) + ' vendas · ' + fBRL0(d.rev) + ')' : ' · sem venda maturada ainda');
    var rcell = noHist
      ? '<span class="qc muted" title="campanha nova / sem venda maturada">🕐</span>'
      : (d
        ? '<span class="qc" style="color:' + roasColor(rv) + ';font-weight:700">' + fRoas(rv) + '</span><div class="qsub">' + fInt(d.sales) + 'v · ' + fBRL0(d.rev) + '</div>'
        : '<span class="qc muted">' + fInt(n.sales) + 'v</span>');
    var row = '<div class="tr-row lvl' + n.lvl + '" data-path="' + encodeURIComponent(path) + '" data-k="' + skey + '"' + (hasKids ? ' data-toggle="1"' : '') + ' title="' + ttl + '">' +
      '<div class="tr-name">' + caret + '<span class="nm" title="' + esc(n.name) + '">' + esc(pretty(n.name)) + '</span></div>' +
      '<div class="tr-num">' + fBRL0(n.sp) + '</div>' +
      '<div class="tr-num muted">' + fInt(n.ld) + '</div>' +
      '<div class="tr-num"><span class="cpl-pill" style="color:' + cplc + '">' + (n.cpl == null ? '—' : fBRL(n.cpl)) + '</span></div>' +
      '<div class="tr-num tr-q">' + rcell + '</div>' +
      '<div class="tr-num acao">' + (tag ? '<span class="tag ' + tag.c + '">' + tag.t + '</span>' : '<span class="muted">—</span>') +
        (accelN > 0 && (!tag || tag.c !== 'acelerar') ? '<span class="accel-mark" title="' + accelN + ' conjunto(s)/anúncio(s) LUCRANDO (ROAS bom) pra acelerar aqui dentro — clique pra abrir">⚡ Acelerar</span>' : '') +
        (pausarN > 0 && (!tag || tag.c !== 'pausar') ? '<span class="pausar-mark" title="' + pausarN + ' conjunto(s)/anúncio(s) no prejuízo (ROAS baixo) pra pausar aqui dentro — clique pra abrir">⏸ Pausar</span>' : '') +
      '</div>' +
      '</div>';
    var kids = '';
    if (hasKids && open) kids = n.children.map(function (c) { return treeRows(c, plat, fk, medCpl, path, true); }).join('');
    return row + kids;
  }
  function wireTrees(key) {
    Array.prototype.forEach.call(document.querySelectorAll('#fbody-' + key + ' .tr-row[data-toggle]'), function (r) {
      r.addEventListener('click', function () {
        var skey = r.getAttribute('data-k'), path = decodeURIComponent(r.getAttribute('data-path'));
        var set = TREE_STATE[skey] || (TREE_STATE[skey] = {});
        if (set[path]) delete set[path]; else set[path] = 1;
        renderFunnel(key);
      });
    });
    Array.prototype.forEach.call(document.querySelectorAll('#fbody-' + key + ' .tr-row.head .sortable'), function (h) {
      h.addEventListener('click', function () {
        var sortKey = h.getAttribute('data-sortk'), sk = h.getAttribute('data-sk');
        var st = SORT_STATE[sortKey] || { sk: 'sp', dir: -1 };
        if (st.sk === sk) st = { sk: sk, dir: -st.dir }; else st = { sk: sk, dir: bestDir(sk) };
        SORT_STATE[sortKey] = st;
        renderFunnel(key);
      });
    });
  }
  function pretty(s) { if (!s) return '—'; if (s === '(sem rastreio)' || s === '(sem)') return '— sem rastreio —'; return s; }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }

  /* ---------- charts (SVG) ---------- */
  var TIP = document.getElementById('tooltip');
  function showTip(html, ev) { TIP.innerHTML = html; TIP.hidden = false; var x = ev.clientX + 14, y = ev.clientY + 14; if (x + 250 > innerWidth) x = ev.clientX - 250; TIP.style.left = x + 'px'; TIP.style.top = y + 'px'; }
  function hideTip() { TIP.hidden = true; }

  function drawCharts(key, a) {
    var days = a.dayArr;
    barLeads($('#ch-leads-' + key), days);
    invCpl($('#ch-inv-' + key), days);
  }
  function svgEl(w, h) { return '<svg class="chart" viewBox="0 0 ' + w + ' ' + h + '" preserveAspectRatio="none">'; }

  function barLeads(host, days) {
    if (!days.length) { host.innerHTML = '<div class="empty">Sem dados no período.</div>'; return; }
    var W = 560, H = 200, pad = { l: 34, r: 8, t: 10, b: 20 };
    var iw = W - pad.l - pad.r, ih = H - pad.t - pad.b;
    var max = Math.max.apply(null, days.map(function (d) { return d.gLd + d.mLd; })) || 1;
    var bw = iw / days.length, bar = Math.max(1, Math.min(bw * 0.7, 22));
    var s = svgEl(W, H);
    // gridlines
    for (var i = 0; i <= 3; i++) { var gy = pad.t + ih * i / 3; var gv = Math.round(max * (3 - i) / 3); s += line(pad.l, gy, W - pad.r, gy, 'var(--line)'); s += txt(pad.l - 5, gy + 3, fInt(gv), 'end', 9, 'var(--muted2)'); }
    days.forEach(function (d, k) {
      var cx = pad.l + bw * k + (bw - bar) / 2;
      var hg = d.gLd / max * ih, hm = d.mLd / max * ih;
      var yg = pad.t + ih - hg, ym = yg - hm;
      s += '<rect x="' + cx + '" y="' + yg + '" width="' + bar + '" height="' + hg + '" fill="var(--goog)" rx="1"></rect>';
      s += '<rect x="' + cx + '" y="' + ym + '" width="' + bar + '" height="' + hm + '" fill="var(--meta)" rx="1"></rect>';
    });
    // x labels sparse
    labelSparse(days, pad, bw, ih, function (t) { s += t; });
    s += '</svg>';
    host.innerHTML = s;
    hit(host, days, pad, bw, function (d) {
      return '<div class="tt-t">' + dfull(d.date) + '</div>' +
        row2('Google', fInt(d.gLd)) + row2('Meta', fInt(d.mLd)) + row2('Total', fInt(d.gLd + d.mLd));
    });
  }

  function invCpl(host, days) {
    if (!days.length) { host.innerHTML = '<div class="empty">Sem dados no período.</div>'; return; }
    var W = 560, H = 200, pad = { l: 40, r: 40, t: 10, b: 20 };
    var iw = W - pad.l - pad.r, ih = H - pad.t - pad.b;
    var maxSp = Math.max.apply(null, days.map(function (d) { return d.sp; })) || 1;
    var cpls = days.map(function (d) { return d.ld ? d.sp / d.ld : null; });
    var maxCpl = Math.max.apply(null, cpls.filter(function (x) { return x != null; }).concat([1]));
    var bw = iw / days.length, bar = Math.max(1, Math.min(bw * 0.7, 22));
    var s = svgEl(W, H);
    for (var i = 0; i <= 3; i++) { var gy = pad.t + ih * i / 3; s += line(pad.l, gy, W - pad.r, gy, 'var(--line)'); s += txt(pad.l - 5, gy + 3, 'R$' + fInt(maxSp * (3 - i) / 3), 'end', 9, 'var(--muted2)'); s += txt(W - pad.r + 5, gy + 3, fInt(maxCpl * (3 - i) / 3), 'start', 9, 'var(--teal-dim)'); }
    days.forEach(function (d, k) {
      var cx = pad.l + bw * k + (bw - bar) / 2;
      var hs = d.sp / maxSp * ih;
      s += '<rect x="' + cx + '" y="' + (pad.t + ih - hs) + '" width="' + bar + '" height="' + hs + '" fill="var(--gold-dim)" opacity=".9" rx="1"></rect>';
    });
    // cpl line
    var pts = [];
    days.forEach(function (d, k) { var c = cpls[k]; if (c == null) return; var x = pad.l + bw * k + bw / 2; var y = pad.t + ih - c / maxCpl * ih; pts.push([x, y]); });
    if (pts.length) { s += '<polyline points="' + pts.map(function (p) { return p[0] + ',' + p[1]; }).join(' ') + '" fill="none" stroke="var(--teal)" stroke-width="2" stroke-linejoin="round"></polyline>'; pts.forEach(function (p) { s += '<circle cx="' + p[0] + '" cy="' + p[1] + '" r="2" fill="var(--teal)"></circle>'; }); }
    labelSparse(days, pad, bw, ih, function (t) { s += t; });
    s += '</svg>';
    host.innerHTML = s;
    hit(host, days, pad, bw, function (d) {
      return '<div class="tt-t">' + dfull(d.date) + '</div>' + row2('Investimento', fBRL0(d.sp)) + row2('Leads', fInt(d.ld)) + row2('CPL', d.ld ? fBRL(d.sp / d.ld) : '—');
    });
  }

  function labelSparse(days, pad, bw, ih, push) {
    var n = days.length, step = Math.max(1, Math.ceil(n / 8)), last = -99;
    days.forEach(function (d, k) { if (k % step === 0) { push(txt(pad.l + bw * k + bw / 2, pad.t + ih + 14, dfmt(d.date), 'middle', 9, 'var(--muted2)')); last = k; } });
    if (n - 1 - last > step * 0.5) push(txt(pad.l + bw * (n - 1) + bw / 2, pad.t + ih + 14, dfmt(days[n - 1].date), 'middle', 9, 'var(--muted2)'));
  }
  function hit(host, days, pad, bw, tipFn) {
    var svg = host.querySelector('svg'); if (!svg) return;
    var H = 200, ih = H - pad.t - pad.b;
    days.forEach(function (d, k) {
      var r = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
      r.setAttribute('x', pad.l + bw * k); r.setAttribute('y', pad.t); r.setAttribute('width', bw); r.setAttribute('height', ih);
      r.setAttribute('fill', 'transparent'); r.style.cursor = 'crosshair';
      r.addEventListener('mousemove', function (e) { showTip(tipFn(d), e); });
      r.addEventListener('mouseleave', hideTip);
      svg.appendChild(r);
    });
  }
  function line(x1, y1, x2, y2, c) { return '<line x1="' + x1 + '" y1="' + y1 + '" x2="' + x2 + '" y2="' + y2 + '" stroke="' + c + '" stroke-width="1"></line>'; }
  function txt(x, y, t, anc, sz, c) { return '<text x="' + x + '" y="' + y + '" text-anchor="' + anc + '" font-size="' + sz + '" fill="' + c + '" font-family="Space Grotesk,sans-serif">' + esc(t) + '</text>'; }
  function row2(l, v) { return '<div class="tt-r"><span>' + l + '</span><b>' + v + '</b></div>'; }

  /* =====================================================================
     PESQUISA VIEW
  ===================================================================== */
  var PSTATE = 'soma';
  function mountPesquisa() {
    var host = document.getElementById('view-pesquisa');
    host.innerHTML =
      '<div class="periodbar" style="justify-content:space-between">' +
      '<div class="seg-toggle" id="pseg">' +
      '<button data-s="segunda">Segunda</button><button data-s="terca">Terça</button><button data-s="soma" class="active">Soma</button>' +
      '</div>' +
      '<span class="daterange" style="margin:0">Pesquisa acumulada desde ' + dfull(D.surveyStart) + '</span>' +
      '</div>' +
      '<div id="pbody"></div>';
    Array.prototype.forEach.call(host.querySelectorAll('#pseg button'), function (b) {
      b.addEventListener('click', function () {
        PSTATE = b.getAttribute('data-s');
        Array.prototype.forEach.call(host.querySelectorAll('#pseg button'), function (x) { x.classList.toggle('active', x === b); });
        renderPesquisa();
      });
    });
    renderPesquisa();
  }

  function pickTier(which) {
    var P = D.pesquisa;
    if (which === 'segunda') return { rt: P.seg.respTot, rm: P.seg.respMatch, t: P.seg.tierTot, era: P.seg.leadsEra };
    if (which === 'terca') return { rt: P.ter.respTot, rm: P.ter.respMatch, t: P.ter.tierTot, era: P.ter.leadsEra };
    return {
      rt: P.seg.respTot + P.ter.respTot, rm: P.seg.respMatch + P.ter.respMatch,
      t: { f: P.seg.tierTot.f + P.ter.tierTot.f, m: P.seg.tierTot.m + P.ter.tierTot.m, q: P.seg.tierTot.q + P.ter.tierTot.q },
      era: P.seg.leadsEra + P.ter.leadsEra
    };
  }

  function renderPesquisa() {
    var P = D.pesquisa, w = PSTATE, T = pickTier(w);
    var tot = T.t.f + T.t.m + T.t.q || 1;
    var rate = T.era ? T.rm / T.era : null;
    var body = $('#pbody');

    var summary = '<div class="kpi-row">' +
      card3('📝 Total de respostas', fInt(T.rt), '<span>rastreadas ao lead <span class="kv">' + fInt(T.rm) + '</span></span>') +
      card3('📈 Taxa de resposta', fPct(rate), '<span>respostas ÷ leads do período</span>') +
      card3('🔥 Qualificados <span class="pill-plat m" style="background:rgba(255,106,77,.16);color:var(--hot)">Quente</span>', fInt(T.t.q), '<span>% do total <span class="kv">' + fPct(T.t.q / tot) + '</span></span>') +
      card3('❄️ Frio / 🟡 Morno', fInt(T.t.f) + ' / ' + fInt(T.t.m), '<span>evitar / mediano</span>') +
      '</div>';

    // score strip
    var wf = T.t.f / tot * 100, wm = T.t.m / tot * 100, wq = T.t.q / tot * 100;
    function seg(cls, wd, n) { return '<span class="' + cls + '" style="width:' + wd + '%">' + (wd > 8 ? fInt(n) : '') + '</span>'; }
    var strip = '<div class="card" style="margin-top:14px"><div class="klabel" style="margin-bottom:12px">Distribuição de leadscore — ' + labelOf(w) + '</div>' +
      '<div class="score-strip"><div class="score-bar">' + seg('seg-frio', wf, T.t.f) + seg('seg-morno', wm, T.t.m) + seg('seg-quente', wq, T.t.q) + '</div>' +
      '<div class="score-legend">' +
      liScore('var(--cold)', 'Frio', '0–4', T.t.f, tot) + liScore('var(--warm)', 'Morno', '5–10', T.t.m, tot) + liScore('var(--hot)', 'Quente', '11–15', T.t.q, tot) +
      '</div></div></div>';

    // qualified profile
    var prof = '<div class="section-title">Perfil do lead qualificado <span style="font-weight:400;text-transform:none;letter-spacing:0;color:var(--muted2)">(Quente · soma segunda + terça)</span><span class="st-line"></span></div>' +
      '<div class="card"><div class="profile-grid">' +
      arr(P.profile).map(function (dm) {
        var opts = arr(dm.options).filter(function (o) { return o.cnt > 0; });
        var totc = opts.reduce(function (s, o) { return s + o.cnt; }, 0) || 1;
        var top = opts[0];
        if (!top) return '';
        return '<div class="prof-item"><div class="pi-l">' + esc(dm.label) + '</div><div class="pi-v">' + esc(top.label) + '</div><div class="pi-p">' + fPct(top.cnt / totc, 0) + ' dos qualificados</div></div>';
      }).join('') +
      '</div></div>';

    // dimensions distributions
    var dims = '<div class="section-title">O que os leads respondem <span style="font-weight:400;text-transform:none;letter-spacing:0;color:var(--muted2)">(' + labelOf(w) + ')</span><span class="st-line"></span></div>' +
      '<div class="dims-grid">' + arr(P.dims).map(function (dm) { return dimCard(dm, w); }).join('') + '</div>';

    body.innerHTML = summary + strip + prof + dims + ruler();
  }
  function labelOf(w) { return w === 'segunda' ? 'Segunda-feira' : (w === 'terca' ? 'Terça-feira' : 'Soma dos dois funis'); }

  function dimCard(dm, w) {
    var opts = arr(dm.options).map(function (o) { var v = w === 'segunda' ? o.seg : (w === 'terca' ? o.ter : o.seg + o.ter); return { label: o.label, pts: o.pts, v: v }; });
    opts = opts.filter(function (o) { return o.v > 0; }).sort(function (a, b) { return b.v - a.v; });
    var tot = opts.reduce(function (s, o) { return s + o.v; }, 0) || 1;
    var max = opts.length ? opts[0].v : 1;
    var rows = opts.map(function (o) {
      var w2 = o.v / max * 100;
      return '<div class="ob-row"><div class="ob-lab"><span class="pts-badge pts-' + o.pts + '" title="' + o.pts + ' ponto(s)">' + o.pts + '</span><span title="' + esc(o.label) + '">' + esc(o.label) + '</span></div>' +
        '<div class="ob-track"><div class="ob-fill" style="width:' + w2 + '%"></div></div>' +
        '<div class="ob-val">' + fInt(o.v) + '<div style="font-size:10px;color:var(--muted2)">' + fPct(o.v / tot, 0) + '</div></div></div>';
    }).join('');
    return '<div class="dim-card"><div class="dim-head"><div class="dh-t">' + esc(dm.label) + '</div><div class="dh-w">peso máx. ' + dm.peso + '</div></div><div class="opt-bar">' + rows + '</div></div>';
  }

  function ruler() {
    return '<details class="ruler"><summary>Régua de pontuação (protocolo v1.1) — como o leadscore é calculado</summary>' +
      '<table class="ruler-tbl"><thead><tr><th>Dimensão / resposta</th><th style="text-align:center">Pontos</th></tr></thead><tbody>' +
      rgrp('Idade (peso 3)') + rr('50 anos ou mais', 3) + rr('31 a 50 anos', 2) + rr('Até 30 anos', 0) +
      rgrp('Renda mensal (peso 3)') + rr('Acima de R$ 10.000', 3) + rr('R$ 2.000 a R$ 10.000', 2) + rr('Até R$ 2.000', 1) + rr('Não possui renda', 0) +
      rgrp('Motivação (peso 2)') + rr('Futuro/aposentadoria · perde tempo', 2) + rr('Segurança da família · renda extra', 1) + rr('Sair da poupança', 0) +
      rgrp('O que trava (peso 2)') + rr('Falta de confiança · não sabe onde investir', 2) + rr('Falta de tempo', 1) + rr('Medo · falta de dinheiro · tarde demais', 0) +
      rgrp('Valor já investido (peso 2)') + rr('Acima de R$ 100.000', 2) + rr('Até R$ 100.000', 1) + rr('Ainda não investiu', 0) +
      rgrp('Nível de investidor (peso 1)') + rr('Já investe', 1) + rr('Nunca investiu', 0) +
      rgrp('Capacidade mensal (peso 1)') + rr('Qualquer valor', 1) + rr('Não consegue investir agora', 0) +
      rgrp('Resultado esperado (peso 1)') + rr('Qualquer, exceto abaixo', 1) + rr('Saber por onde começar', 0) +
      '</tbody></table>' +
      '<div style="padding:6px 14px 14px;color:var(--muted);font-size:12px">Score total 0–15 · <b style="color:var(--cold)">Frio 0–4</b> · <b style="color:var(--warm)">Morno 5–10</b> · <b style="color:var(--hot)">Quente 11–15 = Qualificado</b>. O tier Quente converte ~2,4× a média do funil.</div>' +
      '</details>';
  }
  function rgrp(t) { return '<tr class="ruler-grp"><td>' + t + '</td><td class="pt"></td></tr>'; }
  function rr(t, p) { return '<tr><td style="color:var(--muted)">' + t + '</td><td class="pt pts-' + p + '" style="color:' + (p === 3 ? 'var(--hot)' : p === 2 ? 'var(--warm)' : p === 1 ? 'var(--cold)' : 'var(--muted)') + '">' + p + '</td></tr>'; }

  /* =====================================================================
     VENDAS VIEW (visão geral do produto FDI)
  ===================================================================== */
  function allSpend(f) { var s = 0; arr(f.daily).forEach(function (r) { s += r.sp; }); return s; }
  function tk(rev, n) { return n ? fBRL(rev / n) : '—'; }
  function srcLabel(s) { if (!s || s === '(sem utm_source)') return '— sem utm_source —'; return s; }
  function mountVendas() {
    var host = document.getElementById('view-vendas');
    var S = D.sales;
    if (!S) { host.innerHTML = '<p class="empty">Sem dados de vendas.</p>'; return; }
    var unRev = S.totalRev - S.attrRev, unSales = S.totalSales - S.attrSales;
    var pctAttr = S.totalRev ? S.attrRev / S.totalRev : 0;
    var segSp = allSpend(D.segunda), terSp = allSpend(D.terca);
    var wAttr = S.totalRev ? S.attrRev / S.totalRev * 100 : 0;

    // hero
    var hero = '<div class="kpi-row" style="margin-top:14px">' +
      card3('💰 Faturamento total · FDI', fBRL0(S.totalRev), '<span>todas as vendas do produto · líquido</span>') +
      card3('🛒 Vendas totais', fInt(S.totalSales), '<span>ticket médio <span class="kv">' + tk(S.totalRev, S.totalSales) + '</span></span>') +
      card3('🎯 Rastreado', fPct(pctAttr, 1), '<span>' + fBRL0(S.attrRev) + ' de ' + fBRL0(S.totalRev) + '</span>') +
      '</div>';

    // stacked bar rastreado vs nao
    var bar = '<div class="card" style="margin-top:14px"><div class="klabel" style="margin-bottom:10px">Rastreadas × Não rastreadas (faturamento)</div>' +
      '<div class="split-bar"><span class="s-attr" style="width:' + wAttr + '%">' + (wAttr > 12 ? fPct(pctAttr, 0) : '') + '</span><span class="s-un" style="width:' + (100 - wAttr) + '%">' + (100 - wAttr > 12 ? fPct(1 - pctAttr, 0) : '') + '</span></div>' +
      '<div class="score-legend" style="margin-top:10px"><div class="li"><span class="sw" style="background:var(--teal)"></span>Rastreadas <b>' + fBRL0(S.attrRev) + '</b></div><div class="li"><span class="sw" style="background:var(--muted2)"></span>Não rastreadas <b>' + fBRL0(unRev) + '</b></div></div></div>';

    // Table 1 — resumo (soma)
    var t1 = tblCard('Σ Resumo — soma das duas', tbl(
      ['Categoria', 'Vendas', 'Faturamento', 'Ticket', '% Fat.'],
      [
        rowV(['<span class="src-dot" style="background:var(--teal)"></span>Rastreadas (tráfego)', fInt(S.attrSales), fBRL0(S.attrRev), tk(S.attrRev, S.attrSales), fPct(pctAttr, 1)]),
        rowV(['<span class="src-dot" style="background:var(--muted2)"></span>Não rastreadas', fInt(unSales), fBRL0(unRev), tk(unRev, unSales), fPct(1 - pctAttr, 1)])
      ],
      rowV(['Total FDI', fInt(S.totalSales), fBRL0(S.totalRev), tk(S.totalRev, S.totalSales), '100%'], 'tot')
    ));

    // Table 2 — rastreadas por funil
    var attrSp = terSp + segSp;
    var t2 = tblCard('✅ Rastreadas — por funil (vieram do tráfego dos webinários)', tbl(
      ['Funil', 'Vendas', 'Faturamento', 'Ticket', 'Investimento', 'ROAS'],
      [
        rowV(['Terça', fInt(D.terca.totalSales), fBRL0(D.terca.totalRev), tk(D.terca.totalRev, D.terca.totalSales), fBRL0(terSp), roasCell(terSp ? D.terca.totalRev / terSp : null)]),
        rowV(['Segunda', fInt(D.segunda.totalSales), fBRL0(D.segunda.totalRev), tk(D.segunda.totalRev, D.segunda.totalSales), fBRL0(segSp), roasCell(segSp ? D.segunda.totalRev / segSp : null)])
      ],
      rowV(['Total rastreado', fInt(S.attrSales), fBRL0(S.attrRev), tk(S.attrRev, S.attrSales), fBRL0(attrSp), roasCell(attrSp ? S.attrRev / attrSp : null)], 'tot')
    ));

    // Table 3 — nao rastreadas por fonte
    var un = arr(S.unSrc);
    var unRows = un.map(function (o) { return rowV(['<span class="src-dot" style="background:var(--muted2)"></span>' + esc(srcLabel(o.src)), fInt(o.sales), fBRL0(o.rev), tk(o.rev, o.sales), fPct(unRev ? o.rev / unRev : 0, 1)]); }).join('');
    var t3 = tblCard('❓ Não rastreadas — por fonte (orgânico, outras origens, ou anteriores ao funil)', tbl(
      ['Fonte (utm_source)', 'Vendas', 'Faturamento', 'Ticket', '% do não rastr.'],
      [unRows],
      rowV(['Total não rastreado', fInt(unSales), fBRL0(unRev), tk(unRev, unSales), '100%'], 'tot')
    ));

    // por ano (contexto)
    var yr = arr(S.byYear);
    var t4 = '';
    if (yr.length) {
      var yrRows = yr.map(function (o) { return rowV([o.year, fInt(o.sales), fBRL0(o.rev), tk(o.rev, o.sales)]); }).join('');
      t4 = tblCard('📅 Todas as vendas de FDI — por ano', tbl(['Ano', 'Vendas', 'Faturamento', 'Ticket'], [yrRows], ''));
    }

    var note = '<div class="banner" style="margin-top:16px">ℹ️ <div><b>Rastreadas</b> = compradores cruzados por e-mail com um lead do tráfego que entrou <b>antes</b> da compra. <b>Não rastreadas</b> = demais vendas do FDI (tráfego orgânico, outras origens, ou compras anteriores aos webinários de 2026). Faturamento = valor <b>líquido</b> (já sem as taxas da plataforma).</div></div>';

    host.innerHTML = '<div class="section-title" style="margin-top:18px">Visão geral de vendas <span style="font-weight:400;text-transform:none;letter-spacing:0;color:var(--muted2)">· Fórmula dos Investimentos</span><span class="st-line"></span></div>' +
      hero + bar + note +
      '<div class="vtbl-grid">' + t1 + t2 + '</div>' + t3 + t4;
  }
  function tblCard(title, inner) { return '<div class="card tbl-card"><div class="klabel" style="margin-bottom:10px">' + title + '</div><div class="tbl-scroll">' + inner + '</div></div>'; }
  function tbl(heads, bodyRows, totRow) {
    var th = '<tr>' + heads.map(function (h, i) { return '<th class="' + (i === 0 ? '' : 'num') + '">' + h + '</th>'; }).join('') + '</tr>';
    return '<table class="vtbl"><thead>' + th + '</thead><tbody>' + bodyRows.join('') + (totRow || '') + '</tbody></table>';
  }
  function rowV(cells, cls) { return '<tr' + (cls ? ' class="' + cls + '"' : '') + '>' + cells.map(function (c, i) { return '<td class="' + (i === 0 ? 'lab' : 'num') + '">' + c + '</td>'; }).join('') + '</tr>'; }
  function roasCell(r) { if (r == null) return '—'; var c = r >= 1.5 ? 'var(--teal)' : r >= 1 ? 'var(--gold)' : 'var(--red)'; return '<b style="color:' + c + '">' + fRoas(r) + '</b>'; }

  /* =====================================================================
     ROUTER
  ===================================================================== */
  var mounted = {};
  function show(tab) {
    if (tab !== 'pesquisa' && tab !== 'vendas' && !D[tab]) tab = 'segunda';
    Array.prototype.forEach.call(document.querySelectorAll('#mainTabs .tab'), function (b) { b.classList.toggle('active', b.getAttribute('data-tab') === tab); });
    Array.prototype.forEach.call(document.querySelectorAll('.view'), function (v) { v.classList.toggle('active', v.id === 'view-' + tab); });
    if (!mounted[tab]) { mounted[tab] = true; if (tab === 'pesquisa') mountPesquisa(); else if (tab === 'vendas') mountVendas(); else mountFunnel(tab); }
    if (location.hash.slice(1) !== tab) history.replaceState(null, '', '#' + tab);
  }
  Array.prototype.forEach.call(document.querySelectorAll('#mainTabs .tab'), function (b) { b.addEventListener('click', function () { show(b.getAttribute('data-tab')); }); });
  window.addEventListener('hashchange', function () { show(location.hash.slice(1) || 'segunda'); });

  // header meta
  var gen = 'Atualizado ' + (D.generatedAtBR || '') + ' (BRT)';
  $('#genAt').textContent = gen; $('#footGen').textContent = gen;

  show(location.hash.slice(1) || 'segunda');
})();
