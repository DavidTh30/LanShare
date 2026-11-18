{ Generated from webui.html by tools/html2inc.py - do not edit by hand }
const
  WebUIHtml: string =
    '<!doctype html>' + #10 +
    '<html lang="th">' + #10 +
    '<head>' + #10 +
    '<meta charset="utf-8">' + #10 +
    '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">' + #10 +
    '<meta name="color-scheme" content="dark light">' + #10 +
    '<link rel="icon" type="image/png" href="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAADJElEQVR4nM2XS08TYRSGWfS3EA2GtdKaGFf8AzfGW4iSaCSo0JbeKC1QSkRAhHhBSpESbx' +
    'uNC1m48A9ourImuqaSuFBk7nM870wHWvtNmXJpPMmToed7z/uefk2a0tb2P1f3DPn6V6mTOct07wPMdcKnqeC+FeoYKNDL4Br9Ca0RHRT4wA++e4bfyZv9wWemGlo16bCBL/zdw3Nmf2iFxUcMcurCB5bMjlCO3/kyi44azkFezQKDi+bz8J' +
    'JJrQJ5O+HnMoYvvGhsMdRCtpBrX/+CcWLokUFuxHkg986gyYK7phrooMdcIx1yrQWCC0Zg6CE3BSSeGPTjJ1ml6USLb8Q6B5xDh8Ic5t20yLUWCD3QT0fmdRKRf2tQdX0umUKdA86rC/NuWuTaNzCjByJz3BQwmdNJ03YNNzZNis2Ltejj3C' +
    'nMYd7NG7nWAuFpPRCd1cmNp68NKn4xqVwxL303KT5Xq8Fr9FHQQY+5Rr7ItRaITGmB6D2N9iI2rVHpW2UJfuZe6fT+o2E9q/vQefFDrn0DWS0Qu8sBHohP7S7xb6GPc69eyLVvIMMLZLnpkeUXunAB9JvxQa61QIz/SExo5JX1D4ZwAfSb8Y' +
    'k5C0RTqj8xppJX8muacAH0m/FBrrVAPMkLpLjpgeSoSqWv4htAH+devZBrLTA8rPoZ2otkksNLdjie+Tx/HOu69azuQ+fFD7nWAomI0jUcU8iN5SWVikWDymVzNyReq8FrZwnooMdcI1/k2jcQVrpGhhQSMZNVa74JyxsmpaNiLfo4dwpzmH' +
    'fzRq59AwPKqZEQNwUUcmrN51z8ZAh1DjivLsy7aZFrLZC8LZ9MDcokYjwi02bl6vGOVh6rQp0Dzp0bwxzm3bTItRfok4+nb8nkRiYoU4GN76cVV0010EGPuUY65NofQa/sS9+Uf6f7+KBVcB5yd36WjV6X8qM3JGoZnFfzozTVI7WP9UoKQy' +
    '1AQV7dT/PxHql3/KpERw7n1IXvLHFJupa5LMmZKxIdOuwLf9dwpyYubLczOeZX9uI2HRT4VPzqr71RZc9v+5hjjJ85sw/8lXnX/47/AriMiRJ2A1HpAAAAAElFTkSuQmCC">' + #10 +
    '<title>LAN Share</title>' + #10 +
    '<style>' + #10 +
    '  /* defaults = dark theme; /theme.css (the PC''s current theme) overrides them */' + #10 +
    '  :root { --bg:#17191f; --panel:#1f222b; --side:#1d2029; --card:#282c38; --hover:#2c313f; --sel:#2a4880;' + #10 +
    '          --text:#e8ecf4; --dim:#929aac; --accent:#4891ff; --accent2:#8a5cf6; --ok:#34d382; --err:#f45c66;' + #10 +
    '          --line:#323747; --head1:#1e2a4e; --head2:#341e5c; --page:#ecf0f6; color-scheme:dark; }' + #10 +
    '  * { box-sizing:border-box; -webkit-tap-highlight-color:transparent; }' + #10 +
    '  html,body { margin:0; background:var(--bg); color:var(--text);' + #10 +
    '    font-family: system-ui, -apple-system, "Segoe UI", Roboto, "Noto Sans Thai", "Leelawadee UI", sans-serif; }' + #10 +
    '  header { position:sticky; top:0; z-index:5; padding:14px 16px 12px;' + #10 +
    '    background:linear-gradient(120deg,var(--head1),var(--head2)); border-bottom:1px solid var(--line); }' + #10 +
    '  .brand { display:flex; align-items:center; gap:12px; }' + #10 +
    '  .logo { width:38px; height:38px; border-radius:11px; display:grid; place-items:center;' + #10 +
    '    background:linear-gradient(160deg,var(--accent),var(--accent2)); flex:none; }' + #10 +
    '  .brand h1 { font-size:18px; margin:0; }' + #10 +
    '  .brand p { margin:2px 0 0; font-size:12.5px; color:var(--dim); }' + #10 +
    '  .brand p u { cursor:pointer; text-decoration-style:dotted; }' + #10 +
    '  .brand > div:nth-child(2) { flex:1; min-width:0; }' + #10 +
    '  .iconbtn { flex:none; width:40px; height:40px; border:0; border-radius:11px; background:var(--card); color:var(--text);' + #10 +
    '    display:grid; place-items:center; cursor:pointer; }' + #10 +
    '  .iconbtn:hover { background:var(--hover); }' + #10 +
    '  .sheet { position:fixed; inset:0; z-index:20; display:none; background:#0008; align-items:flex-end; justify-content:center; }' + #10 +
    '  .sheet.open { display:flex; }' + #10 +
    '  .sheetbox { width:100%; max-width:560px; max-height:85vh; overflow:auto; background:var(--panel); color:var(--text);' + #10 +
    '    border-radius:18px 18px 0 0; padding:16px 16px calc(18px + env(safe-area-inset-bottom)); box-shadow:0 -10px 40px #0006; }' + #10 +
    '  .sheethead { display:flex; align-items:center; font-weight:700; font-size:17px; margin-bottom:12px; }' + #10 +
    '  .sheethead span { flex:1; }' + #10 +
    '  .tgrid { display:grid; grid-template-columns:repeat(auto-fill,minmax(96px,1fr)); gap:10px; }' + #10 +
    '  .topt { border:2px solid transparent; border-radius:14px; padding:6px; background:var(--card); cursor:pointer; color:var(--text); font:inherit; text-align:center; }' + #10 +
    '  .topt.sel { border-color:var(--accent); }' + #10 +
    '  .topt .mini { height:46px; border-radius:9px; position:relative; overflow:hidden; margin-bottom:6px; border:1px solid #8883; }' + #10 +
    '  .topt .mini i { position:absolute; display:block; border-radius:3px; }' + #10 +
    '  .topt small { display:block; font-size:12.5px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }' + #10 +
    '  .tag { display:inline-block; font-size:11px; padding:2px 7px; border-radius:20px; background:var(--card); color:var(--dim); margin-left:6px; vertical-align:2px; }' + #10 +
    '  nav { display:flex; flex-wrap:wrap; align-items:center; gap:2px; margin-top:12px; padding:5px 6px;' + #10 +
    '    background:var(--card); border-radius:10px; font-size:14px; }' + #10 +
    '  nav button { background:none; border:0; color:var(--dim); font:inherit; padding:5px 7px; border-radius:7px; cursor:pointer; }' + #10 +
    '  nav button:last-child { color:var(--text); font-weight:600; }' + #10 +
    '  nav span { color:var(--dim); }' + #10 +
    '  main { padding:8px 10px 120px; max-width:1000px; margin:0 auto; }' + #10 +
    '  .row { display:flex; align-items:center; gap:12px; padding:10px 10px; border-radius:10px; text-decoration:none; color:inherit; cursor:pointer; }' + #10 +
    '  .row:active, .row:hover { background:var(--hover); }' + #10 +
    '  .ico { width:34px; height:34px; flex:none; }' + #10 +
    '  .name { flex:1; min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; font-size:15px; }' + #10 +
    '  .meta { color:var(--dim); font-size:12.5px; white-space:nowrap; }' + #10 +
    '  .dl { flex:none; width:34px; height:34px; border-radius:9px; display:grid; place-items:center; color:var(--dim); text-decoration:none; }' + #10 +
    '  .dl:hover { background:var(--card); color:var(--text); }' + #10 +
    '  .empty { text-align:center; color:var(--dim); padding:60px 20px; }' + #10 +
    '  .bar { position:fixed; left:0; right:0; bottom:0; padding:12px 14px calc(12px + env(safe-area-inset-bottom));' + #10 +
    '    background:var(--panel); border-top:1px solid var(--line); display:flex; gap:10px; align-items:center; }' + #10 +
    '  .btn { flex:none; border:0; border-radius:10px; padding:11px 16px; font:600 15px inherit; color:#fff; cursor:pointer;' + #10 +
    '    background:linear-gradient(120deg,var(--accent),var(--accent2)); text-decoration:none; }' + #10 +
    '  .btn.ghost { background:var(--card); color:var(--text); font-weight:500; }' + #10 +
    '  .status { flex:1; min-width:0; font-size:13px; color:var(--dim); }' + #10 +
    '  .prog { height:5px; border-radius:3px; background:var(--card); margin-top:6px; overflow:hidden; display:none; }' + #10 +
    '  .prog i { display:block; height:100%; width:0; background:linear-gradient(90deg,var(--accent),var(--accent2)); }' + #10 +
    '' + #10 +
    '  /* Markdown pages (README banner and viewer) */' + #10 +
    '  .banner { background:var(--panel); border:1px solid var(--line); border-radius:14px; padding:6px 18px; margin:6px 0 12px; }' + #10 +
    '  .md { line-height:1.65; font-size:16px; overflow-wrap:anywhere; }' + #10 +
    '  .md h1,.md h2,.md h3 { line-height:1.3; margin:1.1em 0 .5em; }' + #10 +
    '  .md h1 { font-size:1.9em; background:linear-gradient(90deg,var(--accent),var(--accent2)); -webkit-background-clip:text; background-clip:text; color:transparent; }' + #10 +
    '  .md h2 { font-size:1.45em; border-bottom:1px solid var(--line); padding-bottom:.25em; }' + #10 +
    '  .md a { color:var(--accent); }' + #10 +
    '  .md img, .md video { max-width:100%; border-radius:12px; display:block; margin:12px auto; }' + #10 +
    '  .md video { background:#000; }' + #10 +
    '  .md video { width:100%; }' + #10 +
    '  .md audio { width:100%; margin:8px 0; }' + #10 +
    '  .md figure { margin:14px 0; } .md figcaption { text-align:center; color:var(--dim); font-size:14px; }' + #10 +
    '  .md .pdf { margin:12px 0; } .md .pdf iframe { width:100%; height:75vh; border:0; border-radius:12px; background:#fff; }' + #10 +
    '  .md .pdf a { display:inline-block; margin-top:6px; }' + #10 +
    '  .md blockquote { margin:12px 0; padding:8px 16px; border-left:4px solid var(--accent); background:var(--panel); border-radius:0 10px 10px 0; color:var(--text); }' + #10 +
    '  .md code { background:var(--card); padding:2px 6px; border-radius:6px; font-size:.9em; }' + #10 +
    '  .md pre { background:var(--card); padding:12px 14px; border-radius:10px; overflow:auto; } .md pre code { padding:0; background:none; }' + #10 +
    '  .md table { border-collapse:collapse; width:100%; margin:12px 0; } .md th,.md td { border:1px solid var(--line); padding:8px 10px; text-align:left; }' + #10 +
    '  .md th { background:var(--panel); } .md hr { border:0; border-top:1px solid var(--line); margin:22px 0; }' + #10 +
    '  .md ul,.md ol { padding-left:1.4em; }' + #10 +
    '' + #10 +
    '  /* viewer */' + #10 +
    '  #viewer { display:none; }' + #10 +
    '  .vbar { position:sticky; top:0; z-index:5; display:flex; align-items:center; gap:10px; padding:10px 14px;' + #10 +
    '    background:var(--panel); border-bottom:1px solid var(--line); }' + #10 +
    '  .vbar .t { flex:1; min-width:0; font-weight:600; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }' + #10 +
    '  .vbody { max-width:960px; margin:0 auto; padding:10px 16px 60px; }' + #10 +
    '  .vbody > img, .vbody > video { display:block; max-width:100%; max-height:85vh; margin:20px auto; border-radius:12px; }' + #10 +
    '  .vbody > iframe { width:100%; height:85vh; border:0; border-radius:12px; background:#fff; margin-top:14px; }' + #10 +
    '  body.kiosk .vbar { display:none; }' + #10 +
    '  body.kiosk .vbody { max-width:none; padding:0 4vw 4vh; }' + #10 +
    '  body.kiosk .vbody > img, body.kiosk .vbody > video { max-height:100vh; margin:0 auto; border-radius:0; }' + #10 +
    '  body.kiosk .md { font-size:clamp(18px, 2.2vw, 34px); }' + #10 +
    '</style>' + #10 +
    '<script>' + #10 +
    '/* theme chosen on this phone: "pc" (follow the computer, default), "auto"' + #10 +
    '   (follow the phone''s light/dark mode) or a theme name. Applied before the' + #10 +
    '   first paint so the page never flashes in another theme. */' + #10 +
    'function themeChoice() { try { return localStorage.getItem("lanshare.theme") || "pc"; } catch (e) { return "pc"; } }' + #10 +
    'function themeHref(c) {' + #10 +
    '  if (c === "auto") return "/theme.css?name=" + (matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark");' + #10 +
    '  if (c && c !== "pc") return "/theme.css?name=" + encodeURIComponent(c);' + #10 +
    '  return "/theme.css?t=" + Date.now();' + #10 +
    '}' + #10 +
    'document.write(''<link rel="stylesheet" id="themecss" href="'' + themeHref(themeChoice()) + ''">'');' + #10 +
    '</script>' + #10 +
    '</head>' + #10 +
    '<body>' + #10 +
    '<div id="browser">' + #10 +
    '  <header>' + #10 +
    '    <div class="brand">' + #10 +
    '      <div class="logo"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round">' + #10 +
    '        <path d="M12 12L5 5M12 12l7-7M12 12l-7 7M12 12l7 7"/><circle cx="12" cy="12" r="3.4" fill="#fff"/>' + #10 +
    '        <circle cx="5" cy="5" r="2.2" fill="#fff"/><circle cx="19" cy="5" r="2.2" fill="#fff"/>' + #10 +
    '        <circle cx="5" cy="19" r="2.2" fill="#fff"/><circle cx="19" cy="19" r="2.2" fill="#fff"/></svg></div>' + #10 +
    '      <div><h1><span id="pcname">LAN Share</span><span class="tag">แชร์สาธารณะ</span></h1><p id="sub">กำลังเชื่อมต่อ...</p></div>' + #10 +
    '      <button class="iconbtn" id="themebtn" title="ธีม" aria-label="เลือกธีม"><svg width="20" height="20" viewBox="0 0 24 24" fill="none"' + #10 +
    '        stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3a9 9 0 1 0 0 18c1.1 0 1.6-.8 1.6-1.6' + #10 +
    '        0-.5-.2-.9-.5-1.2-.3-.3-.5-.7-.5-1.2 0-.9.7-1.6 1.6-1.6H16a5 5 0 0 0 5-5C21 6.5 17 3 12 3z"/><circle cx="7.5" cy="11" r="1.2"' + #10 +
    '        fill="currentColor"/><circle cx="10.5" cy="7" r="1.2" fill="currentColor"/><circle cx="15" cy="7.5" r="1.2" fill="currentColor"/></svg></button>' + #10 +
    '    </div>' + #10 +
    '    <nav id="crumbs"></nav>' + #10 +
    '  </header>' + #10 +
    '  <main><div id="banner"></div><div id="list"></div></main>' + #10 +
    '  <div class="bar">' + #10 +
    '    <div class="status"><div id="status">แตะโฟลเดอร์เพื่อเปิด แตะไฟล์เพื่อดู/ดาวน์โหลด</div><div class="prog" id="prog"><i id="progi"></i></div></div>' + #10 +
    '    <button class="btn" id="sendbtn">ส่งไฟล์</button>' + #10 +
    '    <input type="file" id="picker" multiple hidden>' + #10 +
    '  </div>' + #10 +
    '</div>' + #10 +
    '' + #10 +
    '<div class="sheet" id="sheet">' + #10 +
    '  <div class="sheetbox">' + #10 +
    '    <div class="sheethead"><span>ธีมของหน้านี้</span><button class="iconbtn" id="sheetclose" aria-label="ปิด">✕</button></div>' + #10 +
    '    <div class="tgrid" id="tgrid"></div>' + #10 +
    '  </div>' + #10 +
    '</div>' + #10 +
    '' + #10 +
    '<div id="viewer">' + #10 +
    '  <div class="vbar">' + #10 +
    '    <a class="btn ghost" id="vback" href="/">‹ กลับ</a>' + #10 +
    '    <div class="t" id="vtitle"></div>' + #10 +
    '    <a class="btn ghost" id="vkiosk" title="เปิดแบบจอโฆษณา: เต็มจอ ไม่มีแถบ อัปเดตเองทุก 30 วินาที">จอโฆษณา</a>' + #10 +
    '    <button class="btn ghost" id="vfull" title="เต็มจอ">⛶</button>' + #10 +
    '    <a class="btn" id="vdl">ดาวน์โหลด</a>' + #10 +
    '  </div>' + #10 +
    '  <div class="vbody" id="vbody"></div>' + #10 +
    '</div>' + #10 +
    '' + #10 +
    '<script>' + #10 +
    '"use strict";' + #10 +
    'var ua = navigator.userAgent;' + #10 +
    'var me = localStorage.getItem("lanshare.name") ||' + #10 +
    '  (/Android/.test(ua) ? "มือถือ Android" : /iPhone|iPad/.test(ua) ? "iPhone/iPad" : "เบราว์เซอร์");' + #10 +
    'var cur = "";' + #10 +
    'var $ = function (id) { return document.getElementById(id); };' + #10 +
    'var PREVIEW = /\.(md|markdown|png|jpe?g|gif|webp|svg|pdf|mp4|webm|m4v|mov|mp3|m4a|wav|ogg|txt)$/i;' + #10 +
    '' + #10 +
    'function fmt(b) {' + #10 +
    '  if (b < 1024) return b + " B";' + #10 +
    '  if (b < 1048576) return (b / 1024).toFixed(1) + " KB";' + #10 +
    '  if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB";' + #10 +
    '  return (b / 1073741824).toFixed(2) + " GB";' + #10 +
    '}' + #10 +
    'function api(path, params) {' + #10 +
    '  var q = Object.keys(params || {}).map(function (k) { return encodeURIComponent(k) + "=" + encodeURIComponent(params[k]); }).join("&");' + #10 +
    '  return "/api/" + path + (q ? "?" + q : "");' + #10 +
    '}' + #10 +
    'function fileUrl(path, dl) { return api("file", dl ? { path: path, dl: 1, client: me } : { path: path, client: me }); }' + #10 +
    'function viewUrl(path, kiosk) { return "/view?path=" + encodeURIComponent(path) + (kiosk ? "&kiosk=1" : ""); }' + #10 +
    'function dirOf(path) { var i = path.lastIndexOf("/"); return i < 0 ? "" : path.slice(0, i); }' + #10 +
    'function esc(s) { return String(s).replace(/[&<>"'']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", ''"'': "&quot;", "''": "&#39;" }[c]; }); }' + #10 +
    'function unesc(s) { return s.replace(/&quot;/g, ''"'').replace(/&#39;/g, "''").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&"); }' + #10 +
    '' + #10 +
    '/* ---------- Markdown ---------- */' + #10 +
    '/* path written in a .md file -> path inside the shares (null = external link) */' + #10 +
    'function resolvePath(base, rel) {' + #10 +
    '  if (/^[a-z][a-z0-9+.-]*:/i.test(rel)) return null;' + #10 +
    '  var parts = rel.charAt(0) === "/" ? [] : (base ? base.split("/") : []);' + #10 +
    '  rel.replace(/^\//, "").split(/[?#]/)[0].split("/").forEach(function (p) {' + #10 +
    '    if (p === "" || p === ".") return;' + #10 +
    '    if (p === "..") parts.pop(); else { try { parts.push(decodeURIComponent(p)); } catch (e) { parts.push(p); } }' + #10 +
    '  });' + #10 +
    '  return parts.join("/");' + #10 +
    '}' + #10 +
    'function media(path, alt) {' + #10 +
    '  var u = esc(fileUrl(path)), ext = (path.split(".").pop() || "").toLowerCase(), cap = alt ? "<figcaption>" + alt + "</figcaption>" : "";' + #10 +
    '  if (/^(mp4|webm|m4v|mov)$/.test(ext))' + #10 +
    '    return "<figure><video src=\"" + u + "\" controls autoplay muted loop playsinline preload=\"metadata\"></video>" + cap + "</figure>";' + #10 +
    '  if (/^(mp3|m4a|wav|ogg)$/.test(ext)) return "<audio src=\"" + u + "\" controls></audio>";' + #10 +
    '  if (ext === "pdf")' + #10 +
    '    return "<div class=\"pdf\"><iframe src=\"" + u + "#view=FitH\" loading=\"lazy\"></iframe><a class=\"btn ghost\" href=\"" + u + "\" target=\"_blank\">เปิด PDF" + (alt ? ": " + a' +
    'lt : "") + "</a></div>";' + #10 +
    '  return "<img src=\"" + u + "\" alt=\"" + alt + "\" loading=\"lazy\">";' + #10 +
    '}' + #10 +
    'function inline(t, base) {' + #10 +
    '  var keep = [];' + #10 +
    '  var hold = function (html) { keep.push(html); return "\u0001" + (keep.length - 1) + "\u0002"; };' + #10 +
    '  t = t.replace(/`([^`]+)`/g, function (m, c) { return hold("<code>" + esc(c) + "</code>"); });' + #10 +
    '  t = esc(t);' + #10 +
    '  t = t.replace(/!\[([^\]]*)\]\(\s*([^)\s]+)(?:\s+&quot;[^&]*&quot;)?\s*\)/g, function (m, alt, src) {' + #10 +
    '    src = unesc(src);' + #10 +
    '    var p = resolvePath(base, src);' + #10 +
    '    if (p === null) return /^https?:/i.test(src) ? hold("<img src=\"" + esc(src) + "\" alt=\"" + alt + "\" loading=\"lazy\">") : m;' + #10 +
    '    return hold(media(p, alt));' + #10 +
    '  });' + #10 +
    '  t = t.replace(/\[([^\]]+)\]\(\s*([^)\s]+)\s*\)/g, function (m, text, href) {' + #10 +
    '    href = unesc(href);' + #10 +
    '    var p = resolvePath(base, href);' + #10 +
    '    if (p === null) {' + #10 +
    '      if (!/^(https?|mailto):/i.test(href)) return text;          // no javascript: etc.' + #10 +
    '      return hold("<a href=\"" + esc(href) + "\" target=\"_blank\" rel=\"noopener\">") + text + hold("</a>");' + #10 +
    '    }' + #10 +
    '    var url = PREVIEW.test(p) ? viewUrl(p) : fileUrl(p, true);' + #10 +
    '    return hold("<a href=\"" + esc(url) + "\">") + text + hold("</a>");' + #10 +
    '  });' + #10 +
    '  t = t.replace(/(^|[\s(])(https?:\/\/[^\s<]+)/g, function (m, pre, u) {' + #10 +
    '    return pre + hold("<a href=\"" + u + "\" target=\"_blank\" rel=\"noopener\">" + u + "</a>");' + #10 +
    '  });' + #10 +
    '  t = t.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>").replace(/__([^_]+)__/g, "<strong>$1</strong>")' + #10 +
    '       .replace(/\*([^*\s][^*]*)\*/g, "<em>$1</em>").replace(/(^|\W)_([^_\s][^_]*)_(?=\W|$)/g, "$1<em>$2</em>")' + #10 +
    '       .replace(/~~([^~]+)~~/g, "<del>$1</del>");' + #10 +
    '  t = t.replace(/ {2,}\n/g, "<br>").replace(/\n/g, " ");' + #10 +
    '  return t.replace(/\u0001(\d+)\u0002/g, function (m, i) { return keep[+i]; });' + #10 +
    '}' + #10 +
    'var LIST = /^\s*([-*+]|\d+[.)])\s+/;' + #10 +
    'function md(src, base) {' + #10 +
    '  var lines = src.replace(/\r\n?/g, "\n").split("\n"), out = [], i = 0, m;' + #10 +
    '  var isTableSep = function (l) { return /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/.test(l); };' + #10 +
    '  var cells = function (l) { return l.trim().replace(/^\||\|$/g, "").split("|").map(function (c) { return inline(c.trim(), base); }); };' + #10 +
    '  while (i < lines.length) {' + #10 +
    '    var l = lines[i];' + #10 +
    '    if (/^\s*```/.test(l)) {' + #10 +
    '      var code = []; i++;' + #10 +
    '      while (i < lines.length && !/^\s*```/.test(lines[i])) code.push(lines[i++]);' + #10 +
    '      i++; out.push("<pre><code>" + esc(code.join("\n")) + "</code></pre>"); continue;' + #10 +
    '    }' + #10 +
    '    if ((m = /^(#{1,6})\s+(.*?)\s*#*\s*$/.exec(l))) { out.push("<h" + m[1].length + ">" + inline(m[2], base) + "</h" + m[1].length + ">"); i++; continue; }' + #10 +
    '    if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(l)) { out.push("<hr>"); i++; continue; }' + #10 +
    '    if (/^\s*>/.test(l)) {' + #10 +
    '      var q = []; while (i < lines.length && /^\s*>/.test(lines[i])) q.push(lines[i++].replace(/^\s*>\s?/, ""));' + #10 +
    '      out.push("<blockquote>" + md(q.join("\n"), base) + "</blockquote>"); continue;' + #10 +
    '    }' + #10 +
    '    if (LIST.test(l)) {' + #10 +
    '      var ordered = /^\s*\d/.test(l), items = [];' + #10 +
    '      while (i < lines.length && LIST.test(lines[i])) {' + #10 +
    '        items.push(lines[i++].replace(LIST, ""));' + #10 +
    '        while (i < lines.length && /^\s{2,}\S/.test(lines[i]) && !LIST.test(lines[i])) items[items.length - 1] += "\n" + lines[i++].trim();' + #10 +
    '      }' + #10 +
    '      var tag = ordered ? "ol" : "ul";' + #10 +
    '      out.push("<" + tag + ">" + items.map(function (x) {' + #10 +
    '        var box = /^\[( |x)\]\s+/i.exec(x);' + #10 +
    '        if (box) x = x.slice(box[0].length);' + #10 +
    '        return "<li>" + (box ? (box[1] === " " ? "☐ " : "☑ ") : "") + inline(x, base) + "</li>";' + #10 +
    '      }).join("") + "</" + tag + ">");' + #10 +
    '      continue;' + #10 +
    '    }' + #10 +
    '    if (l.indexOf("|") >= 0 && i + 1 < lines.length && isTableSep(lines[i + 1])) {' + #10 +
    '      var head = cells(l); i += 2;' + #10 +
    '      var body = []; while (i < lines.length && lines[i].indexOf("|") >= 0 && lines[i].trim()) body.push(cells(lines[i++]));' + #10 +
    '      out.push("<table><thead><tr>" + head.map(function (c) { return "<th>" + c + "</th>"; }).join("") + "</tr></thead><tbody>" +' + #10 +
    '        body.map(function (r) { return "<tr>" + r.map(function (c) { return "<td>" + c + "</td>"; }).join("") + "</tr>"; }).join("") + "</tbody></table>");' + #10 +
    '      continue;' + #10 +
    '    }' + #10 +
    '    if (!l.trim()) { i++; continue; }' + #10 +
    '    var p = [];' + #10 +
    '    while (i < lines.length && lines[i].trim() && !/^\s*(#{1,6}\s|```|>)/.test(lines[i]) && !LIST.test(lines[i])' + #10 +
    '           && !(lines[i].indexOf("|") >= 0 && i + 1 < lines.length && isTableSep(lines[i + 1]))) p.push(lines[i++]);' + #10 +
    '    out.push("<p>" + inline(p.join("\n"), base) + "</p>");' + #10 +
    '  }' + #10 +
    '  return out.join("\n");' + #10 +
    '}' + #10 +
    '' + #10 +
    '/* ---------- browser (folder list) ---------- */' + #10 +
    'function icon(isDir, name) {' + #10 +
    '  if (isDir) return ''<svg class="ico" viewBox="0 0 34 34"><path d="M3 9a3 3 0 0 1 3-3h8l3 3h11a3 3 0 0 1 3 3v2H3z" fill="#d69124"/><rect x="3" y="11" width="28" height="18" rx="3" ' +
    'fill="#fcc24f"/></svg>'';' + #10 +
    '  var e = (name.split(".").pop() || "").slice(0, 4).toUpperCase();' + #10 +
    '  var c = /^(JPG|JPEG|PNG|GIF|WEBP|HEIC)$/.test(e) ? "#2ecc71" : /^(MP4|MKV|MOV|AVI|WEBM)$/.test(e) ? "#9b59b6" :' + #10 +
    '          /^(MP3|WAV|FLAC|M4A|OGG)$/.test(e) ? "#e84393" : /^(ZIP|RAR|7Z|GZ|TAR)$/.test(e) ? "#f39c12" :' + #10 +
    '          e === "PDF" ? "#e74c3c" : e === "MD" ? "#00b4d8" : /^(DOC|DOCX|TXT)$/.test(e) ? "#3498db" : /^(XLS|XLSX|CSV)$/.test(e) ? "#27ae60" : "#828c9b";' + #10 +
    '  return ''<svg class="ico" viewBox="0 0 34 34"><path d="M7 2h14l7 7v23H7z" fill="var(--page)"/><path d="M21 2l7 7h-7z" fill="#bec6d4"/>'' +' + #10 +
    '    ''<rect x="3" y="18" width="22" height="10" rx="2" fill="'' + c + ''"/><text x="14" y="25.6" font-size="6.5" font-weight="700" '' +' + #10 +
    '    ''font-family="Arial" fill="#fff" text-anchor="middle">'' + e.replace(/[<>&]/g, "") + "</text></svg>";' + #10 +
    '}' + #10 +
    'var DLICON = ''<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12M7 ' +
    '10l5 5 5-5M4 17v3h16v-3"/></svg>'';' + #10 +
    'function crumbs() {' + #10 +
    '  var nav = $("crumbs"); nav.innerHTML = "";' + #10 +
    '  var parts = cur ? cur.split("/") : [];' + #10 +
    '  var add = function (label, path) {' + #10 +
    '    var b = document.createElement("button"); b.textContent = label;' + #10 +
    '    b.onclick = function () { go(path); }; nav.appendChild(b);' + #10 +
    '  };' + #10 +
    '  add("ทั้งหมด", "");' + #10 +
    '  parts.forEach(function (p, i) {' + #10 +
    '    var s = document.createElement("span"); s.textContent = "›"; nav.appendChild(s);' + #10 +
    '    add(p, parts.slice(0, i + 1).join("/"));' + #10 +
    '  });' + #10 +
    '}' + #10 +
    'function showBanner(path, items) {' + #10 +
    '  var b = $("banner"); b.innerHTML = "";' + #10 +
    '  var readme = items.filter(function (it) { return !it.dir && /^(readme|index)\.(md|markdown)$/i.test(it.name); })[0];' + #10 +
    '  if (!readme) return;' + #10 +
    '  var full = path ? path + "/" + readme.name : readme.name;' + #10 +
    '  fetch(fileUrl(full)).then(function (r) { return r.ok ? r.text() : ""; }).then(function (t) {' + #10 +
    '    if (!t || cur !== path) return;' + #10 +
    '    b.innerHTML = ''<div class="banner md">'' + md(t, path) + "</div>";' + #10 +
    '  });' + #10 +
    '}' + #10 +
    'function go(path) {' + #10 +
    '  cur = path; crumbs();' + #10 +
    '  var list = $("list"); list.innerHTML = ''<div class="empty">กำลังโหลด...</div>''; $("banner").innerHTML = "";' + #10 +
    '  fetch(api("list", { path: path, client: me })).then(function (r) { return r.json(); }).then(function (d) {' + #10 +
    '    if (d.error) { list.innerHTML = ""; var e = document.createElement("div"); e.className = "empty"; e.textContent = d.error; list.appendChild(e); return; }' + #10 +
    '    d.items.sort(function (a, b) { return (b.dir - a.dir) || a.name.localeCompare(b.name); });' + #10 +
    '    showBanner(path, d.items);' + #10 +
    '    list.innerHTML = d.items.length ? "" : ''<div class="empty">'' + (path ? "โฟลเดอร์นี้ว่างเปล่า" : "เครื่องนี้ยังไม่ได้แชร์อะไร") + "</div>";' + #10 +
    '    d.items.forEach(function (it) {' + #10 +
    '      var full = path ? path + "/" + it.name : it.name;' + #10 +
    '      var a = document.createElement("a"); a.className = "row";' + #10 +
    '      if (it.dir) { a.href = "#"; a.onclick = function (ev) { ev.preventDefault(); go(full); }; }' + #10 +
    '      else if (PREVIEW.test(it.name)) a.href = viewUrl(full);' + #10 +
    '      else { a.href = fileUrl(full, true); a.setAttribute("download", it.name); }' + #10 +
    '      a.innerHTML = icon(it.dir, it.name) + ''<div class="name"></div><div class="meta"></div>'';' + #10 +
    '      a.querySelector(".name").textContent = it.name;' + #10 +
    '      a.querySelector(".meta").textContent = it.dir ? "โฟลเดอร์" : fmt(it.size);' + #10 +
    '      if (!it.dir) {' + #10 +
    '        var dl = document.createElement("a"); dl.className = "dl"; dl.href = fileUrl(full, true);' + #10 +
    '        dl.setAttribute("download", it.name); dl.title = "ดาวน์โหลด"; dl.innerHTML = DLICON;' + #10 +
    '        dl.onclick = function (ev) { ev.stopPropagation(); };' + #10 +
    '        a.appendChild(dl);' + #10 +
    '      }' + #10 +
    '      list.appendChild(a);' + #10 +
    '    });' + #10 +
    '    history.replaceState(null, "", "/#" + encodeURIComponent(path));' + #10 +
    '  }).catch(function () { list.innerHTML = ''<div class="empty">เชื่อมต่อไม่ได้</div>''; });' + #10 +
    '}' + #10 +
    '' + #10 +
    '/* ---------- viewer ---------- */' + #10 +
    'function startViewer() {' + #10 +
    '  var q = new URLSearchParams(location.search), path = q.get("path") || "", kiosk = q.get("kiosk") === "1";' + #10 +
    '  $("browser").style.display = "none"; $("viewer").style.display = "block";' + #10 +
    '  if (kiosk) document.body.classList.add("kiosk");' + #10 +
    '  var name = path.split("/").pop();' + #10 +
    '  document.title = name + " — LAN Share";' + #10 +
    '  $("vtitle").textContent = name;' + #10 +
    '  $("vback").href = "/#" + encodeURIComponent(dirOf(path));' + #10 +
    '  $("vdl").href = fileUrl(path, true); $("vdl").setAttribute("download", name);' + #10 +
    '  $("vkiosk").href = viewUrl(path, true);' + #10 +
    '  $("vfull").onclick = function () { (document.documentElement.requestFullscreen || function () {}).call(document.documentElement); };' + #10 +
    '  var body = $("vbody"), ext = (name.split(".").pop() || "").toLowerCase(), last = "";' + #10 +
    '  var load = function () {' + #10 +
    '    if (/^(md|markdown|txt)$/.test(ext)) {' + #10 +
    '      fetch(fileUrl(path)).then(function (r) { if (!r.ok) throw new Error(r.status); return r.text(); }).then(function (t) {' + #10 +
    '        if (t === last) return;               // unchanged: keep videos playing' + #10 +
    '        last = t;' + #10 +
    '        body.innerHTML = ext === "txt" ? "<pre class=\"md\">" + esc(t) + "</pre>" : ''<article class="md">'' + md(t, dirOf(path)) + "</article>";' + #10 +
    '      }).catch(function () { if (!last) body.innerHTML = ''<div class="empty">เปิดไม่ได้ (ไฟล์ถูกลบหรือเลิกแชร์แล้ว)</div>''; });' + #10 +
    '    } else if (!last) {' + #10 +
    '      last = "x";' + #10 +
    '      body.innerHTML = media(path, "");' + #10 +
    '      var el = body.firstElementChild;' + #10 +
    '      if (el && el.tagName === "FIGURE") body.innerHTML = el.innerHTML;       // bare <video>' + #10 +
    '      if (ext === "pdf") body.innerHTML = ''<iframe src="'' + esc(fileUrl(path)) + ''"></iframe>'';' + #10 +
    '    }' + #10 +
    '  };' + #10 +
    '  load();' + #10 +
    '  // advert screens: pick up edits of the page every 30 seconds' + #10 +
    '  if (kiosk) { setInterval(load, 30000); document.body.onclick = function () { $("vfull").onclick(); }; }' + #10 +
    '}' + #10 +
    '' + #10 +
    '/* ---------- upload ---------- */' + #10 +
    'function status(t, pct) {' + #10 +
    '  $("status").textContent = t;' + #10 +
    '  $("prog").style.display = pct === undefined ? "none" : "block";' + #10 +
    '  if (pct !== undefined) $("progi").style.width = Math.round(pct * 100) + "%";' + #10 +
    '}' + #10 +
    'function put(url, file, onp) {' + #10 +
    '  return new Promise(function (ok, bad) {' + #10 +
    '    var x = new XMLHttpRequest(); x.open("PUT", url);' + #10 +
    '    x.setRequestHeader("X-LanShare-Name", encodeURIComponent(me));' + #10 +
    '    x.upload.onprogress = function (e) { onp(e.loaded); };' + #10 +
    '    x.onload = function () { x.status === 200 ? ok() : bad(new Error(x.responseText)); };' + #10 +
    '    x.onerror = function () { bad(new Error("network")); };' + #10 +
    '    x.send(file);' + #10 +
    '  });' + #10 +
    '}' + #10 +
    '$("sendbtn").onclick = function () { $("picker").click(); };' + #10 +
    '$("picker").onchange = async function () {' + #10 +
    '  var files = Array.prototype.slice.call(this.files); this.value = "";' + #10 +
    '  if (!files.length) return;' + #10 +
    '  var total = files.reduce(function (s, f) { return s + f.size; }, 0), done = 0;' + #10 +
    '  try {' + #10 +
    '    status("รอให้คอมพิวเตอร์กดยอมรับ...");' + #10 +
    '    var r = await fetch(api("push/begin", { files: files.length, bytes: total, client: me }), { method: "POST" });' + #10 +
    '    var d = await r.json();' + #10 +
    '    if (!r.ok) { status(d.error === "rejected" ? "คอมพิวเตอร์ปฏิเสธการรับไฟล์" : "ส่งไม่ได้: " + d.error); return; }' + #10 +
    '    for (var i = 0; i < files.length; i++) {' + #10 +
    '      var f = files[i], base = done;' + #10 +
    '      await put(api("push/file", { token: d.token, path: f.name }), f, function (n) {' + #10 +
    '        status("กำลังส่ง " + f.name + " (" + (i + 1) + "/" + files.length + ")", (base + n) / Math.max(1, total));' + #10 +
    '      });' + #10 +
    '      done += f.size;' + #10 +
    '    }' + #10 +
    '    await fetch(api("push/end", { token: d.token }), { method: "POST" });' + #10 +
    '    status("ส่งสำเร็จ " + files.length + " ไฟล์ (" + fmt(total) + ")", 1);' + #10 +
    '  } catch (e) { status("ส่งไม่สำเร็จ: " + e.message); }' + #10 +
    '};' + #10 +
    '' + #10 +
    'function showInfo() {' + #10 +
    '  fetch("/api/info").then(function (r) { return r.json(); }).then(function (i) {' + #10 +
    '    var nm = i.name || location.hostname;   // no name set: show the address' + #10 +
    '    $("pcname").textContent = nm; document.title = nm + " — LAN Share";' + #10 +
    '    var sub = $("sub"); sub.innerHTML = "";' + #10 +
    '    sub.appendChild(document.createTextNode("แชร์ไว้ " + i.shares + " รายการ • คุณ: "));' + #10 +
    '    var u = document.createElement("u"); u.textContent = me; u.title = "เปลี่ยนชื่อที่แสดง";' + #10 +
    '    u.onclick = function () {' + #10 +
    '      var n = prompt("ชื่อที่เครื่องอื่นจะเห็น", me);' + #10 +
    '      if (n && n.trim()) { me = n.trim().slice(0, 40); localStorage.setItem("lanshare.name", me); showInfo(); }' + #10 +
    '    };' + #10 +
    '    sub.appendChild(u);' + #10 +
    '  });' + #10 +
    '}' + #10 +
    '' + #10 +
    '/* ---------- theme ---------- */' + #10 +
    '/* swap the stylesheet without flicker: the old one goes only after the new one loaded */' + #10 +
    'function loadTheme() {' + #10 +
    '  var old = $("themecss"), link = document.createElement("link");' + #10 +
    '  link.rel = "stylesheet"; link.href = themeHref(themeChoice());' + #10 +
    '  link.onload = function () { old.remove(); link.id = "themecss"; };' + #10 +
    '  link.onerror = function () { link.remove(); };' + #10 +
    '  old.after(link);' + #10 +
    '}' + #10 +
    'function setChoice(c) {' + #10 +
    '  try { localStorage.setItem("lanshare.theme", c); } catch (e) {}' + #10 +
    '  loadTheme(); buildThemeGrid();' + #10 +
    '}' + #10 +
    'var themes = null;' + #10 +
    'function mini(t) {' + #10 +
    '  return ''<div class="mini" style="background:'' + t.bg + ''"><i style="left:0;top:0;bottom:0;width:30%;background:'' + t.side + ''"></i>'' +' + #10 +
    '    ''<i style="left:36%;top:9px;width:50%;height:5px;background:'' + t.dim + ''"></i>'' +' + #10 +
    '    ''<i style="left:36%;top:19px;width:36%;height:5px;background:'' + t.text + ''"></i>'' +' + #10 +
    '    ''<i style="right:6px;bottom:6px;width:26px;height:9px;background:linear-gradient(90deg,'' + t.accent + '','' + t.accent2 + '')"></i></div>'';' + #10 +
    '}' + #10 +
    'function buildThemeGrid() {' + #10 +
    '  var g = $("tgrid"), c = themeChoice(); g.innerHTML = "";' + #10 +
    '  var add = function (key, label, html) {' + #10 +
    '    var b = document.createElement("button"); b.className = "topt" + (c === key ? " sel" : "");' + #10 +
    '    b.innerHTML = html + "<small></small>"; b.querySelector("small").textContent = label;' + #10 +
    '    b.onclick = function () { setChoice(key); };' + #10 +
    '    g.appendChild(b);' + #10 +
    '  };' + #10 +
    '  add("pc", "ตามเครื่อง", ''<div class="mini" style="background:linear-gradient(120deg,var(--head1),var(--head2))">'' +' + #10 +
    '    ''<i style="left:50%;top:50%;width:22px;height:16px;margin:-8px 0 0 -11px;border:2px solid var(--text);background:none"></i></div>'');' + #10 +
    '  add("auto", "ตามมือถือ", ''<div class="mini" style="background:linear-gradient(135deg,#17191f 50%,#f6f7fa 50%)"></div>'');' + #10 +
    '  (themes || []).forEach(function (t) { add(t.name, t.label, mini(t)); });' + #10 +
    '}' + #10 +
    '$("themebtn").onclick = function () {' + #10 +
    '  $("sheet").classList.add("open");' + #10 +
    '  if (themes) return buildThemeGrid();' + #10 +
    '  buildThemeGrid();' + #10 +
    '  fetch("/api/themes").then(function (r) { return r.json(); }).then(function (l) { themes = l; buildThemeGrid(); });' + #10 +
    '};' + #10 +
    '$("sheetclose").onclick = function () { $("sheet").classList.remove("open"); };' + #10 +
    '$("sheet").onclick = function (e) { if (e.target === this) this.classList.remove("open"); };' + #10 +
    '// "ตามเครื่อง": pick up theme changes on the computer every 10 seconds' + #10 +
    'setInterval(function () { if (themeChoice() === "pc") loadTheme(); }, 10000);' + #10 +
    '// "ตามมือถือ": follow the phone switching between light and dark' + #10 +
    'matchMedia("(prefers-color-scheme: light)").addEventListener("change", function () { if (themeChoice() === "auto") loadTheme(); });' + #10 +
    '' + #10 +
    'if (location.pathname === "/view") startViewer();' + #10 +
    'else { showInfo(); go(decodeURIComponent((location.hash || "#").slice(1))); }' + #10 +
    '</script>' + #10 +
    '</body>' + #10 +
    '</html>' + #10 +
    '' + #10;
