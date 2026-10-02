# res://src/ui/main_menu/main_menu.gd
## Главное меню языка «Отголосок» (§9 «Меню — спека»): название с эхом и пункты-
## мысли слева, без панели; читаемость держит тень мысли за колонкой, а справа
## остаётся живая 3D-сцена L_menu_map, в которую меню вложено.
extends UI_MenuScreen

const WORLD_SCENE := "res://src/world/world.tscn"

@onready var load_button: Button = %Load
@onready var load_aside: Label = %LoadAside
@onready var version_label: Label = %Version


func _ready() -> void:
	super._ready()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UIManager.enabled = false
	# Продолжать нечего, пока на диске нет сейва: WorldSave в этом случае держит
	# свежесгенерированную заготовку, а не сохранённое прохождение. Недоступный
	# пункт объясняет себя словами рядом (§1), а не только тусклым цветом.
	load_button.disabled = not WorldSave.has_save_file
	load_aside.visible = load_button.disabled
	# Номер — чтобы по скриншоту бага было видно, из какого коммита сборка:
	# не-релизной CI вписывает сюда 0.7.0-dev.33+fc91d3c
	# (.github/scripts/build_version.sh), релизу — просто 0.7.0.
	version_label.text = tr("MENU_BUILD") % ProjectSettings.get_setting("application/config/version")


func _on_new_game_pressed() -> void:
	WorldSave.new_game()  # катим новый world_seed до загрузки мира
	# Дерево навыков персистит своим файлом и переживает смерть — это метапрогресс.
	# Но «новая игра» — не смерть, а чистый лист, и оставленные с прошлого
	# прохождения ранги делают первый же забег не тем, каким он задуман.
	# Зовём рядом с WorldSave.new_game(), а не изнутри него: каждый автолоад
	# держит свой файл сам, и сейву мира незачем знать про навыки. Улучшения
	# Архитектора — тот же метапрогресс, и чистый лист снимает их тоже.
	SkillManager.reset()
	ArchitectManager.reset()
	get_tree().change_scene_to_file(WORLD_SCENE)


## Продолжить сохранённое прохождение. Ничего не катим и не грузим руками:
## WorldSave уже поднял сейв в _ready, а RunManager возьмёт из него и сид
## (world_seed + death_count), и узел, на котором игрок остановился.
func _on_load_pressed() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_settings_pressed() -> void:
	var settings_menu = load("res://src/ui/settings_menu/settings_menu.tscn").instantiate()
	UIManager.push_screen(settings_menu, false, self)


func _on_exit_pressed() -> void:
	get_tree().quit()
