## res://addons/game_design_tool/main_screen.gd
## Корень вкладки «Геймдизайн»: `TabContainer`, в который собраны инструменты,
## завязанные конкретно на эту игру.
##
## Вкладки перечислены ЯВНЫМ списком, а не автопоиском файлов в `tabs/`:
## автодискавери выглядит расширяемее, но превращает опечатку в имени файла в
## молчаливо исчезнувшую вкладку. Дописать строку в массив — не та цена, ради
## которой стоит терять предсказуемость.
##
## Общего состояния между вкладками нет и не задумано: инструменты независимы, а
## заводить общий контекст «на будущее» значит связать их раньше, чем появилась
## причина.
##
## Вкладка = самодостаточный `Control` со своим `TAB_TITLE`; заголовок в
## `TabContainer` берётся из `name` дочернего узла, поэтому вкладки ставят его
## себе сами в `_init`.
@tool
extends VBoxContainer

const TAB_SCRIPTS: Array[GDScript] = [
	preload("res://addons/game_design_tool/tabs/templates.gd"),
	preload("res://addons/game_design_tool/tabs/presets.gd"),
]


func _init() -> void:
	name = "GameDesignTool"
	# Скрыт С РОЖДЕНИЯ, а не после add_child: редактор всё равно позовёт
	# _make_visible при выборе вкладки, но _ready у вкладок срабатывает ВНУТРИ
	# add_child — и если экран в этот момент виден, ленивая сборка «при первом
	# показе» отрабатывает сразу на старте редактора, ради чего её и заводили.
	visible = false
	# Главный экран редактора — VBoxContainer, детей он растягивает по size flags,
	# а не по якорям.
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
