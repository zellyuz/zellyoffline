/// Telegram WebApp / brauzer uchun hisobot paneli (statik HTML).
///
/// `GET /reports/view` shu sahifani qaytaradi. Sahifa o'zi login so'raydi va
/// keyingi so'rovlarni `Authorization: Bearer <token>` bilan yuboradi.
library;

String mobileReportHtml() => r'''
<!DOCTYPE html>
<html lang="uz">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0,user-scalable=no,maximum-scale=1.0">
<title>Hisobot Panel</title>
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#0F172A;--sf:#1E293B;--sf2:#253047;--bd:#334155;
  --tx:#F8FAFC;--mu:#94A3B8;--mu2:#64748B;
  --ac:#6C5CE7;--acl:rgba(108,92,231,.18);
  --gr:#10B981;--bl:#3B82F6;--rd:#EF4444;
  --yw:#F59E0B;--cy:#06B6D4;--pu:#8B5CF6;
  --nh:60px;
}
html,body{background:var(--bg);color:var(--tx);min-height:100vh;
  font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',system-ui,sans-serif;
  -webkit-font-smoothing:antialiased;overflow-x:hidden}
button,input,select{font-family:inherit}
::-webkit-scrollbar{width:3px;height:3px}
::-webkit-scrollbar-thumb{background:var(--bd);border-radius:3px}

/* LOGIN */
#login{display:flex;flex-direction:column;align-items:center;justify-content:center;
  min-height:100vh;padding:32px}
.lgo{font-size:52px;margin-bottom:14px}
.lt{font-size:24px;font-weight:800;margin-bottom:6px}
.ls{color:var(--mu);font-size:13px;margin-bottom:40px}
.pin-i{background:var(--sf);border:2px solid var(--bd);border-radius:14px;
  color:var(--tx);font-size:24px;letter-spacing:8px;padding:16px 20px;
  text-align:center;width:240px;outline:none;transition:border-color .2s;-webkit-appearance:none}
.pin-i:focus{border-color:var(--ac)}
.pin-err{color:var(--rd);font-size:13px;min-height:20px;text-align:center;margin:10px 0}
.pin-btn{background:var(--ac);border:none;border-radius:14px;color:#fff;
  font-size:16px;font-weight:700;padding:16px 0;width:240px;
  cursor:pointer;transition:opacity .15s;-webkit-tap-highlight-color:transparent}
.pin-btn:active{opacity:.8}

/* APP */
#app{display:none;max-width:520px;margin:0 auto;padding-bottom:var(--nh)}

/* HEADER */
.hdr{background:var(--sf);padding:12px 16px;position:sticky;top:0;z-index:200;
  border-bottom:1px solid var(--bd)}
.hdr-r{display:flex;justify-content:space-between;align-items:center}
.hdr-nm{font-size:16px;font-weight:800}
.hdr-sb{font-size:11px;color:var(--mu);margin-top:2px}
.hdr-btns{display:flex;gap:6px}
.hdr-btn{background:var(--bd);border:none;border-radius:10px;color:var(--tx);
  font-size:15px;padding:7px 13px;cursor:pointer;line-height:1}
.hdr-btn:active{opacity:.7}

/* PERIOD BAR */
.period-bar{background:var(--sf);border-bottom:1px solid var(--bd)}
.chips-row{display:flex;gap:5px;overflow-x:auto;padding:10px 12px;scrollbar-width:none}
.chips-row::-webkit-scrollbar{display:none}
.chip{background:transparent;border:1.5px solid var(--bd);border-radius:20px;
  color:var(--mu);font-size:13px;font-weight:600;padding:6px 13px;cursor:pointer;
  transition:all .18s;white-space:nowrap;user-select:none;flex-shrink:0}
.chip.on{background:var(--ac);border-color:var(--ac);color:#fff}
.custom-row{display:none;padding:0 12px 10px;gap:8px;align-items:center}
.custom-row.show{display:flex}
.dt-i{background:var(--sf2);border:1.5px solid var(--bd);border-radius:10px;
  color:var(--tx);font-size:12px;padding:7px 10px;flex:1;outline:none;-webkit-appearance:none}
.dt-i:focus{border-color:var(--ac)}
.dt-ok{background:var(--ac);border:none;border-radius:10px;color:#fff;
  font-size:13px;font-weight:700;padding:7px 14px;cursor:pointer}

/* FILTER */
.flt-tgl{display:flex;justify-content:space-between;align-items:center;
  padding:8px 16px;border-bottom:1px solid var(--bd);background:var(--sf)}
.flt-lbl{font-size:12px;color:var(--mu);font-weight:600}
.flt-btn{background:var(--acl);border:1px solid var(--ac);border-radius:8px;
  color:var(--ac);font-size:12px;font-weight:600;padding:5px 12px;cursor:pointer}
.flt-panel{background:var(--sf);border-bottom:1px solid var(--bd);
  padding:12px 16px;display:none;flex-direction:column;gap:10px}
.flt-panel.show{display:flex}
.flt-grp label{font-size:11px;color:var(--mu);font-weight:700;
  text-transform:uppercase;letter-spacing:.4px;margin-bottom:6px;display:block}
.type-chips{display:flex;gap:5px;flex-wrap:wrap}
.tc{background:var(--sf2);border:1.5px solid var(--bd);border-radius:8px;
  color:var(--mu);font-size:12px;font-weight:600;padding:5px 12px;
  cursor:pointer;user-select:none;transition:all .15s}
.tc.on{background:var(--acl);border-color:var(--ac);color:var(--ac)}
.flt-row{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.flt-sel{background:var(--sf2);border:1.5px solid var(--bd);border-radius:10px;
  color:var(--tx);font-size:13px;padding:8px 12px;width:100%;outline:none}
.flt-sel:focus{border-color:var(--ac)}

/* INFO BAR */
.info-bar{display:flex;justify-content:space-between;font-size:11px;
  color:var(--mu2);padding:6px 12px 4px}

/* TAB PANELS */
.tab-p{display:none;padding:12px}
.tab-p.show{display:block}

/* BOTTOM NAV */
.bot-nav{position:fixed;bottom:0;left:0;right:0;z-index:300;
  background:var(--sf);border-top:1px solid var(--bd);
  display:flex;max-width:520px;margin:0 auto}
.nav-btn{flex:1;display:flex;flex-direction:column;align-items:center;
  justify-content:center;padding:8px 4px;gap:2px;background:none;border:none;
  color:var(--mu);font-size:10px;font-weight:600;cursor:pointer;
  transition:color .15s;-webkit-tap-highlight-color:transparent;user-select:none}
.nav-btn.on{color:var(--ac)}
.nav-ico{font-size:20px;line-height:1}

/* CARDS */
.card{background:var(--sf);border-radius:16px;padding:16px;margin-bottom:10px}
.c-lbl{color:var(--mu);font-size:11px;font-weight:700;letter-spacing:.5px;
  text-transform:uppercase;margin-bottom:8px}
.card.ac-l{border-left:4px solid var(--ac)}

/* KPI */
.kpi-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:10px}
.kpi{background:var(--sf);border-radius:14px;padding:14px 16px}
.kv{font-size:20px;font-weight:800;margin-bottom:2px}
.kv.lg{font-size:28px;font-weight:900;letter-spacing:-1px}
.ku{color:var(--mu);font-size:11px}

/* PAYMENT ROW */
.pay-row{display:flex;align-items:center;padding:8px 0;border-bottom:1px solid var(--bd)}
.pay-row:last-child{border-bottom:none}
.pay-ico{width:32px;height:32px;border-radius:8px;display:flex;align-items:center;
  justify-content:center;font-size:15px;margin-right:10px;flex-shrink:0}
.pay-info{flex:1;min-width:0}
.pay-nm{font-size:13px;font-weight:600}
.pay-bar-w{height:4px;background:var(--bd);border-radius:2px;margin-top:3px;overflow:hidden}
.pay-bar{height:100%;border-radius:2px;transition:width .5s}
.pay-pct{font-size:10px;color:var(--mu);margin-top:1px}
.pay-amt{font-size:14px;font-weight:800;text-align:right;white-space:nowrap;padding-left:8px}

/* ROW LIST */
.row{display:flex;justify-content:space-between;align-items:center;
  padding:10px 0;border-bottom:1px solid var(--bd)}
.row:last-child{border-bottom:none}
.row-l{display:flex;align-items:center;gap:8px;min-width:0;flex:1}
.row-nm{font-size:14px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.row-sb{font-size:11px;color:var(--mu);margin-top:1px}
.row-v{font-size:14px;font-weight:700;text-align:right;flex-shrink:0;padding-left:8px}

/* RANK BADGE */
.rnk{width:26px;height:26px;border-radius:7px;background:var(--ac);color:#fff;
  font-size:11px;font-weight:800;display:flex;align-items:center;
  justify-content:center;flex-shrink:0}
.rnk.g{background:var(--yw)}.rnk.s{background:#94A3B8}.rnk.b{background:#CD7C4A}

/* BADGE */
.bdg{font-size:11px;font-weight:700;padding:3px 8px;border-radius:6px;white-space:nowrap}
.bdg.cash,.bdg.naqd{background:rgba(16,185,129,.2);color:var(--gr)}
.bdg.card,.bdg.karta{background:rgba(59,130,246,.2);color:var(--bl)}
.bdg.terminal{background:rgba(139,92,246,.2);color:var(--pu)}
.bdg.bonus{background:rgba(245,158,11,.2);color:var(--yw)}
.bdg.debt,.bdg.qarz{background:rgba(239,68,68,.2);color:var(--rd)}
.bdg.transfer{background:rgba(6,182,212,.2);color:var(--cy)}
.bdg.mixed{background:rgba(108,92,231,.2);color:var(--ac)}
.bdg.t0{background:rgba(108,92,231,.15);color:var(--ac)}
.bdg.t1{background:rgba(16,185,129,.15);color:var(--gr)}
.bdg.t2{background:rgba(6,182,212,.15);color:var(--cy)}

/* ORDER CARD */
.ord-c{background:var(--sf);border-radius:14px;padding:14px;margin-bottom:8px}
.ord-top{display:flex;justify-content:space-between;margin-bottom:6px}
.ord-time{font-size:12px;color:var(--mu)}
.ord-amt{font-size:16px;font-weight:800;color:var(--ac)}
.ord-mid{display:flex;justify-content:space-between;align-items:flex-end}
.ord-nm{font-size:13px;font-weight:600}
.ord-wtr{font-size:11px;color:var(--mu);margin-top:2px}
.ord-bdgs{display:flex;gap:4px;flex-wrap:wrap}

/* SUMMARY STRIP */
.sum-strip{background:var(--sf);border-radius:14px;padding:14px 16px;
  margin-bottom:10px;display:grid;grid-template-columns:repeat(3,1fr);gap:8px}
.ss{text-align:center}
.ss-v{font-size:16px;font-weight:800}
.ss-l{font-size:10px;color:var(--mu);margin-top:2px}

/* CHART */
.chart-w{position:relative;height:190px;margin-top:4px}

/* WAITER CARD */
.wtr-c{background:var(--sf);border-radius:14px;padding:14px;margin-bottom:8px}
.wtr-top{display:flex;justify-content:space-between;align-items:center;margin-bottom:10px}
.wtr-nm{font-size:15px;font-weight:800}
.wtr-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:6px}
.wtr-st{background:var(--sf2);border-radius:8px;padding:8px;text-align:center}
.wtr-sv{font-size:13px;font-weight:700}
.wtr-sl{font-size:10px;color:var(--mu);margin-top:1px}

/* Z-REPORT */
.z-hdr{background:linear-gradient(135deg,#3730A3,var(--ac));border-radius:16px;
  padding:20px;text-align:center;margin-bottom:10px}
.z-v{font-size:32px;font-weight:900;letter-spacing:-1px}
.z-l{font-size:12px;color:rgba(255,255,255,.75);margin-top:4px}
.z-grid{display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px;margin-top:12px}
.z-mini{background:rgba(255,255,255,.12);border-radius:10px;padding:10px;text-align:center}
.z-mv{font-size:15px;font-weight:800}
.z-ml{font-size:10px;color:rgba(255,255,255,.7);margin-top:2px}

/* CATEGORY CHIPS */
.cat-chips{display:flex;gap:5px;overflow-x:auto;margin-bottom:10px;
  padding-bottom:2px;scrollbar-width:none}
.cat-chips::-webkit-scrollbar{display:none}
.cc{background:var(--sf2);border:1.5px solid var(--bd);border-radius:20px;
  color:var(--mu);font-size:12px;font-weight:600;padding:5px 12px;
  white-space:nowrap;flex-shrink:0;cursor:pointer;user-select:none;transition:all .15s}
.cc.on{background:var(--acl);border-color:var(--ac);color:var(--ac)}

/* SORT BUTTONS */
.sort-row{display:flex;gap:6px;margin-bottom:10px}
.sort-btn{background:var(--sf2);border:1.5px solid var(--bd);border-radius:8px;
  color:var(--mu);font-size:12px;font-weight:600;padding:6px 14px;
  cursor:pointer;transition:all .15s}
.sort-btn.on{background:var(--acl);border-color:var(--ac);color:var(--ac)}

/* LOAD MORE */
.load-more{background:var(--sf2);border:none;border-radius:12px;color:var(--mu);
  font-size:13px;font-weight:600;padding:12px;width:100%;margin-top:4px;cursor:pointer}
.load-more:active{opacity:.7}

/* SMENA SELEKTOR */
.shift-row{display:none;flex-direction:column;gap:6px;padding:0 12px 10px}
.shift-row.show{display:flex}
.shift-item{background:var(--sf2);border:1.5px solid var(--bd);border-radius:12px;
  padding:12px 14px;cursor:pointer;transition:all .15s;
  display:flex;justify-content:space-between;align-items:center}
.shift-item.on{border-color:var(--ac);background:var(--acl)}
.shift-item:active{opacity:.8}
.shift-badge{font-size:11px;font-weight:700;padding:3px 8px;border-radius:6px}
.shift-badge.open{background:rgba(16,185,129,.2);color:var(--gr)}
.shift-badge.closed{background:rgba(148,163,184,.15);color:var(--mu)}

/* SKELETON */
.sk{background:linear-gradient(90deg,var(--bd) 25%,var(--sf2) 50%,var(--bd) 75%);
  background-size:200%;animation:sh 1.5s infinite;border-radius:8px;height:18px;margin:7px 0}
@keyframes sh{0%{background-position:200%}100%{background-position:-200%}}
.empty{color:var(--mu);font-size:13px;padding:24px 0;text-align:center}
</style>
</head>
<body>

<!-- LOGIN -->
<div id="login">
  <div class="lgo">📊</div>
  <div class="lt">Hisobot Panel</div>
  <p class="ls">Kirish uchun PIN kodni kiriting</p>
  <input id="pin" type="password" inputmode="numeric" maxlength="8"
         class="pin-i" placeholder="••••" autocomplete="current-password">
  <p class="pin-err" id="perr"></p>
  <button class="pin-btn" id="lbtn">Kirish</button>
</div>

<!-- APP -->
<div id="app">

  <!-- Header -->
  <div class="hdr">
    <div class="hdr-r">
      <div>
        <div class="hdr-nm" id="rest-nm">Dashboard</div>
        <div class="hdr-sb" id="rest-sb">Yuklanmoqda...</div>
      </div>
      <div class="hdr-btns">
        <button class="hdr-btn" id="refresh-btn">↻</button>
        <button class="hdr-btn" id="logout-btn">⏻</button>
      </div>
    </div>
  </div>

  <!-- Period Bar -->
  <div class="period-bar">
    <div class="chips-row">
      <div class="chip on" data-p="today">Bugun</div>
      <div class="chip" data-p="yesterday">Kecha</div>
      <div class="chip" data-p="week">7 kun</div>
      <div class="chip" data-p="month">Bu oy</div>
      <div class="chip" data-p="prevmonth">O'tgan oy</div>
      <div class="chip" data-p="smena">🔄 Smena</div>
      <div class="chip" data-p="custom">📅 Tanlash</div>
    </div>
    <div class="custom-row" id="custom-row">
      <input type="date" class="dt-i" id="dt-from">
      <span style="color:var(--mu);font-size:12px">→</span>
      <input type="date" class="dt-i" id="dt-to">
      <button class="dt-ok" id="dt-ok">OK</button>
    </div>
    <div class="shift-row" id="shift-row">
      <div id="shift-list-sel"><div class="sk"></div><div class="sk" style="width:75%"></div></div>
    </div>
  </div>

  <!-- Filter Toggle -->
  <div class="flt-tgl">
    <span class="flt-lbl" id="flt-sum">Barcha buyurtmalar</span>
    <button class="flt-btn" id="flt-toggle">⚙ Filtr</button>
  </div>

  <!-- Filter Panel -->
  <div class="flt-panel" id="flt-panel">
    <div class="flt-grp">
      <label>Buyurtma turi</label>
      <div class="type-chips">
        <div class="tc on" data-ot="all">Barchasi</div>
        <div class="tc" data-ot="0">🍽 Zalda</div>
        <div class="tc" data-ot="1">📦 Olib ketish</div>
        <div class="tc" data-ot="2">🛵 Yetkazish</div>
      </div>
    </div>
    <div class="flt-row">
      <div class="flt-grp">
        <label>Joy</label>
        <select class="flt-sel" id="flt-loc"><option value="">Barchasi</option></select>
      </div>
      <div class="flt-grp">
        <label>Xodim</label>
        <select class="flt-sel" id="flt-wtr"><option value="">Barchasi</option></select>
      </div>
    </div>
  </div>

  <!-- Info Bar -->
  <div class="info-bar">
    <span>Yangilangan: <span id="last-upd">—</span></span>
    <span style="color:var(--ac)" id="plbl"></span>
  </div>

  <!-- TAB 0: Analitika -->
  <div class="tab-p show" id="tab-0">
    <div class="card ac-l">
      <div class="c-lbl">Jami tushum</div>
      <div class="kv lg" id="d-total"><div class="sk" style="width:55%"></div></div>
      <div class="ku">so'm</div>
    </div>
    <div class="kpi-grid">
      <div class="kpi">
        <div class="c-lbl">Buyurtmalar</div>
        <div class="kv" id="d-count">—</div>
        <div class="ku">ta</div>
      </div>
      <div class="kpi">
        <div class="c-lbl">O'rtacha chek</div>
        <div class="kv" id="d-avg">—</div>
        <div class="ku">so'm</div>
      </div>
    </div>
    <div class="card" id="d-pay-card">
      <div class="c-lbl">To'lov turlari</div>
      <div id="d-pay"><div class="sk"></div><div class="sk" style="width:75%"></div></div>
    </div>
    <div class="card">
      <div class="c-lbl">Soatlik faollik</div>
      <div class="chart-w"><canvas id="hchart"></canvas></div>
    </div>
    <div class="card">
      <div class="c-lbl">Top mahsulotlar (daromad)</div>
      <div id="d-top"><div class="sk"></div><div class="sk" style="width:80%"></div><div class="sk" style="width:60%"></div></div>
    </div>
  </div>

  <!-- TAB 1: Buyurtmalar -->
  <div class="tab-p" id="tab-1">
    <div class="sum-strip">
      <div class="ss"><div class="ss-v" id="os-c">—</div><div class="ss-l">Buyurtmalar</div></div>
      <div class="ss"><div class="ss-v" id="os-t">—</div><div class="ss-l">Tushum</div></div>
      <div class="ss"><div class="ss-v" id="os-a">—</div><div class="ss-l">O'rtacha</div></div>
    </div>
    <div id="ord-list"><div class="sk"></div><div class="sk" style="width:85%"></div></div>
    <button class="load-more" id="load-more" style="display:none">Ko'proq yuklash ↓</button>
  </div>

  <!-- TAB 2: Mahsulotlar -->
  <div class="tab-p" id="tab-2">
    <div class="cat-chips" id="cat-chips">
      <div class="cc on" data-cat="">Barchasi</div>
    </div>
    <div class="sort-row">
      <button class="sort-btn on" id="s-rev" onclick="setSrt('rev')">💰 Daromad</button>
      <button class="sort-btn" id="s-qty" onclick="setSrt('qty')">📦 Miqdor</button>
    </div>
    <div class="card">
      <div id="prod-list"><div class="sk"></div><div class="sk" style="width:80%"></div><div class="sk" style="width:60%"></div></div>
    </div>
  </div>

  <!-- TAB 3: Xodimlar -->
  <div class="tab-p" id="tab-3">
    <div id="wtr-list"><div class="sk"></div><div class="sk" style="width:75%"></div></div>
  </div>

  <!-- TAB 4: Z-Hisobot -->
  <div class="tab-p" id="tab-4">
    <div id="z-cont"><div class="sk"></div><div class="sk" style="width:80%"></div><div class="sk" style="width:60%"></div></div>
  </div>

  <!-- Bottom Nav -->
  <div class="bot-nav">
    <button class="nav-btn on" data-tab="0"><div class="nav-ico">📊</div><div>Analitika</div></button>
    <button class="nav-btn" data-tab="1"><div class="nav-ico">📋</div><div>Buyurtmalar</div></button>
    <button class="nav-btn" data-tab="2"><div class="nav-ico">🍽</div><div>Mahsulotlar</div></button>
    <button class="nav-btn" data-tab="3"><div class="nav-ico">👤</div><div>Xodimlar</div></button>
    <button class="nav-btn" data-tab="4"><div class="nav-ico">📄</div><div>Z-Hisobot</div></button>
  </div>

</div><!-- #app -->

<script>
// ── STATE ─────────────────────────────────────────────────────────────────────
var T = sessionStorage.getItem('_zt');
var _per = 'today', _cs = null, _ce = null;
var _ot = null, _loc = '', _wtr = '';
var _tab = 0, _ld = [false,false,false,false,false];
var _ords = [], _pg = 0, PG = 25;
var _prods = [], _cat = '', _srt = 'rev';
var _hChart = null, _tmr = null;
// Server tomonidan hisoblangan davr chegaralari (getDayStartTime asosida)
var _srv = {};
// Smena filter
var _shiftId = null, _shiftList = [];

// ── UTILS ─────────────────────────────────────────────────────────────────────
function $e(id){ return document.getElementById(id); }

function fN(n){
  var v = parseFloat(n)||0;
  if(v>=1e9) return (v/1e9).toFixed(1).replace('.0','')+'mlrd';
  if(v>=1e6) return (v/1e6).toFixed(1).replace('.0','')+'mln';
  if(v>=1000) return Math.round(v/1000)+'K';
  return Math.round(v).toString();
}
function fF(n){ return Math.round(parseFloat(n)||0).toLocaleString('uz-UZ'); }
function fDT(iso){
  if(!iso) return '—';
  var d=new Date(iso);
  return ('0'+d.getDate()).slice(-2)+'.'+('0'+(d.getMonth()+1)).slice(-2)+
    ' '+('0'+d.getHours()).slice(-2)+':'+('0'+d.getMinutes()).slice(-2);
}
function fD(iso){
  if(!iso) return '—';
  var d=new Date(iso);
  return ('0'+d.getDate()).slice(-2)+'.'+('0'+(d.getMonth()+1)).slice(-2)+'.'+d.getFullYear();
}

function getR(){
  // Display uchun Date object qaytaradi
  // _srv mavjud bo'lsa — server raw string dan Date yasaymiz (faqat display uchun)
  if(_per!=='custom' && _srv[_per]) return [new Date(_srv[_per][0]),new Date(_srv[_per][1])];
  var n=new Date(),y=n.getFullYear(),m=n.getMonth(),d=n.getDate();
  function mk(dy,dm,dd){ return new Date(y+dy,m+dm,d+dd); }
  if(_per==='today')     return [mk(0,0,0),mk(0,0,1)];
  if(_per==='yesterday') return [mk(0,0,-1),mk(0,0,0)];
  if(_per==='week')      return [mk(0,0,-6),mk(0,0,1)];
  if(_per==='month')     return [new Date(y,m,1),mk(0,0,1)];
  if(_per==='prevmonth') return [new Date(y,m-1,1),new Date(y,m,1)];
  if(_per==='custom'&&_cs){ var e=_ce?new Date(_ce.getTime()+86400000):mk(0,0,1); return [_cs,e]; }
  return [mk(0,0,0),mk(0,0,1)];
}

function bQ(){
  if(_shiftId!==null) return 'shift_id='+_shiftId;
  var q;
  // Server raw string (mahalliy vaqt, Z siz) mavjud bo'lsa — shuni yuboramiz
  // toISOString() ishlatmaslik kerak — u UTC ga o'tkazib DB taqqoslashni buzadi
  if(_per!=='custom' && _srv[_per]){
    q='start='+encodeURIComponent(_srv[_per][0])+'&end='+encodeURIComponent(_srv[_per][1]);
  } else {
    var r=getR();
    // Custom yoki fallback uchun ham mahalliy vaqt string yasaymiz (toISOString() EMAS)
    function toLocal(dt){
      var pad=function(n){return ('0'+n).slice(-2);};
      return dt.getFullYear()+'-'+pad(dt.getMonth()+1)+'-'+pad(dt.getDate())
        +'T'+pad(dt.getHours())+':'+pad(dt.getMinutes())+':'+pad(dt.getSeconds())+'.000';
    }
    q='start='+encodeURIComponent(toLocal(r[0]))+'&end='+encodeURIComponent(toLocal(r[1]));
  }
  if(_ot!==null) q+='&order_type='+_ot;
  if(_loc) q+='&location_id='+_loc;
  if(_wtr) q+='&waiter_id='+_wtr;
  return q;
}

function rnk(i){ return 'rnk'+(i===0?' g':i===1?' s':i===2?' b':''); }

var PAYS=[
  {k:'cash_total',     l:'Naqd',      i:'💵', c:'#10B981'},
  {k:'card_total',     l:'Karta',     i:'💳', c:'#3B82F6'},
  {k:'terminal_total', l:'Terminal',  i:'🖥',  c:'#8B5CF6'},
  {k:'bonus_total',    l:'Bonus',     i:'⭐', c:'#F59E0B'},
  {k:'transfer_total', l:"O'tkazma",  i:'📲', c:'#06B6D4'},
  {k:'debt_total',     l:'Qarz',      i:'📒', c:'#EF4444'},
];

function payBdg(pt){
  var map={cash:'cash',naqd:'cash',card:'card',karta:'card',
    terminal:'terminal',bonus:'bonus',transfer:'transfer',debt:'debt',qarz:'debt'};
  var lbl={cash:'Naqd',naqd:'Naqd',card:'Karta',karta:'Karta',
    terminal:'Terminal',bonus:'Bonus',transfer:"O'tkazma",debt:'Qarz',qarz:'Qarz'};
  var k=(pt||'').toLowerCase();
  return '<span class="bdg '+(map[k]||'mixed')+'">'+(lbl[k]||pt||'Aralash')+'</span>';
}

function otBdg(t){
  if(t===0) return '<span class="bdg t0">Zalda</span>';
  if(t===1) return '<span class="bdg t1">Olib ketish</span>';
  if(t===2) return '<span class="bdg t2">Yetkazish</span>';
  return '';
}

// ── API ───────────────────────────────────────────────────────────────────────
async function apig(path){
  var r=await fetch(path,{headers:{'Authorization':'Bearer '+T}});
  if(r.status===401){ doLogout(); throw new Error('unauth'); }
  if(!r.ok) throw new Error('HTTP '+r.status);
  return r.json();
}

// ── DASHBOARD ─────────────────────────────────────────────────────────────────
async function loadDash(){
  var q=bQ();
  var stats,hourly;
  try{
    var res=await Promise.all([apig('/reports/stats?'+q),apig('/reports/hourly?'+q)]);
    stats=res[0]; hourly=res[1];
  }catch(e){ stats={metrics:{},topRevenue:[],topQty:[]}; hourly=[]; }

  var m=(stats&&stats.metrics)||{};
  $e('d-total').textContent=fF(m.total||0);
  $e('d-count').textContent=(m.count||0)+' ta';
  $e('d-avg').textContent=fN(m.avg_check||0);

  // Payment breakdown
  var tot=parseFloat(m.total)||1;
  var pays=PAYS.filter(function(p){ return parseFloat(m[p.k])>0; });
  $e('d-pay').innerHTML=pays.length?pays.map(function(p){
    var amt=parseFloat(m[p.k])||0, pct=Math.round(amt/tot*100);
    return '<div class="pay-row">'+
      '<div class="pay-ico" style="background:'+p.c+'22">'+p.i+'</div>'+
      '<div class="pay-info">'+
        '<div class="pay-nm">'+p.l+'</div>'+
        '<div class="pay-bar-w"><div class="pay-bar" style="width:'+pct+'%;background:'+p.c+'"></div></div>'+
        '<div class="pay-pct">'+pct+'%</div>'+
      '</div>'+
      '<div class="pay-amt" style="color:'+p.c+'">'+fF(amt)+'</div>'+
    '</div>';
  }).join(''):'<div class="empty">To\'lov yo\'q</div>';

  // Hourly chart
  var revs=[];
  for(var h=0;h<24;h++){
    var f=null;
    for(var j=0;j<hourly.length;j++){ if(hourly[j].hour===h){f=hourly[j];break;} }
    revs.push(f?parseFloat(f.revenue)||0:0);
  }
  var lbls=['0','1','2','3','4','5','6','7','8','9','10','11',
            '12','13','14','15','16','17','18','19','20','21','22','23'];
  function buildChart(){
    if(_hChart){ _hChart.data.datasets[0].data=revs; _hChart.update('none'); return; }
    if(typeof Chart==='undefined'){ window._chartPending=buildChart; return; }
    _hChart=new Chart(document.getElementById('hchart').getContext('2d'),{
      type:'bar',
      data:{labels:lbls,datasets:[{data:revs,
        backgroundColor:'rgba(108,92,231,.55)',borderColor:'#6C5CE7',
        borderWidth:1,borderRadius:3}]},
      options:{responsive:true,maintainAspectRatio:false,
        plugins:{legend:{display:false},
          tooltip:{callbacks:{label:function(c){return fF(c.raw)+" so'm";}}}},
        scales:{
          x:{ticks:{color:'#94A3B8',font:{size:9},maxRotation:0},grid:{color:'rgba(51,65,85,.5)'}},
          y:{ticks:{color:'#94A3B8',font:{size:9},callback:function(v){return fN(v);}},
             grid:{color:'rgba(51,65,85,.5)'}}
        }
      }
    });
  }
  buildChart();

  // Top products
  var tp=(stats.topRevenue||[]).slice(0,5);
  $e('d-top').innerHTML=tp.length?tp.map(function(p,i){
    return '<div class="row">'+
      '<div class="row-l"><div class="'+rnk(i)+'">'+(i+1)+'</div>'+
      '<div class="row-nm">'+p.name+'</div></div>'+
      '<div class="row-v" style="color:var(--ac)">'+fN(p.revenue)+'</div></div>';
  }).join(''):'<div class="empty">Ma\'lumot yo\'q</div>';
}

// ── ORDERS ────────────────────────────────────────────────────────────────────
async function loadOrds(){
  var q=bQ();
  try{ _ords=await apig('/reports/orders?'+q); }catch(e){ return; }
  _pg=0;
  var tot=_ords.reduce(function(s,o){return s+(parseFloat(o.grand_total)||parseFloat(o.total)||0);},0);
  $e('os-c').textContent=_ords.length;
  $e('os-t').textContent=fN(tot);
  $e('os-a').textContent=fN(_ords.length?tot/_ords.length:0);
  renderOrds();
}

function renderOrds(){
  var slice=_ords.slice(0,(_pg+1)*PG);
  $e('ord-list').innerHTML=slice.length?slice.map(function(o){
    var amt=parseFloat(o.grand_total)||parseFloat(o.total)||0;
    var place=o.table_name||(o.location_name)||'—';
    return '<div class="ord-c">'+
      '<div class="ord-top">'+
        '<span class="ord-time">'+fDT(o.created_at)+'</span>'+
        '<span class="ord-amt">'+fF(amt)+' so\'m</span>'+
      '</div>'+
      '<div class="ord-mid">'+
        '<div><div class="ord-nm">'+place+'</div>'+
        '<div class="ord-wtr">'+(o.waiter_name||'Kassa')+'</div></div>'+
        '<div class="ord-bdgs">'+otBdg(o.order_type)+payBdg(o.payment_type)+'</div>'+
      '</div>'+
    '</div>';
  }).join(''):'<div class="empty">Buyurtma topilmadi</div>';
  $e('load-more').style.display=((_pg+1)*PG<_ords.length)?'':'none';
}

// ── PRODUCTS ──────────────────────────────────────────────────────────────────
async function loadProds(){
  var q=bQ();
  try{ _prods=await apig('/reports/products?'+q); }catch(e){ return; }

  var cats={};
  _prods.forEach(function(p){ if(p.category) cats[p.category]=true; });
  var catList=Object.keys(cats).sort();
  var ch='<div class="cc on" data-cat="">Barchasi</div>';
  catList.forEach(function(c){ ch+='<div class="cc" data-cat="'+c+'">'+c+'</div>'; });
  $e('cat-chips').innerHTML=ch;
  document.querySelectorAll('.cc').forEach(function(el){
    el.addEventListener('click',function(){
      document.querySelectorAll('.cc').forEach(function(x){x.classList.remove('on');});
      el.classList.add('on'); _cat=el.getAttribute('data-cat'); renderProds();
    });
  });
  renderProds();
}

function setSrt(s){
  _srt=s;
  $e('s-rev').className='sort-btn'+(s==='rev'?' on':'');
  $e('s-qty').className='sort-btn'+(s==='qty'?' on':'');
  renderProds();
}

function renderProds(){
  var list=_prods.filter(function(p){return !_cat||p.category===_cat;});
  list=list.slice().sort(function(a,b){
    return _srt==='rev'?(b.total_revenue-a.total_revenue):(b.total_qty-a.total_qty);
  });
  $e('prod-list').innerHTML=list.length?list.map(function(p,i){
    return '<div class="row">'+
      '<div class="row-l"><div class="'+rnk(i)+'">'+(i+1)+'</div>'+
      '<div style="min-width:0"><div class="row-nm">'+p.name+'</div>'+
      '<div class="row-sb">'+(p.category||'')+'</div></div></div>'+
      '<div style="text-align:right;flex-shrink:0;padding-left:8px">'+
        '<div class="row-v" style="color:var(--ac)">'+fF(p.total_revenue)+'</div>'+
        '<div class="row-sb">'+Math.round(p.total_qty||0)+' ta</div>'+
      '</div></div>';
  }).join(''):'<div class="empty">Mahsulot topilmadi</div>';
}

// ── WAITERS ───────────────────────────────────────────────────────────────────
async function loadWtrs(){
  var q=bQ();
  var ws;
  try{ ws=await apig('/reports/waiters?'+q); }catch(e){ return; }
  if(!ws||!ws.length){ $e('wtr-list').innerHTML='<div class="empty">Ma\'lumot yo\'q</div>'; return; }
  $e('wtr-list').innerHTML=ws.map(function(w,i){
    var s=parseFloat(w.total_sales)||0, c=parseInt(w.order_count)||0;
    return '<div class="wtr-c">'+
      '<div class="wtr-top">'+
        '<div style="display:flex;align-items:center;gap:8px">'+
          '<div class="'+rnk(i)+'" style="width:32px;height:32px;font-size:14px">'+(i+1)+'</div>'+
          '<div><div class="wtr-nm">'+(w.name||'Nomalum')+'</div>'+
          '<div style="font-size:11px;color:var(--mu)">'+c+' ta buyurtma</div></div>'+
        '</div>'+
        '<div style="text-align:right">'+
          '<div style="font-size:16px;font-weight:800;color:var(--ac)">'+fN(s)+'</div>'+
          '<div style="font-size:11px;color:var(--mu)">so\'m</div>'+
        '</div>'+
      '</div>'+
      '<div class="wtr-grid">'+
        '<div class="wtr-st"><div class="wtr-sv">'+fN(s)+'</div><div class="wtr-sl">Tushum</div></div>'+
        '<div class="wtr-st"><div class="wtr-sv">'+c+'</div><div class="wtr-sl">Buyurtma</div></div>'+
        '<div class="wtr-st"><div class="wtr-sv">'+fN(c?s/c:0)+'</div><div class="wtr-sl">O\'rtacha</div></div>'+
      '</div>'+
    '</div>';
  }).join('');
}

// ── Z-REPORT ──────────────────────────────────────────────────────────────────
async function loadZ(){
  var q=bQ();
  var z;
  try{ z=await apig('/reports/zreport?'+q); }catch(e){ return; }
  var s=z.summary||{}, tot=parseFloat(s.total)||0, cnt=parseInt(s.count)||0;
  var r=getR();
  var d1=fD(r[0].toISOString()), d2=fD(new Date(r[1]-1).toISOString());

  var payH=PAYS.map(function(p){
    var a=parseFloat(s[p.k])||0;
    if(!a) return '';
    return '<div class="pay-row">'+
      '<div class="pay-ico" style="background:'+p.c+'22">'+p.i+'</div>'+
      '<div class="pay-info"><div class="pay-nm">'+p.l+'</div></div>'+
      '<div class="pay-amt" style="color:'+p.c+'">'+fF(a)+' so\'m</div></div>';
  }).filter(Boolean).join('');

  var wH=(z.waiterSales||[]).map(function(w,i){
    return '<div class="row">'+
      '<div class="row-l"><div class="'+rnk(i)+'">'+(i+1)+'</div>'+
      '<div class="row-nm">'+(w.name||'—')+'</div></div>'+
      '<div class="row-v" style="color:var(--ac)">'+fF(w.sales||0)+' so\'m</div></div>';
  }).join('');

  var cH=(z.categorySales||[]).map(function(c,i){
    return '<div class="row">'+
      '<div class="row-l"><div class="'+rnk(i)+'">'+(i+1)+'</div>'+
      '<div><div class="row-nm">'+(c.category||'Boshqa')+'</div>'+
      '<div class="row-sb">'+Math.round(c.qty||0)+' ta</div></div></div>'+
      '<div class="row-v" style="color:var(--ac)">'+fF(c.total||0)+' so\'m</div></div>';
  }).join('');

  var pH=(z.topProducts||[]).slice(0,10).map(function(p,i){
    return '<div class="row">'+
      '<div class="row-l"><div class="'+rnk(i)+'">'+(i+1)+'</div>'+
      '<div><div class="row-nm">'+p.name+'</div>'+
      '<div class="row-sb">'+Math.round(p.qty||0)+' ta</div></div></div>'+
      '<div style="text-align:right;flex-shrink:0;padding-left:8px">'+
        '<div class="row-v" style="color:var(--ac)">'+fF(p.revenue||0)+'</div>'+
      '</div></div>';
  }).join('');

  var hdrDate=_shiftId!==null?(
    (function(){
      var sv=_shiftList.find(function(x){return x.id===_shiftId;});
      return sv?'Smena: '+fD(sv.opened_at)+(sv.closed_at?' → '+fD(sv.closed_at):''):d1+' — '+d2;
    })()
  ):(d1+' — '+d2);
  var expHtml='';
  if(s.total_expenses&&parseFloat(s.total_expenses)>0){
    expHtml='<div class="card"><div class="c-lbl">Xarajatlar</div>'
      +'<div class="row"><div class="row-l"><div class="row-nm">Jami xarajat</div></div>'
      +'<div class="row-v" style="color:var(--rd)">'+fF(s.total_expenses)+' so\'m</div></div></div>';
  }
  $e('z-cont').innerHTML=
    '<div class="z-hdr">'+
      '<div style="font-size:12px;color:rgba(255,255,255,.7);margin-bottom:6px">'+hdrDate+'</div>'+
      '<div class="z-v">'+fF(tot)+' so\'m</div>'+
      '<div class="z-l">Jami tushum</div>'+
      '<div class="z-grid">'+
        '<div class="z-mini"><div class="z-mv">'+cnt+'</div><div class="z-ml">Buyurtmalar</div></div>'+
        '<div class="z-mini"><div class="z-mv">'+fN(cnt?tot/cnt:0)+'</div><div class="z-ml">O\'rtacha chek</div></div>'+
        (s.opening_cash!==undefined?'<div class="z-mini"><div class="z-mv">'+fN(s.opening_cash||0)+'</div><div class="z-ml">Ochilish</div></div>':'')+
      '</div>'+
    '</div>'+
    (payH?'<div class="card"><div class="c-lbl">To\'lov turlari</div>'+payH+'</div>':'')+
    expHtml+
    (wH?'<div class="card"><div class="c-lbl">Xodimlar savdosi</div>'+wH+'</div>':'')+
    (cH?'<div class="card"><div class="c-lbl">Kategoriyalar</div>'+cH+'</div>':'')+
    (pH?'<div class="card"><div class="c-lbl">Top mahsulotlar</div>'+pH+'</div>':'');
}

// ── SMENA ─────────────────────────────────────────────────────────────────────
async function loadShiftList(){
  $e('shift-list-sel').innerHTML='<div class="sk"></div><div class="sk" style="width:75%"></div>';
  try{
    var r=await fetch('/reports/shifts?limit=20',{headers:{'Authorization':'Bearer '+T}});
    if(r.ok) _shiftList=await r.json();
  }catch(e){ _shiftList=[]; }
  renderShiftList();
}

function renderShiftList(){
  var el=$e('shift-list-sel');
  if(!_shiftList||!_shiftList.length){
    el.innerHTML='<div class="empty">Smena topilmadi</div>'; return;
  }
  el.innerHTML=_shiftList.map(function(s,i){
    var isOpen=s.status===0;
    var opened=fDT(s.opened_at);
    var closed=s.closed_at?fDT(s.closed_at):'Ochiq';
    var isSel=_shiftId===s.id;
    var tot=parseFloat(s.total_sales)||0;
    var cnt=parseInt(s.order_count)||0;
    return '<div class="shift-item'+(isSel?' on':'')+'" onclick="selectShift('+s.id+')">'
      +'<div>'
        +'<div style="display:flex;align-items:center;gap:6px;margin-bottom:4px">'
          +'<span style="font-weight:800;font-size:13px">Smena #'+(i+1)+'</span>'
          +'<span class="shift-badge '+(isOpen?'open':'closed')+'">'+(isOpen?'Ochiq':'Yopildi')+'</span>'
        +'</div>'
        +'<div style="font-size:11px;color:var(--mu)">'+opened+(isOpen?'':' → '+closed)+'</div>'
        +'<div style="font-size:11px;color:var(--mu)">Ochgan: '+(s.opened_by_name||'—')+'</div>'
      +'</div>'
      +'<div style="text-align:right;flex-shrink:0;padding-left:10px">'
        +'<div style="font-weight:800;color:var(--ac);font-size:15px">'+fF(tot)+'</div>'
        +'<div style="font-size:10px;color:var(--mu)">so\'m</div>'
        +'<div style="font-size:11px;color:var(--mu);margin-top:2px">'+cnt+' buyurtma</div>'
      +'</div>'
    +'</div>';
  }).join('');
}

function selectShift(id){
  _shiftId=(_shiftId===id)?null:id;
  renderShiftList();
  var s=_shiftId!==null?_shiftList.find(function(x){return x.id===id;}):null;
  $e('plbl').textContent=s?('Smena: '+fD(s.opened_at)):'Smena';
  _ld=[false,false,false,false,false];
  loadTab(_tab);
  $e('last-upd').textContent=new Date().toLocaleTimeString('uz-UZ',{hour:'2-digit',minute:'2-digit'});
}

// ── LOADER ────────────────────────────────────────────────────────────────────
async function loadTab(n){
  try{
    if(n===0) await loadDash();
    else if(n===1) await loadOrds();
    else if(n===2) await loadProds();
    else if(n===3) await loadWtrs();
    else if(n===4) await loadZ();
    _ld[n]=true;
  }catch(e){ if(e.message!=='unauth') console.error(e); }
  $e('last-upd').textContent=new Date().toLocaleTimeString('uz-UZ',{hour:'2-digit',minute:'2-digit'});
}

function reload(){
  _ld=[false,false,false,false,false];
  loadTab(_tab);
}

// ── TAB SWITCH ────────────────────────────────────────────────────────────────
function switchTab(n){
  _tab=n;
  document.querySelectorAll('.tab-p').forEach(function(p,i){
    p.className='tab-p'+(i===n?' show':'');
  });
  document.querySelectorAll('.nav-btn').forEach(function(b){
    b.className='nav-btn'+(parseInt(b.getAttribute('data-tab'))===n?' on':'');
  });
  if(!_ld[n]) loadTab(n);
}

// ── PERIOD CHIPS ──────────────────────────────────────────────────────────────
var PLBL={today:'Bugun',yesterday:'Kecha',week:'7 kun',month:'Bu oy',prevmonth:"O'tgan oy",custom:'Tanlangan',smena:'Smena'};
function updPLbl(){
  if(_per==='smena'&&_shiftId!==null){
    var s=_shiftList.find(function(x){return x.id===_shiftId;});
    $e('plbl').textContent=s?'Smena: '+fD(s.opened_at):'Smena';
  } else {
    $e('plbl').textContent=PLBL[_per]||'';
  }
}

document.querySelectorAll('.chip').forEach(function(el){
  el.addEventListener('click',function(){
    _per=el.getAttribute('data-p');
    document.querySelectorAll('.chip').forEach(function(c){c.classList.remove('on');});
    el.classList.add('on');
    var isCustom=_per==='custom';
    var isSmena=_per==='smena';
    $e('custom-row').className='custom-row'+(isCustom?' show':'');
    $e('shift-row').className='shift-row'+(isSmena?' show':'');
    if(isSmena){
      _shiftId=null;
      loadShiftList();
    } else {
      _shiftId=null;
      if(!isCustom) reload();
    }
    updPLbl();
  });
});

$e('dt-ok').addEventListener('click',function(){
  var f=$e('dt-from').value, t=$e('dt-to').value;
  if(f&&t){ _cs=new Date(f); _ce=new Date(t); reload(); updPLbl(); }
});

// ── FILTER PANEL ──────────────────────────────────────────────────────────────
$e('flt-toggle').addEventListener('click',function(){
  var p=$e('flt-panel');
  p.className='flt-panel'+(p.classList.contains('show')?'':' show');
});

document.querySelectorAll('.tc').forEach(function(el){
  el.addEventListener('click',function(){
    document.querySelectorAll('.tc').forEach(function(c){c.classList.remove('on');});
    el.classList.add('on');
    var v=el.getAttribute('data-ot');
    _ot=(v==='all')?null:parseInt(v);
    reload(); updFltSum();
  });
});

$e('flt-loc').addEventListener('change',function(){ _loc=this.value; reload(); updFltSum(); });
$e('flt-wtr').addEventListener('change',function(){ _wtr=this.value; reload(); updFltSum(); });

function updFltSum(){
  var parts=[];
  if(_ot!==null) parts.push(['Zalda','Olib ketish','Yetkazish'][_ot]);
  var ls=$e('flt-loc'), ws=$e('flt-wtr');
  if(_loc) parts.push(ls.options[ls.selectedIndex].text);
  if(_wtr) parts.push(ws.options[ws.selectedIndex].text);
  $e('flt-sum').textContent=parts.length?parts.join(' · '):'Barcha buyurtmalar';
}

// ── LOAD MORE ─────────────────────────────────────────────────────────────────
$e('load-more').addEventListener('click',function(){ _pg++; renderOrds(); });

// ── NAV ───────────────────────────────────────────────────────────────────────
document.querySelectorAll('.nav-btn').forEach(function(el){
  el.addEventListener('click',function(){ switchTab(parseInt(el.getAttribute('data-tab'))); });
});

$e('refresh-btn').addEventListener('click', reload);

// ── AUTH ──────────────────────────────────────────────────────────────────────
async function doLogin(){
  var pin=$e('pin').value.trim();
  $e('perr').textContent='';
  if(!pin) return;
  $e('lbtn').disabled=true;
  try{
    var r=await fetch('/auth/login',{method:'POST',
      headers:{'Content-Type':'application/json'},body:JSON.stringify({pin:pin})});
    var d=await r.json();
    if(!r.ok){ $e('perr').textContent=(d&&d.message)||"PIN noto'g'ri"; return; }
    T=d.token; sessionStorage.setItem('_zt',T); await showApp();
  }catch(e){ $e('perr').textContent="Serverga ulanib bo'lmadi"; }
  finally{ $e('lbtn').disabled=false; }
}

function doLogout(){
  sessionStorage.removeItem('_zt'); T=null;
  $e('login').style.display=''; $e('app').style.display='none';
  $e('pin').value=''; clearInterval(_tmr);
}

async function showApp(){
  $e('login').style.display='none'; $e('app').style.display='block';
  try{
    var res=await Promise.all([
      fetch('/settings',{headers:{'Authorization':'Bearer '+T}}).then(function(r){return r.json();}),
      apig('/locations'),
      apig('/waiters'),
    ]);
    $e('rest-nm').textContent=res[0].restaurant_name||res[0].name||'Hisobot';
    $e('rest-sb').textContent='Hisobot paneli';
    var ls=$e('flt-loc'), ws=$e('flt-wtr');
    (res[1]||[]).forEach(function(l){
      var o=document.createElement('option'); o.value=l.id; o.textContent=l.name; ls.appendChild(o);
    });
    (res[2]||[]).forEach(function(w){
      var o=document.createElement('option'); o.value=w.id; o.textContent=w.name; ws.appendChild(o);
    });
  }catch(e){ $e('rest-sb').textContent='Hisobot paneli'; }
  // Server tomonida hisoblangan davr chegaralarini yuklaymiz
  // Bu Flutter ilovasidagi getDayStartTime() bilan bir xil natija beradi
  try{
    var pr=await fetch('/reports/periods',{headers:{'Authorization':'Bearer '+T}});
    if(pr.ok){
      var pd=await pr.json();
      ['today','yesterday','week','month','prevmonth'].forEach(function(k){
        if(pd[k]&&pd[k].length===2){
          // Raw string (mahalliy vaqt, Z siz) saqlayamiz — toISOString() UTC ga o'tkazib yuboradi
          _srv[k]=pd[k]; // ['2026-06-23T06:00:00.000', '2026-06-24T06:00:00.000']
        }
      });
    }
  }catch(_){}
  try{ updPLbl(); }catch(_){}
  try{ switchTab(0); }catch(_){}
  clearInterval(_tmr);
  _tmr=setInterval(reload,5*60*1000);
}

$e('lbtn').addEventListener('click',doLogin);
$e('pin').addEventListener('keydown',function(e){ if(e.key==='Enter') doLogin(); });
$e('logout-btn').addEventListener('click',function(){
  if(confirm("Chiqishni istaysizmi?")) doLogout();
});

if(T){
  fetch('/auth/me',{headers:{'Authorization':'Bearer '+T}})
    .then(function(r){ if(r.ok) showApp(); else doLogout(); })
    .catch(function(){ doLogout(); });
}
</script>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js" onload="if(window._chartPending)window._chartPending()"></script>
</body>
</html>
''';
