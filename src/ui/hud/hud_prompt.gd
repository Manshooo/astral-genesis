# res://src/ui/hud/hud_prompt.gd
## Подсказка взаимодействия: пока крестик наведён на интерактивный объект,
## S_InteractionDetector держит на нём C_Highlighted — показываем его prompt_text
## с клавишей (напр. «[F] Древо навыков»).
##
## Клавиша НЕ пишется в подсказку руками: она резолвится из InputMap по
## C_Interactable.action_name, поэтому верна для любого действия (у тела для
## захвата это будет «ЛКМ», а не «F») и сама обновляется после переназначения —
## подписаны на SettingsManager.settings_changed.
##
## Реагируем на добавление/снятие C_Highlighted через сигналы мира — тем же
## паттерном, что и crosshair.gd. C_Highlighted навешивается ТОЛЬКО на интерактивы
## (тела для захвата — на слое enemies, без C_Interactable, сюда не попадают).
##
## Подаётся мыслью, без плашки (UI_ThoughtLine): проявляется и гаснет, а не
## переключается. Текст держится до конца угасания — иначе, отведя взгляд,
## игрок видел бы, как гаснет пустое место.
class_name UI_HudPrompt
extends Control

const APPEAR_TAU := 0.1
const FADE_TAU := 0.15
## Подъём при появлении, px: строка «всплывает» к своему месту.
const RISE := 4.0
## Размытие при появлении, px: строка «фокусируется», как мысль, а не
## включается табличкой.
const BLUR := 3.0

@onready var _line: UI_ThoughtLine = $Blur/Line
@onready var _blur: CanvasGroup = $Blur

## Интерактив, на который сейчас смотрим (null — подсказка гаснет). Держим ссылку,
## чтобы пересобрать текст при смене раскладки, не дожидаясь нового наведения.
var _shown: C_Interactable = null
var _alpha := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur.material = UI_HudMood.blur_material()
	modulate.a = 0.0
	visible = false
	if ECS.world:
		_connect_world_signals(ECS.world)
	ECS.world_changed.connect(_on_world_changed)
	SettingsManager.settings_changed.connect(_on_settings_changed)


func _process(delta: float) -> void:
	var target := 1.0 if _shown != null else 0.0
	_alpha = UI_HudMood.approach(_alpha, target, APPEAR_TAU if target > _alpha else FADE_TAU, delta)
	if target == 0.0 and _alpha < 0.01:
		_alpha = 0.0
	modulate.a = _alpha
	_line.position.y = (1.0 - _alpha) * RISE
	(_blur.material as ShaderMaterial).set_shader_parameter(&"blur_px", blur_px())
	visible = _alpha > 0.0


## Текущее размытие, px — для проверок.
func blur_px() -> float:
	return (1.0 - _alpha) * BLUR


## Видна ли подсказка по смыслу (а не по прозрачности посреди угасания).
func is_shown() -> bool:
	return _shown != null


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
	# Вселение/развоплощение меняет доступность механизмов — если подсказка на
	# экране, она обязана переписаться, а не ждать нового наведения.
	if component is C_Embodied:
		if _shown != null:
			_render()
		return
	if not (component is C_Highlighted):
		return
	var inter := entity.get_component(C_Interactable) as C_Interactable
	if inter == null or inter.prompt_text == "":
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


## Раскладку переназначили — если подсказка на экране, она обязана показать новую
## клавишу немедленно, а не после того как игрок отведёт и наведёт крестик снова.
func _on_settings_changed(_settings: RS_Settings) -> void:
	if _shown != null:
		_render()


func _render() -> void:
	# tr() вручную: подсказка вклеивается в строку с клавишей, и перевод подписи
	# склеенное уже не узнает. Старые подсказки — готовые строки, не ключи, и
	# проходят через tr() как есть.
	var prompt := tr(_shown.prompt_text)
	# Механизм, до которого бестелесному не дотянуться: объясняем ПРИЧИНУ и не
	# предлагаем клавишу — нажатие всё равно не пройдёт (см. S_InteractInput).
	if _shown.requires_body and not E_Player.is_embodied():
		_line.set_line("", tr("HUD_PROMPT_NEEDS_BODY") % prompt)
		return

	var key := SettingsManager.action_display_name(_shown.action_name) if _shown.show_key_hint else ""
	_line.set_line(key, prompt)
