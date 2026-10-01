extends "res://dev/check_harness.gd"
## HUD «Отголосок» без пикселей: всё, что в нём ломается молча.
##   - кривые эффектов экрана против таблиц спеки («HUD — спека» §8): опечатка в
##     пороге не роняет ничего — экран просто давит не тогда;
##   - когда видна дуга и какой карман она показывает (§7);
##   - смятение T от числа поглощённых тел (§9);
##   - удар и волна вселения — импульсы, которые обязаны погаснуть;
##   - таймлайн сообщения и его согласие с таймером C_ScreenMessage;
##   - строка подсказки: клавиша отдельно от действия;
##   - каждый ключ перевода, который код называет литералом, есть в ui.csv на
##     обоих языках (опечатка в ключе показала бы игроку сам ключ);
##   - в сцене HUD не осталось подложек и полос.
## Как это ВЫГЛЯДИТ — только живой прогон.
## Запуск: godot --headless dev/hud_check.tscn

## Допуск сверки с таблицами: в спеке числа округлены до сотых.
const EPS := 0.011
const SOURCE_DIRS := ["res://src"]
const KEY_PATTERN := "\"((?:HUD|KEY|ITEM)_[A-Z0-9_]+)\""


func _ready() -> void:
	_check_soul_curve()
	_check_body_curve()
	_check_blood_curve()
	_check_impulses()
	_check_arc()
	_check_turmoil()
	await _check_message()
	await _check_thought_line()
	_check_key_names()
	_check_translation_keys()
	_check_scene()
	_finish()


func _vitals(soul: float, body_pocket: bool = false, body: float = 1.0, health: float = 1.0) -> UI_HudMood.Vitals:
	var v := UI_HudMood.Vitals.new()
	v.soul = minf(soul, 1.0)
	v.overflow = maxf(soul - 1.0, 0.0)
	v.body_pocket = body_pocket
	v.body = body
	v.has_health = body_pocket
	v.health = health if body_pocket else 1.0
	v.maximum = 60.0
	return v


## t = 0: сердцебиение там в нуле, и таблицы спеки (без пульса) сравнимы как есть.
## Дельта в секунду — тон души/тела успевает переключиться целиком.
func _fx_at(vitals: UI_HudMood.Vitals) -> Dictionary:
	var fx := UI_HudScreenFx.new()
	fx.update_params(vitals, 0.0, 1.0)
	var params := fx.params
	fx.free()
	return params


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= EPS


# --- 1. Распад души (§8, таблица «от доли запаса души») -----------------------
func _check_soul_curve() -> void:
	# доля: [виньетка, обесцвечивание, искажение в долях от 4 px]
	var table := {
		1.0: [0.12, 0.15, 0.00], 0.5: [0.12, 0.15, 0.00], 0.35: [0.12, 0.15, 0.00],
		0.25: [0.22, 0.27, 0.03], 0.15: [0.33, 0.39, 0.12], 0.10: [0.38, 0.46, 0.19],
		0.05: [0.58, 0.69, 0.58], 0.0: [0.72, 0.85, 1.00],
	}
	for f: float in table:
		var row: Array = table[f]
		var p := _fx_at(_vitals(f))
		_check(
			"распад души на %d %% — как в таблице спеки" % roundi(f * 100.0),
			_near(p.vignette, row[0]) and _near(p.desaturation, row[1]) and _near(p.distortion_px / 4.0, row[2]),
			"виньетка %.3f, обесцвечивание %.3f, искажение %.3f" % [p.vignette, p.desaturation, p.distortion_px / 4.0]
		)
	var over := _fx_at(_vitals(1.4))
	_check("излишек давит не сильнее полного запаса", _near(over.vignette, 0.12), str(over.vignette))
	_check("душа уходит в серое, а не в сепию", over.desat_tint.is_equal_approx(Color.WHITE), str(over.desat_tint))


# --- 2. Распад тела: та же кривая, без базы, в сепию ---------------------------
func _check_body_curve() -> void:
	var table := {
		1.0: [0.0, 0.0], 0.35: [0.0, 0.0], 0.25: [0.10, 0.12], 0.15: [0.21, 0.24],
		0.10: [0.26, 0.31], 0.05: [0.46, 0.54], 0.0: [0.60, 0.70],
	}
	for b: float in table:
		var row: Array = table[b]
		# Душа почти пуста — её распад не должен протечь в тон тела.
		var p := _fx_at(_vitals(0.05, true, b))
		_check(
			"распад тела на %d %% — как в таблице спеки" % roundi(b * 100.0),
			_near(p.vignette, row[0]) and _near(p.desaturation, row[1]),
			"виньетка %.3f, обесцвечивание %.3f" % [p.vignette, p.desaturation]
		)
	var p := _fx_at(_vitals(0.05, true, 1.0))
	_check("у полного тела экран чистый (у распада тела нет базы)", p.vignette < 0.001 and p.desaturation < 0.001, str(p))
	_check("тело уходит в сепию", p.desat_tint.is_equal_approx(UI_HudMood.BODY_SEPIA), str(p.desat_tint))
	_check("виньетка тела тёплая", p.vignette_color.is_equal_approx(UI_HudMood.BODY_TINT), str(p.vignette_color))


