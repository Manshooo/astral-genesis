# Корень игровой сцены: кадровый цикл ECS, вход в забег под загрузочным экраном. Вики: [[GECS и правила движка]], [[Цикл забега]].
extends Node

@onready var world: World = $World

const HUD_SCENE := preload("res://src/ui/hud/hud.tscn")

## Отладочный оверлей (dev/debug_overlay.gd). load() по пути, не preload: dev/* исключён из экспорта — отсутствие файла значит «нет читов», а не «мир не грузится».
const DEBUG_OVERLAY_PATH := "res://dev/debug_overlay.tscn"

func _ready() -> void:
	ECS.world = world
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_child(HUD_SCENE.instantiate())
	add_child(ShadowBudget.new())
	_add_debug_overlay()
	# Комплекс строится в фоне, кадры идут под шторкой (UI_LoadingScreen).
	var loading := UI_LoadingScreen.create()
	add_child(loading)
	if not await RunManager.enter_complex_async():
		return  # вход отменён — сцену уже сменили
	# Пауза и карты — когда мир есть: иначе Esc открыл бы паузу поверх шторки.
	UIManager.enabled = true
	await loading.dismiss()


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
