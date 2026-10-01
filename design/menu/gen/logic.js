var STYLE = __STYLE__;
var STR = __STR__;
var BOOT = __BOOT__;
var MAPDATA = __MAP__;
var LAYOUT = __LAYOUT__;
var CL_IDS = __CLIDS__;
var BUILD = '0.7.0-dev.142+41f9239';

var DEF = { preset: 'high', scale: 100, shadows: true, shadowRes: '4096', aa: 'msaa2', vsync: true, fov: 90, fps: 0, volume: 80, sens: 2.0, binds: {} };
var PRESETS = {
  low: { scale: 70, shadows: false, shadowRes: '1024', aa: 'off' },
  medium: { scale: 85, shadows: true, shadowRes: '2048', aa: 'fxaa' },
  high: { scale: 100, shadows: true, shadowRes: '4096', aa: 'msaa2' }
};
var PRESET_FIELDS = ['scale', 'shadows', 'shadowRes', 'aa'];
var ACTIONS = [
  ['move_forward', 'ACTION_MOVE_FORWARD', 'KeyW'], ['move_backward', 'ACTION_MOVE_BACKWARD', 'KeyS'],
  ['move_left', 'ACTION_MOVE_LEFT', 'KeyA'], ['move_right', 'ACTION_MOVE_RIGHT', 'KeyD'],
  ['jump', 'ACTION_JUMP', 'Space'], ['sprint', 'ACTION_SPRINT', 'ShiftLeft'],
  ['interact', 'ACTION_INTERACT', 'KeyF'], ['snatch_body', 'ACTION_SNATCH_BODY', 'Mouse0'],
  ['leave_body', 'ACTION_LEAVE_BODY', 'KeyQ'], ['map', 'ACTION_MAP', 'KeyM']
];
var SOUL = [
  { id: 'body_snatch', br: 'possession', max: 1, cost: [1], req: [] },
  { id: 'capture_precision', br: 'possession', max: 3, cost: [1, 2, 3], req: [['body_snatch', 1]] },
  { id: 'lifespan', br: 'survival', max: 3, cost: [1, 2, 3], req: [['body_snatch', 1]] },
  { id: 'decay_capacity', br: 'survival', max: 3, cost: [1, 2, 3], req: [['lifespan', 1]] },
  { id: 'graceful_exit', br: 'survival', max: 3, cost: [1, 2, 3], req: [['lifespan', 1]] },
  { id: 'overflow_control', br: 'survival', max: 2, cost: [2, 3], req: [['lifespan', 2]] },
  { id: 'last_breath', br: 'survival', max: 2, cost: [2, 3], req: [['lifespan', 2]] },
  { id: 'steady_legs', br: 'embodiment', max: 3, cost: [1, 2, 3], req: [['body_snatch', 1]] },
  { id: 'spring_step', br: 'embodiment', max: 3, cost: [1, 2, 3], req: [['steady_legs', 1]] },
  { id: 'resilient_flesh', br: 'embodiment', max: 3, cost: [1, 2, 3], req: [['steady_legs', 1]] },
  { id: 'second_wind', br: 'embodiment', max: 3, cost: [1, 2, 3], req: [['steady_legs', 1]] }
];
var ARCH = [
  { id: 'map_level', br: 'knowledge', max: 4, cost: [1000, 1000, 2000, 2000], req: [], name: 'ARCHITECT_MAP', desc: 'ARCHITECT_MAP_DESC' },
  { id: 'future_1', br: 'future', ph: true, max: 1, cost: [0], req: [] },
  { id: 'future_2', br: 'future', ph: true, max: 1, cost: [0], req: [] }
];
var BRANCH_KEY = { possession: 'SKILL_BRANCH_POSSESSION', survival: 'SKILL_BRANCH_SURVIVAL', embodiment: 'SKILL_BRANCH_EMBODIMENT', knowledge: 'ARCHITECT_BRANCH_KNOWLEDGE', future: 'ARCHITECT_BRANCH_FUTURE' };

var INIT = {
  screen: 'menu', from: 'menu', lang: 'ru', hasSave: true, saved: false, tab: 'graphics',
  applied: DEF, draft: DEF, dd: '', waiting: '', swap: null, hintRow: 'preset', reviving: false,
  tree: 'soul', points: 3, essence: 12400,
  ranks: { body_snatch: 1, capture_precision: 1, lifespan: 2, steady_legs: 1 }, aranks: { map_level: 2 },
  sel: 'decay_capacity', asel: 'map_level', flash: '', toast: '',
  mapLevel: 3, mapLayer: 2, hover: '', pinned: '', fx: 0, force: {}, bare: false
};

