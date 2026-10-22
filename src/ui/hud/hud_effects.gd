# res://src/ui/hud/hud_effects.gd
## Эффекты слева ([[HUD — спека]] §7в), сгруппированные по источнику: «Бесплотность» души вне тела (C_SoulTrait) и временные эффекты способностей — у тела подпись
## его именем и янтарём, у поглощённой — именем тела-источника и сиренью. Своего дизайна у эффектов нет, это временное оформление в языке мыслей.
## Группы и строки — инстансы effect_group.tscn и effect_row.tscn: их число известно только в рантайме.
class_name UI_HudEffects
extends Control

const GROUP_SCENE := preload("res://src/ui/hud/effect_group.tscn")
const ROW_SCENE := preload("res://src/ui/hud/effect_row.tscn")
const IDLE_ALPHA := 0.55
const BRIGHT_FOR := 2.5
const APPEAR_TAU := 0.12
const FADE_TAU := 0.4
const SOUL_CAPTION_ALPHA := 0.8
const BODY_CAPTION_ALPHA := 0.85


## Один эффект в кадре; группы собираются по caption_key.
class Effect:
	extends RefCounted
	var caption_key: StringName
	var tint: Color
	var icon: Texture2D
	var name_key: StringName
	var left := 0.0
	var duration := 0.0


@onready var _groups: VBoxContainer = %Groups

var target_alpha := 0.0
var _bright_until := -INF
var _signature := ""
var _rows: Array[UI_EffectRow] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0


func _process(delta: float) -> void:
	var effects := collect(E_Player.find())
	var signature := _signature_of(effects)
	if signature != _signature:
		_signature = signature
		_rebuild(effects)
		_bright_until = UI_HudMood.now() + BRIGHT_FOR
	for i in effects.size():
		var e := effects[i]
		_rows[i].show_effect(e.icon, e.tint, e.name_key, e.left, e.duration)
	if effects.is_empty():
		target_alpha = 0.0
	else:
		target_alpha = 1.0 if UI_HudMood.now() < _bright_until else IDLE_ALPHA
	var tau := APPEAR_TAU if target_alpha > modulate.a else FADE_TAU
	modulate.a = UI_HudMood.approach(modulate.a, target_alpha, tau, delta)


## Эффекты игрока сейчас, уже в порядке групп: сначала душа, потом способности (два прохода — sort_custom неустойчив).
static func collect(player: Entity) -> Array[Effect]:
	var effects: Array[Effect] = []
	if player == null:
		return effects
	for component in player.components.values():
		var trait_ := component as C_SoulTrait
		if trait_ and trait_.effect_key != &"":
			var e := Effect.new()
			e.caption_key = &"HUD_EFFECT_INCORPOREAL"
			e.tint = UI_HudMood.SOUL
			e.icon = trait_.effect_icon
			e.name_key = trait_.effect_key
			effects.append(e)
	var body_key := _body_name_key(player)
	# Подпись группы → её эффекты: строки одного источника обязаны стоять подряд.
	var by_source := {}
	for component in player.components.values():
		var ability := component as C_Ability
		if ability == null or ability.effect_left() <= 0.0:
			continue
		var e := Effect.new()
		e.caption_key = ability.source_key if ability.absorbed else body_key
		e.tint = UI_HudMood.SOUL if ability.absorbed else UI_HudMood.BODY
		e.icon = ability.icon
		e.name_key = ability.name_key
		e.left = ability.effect_left()
		e.duration = ability.effect_duration()
		if not by_source.has(e.caption_key):
			by_source[e.caption_key] = []
		by_source[e.caption_key].append(e)
	for group: Array in by_source.values():
		for e: Effect in group:
			effects.append(e)
	return effects


## Видимые строки по группам: «ПОДПИСЬ: строка, строка» — для проверок.
func visible_groups() -> PackedStringArray:
	var lines := PackedStringArray()
	for group in _groups.get_children():
		var rows := PackedStringArray()
		for row: UI_EffectRow in group.get_node("%Rows").get_children():
			rows.append(row.plain_text())
		lines.append("%s: %s" % [(group.get_node("%Caption") as Label).text, ", ".join(rows)])
	return lines


static func _body_name_key(player: Entity) -> StringName:
	var embodied := player.get_component(C_Embodied) as C_Embodied
	return E_Body.name_key_of_scene(embodied.body_scene_path) if embodied else &""


static func _signature_of(effects: Array[Effect]) -> String:
	var parts := PackedStringArray()
	for e in effects:
		parts.append("%s/%s/%s" % [e.caption_key, e.name_key, e.tint.to_html()])
	return "|".join(parts)


func _rebuild(effects: Array[Effect]) -> void:
	for group in _groups.get_children():
		group.queue_free()
	_rows.clear()
	var rows_parent: Container = null
	var caption := &"-"
	for e in effects:
		if e.caption_key != caption:
			caption = e.caption_key
			var group: VBoxContainer = GROUP_SCENE.instantiate()
			_groups.add_child(group)
			var label := group.get_node("%Caption") as Label
			label.text = tr(caption)
			var alpha := SOUL_CAPTION_ALPHA if e.tint == UI_HudMood.SOUL else BODY_CAPTION_ALPHA
			label.add_theme_color_override(&"font_color", Color(e.tint, alpha))
			rows_parent = group.get_node("%Rows")
		var row: UI_EffectRow = ROW_SCENE.instantiate()
		rows_parent.add_child(row)
		_rows.append(row)
