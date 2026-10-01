// Прогон renderVals каждого артборда с заглушкой DCLogic: ловит синтаксис и падения логики.
const fs = require('fs');
const path = require('path');
const dir = path.join(__dirname, '..', 'canvas');
let fails = 0;
for (const fn of fs.readdirSync(dir).filter(f => f.endsWith('.dc.html'))) {
  const src = fs.readFileSync(path.join(dir, fn), 'utf8');
  const m = src.match(/data-dc-script[^>]*>([\s\S]*?)<\/script>/);
  const code = 'class DCLogic { constructor(){ this.state = null; this.props = {}; } setState(o){ this.state = Object.assign({}, this.state || {}, o); } }\n' + m[1] + '\nmodule.exports = Component;';
  try {
    const mod = { exports: null };
    new Function('module', 'setTimeout', 'clearTimeout', 'performance', code)(mod, () => 0, () => 0, { now: () => 0 });
    const C = mod.exports, c = new C();
    let v = c.renderVals();
    if (fn.startsWith('Spec')) { console.log('ok', fn); continue; }
    const holes = new Set([...src.matchAll(/\{\{\s*([a-zA-Z_][\w.]*)\s*\}\}/g)].map(x => x[1]));
    // корневые имена дыр должны существовать в renderVals (кроме переменных циклов)
    const loopVars = new Set([...src.matchAll(/as="(\w+)"/g)].map(x => x[1]));
    const missing = [...holes].filter(h => { const r = h.split('.')[0]; return !loopVars.has(r) && !(r in v) && r !== 'false' && r !== 'true'; });
    if (missing.length) { console.log('MISSING', fn, missing); fails++; }
    // проход по экранам и обработчикам
    for (const scr of ['menu', 'game', 'pause', 'settings', 'summary', 'skills', 'map']) {
      c.setState({ screen: scr }); v = c.renderVals();
    }
    // макеты стартуют с уже правленым черновиком — проверки ведём от применённых настроек
    c.setState({ screen: 'settings', tab: 'graphics', draft: c.S().applied, swap: null, waiting: '' }); v = c.renderVals();
    v.rows[0].opts[0].pick(); v = c.renderVals(); v.rows[1].onInput({ target: { value: 75 } }); v = c.renderVals();
    v.rows[2].toggle(); v = c.renderVals();
    if (v.rows[0].valueText !== c.renderVals().t.SETTINGS_PRESET_CUSTOM) throw new Error('preset should become custom');
    c.setState({ tab: 'controls' }); v = c.renderVals();
    v.binds[0].start(); v = c.renderVals();
    v.binds[0].key_down({ code: 'KeyS', preventDefault() {}, stopPropagation() {} }); v = c.renderVals();
    if (!v.hasSwap) throw new Error('swap expected');
    v.apply(); v = c.renderVals(); if (!v.applyOff) throw new Error('apply should disable');
    c.setState({ screen: 'skills', tree: 'soul', sel: 'decay_capacity', points: 3, ranks: { body_snatch: 1, lifespan: 1 } }); v = c.renderVals(); v.unlock(); v = c.renderVals();
    if (c.state.points !== 2 || c.state.ranks.decay_capacity !== 1) throw new Error('unlock should spend');
    c.setState({ tree: 'arch' }); v = c.renderVals(); v.unlock(); v = c.renderVals();
    c.setState({ screen: 'map', mapLevel: 4 }); v = c.renderVals();
    for (const L of [0, 1, 2, 3, 4, 5]) { c.setState({ mapLayer: L }); v = c.renderVals(); }
    c.setState({ mapLayer: 2 }); v = c.renderVals(); const pt = v.floors.flatMap(f => f.portals)[0]; if (pt) { pt.jump(); v = c.renderVals(); }
    c.setState({ lang: 'en', mapLevel: 0 }); v = c.renderVals();
    console.log('ok', fn, 'nodes', v.nodes.length, 'floors', v.floors.length);
  } catch (err) { console.log('FAIL', fn, err.message); fails++; }
}
process.exit(fails ? 1 : 0);