# --- 3. Здоровье тела — только кровь -------------------------------------------
func _check_blood_curve() -> void:
	var table := {1.0: 0.0, 0.5: 0.0, 0.35: 0.14, 0.25: 0.42, 0.15: 0.66, 0.10: 0.70, 0.0: 0.70}
	for h: float in table:
		var p := _fx_at(_vitals(1.0, true, 1.0, h))
		_check("кровь при HP %d %% — как в таблице спеки" % roundi(h * 100.0), _near(p.blood, table[h]), "%.3f" % p.blood)
	var soul := _fx_at(_vitals(1.0))
	_check("у души крови нет — прочности у неё нет", soul.blood == 0.0, str(soul.blood))


# --- 4. Удар и волна вселения — импульсы, а не состояния -----------------------
func _check_impulses() -> void:
	var fx := UI_HudScreenFx.new()
	var body := _vitals(1.0, true)
	fx.update_params(body, 10.0, 1.0)
	fx.hit(0.3, 10.0)
	fx.update_params(body, 10.0, 0.0)
	_check("удар сразу темнит края", _near(fx.params.edge_dark, UI_HudScreenFx.HIT_DARK), str(fx.params.edge_dark))
	var shake := UI_HudScreenFx.SHAKE_PX * Vector2(UI_HudMood.noise(370.0, 1.0), UI_HudMood.noise(410.0, 2.3))
	_check("удар трясёт экран на SHAKE_PX", (fx.params.shake_px as Vector2).is_equal_approx(shake), str(fx.params.shake_px))
	_check("тяжёлый удар (30 % HP) — полная красная вспышка", _near(fx.params.blood, UI_HudScreenFx.HIT_RED), str(fx.params.blood))
	var first_layout: Vector3 = fx.params.blot_to
	_check("удар перекладывает пятна крови", not first_layout.is_zero_approx(), str(first_layout))
	_check("новая раскладка проступает не рывком", fx.params.blot_mix < 0.01, str(fx.params.blot_mix))
	fx.update_params(body, 10.0 + UI_HudScreenFx.BLOT_SECONDS, 0.0)
	_check("за BLOT_SECONDS пятна перетекли целиком", is_equal_approx(fx.params.blot_mix, 1.0), str(fx.params.blot_mix))
	fx.update_params(body, 13.0, 0.0)
	_check("через 3 с от удара не осталось видимого следа", fx.params.edge_dark < 0.01 and fx.params.blood < 0.01, str(fx.params))

	fx.hit(0.02, 14.0)
	fx.update_params(body, 14.0, 0.0)
	var scratch: float = fx.params.blood
	_check(
		"царапина краснит слабо, но заметно",
		_near(scratch, UI_HudScreenFx.HIT_RED * UI_HudScreenFx.HIT_MIN_SHARE),
		str(scratch)
	)
	_check("каждый удар — своя раскладка пятен", not (fx.params.blot_to as Vector3).is_equal_approx(first_layout), "")
	_check("перетекание начинается с прежней раскладки", (fx.params.blot_from as Vector3).is_equal_approx(first_layout), "")
	fx.hit(0.125, 18.0)
	fx.update_params(body, 18.0, 0.0)
	_check(
		"вспышка растёт с долей урона",
		_near(fx.params.blood, UI_HudScreenFx.HIT_RED * 0.5) and fx.params.blood > scratch,
		str(fx.params.blood)
	)

	var ghost := _vitals(1.0)
	fx.update_params(ghost, 20.0, 0.0)
	_check("выход из тела запускает волну", _near(fx.params.shine, UI_HudScreenFx.SHINE), str(fx.params.shine))
	_check("волна выхода — цветом души", (fx.params.shine_color as Color).is_equal_approx(UI_HudMood.SOUL), "")
	fx.update_params(ghost, 22.0, 0.0)
	_check("волна гаснет", fx.params.shine < 0.001, str(fx.params.shine))
	fx.update_params(body, 30.0, 0.0)
	_check("вселение — волна цветом тела", (fx.params.shine_color as Color).is_equal_approx(UI_HudMood.BODY), "")
	fx.free()
	_check("без игрока экран чистый", _fx_none().vignette == 0.0, "")


