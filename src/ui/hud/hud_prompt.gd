# res://src/ui/hud/hud_prompt.gd
## Подсказка взаимодействия: пока крестик на интерактиве (C_Highlighted от S_InteractionDetector) — prompt_text с клавишей. Клавиша резолвится из InputMap по C_Interactable.action_name
## и обновляется после переназначения. Реагируем на сигналы мира, как crosshair.gd; подаётся мыслью без плашки (UI_ThoughtLine), текст держится до конца угасания. Вики: [[Взаимодействие]].
class_name UI_HudPrompt
extends Control

const APPEAR_TAU := 0.1
const FADE_TAU := 0.15
## Подъём при появлении, px.
const RISE := 4.0
## Размытие при появлении, px: «фокусируется», а не включается табличкой.
const BLUR := 3.0

@onready var _line: UI_ThoughtLine = $Blur/Line
@onready var _blur: CanvasGroup = $Blur

## Интерактив под взглядом (null — гаснет); ссылка нужна, чтобы пересобрать текст при смене раскладки.
var _shown: C_Interactable = null
var _alpha := 0.0


func _ready() -> void:
	modulate.a = 0.0
	visible = false
	if ECS.world:
		_connect_world_signals(ECS.world)
	ECS.world_changed.connect(_on_world_changed)
	SettingsManager.settings_changed.connect(_on_settings_changed)


func _process(delta: float) -> void:
	var target := 1.0 if is_shown() else 0.0
	_alpha = UI_HudMood.approach(_alpha, target, APPEAR_TAU if target > _alpha else FADE_TAU, delta)
	if target == 0.0 and _alpha < 0.01:
		_alpha = 0.0
	modulate.a = _alpha
	# Подъём — позицией группы (Node2D): Control округляется до пикселей, подъём шёл бы ступеньками.
	_blur.position.y = (1.0 - _alpha) * RISE
	(_blur.material as ShaderMaterial).set_shader_parameter(&"blur_px", blur_px())
	visible = _alpha > 0.0


## Текущее размытие, px — для проверок.
func blur_px() -> float:
	return (1.0 - _alpha) * BLUR


## Видна ли подсказка по смыслу, а не по прозрачности.
func is_shown() -> bool:
	return _shown != null and (_shown.prompt_text != "" or _needs_body(_shown))


## Механизм недоступен бестелесному: у двери подписи нет, но причину отказа призрак обязан прочитать.
func _needs_body(inter: C_Interactable) -> bool:
	return inter.requires_body and not E_Player.is_embodied()


## Текст строки — для проверок.
func shown_text() -> String:
	return _line.plain_text()


func _on_world_changed(world: World) -> void:
	_shown = null
	_alpha = 0.0
	if world:
		_connect_world_signals(world)


func _connect_world_signals(world: World) -> void:
	if not world.component_added.is_connected(_on_component_added):
		world.component_added.connect(_on_component_added)
	if not world.component_removed.is_connected(_on_component_removed):
		world.component_removed.connect(_on_component_removed)


func _on_component_added(entity: Entity, component: Variant) -> void:
	# Вселение/развоплощение меняет доступность механизмов — подсказка переписывается.
	if component is C_Embodied:
		if _shown != null:
			_render()
		return
	if not (component is C_Highlighted):
		return
	var inter := entity.get_component(C_Interactable) as C_Interactable
	if inter == null or (inter.prompt_text == "" and not inter.requires_body):
		return  # интерактив без подписи — крестик подсветит, но текста нет
	_shown = inter
	_render()


func _on_component_removed(_entity: Entity, component: Variant) -> void:
	if component is C_Embodied:
		if _shown != null:
			_render()
		return
	if component is C_Highlighted:
		_shown = null


## Раскладку переназначили — новая клавиша немедленно.
func _on_settings_changed(_settings: RS_Settings) -> void:
	if _shown != null:
		_render()


func _render() -> void:
	# tr() вручную: подсказка вклеивается в строку с клавишей; старые подсказки — готовые строки, проходят как есть.
	var prompt := tr(_shown.prompt_text) if _shown.prompt_text != "" else ""
	# Объясняем ПРИЧИНУ, клавишу не предлагаем (S_InteractInput).
	if _needs_body(_shown):
		var reason := tr("HUD_PROMPT_NEEDS_BODY") % prompt if prompt != "" else tr("HUD_PROMPT_NEEDS_BODY_BARE")
		_line.set_line("", reason)
		return
	if prompt == "":
		return

	var key := SettingsManager.action_display_name(_shown.action_name) if _shown.show_key_hint else ""
	_line.set_line(key, prompt)
