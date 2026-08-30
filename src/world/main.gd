# res://src/world/main.gd
extends Node

@onready var world: World = $World

const HUD_SCENE := preload("res://src/ui/hud/hud.tscn")

## Отладочный оверлей — читы и телепорты для проверки механик (dev/debug_overlay.gd).
## Путём, а не preload: `dev/*` исключён из экспорта, и в собранной игре этого
## файла нет вовсе. preload резолвится на компиляции и уронил бы релиз, поэтому
## тут load() по существующему пути — отсутствие оверлея обязано означать «нет
## читов», а не «мир не грузится».
const DEBUG_OVERLAY_PATH := "res://dev/debug_overlay.tscn"

func _ready() -> void:
	ECS.world = world
	UIManager.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_child(HUD_SCENE.instantiate())
	_add_debug_overlay()
	RunManager.enter_complex()


func _add_debug_overlay() -> void:
	if not OS.has_feature("debug"):
		return
	if not ResourceLoader.exists(DEBUG_OVERLAY_PATH):
		return
	add_child(load(DEBUG_OVERLAY_PATH).instantiate())

func _process(delta: float) -> void:
	ECS.process(delta, "input")
	ECS.process(delta, "gameplay")

func _physics_process(delta: float) -> void:
	ECS.process(delta, "physics")