func _fx_none() -> Dictionary:
	var fx := UI_HudScreenFx.new()
	fx.update_params(null, 0.0, 1.0)
	var params := fx.params
	fx.free()
	return params


# --- 5. Дуга: когда видна и что показывает (§7) --------------------------------
func _check_arc() -> void:
	var arc := UI_DecayArc.new()
	var t := 100.0
	arc.update_state(_vitals(0.9), t, 0.016)
	_check("первое появление игрока заметно — дуга загорается", arc.target_alpha > 0.0, str(arc.target_alpha))
	t += UI_DecayArc.HOLD_SECONDS + 0.1
	arc.update_state(_vitals(0.89), t, 0.016)
	_check("ровное убывание дугу гасит", arc.target_alpha == 0.0, str(arc.target_alpha))
	t += UI_DecayArc.NOTABLE_WINDOW
	arc.update_state(_vitals(0.80), t, 0.016)
	_check("скачок на 0.05+ за полсекунды — заметное изменение", is_equal_approx(arc.target_alpha, 0.9), str(arc.target_alpha))
	arc.update_state(_vitals(0.30), t + 5.0, 0.016)
	_check("ниже 35 % дуга видна спокойно", is_equal_approx(arc.target_alpha, 0.75), str(arc.target_alpha))
	arc.update_state(_vitals(0.10), t + 10.0, 0.016)
	_check("ниже 15 % — во всю силу", is_equal_approx(arc.target_alpha, 1.0), str(arc.target_alpha))
	arc.update_state(_vitals(1.3), t + 20.0, 0.016)
	_check("излишек держит дугу видимой", is_equal_approx(arc.target_alpha, 0.9), str(arc.target_alpha))

	# Во плоти показывается карман тела, даже когда душа на исходе.
	var embodied := _vitals(0.05, true, 0.9)
	_check("во плоти дуга — запас тела, а не души", is_equal_approx(embodied.active(), 0.9), str(embodied.active()))
	arc.update_state(embodied, t + 40.0, 0.016)
	_check("вселение — заметное изменение", arc.target_alpha > 0.0, str(arc.target_alpha))
	arc.update_state(embodied, t + 40.0 + UI_DecayArc.HOLD_SECONDS + 0.1, 0.016)
	_check("на полном теле при пустой душе дуга гаснет", arc.target_alpha == 0.0, str(arc.target_alpha))
	arc.update_state(null, t + 60.0, 0.016)
	_check("без игрока дуги нет", arc.target_alpha == 0.0, "")
	arc.free()


# --- 6. Смятение T тает с числом поглощённых (§9) ------------------------------
func _check_turmoil() -> void:
	var saved: RS_RunStats = RunStats.current
	var stats := RS_RunStats.new()
	RunStats.current = stats
	_check("первое тело — смятение в полную силу", is_equal_approx(UI_HudMood.turmoil(), 1.0), str(UI_HudMood.turmoil()))
	stats.put(RS_RunStats.BODIES, 6.0)
	_check("к шестому телу ≈ 0.53", absf(UI_HudMood.turmoil() - 0.526) < 0.01, str(UI_HudMood.turmoil()))
	stats.put(RS_RunStats.BODIES, 100.0)
	_check("смятение не уходит ниже 0.25", UI_HudMood.turmoil() >= 0.25, str(UI_HudMood.turmoil()))
	RunStats.current = saved


