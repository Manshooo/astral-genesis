import json
import os
import random
import re
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(__file__))
from strings import S  # noqa: E402
import scenes  # noqa: E402
import spec  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
# Файлы холста лежат плоско: на холсте Claude Design это project/<имя>, сюда — без project/.
PROJ = os.path.join(os.path.dirname(HERE), "canvas")
# Кадр коридора взят с холста HUD (Main.dc.html), чтобы фон меню в забеге был тем же миром.
HUD_FRAME = os.path.join(HERE, "hud_corridor.fragment.html")
os.makedirs(PROJ, exist_ok=True)


def rd(name):
	with open(os.path.join(HERE, name), encoding="utf-8") as f:
		return f.read()


STR = {"ru": {k: ru for k, ru, en, _ in S}, "en": {k: en for k, ru, en, _ in S}}

# --- Карта: 6 слоёв, этажи, комнаты на сетке 12×8, коридоры, лестница, порталы ---
COLS, ROWS = 12, 8
FLOORS = [2, 3, 2, 3, 2, 2]
HERE_LAYER, HERE_FLOOR = 2, 0


def gen_floor(rnd, li, fi, stairs):
	occ = [[False] * COLS for _ in range(ROWS)]
	rooms = []

	def free(x, y, w, h):
		if x < 0 or y < 0 or x + w > COLS or y + h > ROWS:
			return False
		for yy in range(max(0, y - 1), min(ROWS, y + h + 1)):
			for xx in range(max(0, x - 1), min(COLS, x + w + 1)):
				if occ[yy][xx]:
					return False
		return True

	def put(x, y, w, h, kind):
		for yy in range(y, y + h):
			for xx in range(x, x + w):
				occ[yy][xx] = True
		rooms.append({"id": "L%dF%dR%d" % (li, fi, len(rooms)), "x": x, "y": y, "w": w, "h": h, "kind": kind, "visited": False})

	if stairs:
		put(stairs[0], stairs[1], 1, 2, "stairs")
	tries = 0
	while len(rooms) < 8 and tries < 400:
		tries += 1
		w, h = rnd.choice([(1, 1), (2, 1), (2, 2), (3, 2), (1, 2), (2, 1)])
		x, y = rnd.randrange(0, COLS), rnd.randrange(0, ROWS)
		if free(x, y, w, h):
			put(x, y, w, h, "room")
	rooms.sort(key=lambda r: (r["x"] + r["w"] / 2.0))
	for i, r in enumerate(rooms):
		r["id"] = "L%dF%dR%d" % (li, fi, i)
	corr = []
	for a, b in zip(rooms, rooms[1:]):
		ax, ay = a["x"] + a["w"] / 2.0, a["y"] + a["h"] / 2.0
		bx, by = b["x"] + b["w"] / 2.0, b["y"] + b["h"] / 2.0
		corr.append([ax, ay, bx, ay, a["id"], b["id"]])
		corr.append([bx, ay, bx, by, a["id"], b["id"]])
	return {"rooms": rooms, "corr": corr, "portals": []}


def gen_map():
	rnd = random.Random(16)
	layers = []
	for li, nf in enumerate(FLOORS):
		st = (rnd.randrange(3, 9), rnd.randrange(2, 5))
		floors = [gen_floor(rnd, li, fi, st) for fi in range(nf)]
		layers.append({"idx": li, "floors": floors})
	# уникальные комнаты
	def first_room(fl, k=0):
		rs = [r for r in fl["rooms"] if r["kind"] == "room"]
		return rs[k % len(rs)]
	first_room(layers[0]["floors"][0], 1)["kind"] = "hub"
	first_room(layers[2]["floors"][1], 2)["kind"] = "arch"
	first_room(layers[5]["floors"][-1], 3)["kind"] = "exit"
	# посещённое
	for li, ly in enumerate(layers):
		for fi, fl in enumerate(ly["floors"]):
			for ri, r in enumerate(fl["rooms"]):
				if li == 0:
					r["visited"] = True
				elif li == 1:
					r["visited"] = fi == 0 or (fi == 1 and ri % 2 == 0) or (fi == 2 and ri < 3)
				elif li == 2:
					r["visited"] = fi == 0 and ri <= 4
	here_room = [r for r in layers[HERE_LAYER]["floors"][HERE_FLOOR]["rooms"] if r["visited"] and r["kind"] == "room"][-1]
	# порталы между слоями: вниз с последнего этажа слоя i, вверх на первый этаж слоя i+1
	links = []
	for li in range(len(layers) - 1):
		a_fl = layers[li]["floors"][-1]
		b_fl = layers[li + 1]["floors"][0]
		ra = [r for r in a_fl["rooms"] if r["kind"] == "room"][-1]
		rb = [r for r in b_fl["rooms"] if r["kind"] == "room"][0]
		ida, idb = "P%dd" % li, "P%du" % (li + 1)
		a_fl["portals"].append({"id": ida, "pair": idb, "x": ra["x"], "y": ra["y"], "dir": "down", "to": [li + 1, 0], "visited": ra["visited"]})
		b_fl["portals"].append({"id": idb, "pair": ida, "x": rb["x"], "y": rb["y"], "dir": "up", "to": [li, len(layers[li]["floors"]) - 1], "visited": rb["visited"]})
		links.append([li, ra["x"]])
	vis = {}
	for ly in layers:
		for fl in ly["floors"]:
			for r in fl["rooms"]:
				vis[r["id"]] = r["visited"]
	for ly in layers:
		for fl in ly["floors"]:
			fl["corr"] = [[c[0], c[1], c[2], c[3], 1 if (vis[c[4]] and vis[c[5]]) else 0] for c in fl["corr"]]
	return {"cols": COLS, "rows": ROWS, "layers": layers, "layerLinks": links,
		"here": {"layer": HERE_LAYER, "floor": HERE_FLOOR, "room": here_room["id"]}}


