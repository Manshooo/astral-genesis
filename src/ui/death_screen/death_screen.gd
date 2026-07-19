# res://src/ui/death_screen/death_screen.gd
## Экран смерти: БФЖ распался, запас жизни иссяк в развоплощён. Показывается
## RunManager.die() ПОСЛЕ фиксации смерти в сейве (death_count уже увеличен).
## Отсюда — новый забег (тот же world_seed, но death_count++ → другой комплекс) или
## выход в меню.
extends Control

const WORLD_SCENE := "res://src/world/world.tscn"
const MENU_SCENE := "res://src/levels/menu_map/L_menu_map.tscn"


func _ready() -> void:
	# Мы вне игровой сцены: погасить игровой UI-стек (дерево навыков могло остаться
	# открытым, если распад случился у инкубатора) и вернуть курсор.
	# ПОРЯДОК ВАЖЕН: enabled=false ДО close_all(), иначе close_all() при enabled=true
	# заново ЗАХВАТИТ курсор (см. UIManager.close_all). Видимый курсор — последним.
	UIManager.enabled = false
	UIManager.close_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_retry_pressed() -> void:
	# Новый забег: world_seed/death_count НЕ трогаем — смерть уже записана, и
	# генерация возьмёт свежий run_seed() из (world_seed, death_count).
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
