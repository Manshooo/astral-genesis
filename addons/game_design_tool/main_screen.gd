## res://addons/game_design_tool/main_screen.gd
## Корень вкладки «Геймдизайн»: `TabContainer` с инструментами этой игры.
## Вкладка — самодостаточный `Control`, заголовок берётся из его `name`.
## См. [[Редакторские инструменты]].
@tool
extends VBoxContainer

const EditorState := preload("res://addons/game_design_tool/shared/editor_state.gd")

const TAB_SCRIPTS: Array[GDScript] = [
	preload("res://addons/game_design_tool/tabs/templates.gd"),
	preload("res://addons/game_design_tool/tabs/presets.gd"),
	preload("res://addons/game_design_tool/tabs/world_gen.gd"),
]

## Свой раздел project metadata, не общий с вкладками (см. GDT_EditorState).
const SETTINGS_SECTION := "game_design_tool_main"


func _init() -> void:
	name = "GameDesignTool"
	# Скрыт с рождения: иначе ленивая сборка вкладок сработает на старте (вики, грабля 2).
	visible = false
	# Главный экран редактора — VBoxContainer: растягивает по size flags, не по якорям.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)

	for tab_script: GDScript in TAB_SCRIPTS:
		var tab := tab_script.new() as Control
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tabs.add_child(tab)

	# clampi: current_tab кидает "Index out of bounds", а сохранённый индекс мог устареть.
	tabs.current_tab = clampi(
		EditorState.read(SETTINGS_SECTION, "current_tab", 0), 0, TAB_SCRIPTS.size() - 1
	)
	tabs.tab_changed.connect(
		func(index: int) -> void: EditorState.write(SETTINGS_SECTION, "current_tab", index)
	)