MAP = gen_map()
HOVER_ROOM = [r for r in MAP["layers"][2]["floors"][0]["rooms"] if r["visited"] and r["kind"] == "room"][1]["id"]
PIN_PORTAL = MAP["layers"][2]["floors"][0]["portals"][0]["id"]

# --- Раскладки ---
A_ARCH_CX, A_ARCH_CY, A_ARCH_S = 520, 390, 2.2
LAYOUT = {
	"A": {
		"skills": {
			"soul": {
				"nodes": {
					"body_snatch": [520, 390, "r"], "capture_precision": [520, 215, "r"],
					"lifespan": [720, 470, "r"], "decay_capacity": [860, 372, "r"], "graceful_exit": [890, 545, "r"],
					"overflow_control": [700, 628, "r"], "last_breath": [880, 650, "r"],
					"steady_legs": [320, 470, "l"], "spring_step": [200, 372, "l"], "resilient_flesh": [170, 560, "l"], "second_wind": [330, 640, "r"],
				},
				"branches": [["possession", 470, 150], ["survival", 760, 414], ["embodiment", 180, 428]],
				"extra": "",
			},
			"arch": {
				"nodes": {"map_level": [324, 313, "l"], "future_1": [716, 313, "r"], "future_2": [381, 529, "l"]},
				"branches": [["knowledge", 196, 262], ["future", 720, 262], ["future", 230, 580]],
				"extra": scenes.logo_transformed(A_ARCH_CX, A_ARCH_CY, A_ARCH_S),
			},
		},
		"map": {"x0": 560, "y0": 110, "w": 840, "h": 490, "gap": 28, "maxCell": 34,
			"slice": {"x0": 112, "y0": 110, "w": 364, "band": 90, "lx": 46}},
	},
	"B": {
		"cellW": 230, "cellH": 52,
		"skills": {
			"soul": {
				"nodes": {
					"body_snatch": [382, 128, "r", "root"], "capture_precision": [112, 236, "r"],
					"lifespan": [382, 236, "r"], "decay_capacity": [382, 314, "r"], "graceful_exit": [382, 392, "r"],
					"overflow_control": [382, 470, "r"], "last_breath": [382, 548, "r"],
					"steady_legs": [652, 236, "r"], "spring_step": [652, 314, "r"], "resilient_flesh": [652, 392, "r"], "second_wind": [652, 470, "r"],
				},
				"branches": [["possession", 112, 190], ["survival", 382 - 130, 190], ["embodiment", 652, 190]],
				"extra": "",
			},
			"arch": {
				"nodes": {"map_level": [112, 236, "r"], "future_1": [382, 236, "r"], "future_2": [652, 236, "r"]},
				"branches": [["knowledge", 112, 212], ["future", 382, 212], ["future", 652, 212]],
				"extra": "",
			},
		},
		"map": {"x0": 396, "y0": 78, "w": 1005, "h": 548, "gap": 16, "maxCell": 40},
	},
}
# подпись ветви «Выживание» в B стоит над колонкой, слева от корня ей не место
LAYOUT["B"]["skills"]["soul"]["branches"][1][1] = 382 - 0
LAYOUT["B"]["skills"]["soul"]["branches"][1][2] = 212
LAYOUT["B"]["skills"]["soul"]["branches"][0][2] = 212
LAYOUT["B"]["skills"]["soul"]["branches"][2][2] = 212