function tr(t, key) {
  var s = t[key] != null ? t[key] : key, i = 2, a = arguments;
  return s.replace(/%[sd]/g, function () { return a[i] != null ? String(a[i++]) : ''; });
}
function keyName(code, t) {
  if (!code) return '—';
  if (code.indexOf('Key') === 0) return code.slice(3);
  if (code.indexOf('Digit') === 0) return code.slice(5);
  if (code === 'Space') return t.KEY_SPACE;
  if (code === 'Mouse0') return t.KEY_LMB;
  if (code === 'Mouse1') return t.KEY_MMB;
  if (code === 'Mouse2') return t.KEY_RMB;
  if (code.indexOf('Shift') === 0) return 'Shift';
  if (code.indexOf('Control') === 0) return 'Ctrl';
  if (code.indexOf('Alt') === 0) return 'Alt';
  var arrows = { ArrowUp: '↑', ArrowDown: '↓', ArrowLeft: '←', ArrowRight: '→' };
  if (arrows[code]) return arrows[code];
  return code.replace('Numpad', 'Num ');
}
function nz(a, s) { return Math.sin(3 * a + s) * 0.5 + Math.sin(7 * a + 1.7 + s * 1.3) * 0.3 + Math.sin(13 * a + 0.4 + s * 0.7) * 0.2; }
function rag(x1, y1, x2, y2, seed, amp) {
  var dx = x2 - x1, dy = y2 - y1, L = Math.sqrt(dx * dx + dy * dy) || 1, n = Math.max(3, Math.round(L / 9));
  var px = -dy / L, py = dx / L, out = [];
  for (var i = 0; i <= n; i++) {
    var k = i / n, w = Math.sin(Math.PI * k), o = amp * w * nz(k * 6.3, seed);
    out.push((x1 + dx * k + px * o).toFixed(1) + ' ' + (y1 + dy * k + py * o).toFixed(1));
  }
  return 'M' + out.join(' L');
}
// Связь в схеме B: от корня — колено сверху вниз, внутри колонки — шина слева от ячеек.
function elbow(a, b, W, H) {
  if (a[3] !== 'root') return 'M' + a[0] + ' ' + (a[1] + H / 2) + ' H' + (a[0] - 16) + ' V' + (b[1] + H / 2) + ' H' + b[0];
  var x1 = a[0] + W / 2, y1 = a[1] + H, x2 = b[0] + W / 2, y2 = b[1], my = Math.round(y1 + (y2 - y1) / 2);
  return 'M' + x1 + ' ' + y1 + ' V' + my + ' H' + x2 + ' V' + y2;
}
function arcSeg(cx, cy, r, a0, a1) {
  var p = function (a) { var rad = (a - 90) * Math.PI / 180; return (cx + r * Math.cos(rad)).toFixed(2) + ' ' + (cy + r * Math.sin(rad)).toFixed(2); };
  return 'M' + p(a0) + ' A' + r + ' ' + r + ' 0 ' + (a1 - a0 > 180 ? 1 : 0) + ' 1 ' + p(a1);
}
function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
function fmtK(v, lang, t) {
  var x = v / 1000, s = (Math.round(x * 10) / 10).toString();
  if (lang === 'ru') s = s.replace('.', ',');
  return tr(t, 'SKILL_THOUSANDS', s);
}

class Component extends DCLogic {
  S() { return Object.assign({}, INIT, BOOT, this.state || {}); }

  set(o) { this.setState(o); }

  go(screen, extra) {
    var self = this, o = Object.assign({ screen: screen, dd: '', waiting: '', hover: '', fx: (this.S().fx || 0) + 1 }, extra || {});
    this.setState(o);
    clearTimeout(this._fxT);
    this._fxT = setTimeout(function () { self.setState({ fx: 0 }); }, 260);
  }

  componentWillUnmount() { clearTimeout(this._fxT); clearTimeout(this._saveT); clearTimeout(this._revT); clearTimeout(this._flashT); }