# --- 7. Сообщение: проявилось, постояло, растворилось --------------------------
func _check_message() -> void:
	_check(
		"компонент сообщения живёт ровно столько, сколько строка на экране",
		is_equal_approx(C_ScreenMessage.new().remaining, UI_HudMessage.TOTAL),
		"%.2f против %.2f" % [C_ScreenMessage.new().remaining, UI_HudMessage.TOTAL]
	)
	var hud := (load("res://src/ui/hud/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	var message := hud.get_node("Hud/Message") as UI_HudMessage
	message.show_line("HUD_MSG_SEALED")
	message.call("_apply", 1.0)
	_check("сообщение — переведённая строка", message.shown_text() == tr("HUD_MSG_SEALED"), message.shown_text())
	_check("посередине показа строка в полную силу", is_equal_approx(message.modulate.a, 1.0), str(message.modulate.a))
	_check("посередине показа строка резкая", message.blur_px() < 0.01, str(message.blur_px()))
	var label := message.get_node("Blur/Text") as Label
	_check("длинная строка переносится, а не уходит за 720 px", label.size.x <= UI_HudMessage.MAX_WIDTH, str(label.size))
	message.call("_apply", UI_HudMessage.APPEAR + UI_HudMessage.HOLD + UI_HudMessage.FADE * 0.5)
	_check("в растворении строка полупрозрачна", message.modulate.a > 0.3 and message.modulate.a < 0.7, str(message.modulate.a))
	_check("растворяясь, строка расплывается", message.blur_px() > 2.0, str(message.blur_px()))
	message.call("_apply", UI_HudMessage.TOTAL + 0.01)
	_check("после растворения строки нет", not message.visible, "")
	hud.queue_free()
	await get_tree().process_frame


# --- 8. Строка подсказки: клавиша отдельно от действия -------------------------
func _check_thought_line() -> void:
	var line := UI_ThoughtLine.new()
	add_child(line)
	line.set_line("F", tr("HUD_PROMPT_PASS"))
	_check("подсказка — «[клавиша] действие»", line.plain_text() == "[F] %s" % tr("HUD_PROMPT_PASS"), line.plain_text())
	line.set_line("", tr("HUD_PROMPT_SEALED"))
	_check("без клавиши скобок нет", line.plain_text() == tr("HUD_PROMPT_SEALED"), line.plain_text())
	await get_tree().process_frame
	var shadow := line.get_node("ThoughtShadow") as Control
	var row := line.get_node("Row") as Control
	_check("тень мысли шире строки, а не фиксированной коробкой", shadow.size.x > row.size.x and row.size.x > 0.0, "%s / %s" % [shadow.size, row.size])
	_check("строка центрирована по своей точке", is_equal_approx(row.position.x, -row.size.x / 2.0), str(row.position))
	line.queue_free()


# --- 9. Имена клавиш переводятся --------------------------------------------
func _check_key_names() -> void:
	_check("ЛКМ — ключом перевода", SettingsManager.code_display_name("mouse:1") == tr("KEY_MOUSE_LEFT"), SettingsManager.code_display_name("mouse:1"))
	_check("пробел — словом языка игры", SettingsManager.code_display_name("key:%d" % KEY_SPACE) == tr("KEY_SPACE"), SettingsManager.code_display_name("key:%d" % KEY_SPACE))
	_check("редкая кнопка мыши — с номером", SettingsManager.code_display_name("mouse:12") == tr("KEY_MOUSE_N") % 12, SettingsManager.code_display_name("mouse:12"))


# --- 10. Каждый ключ из кода есть на обоих языках --------------------------------
func _check_translation_keys() -> void:
	var regex := RegEx.create_from_string(KEY_PATTERN)
	var keys := {}
	for dir: String in SOURCE_DIRS:
		for path in _source_files(dir):
			for found in regex.search_all(FileAccess.get_file_as_string(path)):
				keys[found.get_string(1)] = path
	_check("ключи HUD в коде найдены", keys.size() >= 20, str(keys.size()))
	var locale := TranslationServer.get_locale()
	for language: String in ["ru", "en"]:
		TranslationServer.set_locale(language)
		var missing := PackedStringArray()
		for key: String in keys:
			if tr(key) == key:
				missing.append("%s (%s)" % [key, keys[key].get_file()])
		_check("все ключи HUD переведены на «%s»" % language, missing.is_empty(), ", ".join(missing))
	TranslationServer.set_locale(locale)


func _source_files(dir: String) -> PackedStringArray:
	var files := PackedStringArray()
	for sub in DirAccess.get_directories_at(dir):
		files.append_array(_source_files(dir.path_join(sub)))
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in ["gd", "tscn", "tres"]:
			files.append(dir.path_join(file))
	return files


# --- 11. Язык «Отголосок»: без подложек и полос -------------------------------
func _check_scene() -> void:
	var hud := (load("res://src/ui/hud/hud.tscn") as PackedScene).instantiate()
	var plates := PackedStringArray()
	for node in hud.find_children("*", "", true, false):
		if node is PanelContainer or node is ProgressBar:
			plates.append(str(hud.get_path_to(node)))
	_check("в HUD нет ни одной подложки и полосы", plates.is_empty(), ", ".join(plates))
	var fx := hud.get_node("ScreenFx") as CanvasLayer
	_check(
		"эффекты экрана — под обводкой интерактива и под HUD",
		fx.layer < S_OutlineMask.OVERLAY_CANVAS_LAYER and fx.layer < (hud as CanvasLayer).layer,
		"%d / %d" % [fx.layer, S_OutlineMask.OVERLAY_CANVAS_LAYER]
	)
	hud.free()

	var theme: Theme = load(ProjectSettings.get_setting("gui/theme/custom"))
	for variation: StringName in [&"HudThought", &"HudKey", &"HudKeyBracket", &"HudMessage", &"HudControls"]:
		var font := theme.get_font(&"font", variation) as FontVariation
		_check(
			"вариация %s — Golos Text из общей темы" % variation,
			theme.get_type_variation_base(variation) == &"Label" and font != null
			and font.base_font.resource_path.contains("GolosText"),
			str(font)
		)