RAG = ('<svg class="ag-rag" viewBox="0 0 100 6" preserveAspectRatio="none" aria-hidden="true"><path pathLength="1" vector-effect="non-scaling-stroke" '
	'd="M0 3.2 L6 2.4 L12 3.6 L19 2.9 L27 3.8 L34 2.6 L41 3.3 L49 2.2 L57 3.5 L64 2.8 L72 3.9 L80 2.7 L87 3.4 L94 2.5 L100 3.1"></path></svg>')
CORNERS = ('<span class="tm-corner" style="left:-1px;top:-1px;border-width:1px 0 0 1px"></span>'
	'<span class="tm-corner" style="right:-1px;top:-1px;border-width:1px 1px 0 0"></span>'
	'<span class="tm-corner" style="left:-1px;bottom:-1px;border-width:0 0 1px 1px"></span>'
	'<span class="tm-corner" style="right:-1px;bottom:-1px;border-width:0 1px 1px 0"></span>')


def strip(style):
	bg, line = ("#121015", "#2a2530") if style == "A" else ("#0D0F0F", "#2E3231")
	name = "A «Отголосок»" if style == "A" else "B «Терминал X-16»"
	return ('<div style="position:absolute;left:0;top:720px;width:1497px;height:80px;box-sizing:border-box;padding:10px 18px;background:%s;border-top:1px solid %s;display:flex;flex-direction:column;justify-content:center;gap:6px">'
		'<div class="pr"><span style="margin-left:0;color:#D8D2E0">Прототип %s · экран</span>'
		'<sc-for list="{{protoScreens}}" as="p" hint-placeholder-count="7"><button class="{{p.cls}}" onClick="{{p.pick}}">{{p.label}}</button></sc-for>'
		'<span>язык</span><sc-for list="{{protoLangs}}" as="p" hint-placeholder-count="2"><button class="{{p.cls}}" onClick="{{p.pick}}">{{p.label}}</button></sc-for>'
		'<span>сейв</span><sc-for list="{{protoSave}}" as="p" hint-placeholder-count="2"><button class="{{p.cls}}" onClick="{{p.pick}}">{{p.label}}</button></sc-for>'
		'<span>уровень карты</span><sc-for list="{{protoLevels}}" as="p" hint-placeholder-count="5"><button class="{{p.cls}}" onClick="{{p.pick}}">{{p.label}}</button></sc-for></div>'
		'<div class="pr"><span style="margin-left:0">Tab — фокус с клавиатуры · Настройки → Управление: клик по клавише ждёт новую (Esc — отмена, мышь тоже ловится) · Навыки: выберите узел и откройте ранг · Карта: наведение на комнату, клик по порталу</span></div>'
		'</div>') % (bg, line, name)


def fill(tpl, style):
	game = open(HUD_FRAME, encoding="utf-8").read().strip()
	out = tpl.replace("RAG", RAG).replace("CORNERS", CORNERS).replace("LOGOD", scenes.LOGO_D)
	out = out.replace("GAMESCENE", game).replace("PROTOSTRIP", strip(style))
	out = out.replace("MENUSCENE", scenes.menu_scene_a() if style == "A" else scenes.menu_scene_b())
	out = out.replace("SUMMARYSCENE", scenes.summary_scene_a())
	return out


TPL = {"A": fill(rd("a.html"), "A"), "B": fill(rd("b.html"), "B")}
CSS = {"A": rd("a.css"), "B": rd("b.css")}
LOGIC = rd("logic.js")
FONTS = '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Golos+Text:wght@400;500;600&amp;family=IBM+Plex+Mono:wght@400;500&amp;display=swap">'


def cl_ids(tpl):
	return sorted(set(re.findall(r"\{\{cl\.([a-z_0-9]+)\}\}", tpl)))