  renderVals() {
    var self = this, s = this.S(), t = STR[s.lang], f = s.force || {};
    var has = function (k, id) { return (f[k] || []).indexOf(id) >= 0; };
    var mod = function (id) { return (has('hover', id) ? ' is-hover' : '') + (has('focus', id) ? ' is-focus' : '') + (has('press', id) ? ' is-press' : ''); };
    var cl = {};
    CL_IDS.forEach(function (id) { cl[id] = mod(id); });
    var go = function (scr, extra) { return function () { self.go(scr, extra); }; };
    var L = LAYOUT[STYLE];

    // --- Экраны ---
    var v = {
      t: t, cl: cl, bare: !!s.bare, live: !s.bare, fx: !!s.fx, build: tr(t, 'MENU_BUILD', BUILD), rootH: s.bare ? 720 : 800,
      buildNo: BUILD, sessionNo: '0147',
      isMenu: s.screen === 'menu', isGame: s.screen === 'game', isPause: s.screen === 'pause',
      isSettings: s.screen === 'settings', isSummary: s.screen === 'summary', isSkills: s.screen === 'skills', isMap: s.screen === 'map',
      inRun: ['game', 'pause', 'skills', 'map'].indexOf(s.screen) >= 0 || (s.screen === 'settings' && s.from === 'pause'),
      overGame: ['pause', 'skills', 'map'].indexOf(s.screen) >= 0 || (s.screen === 'settings' && s.from === 'pause'),
      outRun: s.screen === 'menu' || s.screen === 'summary' || (s.screen === 'settings' && s.from === 'menu'),
      noSave: !s.hasSave, hasSave: !!s.hasSave,
      newGame: go('game'), load: function () { if (s.hasSave) self.go('game'); },
      openSettingsMenu: go('settings', { from: 'menu', draft: s.applied, tab: 'graphics', swap: null }),
      openSettingsPause: go('settings', { from: 'pause', draft: s.applied, tab: 'graphics', swap: null }),
      quit: function () {}, resume: go('game'), toMenu: go('menu'), pause: go('pause'), die: go('summary', { reviving: false }),
      openSkills: go('skills'), openMap: go('map'), closeOverlay: go('game')
    };

    // --- Пауза: сохранение подтверждается на самой кнопке ---
    v.saved = !!s.saved; v.notSaved = !s.saved;
    v.saveLabel = s.saved ? t.PAUSE_SAVED : t.PAUSE_SAVE;
    v.savedCls = s.saved ? 'is-saved' : '';
    v.doSave = function () {
      if (self.S().saved) return;
      self.setState({ saved: true, hasSave: true });
      clearTimeout(self._saveT);
      self._saveT = setTimeout(function () { self.setState({ saved: false }); }, 1500);
    };

    // --- Настройки ---
    var d = s.draft, binds = Object.assign({}, d.binds);
    var setField = function (id, val) {
      var cur = self.S().draft, nd = Object.assign({}, cur);
      nd[id] = val;
      if (id === 'preset' && PRESETS[val]) Object.assign(nd, PRESETS[val]);
      if (PRESET_FIELDS.indexOf(id) >= 0) nd.preset = 'custom';
      self.setState({ draft: nd, dd: '' });
    };
    var opt = function (k) { return t[k] != null ? t[k] : k; };
    var ROWS = {
      graphics: [
        { id: 'preset', type: 'drop', label: 'SETTINGS_PRESET', hint: 'SETTINGS_HINT_PRESET', opts: [['low', 'SETTINGS_PRESET_LOW'], ['medium', 'SETTINGS_PRESET_MEDIUM'], ['high', 'SETTINGS_PRESET_HIGH'], ['custom', 'SETTINGS_PRESET_CUSTOM']] },
        { id: 'scale', type: 'slider', label: 'SETTINGS_RES_SCALE', hint: 'SETTINGS_HINT_RES_SCALE', min: 50, max: 100, step: 5, fmt: function (x) { return x + ' %'; } },
        { id: 'shadows', type: 'check', label: 'SETTINGS_SHADOWS' },
        { id: 'shadowRes', type: 'drop', label: 'SETTINGS_SHADOW_RES', hint: 'SETTINGS_HINT_SHADOW_RES', opts: [['1024', '1024'], ['2048', '2048'], ['4096', '4096']], off: !d.shadows },
        { id: 'aa', type: 'drop', label: 'SETTINGS_AA', opts: [['off', 'SETTINGS_AA_OFF'], ['fxaa', 'FXAA'], ['msaa2', 'MSAA 2×'], ['msaa4', 'MSAA 4×']] },
        { id: 'vsync', type: 'check', label: 'SETTINGS_VSYNC' },
        { id: 'fov', type: 'slider', label: 'SETTINGS_FOV', min: 60, max: 110, step: 1, fmt: function (x) { return x + '°'; } },
        { id: 'fps', type: 'slider', label: 'SETTINGS_FPS_LIMIT', hint: 'SETTINGS_HINT_FPS', min: 0, max: 240, step: 10, fmt: function (x) { return x === 0 ? t.SETTINGS_FPS_UNLIMITED : String(x); } }
      ],
      audio: [
        { id: 'volume', type: 'slider', label: 'SETTINGS_VOLUME_MASTER', min: 0, max: 100, step: 1, fmt: function (x) { return x + ' %'; } }
      ],
      controls: [
        { id: 'sens', type: 'slider', label: 'SETTINGS_MOUSE_SENS', hint: 'SETTINGS_HINT_KEYS', min: 0.1, max: 5, step: 0.1, fmt: function (x) { return Number(x).toFixed(1); } }
      ]
    };
    v.rows = ROWS[s.tab].map(function (r) {
      var val = d[r.id], disabled = !!r.off, rid = 'set_' + r.id;
      var o = {
        id: r.id, label: t[r.label], disabled: disabled, enabled: !disabled,
        isDrop: r.type === 'drop', isSlider: r.type === 'slider', isCheck: r.type === 'check',
        cls: mod(rid) + (disabled ? ' is-disabled' : '') + (s.hintRow === r.id ? ' is-active' : ''),
        mark: function () { if (self.S().hintRow !== r.id) self.setState({ hintRow: r.id }); }
      };
      if (r.type === 'drop') {
        var cur = r.opts.filter(function (p) { return p[0] === val; })[0];
        o.valueText = cur ? opt(cur[1]) : String(val);
        o.open = s.dd === r.id && !disabled; o.closed = !o.open; o.openCls = o.open ? 'is-open' : '';
        o.toggle = function () { if (!disabled) self.setState({ dd: self.S().dd === r.id ? '' : r.id, hintRow: r.id }); };
        o.opts = r.opts.map(function (p) {
          var oid = 'opt_' + r.id + '_' + p[0];
          return { label: opt(p[1]), sel: p[0] === val, cls: mod(oid) + (p[0] === val ? ' is-sel' : ''), pick: function () { setField(r.id, p[0]); } };
        });
      } else if (r.type === 'slider') {
        o.val = val; o.min = r.min; o.max = r.max; o.step = r.step;
        o.pct = (((val - r.min) / (r.max - r.min)) * 100).toFixed(1) + '%';
        o.valueText = r.fmt(val);
        o.trackBg = STYLE === 'A'
          ? 'linear-gradient(to right, #C9A8F2 0 ' + o.pct + ', transparent ' + o.pct + '), repeating-linear-gradient(to right, rgba(236,232,242,.34) 0 1px, transparent 1px 4px)'
          : 'repeating-linear-gradient(to right, transparent 0 9px, #0D0F0F 9px 12px), linear-gradient(to right, #D8DBD6 0 ' + o.pct + ', #2E3231 ' + o.pct + ')';
        o.onInput = function (e) { setField(r.id, Number(e.target.value)); };
      } else {
        o.on = !!val; o.offv = !val; o.valueText = val ? t.SETTINGS_ON : t.SETTINGS_OFF; o.checkCls = val ? 'is-on' : 'is-off';
        o.toggle = function () { setField(r.id, !self.S().draft[r.id]); };
      }
      return o;
    });
    var hintSrc = ROWS[s.tab].filter(function (r) { return r.id === s.hintRow; })[0] || ROWS[s.tab][0];
    v.hintTitle = t[hintSrc.label];
    v.hintText = hintSrc.hint ? t[hintSrc.hint] : '';
    v.tabs = [['graphics', 'SETTINGS_TAB_GRAPHICS'], ['audio', 'SETTINGS_TAB_AUDIO'], ['controls', 'SETTINGS_TAB_CONTROLS']].map(function (p) {
      return { label: t[p[1]], cls: mod('tab_' + p[0]) + (s.tab === p[0] ? ' is-sel' : ''), sel: s.tab === p[0], pick: function () { self.setState({ tab: p[0], dd: '', waiting: '', hintRow: ROWS[p[0]][0].id }); } };
    });
    v.isControls = s.tab === 'controls';
    var codeOf = function (id) { var a = ACTIONS.filter(function (x) { return x[0] === id; })[0]; return binds[id] || a[2]; };
    var nameOf = function (id) { var a = ACTIONS.filter(function (x) { return x[0] === id; })[0]; return t[a[1]]; };
    var assign = function (id, code) {
      var cur = self.S().draft, nb = Object.assign({}, cur.binds), prev = nb[id] || ACTIONS.filter(function (x) { return x[0] === id; })[0][2], other = null;
      ACTIONS.forEach(function (a) { if (a[0] !== id && (nb[a[0]] || a[2]) === code) other = a[0]; });
      nb[id] = code;
      if (other) nb[other] = prev;
      self._assignedAt = Date.now();
      self.setState({ draft: Object.assign({}, cur, { binds: nb }), waiting: '', swap: other ? [id, other] : null });
    };
    v.binds = ACTIONS.map(function (a, i) {
      var id = a[0], w = s.waiting === id, bid = 'bind_' + id;
      return {
        label: t[a[1]], key: keyName(codeOf(id), t), waiting: w, idle: !w, col2: i >= 5,
        cls: mod(bid) + (w ? ' is-wait' : '') + (s.swap && s.swap.indexOf(id) >= 0 ? ' is-swapped' : ''),
        start: function () {
          if (Date.now() - (self._assignedAt || 0) < 350) return;
          self.setState({ waiting: self.S().waiting === id ? '' : id, swap: null, hintRow: 'sens' });
        },
        key_down: function (e) {
          if (self.S().waiting !== id) return;
          e.preventDefault(); e.stopPropagation();
          if (e.code === 'Escape') { self.setState({ waiting: '' }); return; }
          assign(id, e.code);
        },
        mouse_down: function (e) {
          if (self.S().waiting !== id) return;
          e.preventDefault();
          assign(id, 'Mouse' + e.button);
        }
      };
    });
    v.binds1 = v.binds.filter(function (b) { return !b.col2; });
    v.binds2 = v.binds.filter(function (b) { return b.col2; });
    v.waitText = t.SETTINGS_REBIND_WAIT;
    v.cancelText = tr(t, 'SETTINGS_REBIND_CANCEL', 'Esc');
    v.anyWaiting = !!s.waiting;
    v.swapText = s.swap ? tr(t, 'SETTINGS_REBIND_SWAPPED', nameOf(s.swap[0]), nameOf(s.swap[1])) : '';
    v.hasSwap = !!s.swap;
    var dirty = !same(s.draft, s.applied);
    v.dirty = dirty; v.clean = !dirty; v.applyOff = !dirty;
    v.apply = function () { var st = self.S(); self.setState({ applied: st.draft, dd: '', swap: null }); };
    v.reset = function () { self.setState({ draft: DEF, dd: '', waiting: '', swap: null }); };
    v.cancel = function () { var st = self.S(); self.go(st.from, { draft: st.applied, swap: null }); };

    // --- Итоги забега ---
    var bodies = t.BODY_WALKER + ' ×2, ' + t.BODY_CRAWLER + ', ' + t.BODY_HOUND;
    v.stats = [
      ['RUN_STAT_TIME', '14:32'], ['RUN_STAT_ROOMS', '23'], ['RUN_STAT_BODIES', '4'], ['RUN_STAT_BODY_LIST', bodies],
      ['RUN_STAT_DAMAGE_TAKEN', '312'], ['RUN_STAT_DAMAGE_DEALT', '540'], ['RUN_STAT_SKILL_POINTS', '+3']
    ].map(function (p) { return { label: t[p[0]], value: p[1], long: p[1].length > 8 }; });
    v.reviving = !!s.reviving; v.notReviving = !s.reviving;
    v.reviveLabel = s.reviving ? t.RUN_SUMMARY_REVIVING : t.RUN_SUMMARY_REVIVE;
    v.revive = function () {
      if (self.S().reviving) return;
      self.setState({ reviving: true });
      clearTimeout(self._revT);
      self._revT = setTimeout(function () { self.go('game', { reviving: false }); }, 2400);
    };

    // --- Навыки ---
    var arch = s.tree === 'arch', defs = arch ? ARCH : SOUL, ranks = arch ? s.aranks : s.ranks;
    var wallet = arch ? s.essence : s.points, lay = L.skills[arch ? 'arch' : 'soul'];
    var rk = function (id) { return ranks[id] || 0; };
    var costText = function (c) { return arch ? fmtK(c, s.lang, t) : String(c); };
    var info = {};
    defs.forEach(function (df) {
      var r = rk(df.id), met = df.req.every(function (q) { return rk(q[0]) >= q[1]; });
      var cost = r < df.max ? df.cost[r] : 0;
      info[df.id] = { r: r, met: met, cost: cost, can: !df.ph && met && r < df.max && wallet >= cost };
    });
    var selId = arch ? s.asel : s.sel;
    v.nodes = defs.map(function (df, i) {
      var p = lay.nodes[df.id], inf = info[df.id], r = inf.r, st;
      if (df.ph) st = 'ph'; else if (r >= df.max) st = 'max'; else if (r > 0) st = 'part'; else if (inf.met) st = 'avail'; else st = 'lock';
      var seg = 360 / df.max, gap = df.max > 1 ? 16 : 0, on = '', off = '';
      for (var k = 0; k < df.max; k++) {
        var dd = arcSeg(22, 22, 17, k * seg + gap / 2, (k + 1) * seg - gap / 2 - (df.max === 1 ? 0.01 : 0));
        if (k < r) on += dd + ' '; else off += dd + ' ';
      }
      var pips = [];
      for (var q = 0; q < df.max; q++) pips.push({ on: q < r, off: q >= r, cls: q < r ? 'on' : 'off' });
      return {
        id: df.id, x: p[0], y: p[1], lx: p[2] || 'r',
        name: df.ph ? t.ARCHITECT_BRANCH_FUTURE : t[df.name || ('SKILL_' + df.id.toUpperCase() + '_NAME')],
        rankText: df.ph ? '' : r + '/' + df.max, pips: df.ph ? [] : pips,
        costText: df.ph || r >= df.max ? '' : costText(inf.cost),
        ringOn: on || 'M0 0', ringOff: off || 'M0 0',
        cls: ' n-' + st + (selId === df.id ? ' is-sel' : '') + (s.flash === df.id ? ' is-flash' : '') + (inf.can ? ' is-can' : '') + mod('node_' + df.id),
        labelLeft: p[2] === 'l', labelRight: p[2] !== 'l', side: p[2] === 'l' ? 'l' : 'r',
        pos: 'left:' + p[0] + 'px;top:' + p[1] + 'px', stCls: 'n-' + st,
        flash: s.flash === df.id, ph: !!df.ph, real: !df.ph,
        pick: function () { if (!df.ph) self.setState(arch ? { asel: df.id } : { sel: df.id }); }
      };
    });
    var lit = '', av = '', lk = '', fresh = '';
    defs.forEach(function (df, i) {
      df.req.forEach(function (q) {
        var a = lay.nodes[q[0]], b = lay.nodes[df.id];
        var dpath = STYLE === 'A' ? rag(a[0], a[1], b[0], b[1], i * 1.7 + 0.3, 3.2) : elbow(a, b, L.cellW, L.cellH);
        if (s.flash === df.id && rk(df.id) === 1) fresh = dpath;
        if (rk(df.id) > 0) lit += dpath + ' ';
        else if (info[df.id].met) av += dpath + ' ';
        else lk += dpath + ' ';
      });
    });
    v.linkLit = lit || 'M0 0'; v.linkAvail = av || 'M0 0'; v.linkLock = lk || 'M0 0'; v.linkFresh = fresh || 'M0 0'; v.hasFresh = !!fresh;
    v.extraD = lay.extra || 'M0 0';
    v.branches = lay.branches.map(function (b) { return { label: t[BRANCH_KEY[b[0]]], x: b[1], y: b[2], dim: b[0] === 'future' }; });
    v.arch = arch; v.soul = !arch;
    v.treeTabs = [['soul', 'SKILL_TAB_SOUL'], ['arch', 'SKILL_TAB_ARCHITECT']].map(function (p) {
      return { label: t[p[1]], sel: s.tree === p[0], cls: mod('tree_' + p[0]) + (s.tree === p[0] ? ' is-sel' : ''), pick: function () { self.setState({ tree: p[0], flash: '', toast: '' }); } };
    });
    v.walletLabel = arch ? t.ARCHITECT_ESSENCE : t.SKILL_POINTS;
    v.walletValue = arch ? fmtK(s.essence, s.lang, t) : String(s.points);
    v.walletFlash = !!s.flash; v.walletCls = s.flash ? 'is-flash' : '';
    var sd = defs.filter(function (x) { return x.id === selId; })[0] || defs[0], si = info[sd.id];
    var sp = [];
    for (var q2 = 0; q2 < sd.max; q2++) sp.push({ on: q2 < si.r, off: q2 >= si.r, cls: q2 < si.r ? 'on' : 'off' });
    var reason = '';
    if (si.r >= sd.max) reason = t.SKILL_MAXED;
    else if (!si.met) reason = t.SKILL_LOCKED;
    else if (wallet < si.cost) reason = arch ? t.SKILL_NO_ESSENCE : t.SKILL_NO_POINTS;
    v.det = {
      name: t[sd.name || ('SKILL_' + sd.id.toUpperCase() + '_NAME')], desc: t[sd.desc || ('SKILL_' + sd.id.toUpperCase() + '_DESC')],
      branch: t[BRANCH_KEY[sd.br]], rank: tr(t, 'SKILL_RANK', si.r, sd.max), pips: sp,
      costLabel: t.SKILL_COST, cost: si.r >= sd.max ? '—' : costText(si.cost),
      reqLabel: t.SKILL_REQUIRES,
      reqs: (sd.req.length ? sd.req.map(function (q) { var nm = t['SKILL_' + q[0].toUpperCase() + '_NAME']; return { text: tr(t, 'SKILL_REQ_RANK', nm, q[1]), met: rk(q[0]) >= q[1] }; }) : [{ text: t.SKILL_NO_REQ, met: true }]).map(function (q) {
        return { text: q.text, met: q.met, unmet: !q.met, cls: q.met ? 'met' : 'unmet', mark: q.met ? '■' : '□',
          fill: q.met ? '#C9A8F2' : 'none', stroke: q.met ? '#C9A8F2' : 'rgba(236,232,242,.5)', dash: q.met ? '0' : '1 2' };
      }),
      can: si.can, cannot: !si.can, btn: si.can ? tr(t, 'SKILL_UNLOCK', si.r + 1) : reason,
      btnCls: mod('unlock') + (si.can ? '' : ' is-disabled')
    };
    v.toast = s.toast; v.hasToast = !!s.toast;
    v.unlock = function () {
      var st = self.S(), isA = st.tree === 'arch', dfs = isA ? ARCH : SOUL, id = isA ? st.asel : st.sel;
      var df = dfs.filter(function (x) { return x.id === id; })[0], rr = (isA ? st.aranks : st.ranks)[id] || 0;
      var ok = df.req.every(function (q) { return ((isA ? st.aranks : st.ranks)[q[0]] || 0) >= q[1]; });
      var w = isA ? st.essence : st.points;
      if (df.ph || rr >= df.max || !ok || w < df.cost[rr]) return;
      var nr = Object.assign({}, isA ? st.aranks : st.ranks); nr[id] = rr + 1;
      var o = { flash: id, toast: tr(STR[st.lang], 'SKILL_UNLOCKED', rr + 1) };
      if (isA) { o.aranks = nr; o.essence = w - df.cost[rr]; if (id === 'map_level') o.mapLevel = Math.max(st.mapLevel, rr + 1); }
      else { o.ranks = nr; o.points = w - df.cost[rr]; }
      self.setState(o);
      clearTimeout(self._flashT);
      self._flashT = setTimeout(function () { self.setState({ flash: '', toast: '' }); }, 1400);
    };

    // --- Карта ---
    var lvl = s.mapLevel, here = MAPDATA.here, M = L.map;
    v.mapNoLink = lvl <= 0; v.mapOk = lvl > 0;
    v.mapLevelText = tr(t, 'MAP_LEVEL', Math.max(0, lvl), 4);
    var known = function (li) { return lvl >= 3 || li === here.layer; };
    var selLayer = s.mapLayer;
    v.layers = MAPDATA.layers.map(function (ly) {
      var k = known(ly.idx), sub = ly.idx === 0 ? t.MAP_LAYER_SURFACE : ly.idx === MAPDATA.layers.length - 1 ? t.MAP_LAYER_DEPTH : '';
      var o = {
        idx: ly.idx, label: tr(t, 'MAP_LAYER', ly.idx), sub: sub, hasSub: !!sub, known: k, unknown: !k,
        closedText: t.MAP_LAYER_CLOSED, here: ly.idx === here.layer, floorsText: tr(t, 'MAP_FLOORS', ly.floors.length),
        cls: mod('layer_' + ly.idx) + (ly.idx === selLayer ? ' is-sel' : '') + (k ? '' : ' is-unknown') + (ly.idx === here.layer ? ' is-here' : ''),
        pick: function () { self.setState({ mapLayer: ly.idx, hover: '', pinned: '' }); }
      };
      if (M.slice) {
        // Срез: координаты локальные, от левого верхнего угла полосы слоя.
        var sl = M.slice, top = sl.y0 + ly.idx * sl.band, H = sl.band - 4, fh = (H - 24) / Math.max(1, ly.floors.length), lines = '', ticks = '', tdim = '';
        var sx = function (c) { return sl.lx + c * (sl.w - sl.lx - 8) / MAPDATA.cols; };
        ly.floors.forEach(function (fl, fi) {
          var y = 24 + fh * (fi + 0.6);
          lines += 'M' + sl.lx + ' ' + y.toFixed(1) + ' H' + sl.w + ' ';
          fl.rooms.forEach(function (rm) {
            var x = sx(rm.x), w = Math.max(3, sx(rm.x + rm.w) - x - 3);
            var seg = 'M' + x.toFixed(1) + ' ' + y.toFixed(1) + ' h' + w.toFixed(1) + ' ';
            if (!k || !(lvl >= 2 || rm.visited)) return;
            if (rm.visited) ticks += seg; else tdim += seg;
          });
          if (ly.idx === here.layer && fi === here.floor) {
            var hr = fl.rooms.filter(function (rm) { return rm.id === here.room; })[0];
            o.px = sx(hr.x + hr.w / 2).toFixed(1); o.py = (y - 8).toFixed(1); o.hereMark = true;
          }
        });
        o.top = top; o.h = H; o.lines = k ? lines : 'M0 0'; o.ticks = ticks || 'M0 0'; o.tdim = tdim || 'M0 0';
        o.hereMark = !!o.hereMark;
      }
      return o;
    });
    if (M.slice) {
      var sl2 = M.slice, pl = '';
      MAPDATA.layerLinks.forEach(function (lnk) {
        if (!(known(lnk[0]) && known(lnk[0] + 1))) return;
        var x = sl2.x0 + sl2.lx + (lnk[1] + 0.5) * (sl2.w - sl2.lx - 8) / MAPDATA.cols;
        pl += 'M' + x.toFixed(1) + ' ' + (sl2.y0 + lnk[0] * sl2.band + sl2.band - 18) + ' V' + (sl2.y0 + (lnk[0] + 1) * sl2.band + 20) + ' ';
      });
      v.sliceLinks = pl || 'M0 0';
      v.hereLayer = v.layers[here.layer];
    }
    var LY = MAPDATA.layers[selLayer], selKnown = known(selLayer);
    v.selKnown = selKnown && lvl > 0; v.selUnknown = !selKnown && lvl > 0;
    v.selTitle = tr(t, 'MAP_LAYER', selLayer) + (selLayer === 0 ? ' · ' + t.MAP_LAYER_SURFACE : selLayer === MAPDATA.layers.length - 1 ? ' · ' + t.MAP_LAYER_DEPTH : '');
    // Этажи раскладываются сеткой: число колонок выбирается так, чтобы клетка плана была крупнее.
    var nF = LY.floors.length, best = null;
    for (var c = 1; c <= nF; c++) {
      var rws = Math.ceil(nF / c), cw = (M.w - M.gap * (c - 1)) / c, ch = (M.h - M.gap * (rws - 1)) / rws;
      var ce = Math.min(M.maxCell, (cw - 20) / MAPDATA.cols, (ch - 44) / MAPDATA.rows);
      if (!best || ce > best.cell + 0.01) best = { c: c, pw: cw, ph: ch, cell: ce };
    }
    var pw = best.pw, ph = best.ph, cell = Math.floor(best.cell);
    var corrK = '', corrU = '', infoText = '';
    var roomName = function (rm) {
      if (lvl >= 4 && rm.kind === 'hub') return t.MAP_UNIQUE_HUB;
      if (lvl >= 4 && rm.kind === 'exit') return t.MAP_UNIQUE_EXIT;
      if (lvl >= 4 && rm.kind === 'arch') return t.MAP_UNIQUE_ARCHITECT;
      if (rm.kind === 'stairs') return t.MAP_STAIRS;
      return t.MAP_ROOM;
    };
    v.floors = LY.floors.map(function (fl, fi) {
      var px = M.x0 + (fi % best.c) * (pw + M.gap), py = M.y0 + Math.floor(fi / best.c) * (ph + M.gap);
      var gw = cell * MAPDATA.cols, gh = cell * MAPDATA.rows;
      var ox = Math.round(px + (pw - gw) / 2), oy = Math.round(py + 34 + (ph - 34 - gh) / 2);
      var vis = function (rm) { return selKnown && (lvl >= 2 || rm.visited); };
      fl.corr.forEach(function (c) {
        var seg = 'M' + (ox + c[0] * cell).toFixed(1) + ' ' + (oy + c[1] * cell).toFixed(1) + ' L' + (ox + c[2] * cell).toFixed(1) + ' ' + (oy + c[3] * cell).toFixed(1) + ' ';
        if (!selKnown) return;
        if (c[4]) corrK += seg; else if (lvl >= 2) corrU += seg;
      });
      var rooms = fl.rooms.filter(vis).map(function (rm) {
        var rid = rm.id, hov = s.hover === rid;
        if (hov) infoText = roomName(rm) + ' · ' + (rm.visited ? t.MAP_VISITED : t.MAP_UNEXPLORED) + (rid === here.room ? ' · ' + t.MAP_HERE : '');
        var uniq = lvl >= 4 && (rm.kind === 'hub' || rm.kind === 'exit' || rm.kind === 'arch');
        return {
          left: (ox + rm.x * cell + 2).toFixed(1), top: (oy + rm.y * cell + 2).toFixed(1), w: (rm.w * cell - 4).toFixed(1), h: (rm.h * cell - 4).toFixed(1),
          name: roomName(rm), uniq: uniq, uniqText: uniq ? roomName(rm) : '',
          cls: mod('room_' + rid) + (rm.visited ? ' r-vis' : ' r-unx') + (rm.kind === 'stairs' ? ' r-stairs' : '') + (uniq ? ' r-uniq' : '') + (hov ? ' is-hover' : '') + (rid === here.room ? ' r-here' : ''),
          enter: function () { self.setState({ hover: rid }); }, leave: function () { if (self.S().hover === rid) self.setState({ hover: '' }); }
        };
      });
      var portals = fl.portals.filter(function (p) { return selKnown && (lvl >= 2 || p.visited); }).map(function (p) {
        var pid = p.id, hov = s.hover === pid || s.pinned === pid, up = p.dir === 'up';
        var lbl = (up ? t.MAP_PORTAL_UP : t.MAP_PORTAL_DOWN) + ' ' + tr(t, 'MAP_PORTAL_TARGET', p.to[0], p.to[1] + 1);
        if (hov) infoText = lbl;
        return {
          left: (ox + (p.x + 0.5) * cell - 11).toFixed(1), top: (oy + (p.y + 0.5) * cell - 11).toFixed(1), up: up, down: !up, label: lbl,
          arrow: up ? 'M12 19V5 M6 11l6-6 6 6' : 'M12 5v14 M6 13l6 6 6-6',
          cls: mod('portal_' + pid) + (hov ? ' is-hover' : '') + (s.pinned === pid ? ' is-pinned' : ''),
          enter: function () { self.setState({ hover: pid }); }, leave: function () { if (self.S().hover === pid) self.setState({ hover: '' }); },
          jump: function () { self.setState({ mapLayer: p.to[0], pinned: p.pair, hover: '' }); }
        };
      });
      var hr = selLayer === here.layer && fi === here.floor ? fl.rooms.filter(function (rm) { return rm.id === here.room; })[0] : null;
      return {
        label: tr(t, 'MAP_FLOOR', fi + 1), x: px.toFixed(1), y: py.toFixed(1), w: pw.toFixed(1), h: ph.toFixed(1), ly: py.toFixed(1), cell: cell,
        gx: ox, gy: oy, gw: gw, gh: gh,
        rooms: rooms, portals: portals, here: !!hr,
        hx: hr ? (ox + (hr.x + hr.w / 2) * cell).toFixed(1) : 0, hy: hr ? (oy + (hr.y + hr.h / 2) * cell).toFixed(1) : 0,
        hl: hr ? (ox + (hr.x + hr.w / 2) * cell - 12).toFixed(1) : 0, ht: hr ? (oy + (hr.y + hr.h / 2) * cell - 12).toFixed(1) : 0
      };
    });
    v.corrK = corrK || 'M0 0'; v.corrU = corrU || 'M0 0';
    v.mapInfo = infoText || t.MAP_HINT; v.mapHasInfo = !!infoText; v.mapInfoCls = infoText ? 'is-info' : 'is-hint';

    // --- Полоса прототипа ---
    var scr = [['menu', 'Меню'], ['game', 'Игра'], ['pause', 'Пауза'], ['settings', 'Настройки'], ['summary', 'Итоги'], ['skills', 'Навыки'], ['map', 'Карта']];
    v.protoScreens = scr.map(function (p) {
      return { label: p[1], on: s.screen === p[0], cls: s.screen === p[0] ? 'on' : '', pick: function () { self.go(p[0], p[0] === 'settings' ? { from: 'menu', draft: self.S().applied } : (p[0] === 'summary' ? { reviving: false } : {})); } };
    });
    v.protoLangs = [['ru', 'RU'], ['en', 'EN']].map(function (p) { return { label: p[1], cls: s.lang === p[0] ? 'on' : '', pick: function () { self.setState({ lang: p[0] }); } }; });
    v.protoSave = [[true, 'есть'], [false, 'пусто']].map(function (p) { return { label: p[1], cls: s.hasSave === p[0] ? 'on' : '', pick: function () { self.setState({ hasSave: p[0] }); } }; });
    v.protoLevels = [0, 1, 2, 3, 4].map(function (n) { return { label: String(n), cls: s.mapLevel === n ? 'on' : '', pick: function () { self.setState({ mapLevel: n, aranks: Object.assign({}, self.S().aranks, { map_level: n }) }); } }; });
    return v;
  }
}
