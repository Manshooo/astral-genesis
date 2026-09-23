# res://dev/debug_menu.gd
## Меню отладки: читы, которые удобнее нажать мышью, чем держать клавишей, —
## сейчас перенос в уникальные комнаты. Открывается из отладочного оверлея и живёт
## экраном в стеке UIManager: курсор, блок ввода игрока и закрытие по Esc — те же,
## что у дерева навыков, своих правил у меню нет.
##
## Почему меню, а не ещё клавиши. Ряд F-клавиш кончился: F5 занят встроенным
## ui_filedialog_refresh, а F9–F12 при запуске из редактора — его отладчик (точка
## останова, шаги, продолжить), и нажатие уходило редактору вместе с курсором.
## Клавиша на каждую уникальную комнату к тому же росла бы вместе с конфигом.
##
## Разделы — FoldableContainer в общей FoldableGroup, то есть аккордеон: раскрыт
## один раздел, остальные свёрнуты, и меню не растёт с каждым новым. Свернуть можно
## и все — allow_folding_all, иначе единственный пока раздел не сворачивался бы.
##
## Кнопка из шаблона в сцене, копии делает код — как строки шпаргалки оверлея.
extends Control

## Кнопку нажали; куда переносить и как это назвать — решает оверлей, у него же
## и сам перенос (тот, что без меню, по клавише, работает тем же путём).
signal travel_requested(scene_path: String, title: String)

@onready var _rooms: VBoxContainer = %Rooms


## [param rooms] — { "title": String, "scene_path": String } на каждую кнопку.
func setup(rooms: Array[Dictionary]) -> void:
	var template: Button = _rooms.get_child(0)
	for i in rooms.size():
		var button: Button = template if i == 0 else template.duplicate()
		if i > 0:
			_rooms.add_child(button)
		var room := rooms[i]
		button.text = room["title"]
		button.pressed.connect(travel_requested.emit.bind(room["scene_path"], room["title"]))
	# Пустой конфиг — не повод показывать кнопку-заглушку из сцены.
	template.visible = not rooms.is_empty()