def board(style, title, boot, h):
	logic = (LOGIC.replace("__STYLE__", json.dumps(style))
		.replace("__STR__", json.dumps(STR, ensure_ascii=False))
		.replace("__BOOT__", json.dumps(boot, ensure_ascii=False))
		.replace("__MAP__", json.dumps(MAP, ensure_ascii=False))
		.replace("__LAYOUT__", json.dumps(LAYOUT, ensure_ascii=False))
		.replace("__CLIDS__", json.dumps(cl_ids(TPL[style]))))
	return ('<!doctype html>\n<html lang="ru">\n<head>\n<meta charset="utf-8">\n<title>%s</title>\n<script src="./support.js"></script>\n</head>\n<body>\n<x-dc>\n<helmet>\n%s\n<style>\n%s\n</style>\n</helmet>\n%s\n</x-dc>\n'
		'<script type="text/x-dc" data-dc-script data-props=\'{"$preview":{"width":1497,"height":%d}}\'>\n%s\n</script>\n</body>\n</html>\n') % (title, FONTS, CSS[style], TPL[style], h, logic)


DEF = {"preset": "high", "scale": 100, "shadows": True, "shadowRes": "4096", "aa": "msaa2", "vsync": True, "fov": 90, "fps": 0, "volume": 80, "sens": 2.0, "binds": {}}


def d(**kw):
	x = dict(DEF)
	x.update(kw)
	return x


RANKS = {"body_snatch": 1, "capture_precision": 1, "lifespan": 2, "steady_legs": 1}
STATES = [
	("01_Menu", "Главное меню · фокус «Новая игра», наведение «Настройки», «Загрузить» недоступна — пустой сейв",
		{"screen": "menu", "hasSave": False, "force": {"focus": ["menu_new"], "hover": ["menu_set"]}}),
	("02_Menu_EN", "Главное меню EN · «New game» нажата, сейв есть",
		{"screen": "menu", "lang": "en", "force": {"press": ["menu_new"]}}),
	("03_Pause", "Пауза · «Сохранено» на самой кнопке, наведение на «Продолжить»",
		{"screen": "pause", "saved": True, "force": {"hover": ["pause_resume"]}}),
	("04_Pause_EN", "Пауза EN · фокус на длинной «Quit to main menu»",
		{"screen": "pause", "lang": "en", "force": {"focus": ["pause_menu"]}}),
	("05_Settings_Graphics", "Настройки · Графика: список раскрыт, тени выкл → «Разрешение теней» недоступно, фокус на слайдере, пресет стал «Собственный»",
		{"screen": "settings", "from": "menu", "tab": "graphics", "draft": d(shadows=False, preset="custom", fov=100), "applied": DEF, "dd": "aa", "hintRow": "shadowRes",
			"force": {"focus": ["set_fov"], "hover": ["opt_aa_fxaa"]}}),
	("06_Settings_Keys_EN", "Настройки EN · Управление: ожидание клавиши, длинные строки, «Apply» недоступна — изменений нет",
		{"screen": "settings", "from": "pause", "tab": "controls", "lang": "en", "waiting": "snatch_body", "hintRow": "sens",
			"force": {"hover": ["bind_jump"], "focus": ["tab_controls"]}}),
	("07_Settings_Swap", "Настройки · конфликт: «Назад» занял W, «Вперёд» получил S; «Применить» нажата",
		{"screen": "settings", "from": "menu", "tab": "controls", "draft": d(binds={"move_backward": "KeyW", "move_forward": "KeyS"}), "applied": DEF,
			"swap": ["move_backward", "move_forward"], "hintRow": "sens", "force": {"focus": ["bind_move_backward"], "press": ["set_apply"]}}),
	("08_Summary", "Итоги · «Сознание угасло», фокус на «Возродиться»",
		{"screen": "summary", "force": {"focus": ["revive"]}}),
	("09_Summary_EN", "Итоги EN · «Reviving…» на время генерации, кнопка недоступна",
		{"screen": "summary", "lang": "en", "reviving": True}),
	("10_Skills", "Навыки души · выбран доступный навык; наведение и фокус на узлах",
		{"screen": "skills", "tree": "soul", "sel": "decay_capacity", "ranks": RANKS, "force": {"hover": ["node_spring_step"], "focus": ["node_graceful_exit"]}}),
	("11_Skills_Unlock", "Навыки · отклик открытия: пульс узла, синапс загорается, счётчик вспыхивает",
		{"screen": "skills", "tree": "soul", "sel": "decay_capacity", "points": 2, "ranks": dict(RANKS, decay_capacity=1), "flash": "decay_capacity", "toast": "Ранг 1 открыт"}),
	("12_Skills_EN_NoPoints", "Навыки EN · очков 0: «Not enough points» недоступна",
		{"screen": "skills", "tree": "soul", "lang": "en", "points": 0, "sel": "overflow_control", "ranks": RANKS}),
	("13_Architect", "Улучшения Архитектора · эссенция в тысячах, ветви мира, фокус на «Открыть ранг 3»",
		{"screen": "skills", "tree": "arch", "asel": "map_level", "force": {"focus": ["unlock"]}}),
	("14_Map", "Карта · уровень 2 (весь текущий слой), наведение на комнату",
		{"screen": "map", "mapLevel": 2, "mapLayer": 2, "hover": HOVER_ROOM}),
	("15_Map_EN_L4", "Карта EN · уровень 4: подписи уникальных комнат, только что пройден портал",
		{"screen": "map", "lang": "en", "mapLevel": 4, "mapLayer": 2, "pinned": PIN_PORTAL, "force": {"focus": ["layer_3"]}}),
	("16_Map_NoLink", "Карта · уровень 0: нет связи с Архитектором",
		{"screen": "map", "mapLevel": 0}),
]

files = {}
boards = {}
order = []
notes = {}
files["Main.dc.html"] = board("A", "Прототип A — Отголосок", {}, 800)
files["Proto_B.dc.html"] = board("B", "Прототип B — Терминал X-16", {}, 800)
boards["Main.dc.html"] = {"x": 0, "y": 0, "w": 1497, "h": 800, "page": "proto", "title": "Прототип A · «Отголосок» — нажмите Play", "is_interactive": True}
boards["Proto_B.dc.html"] = {"x": 1577, "y": 0, "w": 1497, "h": 800, "page": "proto", "title": "Прототип B · «Терминал X-16» — нажмите Play", "is_interactive": True}
order += ["Main.dc.html", "Proto_B.dc.html"]
notes["tProto"] = {"x": 0, "y": -320, "text": "Два прототипа: душа и машина", "kind": "title1", "maxW": 3074, "page": "proto"}
for style, page in (("A", "a"), ("B", "b")):
	for i, (name, title, boot) in enumerate(STATES):
		fn = "%s_%s.dc.html" % (style, name)
		b = dict(boot)
		b["bare"] = True
		files[fn] = board(style, title, b, 720)
		boards[fn] = {"x": (i % 3) * 1577, "y": (i // 3) * 840, "w": 1497, "h": 720, "page": page, "title": title}
		order.append(fn)
notes["tA"] = {"x": 0, "y": -320, "text": "A «Отголосок» — меню говорит душа", "kind": "title1", "maxW": 4651, "page": "a"}
notes["tB"] = {"x": 0, "y": -320, "text": "B «Терминал X-16» — меню говорит комплекс", "kind": "title1", "maxW": 4651, "page": "b"}

files["Spec.dc.html"] = spec.build(STR, S, rd("a.css"), FONTS, scenes.LOGO_D)
boards["Spec.dc.html"] = {"x": 0, "y": 0, "w": 1280, "h": 14000, "page": "spec", "title": "Спека для Godot — язык A «Отголосок»", "expand": "fill", "is_interactive": True}
order.append("Spec.dc.html")

canvas = {
	"v": 3,
	"attachments": {},
	# индекс уже заведён редактором холста — его отметку создания сохраняем как есть
	"createdOnFiles": {"at": "2026-10-01T14:18:45.310Z", "v": 1},
	"title": "Меню Astral Genesis",
	"launch": {"view": "canvas", "page": "proto"},
	"pages": [{"id": "proto", "name": "Прототипы"}, {"id": "a", "name": "Макеты A · Отголосок"}, {"id": "b", "name": "Макеты B · Терминал"}, {"id": "spec", "name": "Спека (A)"}],
	"boards": boards,
	"order": order,
	"notes": notes,
	"designSystems": [],
}
# Та же спека файлом .md — карточкой в vault рядом с «HUD — спека».
SPEC_MD = os.path.join(HERE, "..", "..", "..", "docs", "astral-genesis", "Задачи", "Карточки", "Меню — спека.md")
with open(SPEC_MD, "w", encoding="utf-8") as f:
	f.write(spec.build_md(S))
for fn, txt in files.items():
	with open(os.path.join(PROJ, fn), "w", encoding="utf-8") as f:
		f.write(txt)
with open(os.path.join(PROJ, "canvas.json"), "w", encoding="utf-8") as f:
	json.dump(canvas, f, ensure_ascii=False, indent=1)
print(len(files), "files;", sum(len(t) for t in files.values()) // 1024, "KB")
print("cl ids A:", cl_ids(TPL["A"]))
print("cl ids B:", cl_ids(TPL["B"]))
